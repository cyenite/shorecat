typedef Json = Map<String, Object?>;

/// Patch lifecycle, in the order a patch moves through it.
enum PatchStatus {
  draft('draft', 'Draft'),
  active('active', 'Live'),
  paused('paused', 'Paused'),
  rolledBack('rolled_back', 'Rolled back');

  final String wireName;
  final String label;

  const PatchStatus(this.wireName, this.label);

  static PatchStatus parse(String? value) =>
      values.firstWhere((s) => s.wireName == value, orElse: () => draft);
}

/// Device events, in the order a patch's life on a device goes.
enum EventKind {
  check('check', 'Checks'),
  download('download', 'Downloads'),
  installSuccess('install_success', 'Installs'),
  installFailure('install_failure', 'Install failures'),
  launchSuccess('launch_success', 'Launches'),
  bootFailure('boot_failure', 'Boot failures'),
  uninstall('uninstall', 'Uninstalls');

  final String wireName;
  final String label;

  const EventKind(this.wireName, this.label);

  static EventKind? parse(String? value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }

  bool get isFailure => this == installFailure || this == bootFailure;
}

class HealthGate {
  final int minLaunches;
  final bool isEnabled;
  final double maxFailureRate;

  const HealthGate({
    required this.minLaunches,
    required this.isEnabled,
    required this.maxFailureRate,
  });

  factory HealthGate.fromJson(Json json) => HealthGate(
    minLaunches: json['min_launches'] as int? ?? 20,
    isEnabled: json['enabled'] as bool? ?? true,
    maxFailureRate: (json['max_failure_rate'] as num? ?? .05).toDouble(),
  );

  Json toJson() => {
    'enabled': isEnabled,
    'min_launches': minLaunches,
    'max_failure_rate': maxFailureRate,
  };
}

class PatchArtifact {
  final int deltaSize;
  final String arch;
  final String hash;

  const PatchArtifact({
    required this.deltaSize,
    required this.arch,
    required this.hash,
  });
}

class Patch {
  final int number;
  final bool isCritical;
  final double failureRate;
  final double rolloutPercentage;
  final String id;
  final String channel;
  final String? notes;
  final String createdAt;
  final String? statusReason;
  final PatchStatus status;
  final List<PatchArtifact> artifacts;
  final Map<String, int> stats;

  const Patch({
    required this.number,
    required this.isCritical,
    required this.failureRate,
    required this.rolloutPercentage,
    required this.id,
    required this.channel,
    this.notes,
    required this.createdAt,
    this.statusReason,
    required this.status,
    this.artifacts = const [],
    this.stats = const {},
  });

  factory Patch.fromJson(Json json) => Patch(
    number: json['number']! as int,
    isCritical: json['is_critical'] as bool? ?? false,
    failureRate: (json['failure_rate'] as num? ?? 0).toDouble(),
    rolloutPercentage: (json['rollout_percentage'] as num? ?? 100).toDouble(),
    id: json['id']! as String,
    channel: json['channel'] as String? ?? 'stable',
    notes: json['notes'] as String?,
    createdAt: json['created_at'] as String? ?? '',
    statusReason: json['status_reason'] as String?,
    status: PatchStatus.parse(json['status'] as String?),
    artifacts: [
      for (final e in (json['artifacts'] as Json? ?? {}).entries)
        PatchArtifact(
          deltaSize: (e.value! as Json)['delta_size'] as int? ?? 0,
          arch: e.key,
          hash: (e.value! as Json)['hash'] as String? ?? '',
        ),
    ],
    stats: {
      for (final e in (json['stats'] as Json? ?? {}).entries)
        e.key: e.value! as int,
    },
  );

  int stat(EventKind kind) => stats[kind.wireName] ?? 0;

  int get launches =>
      stat(EventKind.launchSuccess) + stat(EventKind.bootFailure);
}

class Release {
  final String id;
  final String version;
  final String platform;
  final String? flutterVersion;
  final Map<String, int> artifactSizes;
  final List<Patch> patches;

  const Release({
    required this.id,
    required this.version,
    required this.platform,
    this.flutterVersion,
    this.artifactSizes = const {},
    this.patches = const [],
  });

