import 'package:shorecat_core/shorecat_core.dart';

/// Server side automatic rollback policy. A patch whose boot failure rate
/// crosses [maxFailureRate] once at least [minLaunches] launches have been
/// reported is rolled back for every device, not just the ones that crashed.
class HealthGate {
  final int minLaunches;
  final bool isEnabled;
  final double maxFailureRate;

  const HealthGate({
    this.minLaunches = 20,
    this.isEnabled = true,
    this.maxFailureRate = 0.05,
  });

  factory HealthGate.fromJson(Map<String, Object?> json) => HealthGate(
    minLaunches: json['min_launches'] as int? ?? 20,
    isEnabled: json['enabled'] as bool? ?? true,
    maxFailureRate: (json['max_failure_rate'] as num? ?? 0.05).toDouble(),
  );

  Map<String, Object?> toJson() => {
    'enabled': isEnabled,
    'min_launches': minLaunches,
    'max_failure_rate': maxFailureRate,
  };
}

class AppRecord {
  final String id;
  final String name;
  final String createdAt;
  final HealthGate healthGate;
  final List<String> publicKeys;

  const AppRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    this.healthGate = const HealthGate(),
    this.publicKeys = const [],
  });

  factory AppRecord.fromJson(Map<String, Object?> json) => AppRecord(
    id: json['id'] as String,
    name: json['name'] as String? ?? json['id'] as String,
    createdAt: json['created_at'] as String? ?? '',
    healthGate: HealthGate.fromJson(
      json['health_gate'] as Map<String, Object?>? ?? const {},
    ),
    publicKeys: [
      for (final k in json['public_keys'] as List? ?? []) k as String,
    ],
  );

  List<PatchPublicKey> get trustedKeys => [
    for (final k in publicKeys) PatchPublicKey.parse(k),
  ];

  AppRecord copyWith({
    String? name,
    HealthGate? healthGate,
    List<String>? publicKeys,
  }) => AppRecord(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    healthGate: healthGate ?? this.healthGate,
    publicKeys: publicKeys ?? this.publicKeys,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt,
    'public_keys': publicKeys,
    'health_gate': healthGate.toJson(),
  };
}

class ReleaseArtifact {
  final int size;
  final String sha256;

  const ReleaseArtifact({required this.size, required this.sha256});

  factory ReleaseArtifact.fromJson(Map<String, Object?> json) =>
      ReleaseArtifact(
        size: json['size'] as int,
        sha256: json['sha256'] as String,
      );

  Map<String, Object?> toJson() => {'sha256': sha256, 'size': size};
}

class ReleaseRecord {
  final String id;
  final String appId;
  final String version;
  final String createdAt;
  final String? flutterVersion;
  final AppPlatform platform;
  final Map<Arch, ReleaseArtifact> artifacts;
  final Map<String, Object?> manifest;

  const ReleaseRecord({
    required this.id,
    required this.appId,
    required this.version,
    required this.createdAt,
    this.flutterVersion,
    required this.platform,
    this.artifacts = const {},
    this.manifest = const {},
  });

  factory ReleaseRecord.fromJson(Map<String, Object?> json) => ReleaseRecord(
    id: json['id'] as String,
    appId: json['app_id'] as String,
    version: json['version'] as String,
    createdAt: json['created_at'] as String? ?? '',
    flutterVersion: json['flutter_version'] as String?,
    platform: AppPlatform.parse(json['platform'] as String),
    artifacts: {
      for (final e
          in (json['artifacts'] as Map<String, Object?>? ?? {}).entries)
        Arch.parse(e.key): ReleaseArtifact.fromJson(
          e.value! as Map<String, Object?>,
        ),
    },
    manifest: json['manifest'] as Map<String, Object?>? ?? const {},
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'app_id': appId,
    'version': version,
    'platform': platform.wireName,
    'created_at': createdAt,
    if (flutterVersion != null) 'flutter_version': flutterVersion,
    'artifacts': {
      for (final e in artifacts.entries) e.key.wireName: e.value.toJson(),
    },
    'manifest': manifest,
  };
}

