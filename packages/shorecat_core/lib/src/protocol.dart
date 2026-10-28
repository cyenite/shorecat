/// Wire models shared by the server, the CLI and the on-device updater.
library;

enum AppPlatform {
  android('android'),
  ios('ios');

  final String wireName;

  const AppPlatform(this.wireName);

  static AppPlatform parse(String value) => values.firstWhere(
    (p) => p.wireName == value,
    orElse: () => throw FormatException('Unknown platform "$value"'),
  );
}

enum Arch {
  arm64('aarch64', 'arm64-v8a'),
  arm32('arm', 'armeabi-v7a'),
  x64('x86_64', 'x86_64');

  final String wireName;
  final String androidAbi;

  const Arch(this.wireName, this.androidAbi);

  static Arch parse(String value) => values.firstWhere(
    (a) => a.wireName == value || a.androidAbi == value,
    orElse: () => throw FormatException('Unknown arch "$value"'),
  );

  static Arch? fromAndroidAbi(String abi) {
    for (final arch in values) {
      if (arch.androidAbi == abi) return arch;
    }
    return null;
  }
}

/// Server side lifecycle of a patch. Declaration order is the order a patch
/// moves through, and the order the dashboard and CLI list them in.
enum PatchStatus {
  draft('draft'),
  active('active'),
  paused('paused'),
  rolledBack('rolled_back');

  final String wireName;

  const PatchStatus(this.wireName);

  static PatchStatus parse(String value) => values.firstWhere(
    (s) => s.wireName == value,
    orElse: () => throw FormatException('Unknown patch status "$value"'),
  );

  bool get isServable => this == active;
}

enum PatchEventType {
  download('download'),
  installSuccess('install_success'),
  installFailure('install_failure'),
  launchSuccess('launch_success'),
  bootFailure('boot_failure'),
  uninstall('uninstall');

  final String wireName;

  const PatchEventType(this.wireName);

  static PatchEventType parse(String value) => values.firstWhere(
    (t) => t.wireName == value,
    orElse: () => throw FormatException('Unknown event type "$value"'),
  );
}

class PatchCheckRequest {
  final int? currentPatchNumber;
  final Arch arch;
  final String appId;
  final String channel;
  final String clientId;
  final String releaseVersion;
  final AppPlatform platform;

  const PatchCheckRequest({
    this.currentPatchNumber,
    required this.arch,
    required this.appId,
    required this.channel,
    required this.clientId,
    required this.releaseVersion,
    required this.platform,
  });

  factory PatchCheckRequest.fromJson(Map<String, Object?> json) =>
      PatchCheckRequest(
        currentPatchNumber: json['current_patch_number'] as int?,
        arch: Arch.parse(_string(json, 'arch')),
        appId: _string(json, 'app_id'),
        channel: json['channel'] as String? ?? 'stable',
        clientId: _string(json, 'client_id'),
        releaseVersion: _string(json, 'release_version'),
        platform: AppPlatform.parse(_string(json, 'platform')),
      );

  Map<String, Object?> toJson() => {
    'app_id': appId,
    'channel': channel,
    'client_id': clientId,
    'release_version': releaseVersion,
    'platform': platform.wireName,
    'arch': arch.wireName,
    if (currentPatchNumber != null) 'current_patch_number': currentPatchNumber,
  };
}

class AvailablePatch {
  final int number;
  final int deltaSize;
  final bool isCritical;
  final String hash;
  final String? notes;
  final String baseHash;
  final String signature;
  final String downloadUrl;

  const AvailablePatch({
    required this.number,
    required this.deltaSize,
    required this.isCritical,
    required this.hash,
    this.notes,
    required this.baseHash,
    required this.signature,
    required this.downloadUrl,
  });

  factory AvailablePatch.fromJson(Map<String, Object?> json) => AvailablePatch(
    number: json['number'] as int,
    deltaSize: json['delta_size'] as int? ?? 0,
    isCritical: json['is_critical'] as bool? ?? false,
    hash: _string(json, 'hash'),
    notes: json['notes'] as String?,
    baseHash: _string(json, 'base_hash'),
    signature: _string(json, 'signature'),
    downloadUrl: _string(json, 'download_url'),
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'hash': hash,
    'base_hash': baseHash,
    'signature': signature,
    'download_url': downloadUrl,
    'delta_size': deltaSize,
    'is_critical': isCritical,
    if (notes != null) 'notes': notes,
  };
}

class PatchCheckResponse {
  final bool isPatchAvailable;
  final AvailablePatch? patch;
  final List<int> rolledBackPatchNumbers;

  const PatchCheckResponse({
    required this.isPatchAvailable,
    this.patch,
    this.rolledBackPatchNumbers = const [],
  });

  factory PatchCheckResponse.fromJson(Map<String, Object?> json) {
    final patch = json['patch'];
    return PatchCheckResponse(
      isPatchAvailable: json['patch_available'] as bool? ?? false,
      patch: patch is Map<String, Object?>
          ? AvailablePatch.fromJson(patch)
          : null,
      rolledBackPatchNumbers: [
        for (final n in json['rolled_back_patch_numbers'] as List? ?? const [])
          n as int,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'patch_available': isPatchAvailable,
    if (patch != null) 'patch': patch!.toJson(),
    'rolled_back_patch_numbers': rolledBackPatchNumbers,
  };
}

class PatchEvent {
  final int timestamp;
  final int patchNumber;
  final Arch arch;
  final String appId;
  final String? message;
  final String clientId;
  final String releaseVersion;
  final AppPlatform platform;
  final PatchEventType type;

  const PatchEvent({
    required this.timestamp,
    required this.patchNumber,
    required this.arch,
    required this.appId,
    this.message,
    required this.clientId,
    required this.releaseVersion,
    required this.platform,
    required this.type,
  });

  factory PatchEvent.fromJson(Map<String, Object?> json) => PatchEvent(
    timestamp: json['timestamp'] as int? ?? 0,
    patchNumber: json['patch_number'] as int,
    arch: Arch.parse(_string(json, 'arch')),
    appId: _string(json, 'app_id'),
    message: json['message'] as String?,
    clientId: _string(json, 'client_id'),
    releaseVersion: _string(json, 'release_version'),
    platform: AppPlatform.parse(_string(json, 'platform')),
    type: PatchEventType.parse(_string(json, 'type')),
  );

  Map<String, Object?> toJson() => {
    'app_id': appId,
    'client_id': clientId,
    'release_version': releaseVersion,
    'platform': platform.wireName,
    'arch': arch.wireName,
    'patch_number': patchNumber,
    'type': type.wireName,
    'timestamp': timestamp,
    if (message != null) 'message': message,
  };
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing or empty "$key"');
}
