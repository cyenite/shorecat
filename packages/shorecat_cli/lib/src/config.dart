import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';
import 'package:yaml/yaml.dart';

class CliException implements Exception {
  final int exitCode;
  final int? httpStatus;
  final String message;

  CliException(this.message, {this.exitCode = 1, this.httpStatus});

  @override
  String toString() => message;
}

/// `shorecat.yaml`, bundled into the app as a Flutter asset. Everything in it
/// is public: the private signing key never lives in the project.
class ProjectConfig {
  final int maxBootAttempts;
  final bool isAutoUpdate;
  final String appId;
  final String baseUrl;
  final String channel;
  final List<String> publicKeys;

  const ProjectConfig({
    this.maxBootAttempts = 1,
    this.isAutoUpdate = true,
    required this.appId,
    required this.baseUrl,
    this.channel = 'stable',
    this.publicKeys = const [],
  });

  static const fileName = 'shorecat.yaml';

  static File fileIn(Directory project) => File(p.join(project.path, fileName));

  static ProjectConfig load(Directory project) {
    final file = fileIn(project);
    if (!file.existsSync()) {
      throw CliException(
        'No $fileName in ${project.path}. Run "shorecat init" first.',
      );
    }
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) throw CliException('$fileName is not a YAML map');
    final appId = yaml['app_id'];
    final baseUrl = yaml['base_url'];
    if (appId is! String || baseUrl is! String) {
      throw CliException('$fileName needs app_id and base_url');
    }
    return ProjectConfig(
      maxBootAttempts: yaml['max_boot_attempts'] as int? ?? 1,
      isAutoUpdate: yaml['auto_update'] as bool? ?? true,
      appId: appId,
      baseUrl: baseUrl,
      channel: yaml['channel'] as String? ?? 'stable',
      publicKeys: [
        for (final k in yaml['public_keys'] as YamlList? ?? []) '$k',
      ],
    );
  }

  ProjectConfig copyWith({List<String>? publicKeys}) => ProjectConfig(
    maxBootAttempts: maxBootAttempts,
    isAutoUpdate: isAutoUpdate,
    appId: appId,
    baseUrl: baseUrl,
    channel: channel,
    publicKeys: publicKeys ?? this.publicKeys,
  );

  void save(Directory project) => fileIn(project).writeAsStringSync('''
# shorecat code push configuration. Bundled into the app as an asset.
# Safe to commit: it holds only public keys.
app_id: $appId
base_url: $baseUrl
channel: $channel
auto_update: $isAutoUpdate
# Consecutive crashed boots before a patch is abandoned.
max_boot_attempts: $maxBootAttempts
# Every key listed here is trusted, which is how keys are rotated.
public_keys:
${publicKeys.map((k) => '  - $k').join('\n')}
''');
}

/// Per user state under `~/.config/shorecat`: admin tokens per server and
/// one private signing key per app.
class UserConfig {
  final Directory root;

  UserConfig(this.root);

  factory UserConfig.standard() {
    final env = Platform.environment;
    final override = env['SHORECAT_HOME'];
    if (override != null) return UserConfig(Directory(override));
    final base =
        env['XDG_CONFIG_HOME'] ??
        p.join(env['HOME'] ?? env['USERPROFILE'] ?? '.', '.config');
    return UserConfig(Directory(p.join(base, 'shorecat')));
  }

  File get _credentials => File(p.join(root.path, 'credentials.json'));

  String? tokenFor(String server) {
    final env = Platform.environment['SHORECAT_TOKEN'];
    if (env != null && env.isNotEmpty) return env;
    if (!_credentials.existsSync()) return null;
    final json = jsonDecode(_credentials.readAsStringSync()) as Map;
    return (json['servers'] as Map?)?[_normalise(server)] as String?;
  }

  void saveToken(String server, String token) {
    final json = _credentials.existsSync()
        ? jsonDecode(_credentials.readAsStringSync()) as Map<String, Object?>
        : <String, Object?>{};
    final servers = Map<String, Object?>.from(json['servers'] as Map? ?? {});
    servers[_normalise(server)] = token;
    _writePrivate(_credentials, jsonEncode({...json, 'servers': servers}));
  }

  File keyFile(String appId) {
    final env = Platform.environment['SHORECAT_PRIVATE_KEY'];
    if (env != null && env.isNotEmpty) return File(env);
    return File(p.join(root.path, 'keys', '$appId.pem'));
  }

  Future<PatchKeyPair> loadKey(String appId) async {
    final file = keyFile(appId);
    if (!file.existsSync()) {
      throw CliException(
        'No signing key for $appId at ${file.path}. Restore it, or point '
        'SHORECAT_PRIVATE_KEY at it.',
      );
    }
    return PatchKeyPair.fromPem(await file.readAsString());
  }

  void saveKey(String appId, PatchKeyPair key, {String? path}) {
    final file = path == null ? keyFile(appId) : File(path);
    if (file.existsSync()) {
      throw CliException('Refusing to overwrite the key at ${file.path}');
    }
    _writePrivate(file, key.toPem());
  }

  void _writePrivate(File file, String contents) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents, flush: true);
    if (!Platform.isWindows) Process.runSync('chmod', ['600', file.path]);
  }

  static String _normalise(String server) =>
      server.replaceAll(RegExp(r'/+$'), '');
}
