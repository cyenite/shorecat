import 'dart:convert';
import 'dart:io';

/// Release level boot pointers, persisted as `pointers.json`.
///
/// This file is the contract with the native boot hook
/// (`ShorecatBoot.kt`), which reads it before the Flutter engine starts.
/// Field names are snake_case on disk for that reason.
class Pointers {
  final int? running;
  final int? nextBoot;
  final int? lastBooted;
  final int? currentlyBooting;
  final int bootAttempts;
  final int maxBootAttempts;
  final int? bootStartedAt;
  final String? releaseVersion;

  const Pointers({
    this.running,
    this.nextBoot,
    this.lastBooted,
    this.currentlyBooting,
    this.bootAttempts = 0,
    this.maxBootAttempts = 1,
    this.bootStartedAt,
    this.releaseVersion,
  });

  factory Pointers.fromJson(Map<String, Object?> json) => Pointers(
    running: json['running'] as int?,
    nextBoot: json['next_boot'] as int?,
    lastBooted: json['last_booted'] as int?,
    currentlyBooting: json['currently_booting'] as int?,
    bootAttempts: json['boot_attempts'] as int? ?? 0,
    maxBootAttempts: json['max_boot_attempts'] as int? ?? 1,
    bootStartedAt: json['boot_started_at'] as int?,
    releaseVersion: json['release_version'] as String?,
  );

  Pointers copyWith({
    Object? running = _keep,
    Object? nextBoot = _keep,
    Object? lastBooted = _keep,
    Object? currentlyBooting = _keep,
    int? bootAttempts,
    int? maxBootAttempts,
    Object? bootStartedAt = _keep,
    String? releaseVersion,
  }) => Pointers(
    running: running == _keep ? this.running : running as int?,
    nextBoot: nextBoot == _keep ? this.nextBoot : nextBoot as int?,
    lastBooted: lastBooted == _keep ? this.lastBooted : lastBooted as int?,
    currentlyBooting: currentlyBooting == _keep
        ? this.currentlyBooting
        : currentlyBooting as int?,
    bootAttempts: bootAttempts ?? this.bootAttempts,
    maxBootAttempts: maxBootAttempts ?? this.maxBootAttempts,
    bootStartedAt: bootStartedAt == _keep
        ? this.bootStartedAt
        : bootStartedAt as int?,
    releaseVersion: releaseVersion ?? this.releaseVersion,
  );

  Map<String, Object?> toJson() => {
    'release_version': releaseVersion,
    'next_boot': nextBoot,
    'last_booted': lastBooted,
    'currently_booting': currentlyBooting,
    'running': running,
    'boot_attempts': bootAttempts,
    'max_boot_attempts': maxBootAttempts,
    'boot_started_at': bootStartedAt,
  };
}

const _keep = Object();

/// Per patch lifecycle. A `bad` patch is a tombstone: it is never retried
/// within the release, even if the server keeps offering it.
enum PatchState {
  downloading('downloading'),
  installed('installed'),
  bad('bad');

  final String wireName;

  const PatchState(this.wireName);

  static PatchState parse(String value) => values.firstWhere(
    (s) => s.wireName == value,
    orElse: () => PatchState.bad,
  );
}

enum BadReason {
  bootCrash('boot_crash'),
  hashMismatch('hash_mismatch'),
  installFailed('install_failed'),
  launchFailure('launch_failure');

  final String wireName;

  const BadReason(this.wireName);
}

class PatchRecord {
  final int number;
  final String hash;
  final String? reason;
  final PatchState state;

  const PatchRecord({
    required this.number,
    required this.hash,
    this.reason,
    required this.state,
  });

  factory PatchRecord.fromJson(Map<String, Object?> json) => PatchRecord(
    number: json['number'] as int,
    hash: json['hash'] as String? ?? '',
    reason: json['reason'] as String?,
    state: PatchState.parse(json['state'] as String? ?? 'bad'),
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'state': state.wireName,
    'hash': hash,
    if (reason != null) 'reason': reason,
  };
}

var _writes = 0;

/// Writes JSON next to the target and renames it into place, so a reader on
/// the other side of the native boundary never sees a partial file.
Future<void> writeJsonAtomic(File file, Object? json) async {
  await file.parent.create(recursive: true);
  // A unique name per write: two writers sharing one temp file race, and the
  // loser's rename fails because the winner already moved it.
  final tmp = File('${file.path}.$pid-${_writes++}.tmp');
  await tmp.writeAsString(jsonEncode(json), flush: true);
  await tmp.rename(file.path);
}

Future<Map<String, Object?>?> readJson(File file) async {
  if (!await file.exists()) return null;
  try {
    final json = jsonDecode(await file.readAsString());
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}
