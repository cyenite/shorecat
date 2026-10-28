import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';

import '../android_build.dart';
import '../client.dart';
import '../config.dart';
import '../log.dart';
import 'base.dart';

class ReleasesCommand extends ShorecatCommand {
  @override
  final name = 'releases';

  @override
  final description = 'List releases and their patches.';

  @override
  Future<int> run() async {
    final config = this.config;
    final client = this.client;
    try {
      final releases = await client.releases(config.appId);
      if (releases.isEmpty) Log.info('No releases yet.');
      for (final release in releases) {
        final patches = (release['patches']! as List).cast<Json>();
        final archs = (release['artifacts']! as Json).keys.join(', ');
        Log.info(
          '${release['version']}  ${release['platform']}  [$archs]  '
          'Flutter ${release['flutter_version'] ?? '?'}  ${patches.length} patch(es)',
        );
        for (final patch in patches) {
          Log.detail(describePatch(patch));
        }
      }
      return 0;
    } finally {
      client.close();
    }
  }
}

String describePatch(Json patch) {
  final stats = patch['stats']! as Json;
  final reason = patch['status_reason'];
  return '#${patch['number']}  ${patch['status']}  ${patch['channel']}  '
      '${patch['rollout_percentage']}%  '
      'installs ${stats['install_success'] ?? 0}  '
      'launches ${stats['launch_success'] ?? 0}  '
      'crashes ${stats['boot_failure'] ?? 0}'
      '${patch['is_critical'] == true ? '  critical' : ''}'
      '${reason == null ? '' : '  ($reason)'}';
}

class PatchesCommand extends Command<int> {
  @override
  final name = 'patches';

  @override
  final description = 'Inspect and control published patches.';

  PatchesCommand() {
    addSubcommand(_PatchList());
    addSubcommand(
      _PatchChange(
        'publish',
        'Publish a draft patch.',
        (c, args) => {},
        isPublish: true,
      ),
    );
    addSubcommand(
      _PatchChange(
        'rollout',
        'Set the rollout percentage: shorecat patches rollout <n> <percent>.',
        (c, args) => {'rollout_percentage': c.percentArg(args.single)},
        extraArgs: 1,
      ),
    );
    addSubcommand(
      _PatchChange(
        'pause',
        'Stop offering a patch to new devices.',
        (c, _) => {'status': 'paused'},
      ),
    );
    addSubcommand(
      _PatchChange(
        'resume',
        'Offer a paused or rolled back patch again.',
        (c, _) => {'status': 'active'},
      ),
    );
    addSubcommand(
      _PatchChange(
        'rollback',
        'Roll a patch back: devices uninstall it on their next check.',
        (c, _) => {'status': 'rolled_back', 'reason': ?c.option('reason')},
        hasReason: true,
      ),
    );
    addSubcommand(
      _PatchChange(
        'promote',
        'Move a patch to another channel: shorecat patches promote <n> <channel>.',
        (c, args) => {'channel': args.single},
        extraArgs: 1,
      ),
    );
  }
}

abstract class _ReleaseScoped extends ShorecatCommand {
  _ReleaseScoped() {
    argParser.addOption(
      'release-version',
      help: 'Defaults to the pubspec version.',
    );
  }

  Future<Json> release(ShorecatClient client, ProjectConfig config) async {
    final version = option('release-version') ?? pubspecReleaseVersion(project);
    final releases = await client.releases(
      config.appId,
      version: version,
      platform: 'android',
    );
    if (releases.isEmpty) throw CliException('No release $version');
    return releases.single;
  }
}

class _PatchList extends _ReleaseScoped {
  @override
  final name = 'list';

  @override
  final description = 'List the patches of a release.';

  @override
  Future<int> run() async {
    final config = this.config;
    final client = this.client;
    try {
      final release = await this.release(client, config);
      final patches = (release['patches']! as List).cast<Json>();
      Log.info('Release ${release['version']}: ${patches.length} patch(es)');
      for (final patch in patches) {
        Log.detail(describePatch(patch));
        final notes = patch['notes'];
        if (notes != null) Log.detail('    $notes');
      }
      return 0;
    } finally {
      client.close();
    }
  }
}

class _PatchChange extends _ReleaseScoped {
  @override
  final String name;
  @override
  final String description;
  final int extraArgs;
  final bool isPublish;
  final Json Function(_PatchChange command, List<String> args) body;

  _PatchChange(
    this.name,
    this.description,
    this.body, {
    this.extraArgs = 0,
    this.isPublish = false,
    bool hasReason = false,
  }) {
    if (hasReason) {
      argParser.addOption('reason', help: 'Shown on the dashboard.');
    }
  }

  @override
  String get invocation =>
      'shorecat patches $name <patch number>${extraArgs > 0 ? ' <value>' : ''}';

  @override
  Future<int> run() async {
    if (rest.length != 1 + extraArgs) {
      throw UsageException('Wrong number of arguments', usage);
    }
    final number = intArg(rest.first, 'Patch number');
    final config = this.config;
    final client = this.client;
    try {
      final release = await this.release(client, config);
      final id = release['id']! as String;
      final change = body(this, rest.skip(1).toList());
      final patch = isPublish
          ? await client.publishPatch(id, number, change)
          : await client.updatePatch(id, number, change);
      Log.success(describePatch(patch));
      return 0;
    } finally {
      client.close();
    }
  }
}

class KeysCommand extends Command<int> {
  @override
  final name = 'keys';

  @override
  final description = 'Manage patch signing keys.';

  KeysCommand() {
    addSubcommand(_KeysShow());
    addSubcommand(_KeysRotate());
  }
}

class _KeysShow extends ShorecatCommand {
  @override
  final name = 'show';

  @override
  final description = 'Show the trusted keys and which one signs new patches.';

  @override
  Future<int> run() async {
    final config = this.config;
    final key = await user.loadKey(config.appId);
    Log.info(
      'Signing key: ${key.publicKey.id}  (${user.keyFile(config.appId).path})',
    );
    for (final k in config.publicKeys) {
      final parsed = PatchPublicKey.parse(k);
      Log.detail(
        '${parsed.id}  ${parsed == key.publicKey ? 'signing' : 'trusted'}  $k',
      );
    }
    return 0;
  }
}

class _KeysRotate extends ShorecatCommand {
  @override
  final name = 'rotate';

  @override
  final description =
      'Create a new signing key. Existing releases keep trusting the old one; '
      'releases built afterwards trust both until you drop the old key.';

  @override
  Future<int> run() async {
    final config = this.config;
    final old = await user.loadKey(config.appId);
    final current = user.keyFile(config.appId);
    final archived = p.join(
      current.parent.path,
      '${config.appId}-${old.publicKey.id}.pem',
    );
    current.renameSync(archived);
    final fresh = await PatchKeyPair.generate();
    user.saveKey(config.appId, fresh);

    final keys = [fresh.publicKey.encode(), ...config.publicKeys];
    config.copyWith(publicKeys: keys).save(project);
    final client = this.client;
    try {
      final app = await client.getApp(config.appId);
      final serverKeys = [
        for (final k in app['public_keys']! as List) k as String,
      ];
      await client.updateApp(config.appId, {
        'public_keys': {...serverKeys, fresh.publicKey.encode()}.toList(),
      });
    } finally {
      client.close();
    }
    Log.success(
      'New signing key ${fresh.publicKey.id}. Old key archived at $archived.',
    );
    Log.detail(
      'Patches for releases shipped before this keep using the old key automatically.',
    );
    return 0;
  }
}
