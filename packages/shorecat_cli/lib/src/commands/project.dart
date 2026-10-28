import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';
import 'package:yaml/yaml.dart';

import '../android_build.dart';
import '../client.dart';
import '../config.dart';
import '../log.dart';
import 'base.dart';

const pluginPackage = 'shorecat_code_push';
const activityClass = 'dev.shorecat.code_push.ShorecatFlutterActivity';

class InitCommand extends ShorecatCommand {
  @override
  final name = 'init';

  @override
  final description =
      'Set up shorecat in this Flutter project: signing key, shorecat.yaml, '
      'asset registration, Android activity and server registration.';

  InitCommand() {
    argParser
      ..addOption(
        'server',
        help: 'Base URL of the shorecat server.',
        mandatory: true,
      )
      ..addOption('app-id', help: 'Defaults to the pubspec name.')
      ..addOption('name', help: 'Display name on the dashboard.')
      ..addOption('token', help: 'Admin token, saved as with "shorecat login".')
      ..addOption('channel', defaultsTo: 'stable')
      ..addFlag(
        'register',
        defaultsTo: true,
        help: 'Create the app on the server.',
      )
      ..addFlag(
        'android',
        defaultsTo: true,
        help: 'Switch MainActivity to ShorecatFlutterActivity.',
      )
      ..addFlag('force', negatable: false, help: 'Overwrite shorecat.yaml.');
  }

  @override
  Future<int> run() async {
    final pubspec = File(p.join(project.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw CliException(
        'Run this in a Flutter project (no pubspec.yaml here)',
      );
    }
    if (ProjectConfig.fileIn(project).existsSync() && !flag('force')) {
      throw CliException('shorecat.yaml exists. Use --force to recreate it.');
    }
    final server = option('server')!.replaceAll(RegExp(r'/+$'), '');
    final appId =
        option('app-id') ??
        (loadYaml(pubspec.readAsStringSync()) as YamlMap)['name'] as String;

    final keyFile = user.keyFile(appId);
    final PatchKeyPair key;
    if (keyFile.existsSync()) {
      key = await user.loadKey(appId);
      Log.step('Reusing signing key ${key.publicKey.id} from ${keyFile.path}');
    } else {
      key = await PatchKeyPair.generate();
      user.saveKey(appId, key);
      Log.step('Generated signing key ${key.publicKey.id}');
      Log.detail(
        'Private key: ${keyFile.path} (back this up; it never leaves this machine)',
      );
    }

    final config = ProjectConfig(
      appId: appId,
      baseUrl: server,
      channel: option('channel')!,
      publicKeys: [key.publicKey.encode()],
    )..save(project);
    Log.step('Wrote shorecat.yaml');

    final updated = addAsset(
      pubspec.readAsStringSync(),
      ProjectConfig.fileName,
    );
    if (updated != null) {
      pubspec.writeAsStringSync(updated);
      Log.step('Registered shorecat.yaml as a Flutter asset');
    }

    if (flag('android')) _integrateAndroid();

    final token = option('token');
    if (token != null) user.saveToken(server, token);
    if (flag('register')) await _register(config, key);

    final hasPlugin = pubspec.readAsStringSync().contains('$pluginPackage:');
    Log.success('\nshorecat is set up for $appId.');
    Log.info('Next:');
    if (!hasPlugin) {
      Log.detail('Add the $pluginPackage plugin to pubspec.yaml dependencies.');
    }
    Log.detail('Call Shorecat.initialize() in main() before runApp().');
    Log.detail('shorecat release android');
    return 0;
  }

  Future<void> _register(ProjectConfig config, PatchKeyPair key) async {
    final client = ShorecatClient.forProject(config, user);
    try {
      final existing = await client.findApp(config.appId);
      if (existing == null) {
        await client.createApp({
          'id': config.appId,
          'name': option('name') ?? config.appId,
          'public_keys': config.publicKeys,
        });
        Log.step('Registered ${config.appId} on ${config.baseUrl}');
        return;
      }
      final keys = [
        for (final k in existing['public_keys']! as List) k as String,
      ];
      if (!keys.contains(key.publicKey.encode())) {
        await client.updateApp(config.appId, {
          'public_keys': [...keys, key.publicKey.encode()],
        });
        Log.step('Added this signing key to the existing app');
      } else {
        Log.step('${config.appId} is already registered');
      }
    } finally {
      client.close();
    }
  }

  void _integrateAndroid() {
    final activity = findMainActivity(project);
    if (activity == null) {
      Log.warn('No MainActivity.kt found; extend $activityClass yourself.');
      return;
    }
    final source = activity.readAsStringSync();
    if (source.contains('ShorecatFlutterActivity')) return;
    const stock = 'import io.flutter.embedding.android.FlutterActivity';
    if (!source.contains(stock) || !source.contains(': FlutterActivity()')) {
      Log.warn(
        '${activity.path} is customised; make it extend $activityClass by hand.',
      );
      return;
    }
    activity.writeAsStringSync(
      source
          .replaceFirst(stock, 'import $activityClass')
          .replaceFirst(': FlutterActivity()', ': ShorecatFlutterActivity()'),
    );
    Log.step('MainActivity now extends ShorecatFlutterActivity');
  }
}

/// Adds [asset] under `flutter: assets:` in pubspec text, or returns null when
/// it is already listed.
String? addAsset(String pubspec, String asset) {
  if (RegExp(
    '^\\s*-\\s*${RegExp.escape(asset)}\\s*\$',
    multiLine: true,
  ).hasMatch(pubspec)) {
    return null;
  }
  final lines = pubspec.split('\n');
  final flutter = lines.indexWhere((l) => l.trimRight() == 'flutter:');
  if (flutter == -1) {
    return '${pubspec.trimRight()}\n\nflutter:\n  assets:\n    - $asset\n';
  }
  for (var i = flutter + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    if (RegExp(r'^  assets:\s*$').hasMatch(line)) {
      lines.insert(i + 1, '    - $asset');
      return lines.join('\n');
    }
  }
  lines.insert(flutter + 1, '  assets:\n    - $asset');
  return lines.join('\n');
}

File? findMainActivity(Directory project) {
  final root = Directory(p.join(project.path, 'android', 'app', 'src', 'main'));
  if (!root.existsSync()) return null;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && p.basename(entity.path) == 'MainActivity.kt') {
      return entity;
    }
  }
  return null;
}