class PatchArtifact {
  final int deltaSize;
  final String hash;
  final String baseHash;
  final String signature;
  final String deltaSha256;

  const PatchArtifact({
    required this.deltaSize,
    required this.hash,
    required this.baseHash,
    required this.signature,
    required this.deltaSha256,
  });

  factory PatchArtifact.fromJson(Map<String, Object?> json) => PatchArtifact(
    deltaSize: json['delta_size'] as int,
    hash: json['hash'] as String,
    baseHash: json['base_hash'] as String,
    signature: json['signature'] as String,
    deltaSha256: json['delta_sha256'] as String,
  );

  Map<String, Object?> toJson() => {
    'hash': hash,
    'base_hash': baseHash,
    'signature': signature,
    'delta_sha256': deltaSha256,
    'delta_size': deltaSize,
  };
}

class PatchRecord {
  final int number;
  final bool isCritical;
  final double rolloutPercentage;
  final String id;
  final String channel;
  final String? notes;
  final String createdAt;
  final String releaseId;
  final String? statusReason;
  final PatchStatus status;
  final Map<Arch, PatchArtifact> artifacts;
  final Map<PatchEventType, int> stats;

  const PatchRecord({
    required this.number,
    this.isCritical = false,
    this.rolloutPercentage = 100,
    required this.id,
    required this.channel,
    this.notes,
    required this.createdAt,
    required this.releaseId,
    this.statusReason,
    this.status = PatchStatus.draft,
    this.artifacts = const {},
    this.stats = const {},
  });

  factory PatchRecord.fromJson(Map<String, Object?> json) => PatchRecord(
    number: json['number'] as int,
    isCritical: json['is_critical'] as bool? ?? false,
    rolloutPercentage: (json['rollout_percentage'] as num? ?? 100).toDouble(),
    id: json['id'] as String,
    channel: json['channel'] as String? ?? 'stable',
    notes: json['notes'] as String?,
    createdAt: json['created_at'] as String? ?? '',
    releaseId: json['release_id'] as String,
    statusReason: json['status_reason'] as String?,
    status: PatchStatus.parse(json['status'] as String? ?? 'draft'),
    artifacts: {
      for (final e
          in (json['artifacts'] as Map<String, Object?>? ?? {}).entries)
        Arch.parse(e.key): PatchArtifact.fromJson(
          e.value! as Map<String, Object?>,
        ),
    },
    stats: {
      for (final e in (json['stats'] as Map<String, Object?>? ?? {}).entries)
        PatchEventType.parse(e.key): e.value! as int,
    },
  );

  int get launches =>
      (stats[PatchEventType.launchSuccess] ?? 0) +
      (stats[PatchEventType.bootFailure] ?? 0);

  double get failureRate =>
      launches == 0 ? 0 : (stats[PatchEventType.bootFailure] ?? 0) / launches;

  PatchRecord copyWith({
    bool? isCritical,
    double? rolloutPercentage,
    String? channel,
    String? notes,
    String? statusReason,
    PatchStatus? status,
    Map<Arch, PatchArtifact>? artifacts,
    Map<PatchEventType, int>? stats,
  }) => PatchRecord(
    number: number,
    isCritical: isCritical ?? this.isCritical,
    rolloutPercentage: rolloutPercentage ?? this.rolloutPercentage,
    id: id,
    channel: channel ?? this.channel,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    releaseId: releaseId,
    statusReason: statusReason ?? this.statusReason,
    status: status ?? this.status,
    artifacts: artifacts ?? this.artifacts,
    stats: stats ?? this.stats,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'release_id': releaseId,
    'number': number,
    'channel': channel,
    'status': status.wireName,
    if (statusReason != null) 'status_reason': statusReason,
    'rollout_percentage': rolloutPercentage,
    'is_critical': isCritical,
    if (notes != null) 'notes': notes,
    'created_at': createdAt,
    'artifacts': {
      for (final e in artifacts.entries) e.key.wireName: e.value.toJson(),
    },
    'stats': {for (final e in stats.entries) e.key.wireName: e.value},
    'launches': launches,
    'failure_rate': failureRate,
  };
}