  factory Release.fromJson(Json json) => Release(
    id: json['id']! as String,
    version: json['version']! as String,
    platform: json['platform'] as String? ?? 'android',
    flutterVersion: json['flutter_version'] as String?,
    artifactSizes: {
      for (final e in (json['artifacts'] as Json? ?? {}).entries)
        e.key: (e.value! as Json)['size'] as int? ?? 0,
    },
    patches: [
      for (final p in json['patches'] as List? ?? const [])
        Patch.fromJson(p as Json),
    ],
  );
}

class AppDetail {
  final String id;
  final String name;
  final HealthGate healthGate;
  final List<String> publicKeys;
  final List<Release> releases;

  const AppDetail({
    required this.id,
    required this.name,
    required this.healthGate,
    this.publicKeys = const [],
    this.releases = const [],
  });

  factory AppDetail.fromJson(Json json) => AppDetail(
    id: json['id']! as String,
    name: json['name'] as String? ?? json['id']! as String,
    healthGate: HealthGate.fromJson(json['health_gate'] as Json? ?? const {}),
    publicKeys: [
      for (final k in json['public_keys'] as List? ?? const []) k as String,
    ],
    releases: [
      for (final r in json['releases'] as List? ?? const [])
        Release.fromJson(r as Json),
    ],
  );

  Iterable<Patch> get patches => releases.expand((r) => r.patches);
}

class Bucket {
  final DateTime hour;
  final Map<EventKind, int> counts;

  const Bucket({required this.hour, this.counts = const {}});

  int operator [](EventKind kind) => counts[kind] ?? 0;
}

class Adoption {
  final int? patch;
  final int devices;
  final String release;

  const Adoption({this.patch, required this.devices, required this.release});

  String get label => patch == null ? '$release base' : '$release #$patch';
}

class Metrics {
  final int windowHours;
  final int activeDevices;
  final int knownDevices;
  final double? crashFreeRate;
  final List<Bucket> series;
  final List<Adoption> adoption;
  final Map<EventKind, int> totals;
  final Map<String, int> archs;

  const Metrics({
    required this.windowHours,
    required this.activeDevices,
    required this.knownDevices,
    this.crashFreeRate,
    this.series = const [],
    this.adoption = const [],
    this.totals = const {},
    this.archs = const {},
  });

  factory Metrics.fromJson(Json json) {
    Map<EventKind, int> counts(Json raw) => {
      for (final kind in EventKind.values)
        kind: raw[kind.wireName] as int? ?? 0,
    };
    final devices = json['devices'] as Json? ?? const {};
    return Metrics(
      windowHours: json['window_hours'] as int? ?? 24,
      activeDevices: devices['active'] as int? ?? 0,
      knownDevices: devices['total'] as int? ?? 0,
      crashFreeRate: (json['crash_free_rate'] as num?)?.toDouble(),
      series: [
        for (final b in json['series'] as List? ?? const [])
          Bucket(
            hour: DateTime.parse((b as Json)['hour']! as String).toLocal(),
            counts: counts(b),
          ),
      ],
      adoption: [
        for (final a in json['adoption'] as List? ?? const [])
          Adoption(
            patch: (a as Json)['patch'] as int?,
            devices: a['devices']! as int,
            release: a['release']! as String,
          ),
      ],
      totals: counts(json['totals'] as Json? ?? const {}),
      archs: {
        for (final a in json['archs'] as List? ?? const [])
          (a as Json)['arch']! as String: a['devices']! as int,
      },
    );
  }

  int operator [](EventKind kind) => totals[kind] ?? 0;
}

class DeviceEvent {
  final int patchNumber;
  final String arch;
  final String clientId;
  final String? message;
  final String releaseVersion;
  final DateTime at;
  final EventKind? kind;

  const DeviceEvent({
    required this.patchNumber,
    required this.arch,
    required this.clientId,
    this.message,
    required this.releaseVersion,
    required this.at,
    this.kind,
  });

  factory DeviceEvent.fromJson(Json json) => DeviceEvent(
    patchNumber: json['patch_number'] as int? ?? 0,
    arch: json['arch'] as String? ?? '',
    clientId: json['client_id'] as String? ?? '',
    message: json['message'] as String?,
    releaseVersion: json['release_version'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
    kind: EventKind.parse(json['type'] as String?),
  );
}