class LoginCommand extends ShorecatCommand {
  @override
  final name = 'login';

  @override
  final description = 'Save an admin token for a shorecat server.';

  LoginCommand() {
    argParser
      ..addOption('server', mandatory: true)
      ..addOption('token', mandatory: true);
  }

  @override
  Future<int> run() async {
    final server = option('server')!.replaceAll(RegExp(r'/+$'), '');
    final client = ShorecatClient(baseUrl: server, token: option('token')!);
    try {
      final apps = (await client.listApps())['apps']! as List;
      user.saveToken(server, option('token')!);
      Log.success('Logged in to $server (${apps.length} apps).');
      return 0;
    } finally {
      client.close();
    }
  }
}

class DoctorCommand extends ShorecatCommand {
  @override
  final name = 'doctor';

  @override
  final description = 'Check that this project is ready to release and patch.';

  @override
  Future<int> run() async {
    var problems = 0;
    void check(bool isOk, String good, String bad) {
      if (isOk) {
        Log.success('[ok] $good');
      } else {
        problems++;
        Log.error(bad);
      }
    }

    try {
      final flutter = await FlutterVersion.detect();
      check(true, 'Flutter $flutter', '');
    } on CliException catch (e) {
      check(false, '', e.message);
    }

    final ProjectConfig config;
    try {
      config = this.config;
    } on CliException catch (e) {
      Log.error(e.message);
      return 1;
    }
    check(true, 'shorecat.yaml for ${config.appId}', '');
    final keys = <PatchPublicKey>[];
    for (final k in config.publicKeys) {
      try {
        keys.add(PatchPublicKey.parse(k));
      } on SigningException catch (e) {
        check(false, '', 'Bad public key in shorecat.yaml: ${e.message}');
      }
    }
    check(
      keys.isNotEmpty,
      '${keys.length} trusted public key(s)',
      'shorecat.yaml lists no public keys',
    );

    final pubspec = File(
      p.join(project.path, 'pubspec.yaml'),
    ).readAsStringSync();
    check(
      addAsset(pubspec, ProjectConfig.fileName) == null,
      'shorecat.yaml is bundled as an asset',
      'shorecat.yaml is not listed under flutter: assets: in pubspec.yaml',
    );
    check(
      pubspec.contains('$pluginPackage:'),
      '$pluginPackage dependency present',
      'Add $pluginPackage to pubspec.yaml dependencies',
    );
    final activity = findMainActivity(project);
    check(
      activity?.readAsStringSync().contains('ShorecatFlutterActivity') ?? false,
      'MainActivity extends ShorecatFlutterActivity',
      'MainActivity must extend $activityClass or patches never boot',
    );

    try {
      final key = await user.loadKey(config.appId);
      check(
        keys.contains(key.publicKey),
        'Signing key ${key.publicKey.id} matches shorecat.yaml',
        'The local signing key ${key.publicKey.id} is not in shorecat.yaml',
      );
    } on CliException catch (e) {
      check(false, '', e.message);
    }

    final token = user.tokenFor(config.baseUrl);
    final client = ShorecatClient(baseUrl: config.baseUrl, token: token ?? '');
    try {
      final isUp = await client.isReachable();
      check(
        isUp,
        'Server ${config.baseUrl} is reachable',
        'Cannot reach ${config.baseUrl}',
      );
      if (isUp && token == null) {
        check(false, '', 'Not logged in to ${config.baseUrl}');
      } else if (isUp) {
        final app = await client.findApp(config.appId);
        check(
          app != null,
          'App is registered on the server',
          'App ${config.appId} is not registered (run shorecat init)',
        );
      }
    } on CliException catch (e) {
      check(false, '', e.message);
    } finally {
      client.close();
    }

    if (Uri.parse(config.baseUrl).scheme != 'https') {
      Log.warn(
        'base_url is not HTTPS. Fine for development; use HTTPS in production.',
      );
    }
    Log.info(
      problems == 0 ? '\nNo problems found.' : '\n$problems problem(s) found.',
    );
    return problems == 0 ? 0 : 1;
  }
}
