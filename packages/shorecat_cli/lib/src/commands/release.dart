import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';

import '../android_build.dart';
import '../client.dart';
import '../config.dart';
import '../log.dart';
import 'base.dart';

void _addBuildOptions(ShorecatCommand command) => command.argParser
  ..addOption('flavor', help: 'Android product flavor.')
  ..addOption('target', abbr: 't', help: 'Dart entrypoint (lib/main.dart).')
  ..addOption(
    'release-version',
    help: 'Defaults to the pubspec version as name+code.',
  )
  ..addOption(
    'from-archive',
    help: 'Use an already built .aab/.apk instead of running flutter build.',
  );

void _requireAndroid(List<String> rest, String usage) {
  if (rest.isEmpty || rest.first != 'android') {
    throw UsageException('Only "android" is supported for code push.', usage);
  }
}

class ReleaseCommand extends ShorecatCommand {
  @override
  final name = 'release';

  @override
  final description =
      'Build a store release and register its code with the server. '
      'Usage: shorecat release android [-- extra flutter build args]';

  ReleaseCommand() {
    _addBuildOptions(this);
    argParser.addOption(
      'artifact',
      allowed: ['aab', 'apk'],
      defaultsTo: 'aab',
      help: 'aab for Play, apk for sideloading and testing.',
    );
  }

  @override
  Future<int> run() async {
    _requireAndroid(rest, usage);
    final config = this.config;
    final client = this.client;
    try {
      final version =
          option('release-version') ?? pubspecReleaseVersion(project);
      final existing = await client.releases(
        config.appId,
        version: version,
        platform: 'android',
      );
      if (existing.isNotEmpty) {
        throw CliException(
          'Release $version already exists. Bump the pubspec version.',
        );
      }

      final flutter = await FlutterVersion.detect();
      final type = ArtifactType.parse(option('artifact')!);
      final build = option('from-archive') != null
          ? AndroidBuild.read(File(option('from-archive')!), type)
          : await AndroidBuild.run(
              project: project,
              type: type,
              flavor: option('flavor'),
              target: option('target'),
              extraArgs: rest.skip(1).toList(),
            );

      Log.step('Uploading code for release $version');
      final artifacts = <String, Object?>{};
      for (final e in build.libraries.entries) {
        final sha = await client.uploadBlob(e.value);
        artifacts[e.key.wireName] = {'sha256': sha, 'size': e.value.length};
        Log.detail(
          '${e.key.androidAbi.padRight(12)} ${formatBytes(e.value.length)}  $sha',
        );
      }
      await client.createRelease(config.appId, {
        'version': version,
        'platform': 'android',
        'flutter_version': flutter.version,
        'artifacts': artifacts,
        'manifest': {
          'artifact_type': type.wireName,
          'flutter': flutter.toJson(),
          'public_keys': config.publicKeys,
          'files': build.fingerprint,
        },
      });

      Log.success('\nRelease $version registered.');
      Log.detail('Artifact: ${build.archive.path}');
      Log.detail(
        'Ship this exact build to users; patches are deltas against it.',
      );
      return 0;
    } finally {
      client.close();
    }
  }
}

class PatchCommand extends ShorecatCommand {
  @override
  final name = 'patch';

  @override
  final description =
      'Build the current Dart code, diff it against a release, sign it and '
      'publish it. Usage: shorecat patch android [-- extra flutter build args]';

  PatchCommand() {
    _addBuildOptions(this);
    argParser
      ..addOption('channel', help: 'Defaults to the shorecat.yaml channel.')
      ..addOption('rollout', defaultsTo: '100', help: 'Percentage of devices.')
      ..addOption('notes', help: 'Shown on the dashboard and to the app.')
      ..addFlag(
        'critical',
        negatable: false,
        help: 'Ask the app to restart promptly.',
      )
      ..addFlag('draft', negatable: false, help: 'Upload without publishing.')
      ..addFlag('dry-run', negatable: false, help: 'Build and diff only.')
      ..addFlag(
        'allow-asset-diffs',
        negatable: false,
        help:
            'Publish even though Flutter assets changed (they are not patched).',
      )
      ..addFlag(
        'allow-native-diffs',
        negatable: false,
        help:
            'Publish even though Java/Kotlin/native code changed (not patched).',
      );
  }

