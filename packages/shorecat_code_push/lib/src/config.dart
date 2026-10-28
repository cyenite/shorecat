import 'package:shorecat_updater/shorecat_updater.dart';
import 'package:yaml/yaml.dart';

/// The bundled `shorecat.yaml`, written by `shorecat init`.
class ShorecatConfig {
  final int maxBootAttempts;
  final bool isAutoUpdate;
  final String appId;
  final String baseUrl;
  final String channel;
  final List<PatchPublicKey> publicKeys;

  const ShorecatConfig({
    this.maxBootAttempts = 1,
    this.isAutoUpdate = true,
    required this.appId,
    required this.baseUrl,
    this.channel = 'stable',
    this.publicKeys = const [],
  });

  factory ShorecatConfig.parse(String source) {
    final yaml = loadYaml(source);
    if (yaml is! YamlMap) {
      throw const FormatException('shorecat.yaml is not a map');
    }
    final appId = yaml['app_id'];
    final baseUrl = yaml['base_url'];
    if (appId is! String || baseUrl is! String) {
      throw const FormatException('shorecat.yaml needs app_id and base_url');
    }
    final keys = [
      for (final k in yaml['public_keys'] as YamlList? ?? YamlList())
        PatchPublicKey.parse('$k'),
    ];
    if (keys.isEmpty) {
      throw const FormatException(
        'shorecat.yaml lists no public_keys; patches could never verify',
      );
    }
    return ShorecatConfig(
      maxBootAttempts: yaml['max_boot_attempts'] as int? ?? 1,
      isAutoUpdate: yaml['auto_update'] as bool? ?? true,
      appId: appId,
      baseUrl: baseUrl,
      channel: yaml['channel'] as String? ?? 'stable',
      publicKeys: keys,
    );
  }
}