  @override
  Future<int> run() async {
    _requireAndroid(rest, usage);
    final config = this.config;
    final client = this.client;
    try {
      final version =
          option('release-version') ?? pubspecReleaseVersion(project);
      final releases = await client.releases(
        config.appId,
        version: version,
        platform: 'android',
      );
      if (releases.isEmpty) {
        throw CliException(
          'No release $version on the server. Run "shorecat release android" first.',
        );
      }
      final release = releases.single;
      final manifest = release['manifest']! as Json;

      final flutter = await FlutterVersion.detect();
      final releaseEngine = (manifest['flutter'] as Json?)?['engine_revision'];
      if (releaseEngine != null && releaseEngine != flutter.engine) {
        throw CliException(
          'Release $version was built with Flutter engine $releaseEngine but '
          'this machine has ${flutter.engine}. A patch must use the exact same '
          'Flutter version (${release['flutter_version']}).',
        );
      }

      final key = await _signingKey(config, manifest);
      Log.step('Signing with key ${key.publicKey.id}');

      final type = ArtifactType.parse(
        manifest['artifact_type'] as String? ?? 'aab',
      );
      final build = option('from-archive') != null
          ? AndroidBuild.read(File(option('from-archive')!), type)
          : await AndroidBuild.run(
              project: project,
              type: type,
              flavor: option('flavor'),
              target: option('target'),
              extraArgs: rest.skip(1).toList(),
            );

      _checkUnpatchableChanges(
        AndroidBuild.compare({
          for (final e in (manifest['files'] as Json? ?? {}).entries)
            e.key: e.value! as int,
        }, build.fingerprint),
      );

      final releaseArtifacts = release['artifacts']! as Json;
      final deltas = <Arch, ({Uint8List delta, String hash, int size})>{};
      var isAnyChanged = false;
      for (final e in releaseArtifacts.entries) {
        final arch = Arch.parse(e.key);
        final baseInfo = e.value! as Json;
        final target = build.libraries[arch];
        if (target == null) {
          throw CliException(
            'The patch build has no ${arch.androidAbi} libapp.so',
          );
        }
        final base = await client.downloadBlob(baseInfo['sha256']! as String);
        if (sha256Hex(base) != baseInfo['sha256']) {
          throw CliException(
            'Release ${arch.wireName} artifact failed its hash check',
          );
        }
        final targetHash = sha256Hex(target);
        if (targetHash != baseInfo['sha256']) isAnyChanged = true;
        Log.step('Diffing ${arch.androidAbi}');
        final delta = await Isolate.run(
          () => Delta.createSmallest(base, target),
        );
        deltas[arch] = (delta: delta, hash: targetHash, size: target.length);
        final header = DeltaHeader.parse(delta);
        Log.detail(
          '${formatBytes(base.length)} -> ${formatBytes(target.length)}, '
          'patch ${formatBytes(delta.length)} (${header.compression.name})',
        );
      }
      if (!isAnyChanged) {
        throw CliException(
          'The Dart code is identical to release $version; nothing to patch.',
        );
      }
      if (flag('dry-run')) {
        Log.success('\nDry run: nothing uploaded.');
        return 0;
      }

      final releaseId = release['id']! as String;
      final patch = await client.createPatch(releaseId, {
        'channel': option('channel') ?? config.channel,
        'notes': ?option('notes'),
        'is_critical': flag('critical'),
        'rollout_percentage': percentArg(option('rollout')!),
      });
      final number = patch['number']! as int;
      Log.step('Uploading patch $number');
      for (final e in deltas.entries) {
        final deltaSha = await client.uploadBlob(e.value.delta);
        final signature = await key.sign(
          PatchSignaturePayload(
            patchNumber: number,
            arch: e.key,
            appId: config.appId,
            targetSha256: e.value.hash,
            releaseVersion: version,
            platform: AppPlatform.android,
          ),
        );
        await client.putPatchArtifact(releaseId, number, e.key.wireName, {
          'delta_sha256': deltaSha,
          'signature': signature,
        });
      }

      if (flag('draft')) {
        Log.success(
          '\nPatch $number uploaded as a draft. Publish with "shorecat patches publish $number".',
        );
        return 0;
      }
      await client.publishPatch(releaseId, number, {});
      Log.success(
        '\nPatch $number is live on ${option('channel') ?? config.channel} '
        'for ${option('rollout')}% of $version installs.',
      );
      Log.detail(
        'Devices download it in the background and run it on next launch.',
      );
      return 0;
    } finally {
      client.close();
    }
  }

  void _checkUnpatchableChanges(Map<ChangeKind, List<String>> changes) {
    if (changes.isEmpty) return;
    var isBlocked = false;
    for (final kind in ChangeKind.values) {
      final list = changes[kind];
      if (list == null) continue;
      final isAllowed = switch (kind) {
        ChangeKind.assets => flag('allow-asset-diffs'),
        ChangeKind.android || ChangeKind.native => flag('allow-native-diffs'),
        ChangeKind.other => true,
      };
      (isAllowed ? Log.warn : Log.error)(
        '${kind.label} changed since the release; a patch only replaces Dart code:',
      );
      for (final line in list.take(10)) {
        Log.detail(line);
      }
      if (list.length > 10) Log.detail('... and ${list.length - 10} more');
      if (!isAllowed) isBlocked = true;
    }
    if (isBlocked) {
      throw CliException(
        'Refusing to patch: the changes above need a store release. If the '
        'Dart code does not depend on them, pass --allow-asset-diffs or '
        '--allow-native-diffs.',
      );
    }
  }

  /// The release trusts the keys that were in shorecat.yaml when it was
  /// built, so after a rotation old releases still need the old key.
  Future<PatchKeyPair> _signingKey(ProjectConfig config, Json manifest) async {
    final trusted = {
      for (final k in manifest['public_keys'] as List? ?? config.publicKeys)
        k as String,
    };
    final current = user.keyFile(config.appId);
    final candidates = [
      current,
      if (current.parent.existsSync())
        for (final f in current.parent.listSync())
          if (f is File &&
              p.basename(f.path).startsWith('${config.appId}-') &&
              f.path.endsWith('.pem'))
            f,
    ];
    for (final file in candidates) {
      if (!file.existsSync()) continue;
      final key = await PatchKeyPair.fromPem(await file.readAsString());
      if (trusted.contains(key.publicKey.encode())) return key;
    }
    throw CliException(
      'None of the local signing keys is trusted by this release. It trusts: '
      '${trusted.map((k) => PatchPublicKey.parse(k).id).join(', ')}',
    );
  }
}
