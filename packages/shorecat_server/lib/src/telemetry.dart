import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorecat_core/shorecat_core.dart';

class DeviceSeen {
  final int? patch;
  final int lastSeen;
  final String arch;
  final String release;

  const DeviceSeen({
    this.patch,
    required this.lastSeen,
    required this.arch,
    required this.release,
  });

  factory DeviceSeen.fromJson(Map<String, Object?> json) => DeviceSeen(
    patch: json['patch'] as int?,
    lastSeen: json['last_seen'] as int,
    arch: json['arch'] as String,
    release: json['release'] as String,
  );

  Map<String, Object?> toJson() => {
    'release': release,
    'patch': patch,
    'arch': arch,
    'last_seen': lastSeen,
  };
}

/// Hourly event counts and the last state of each device, per app. Checks
/// arrive far more often than anything else, so this lives apart from
/// `db.json` and is written at most every few seconds.
class Telemetry {
  final File file;
  final Map<String, Map<int, Map<String, int>>> hourly;
  final Map<String, Map<String, DeviceSeen>> devices;
  Timer? _pending;

  Telemetry._(this.file, this.hourly, this.devices);

  static const checkType = 'check';
  static const retention = Duration(days: 31);
  static const flushDelay = Duration(seconds: 3);

  static Future<Telemetry> open(Directory root) async {
    final file = File(p.join(root.path, 'telemetry.json'));
    if (!await file.exists()) return Telemetry._(file, {}, {});
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return Telemetry._(
      file,
      {
        for (final app
            in (json['hourly'] as Map<String, Object?>? ?? {}).entries)
          app.key: {
            for (final hour in (app.value! as Map<String, Object?>).entries)
              int.parse(hour.key): {
                for (final c in (hour.value! as Map<String, Object?>).entries)
                  c.key: c.value! as int,
              },
          },
      },
      {
        for (final app
            in (json['devices'] as Map<String, Object?>? ?? {}).entries)
          app.key: {
            for (final d in (app.value! as Map<String, Object?>).entries)
              d.key: DeviceSeen.fromJson(d.value! as Map<String, Object?>),
          },
      },
    );
  }

  void recordCheck(PatchCheckRequest request, DateTime now) {
    _count(request.appId, checkType, now);
    _see(
      request.appId,
      request.clientId,
      DeviceSeen(
        patch: request.currentPatchNumber,
        lastSeen: now.millisecondsSinceEpoch,
        arch: request.arch.wireName,
        release: request.releaseVersion,
      ),
    );
    _scheduleFlush();
  }

  void recordEvent(PatchEvent event, DateTime now) {
    final sent = DateTime.fromMillisecondsSinceEpoch(event.timestamp);
    final isPlausible =
        sent.isAfter(now.subtract(retention)) &&
        sent.isBefore(now.add(const Duration(minutes: 5)));
    final at = isPlausible ? sent : now;
    _count(event.appId, event.type.wireName, at);
    final previous = devices[event.appId]?[event.clientId];
    if (event.type == PatchEventType.launchSuccess &&
        (previous == null || previous.lastSeen <= at.millisecondsSinceEpoch)) {
      _see(
        event.appId,
        event.clientId,
        DeviceSeen(
          patch: event.patchNumber,
          lastSeen: at.millisecondsSinceEpoch,
          arch: event.arch.wireName,
          release: event.releaseVersion,
        ),
      );
    }
    _scheduleFlush();
  }

  Map<String, Object?> metrics(
    String appId, {
    required int hours,
    required DateTime now,
  }) {
    final end = _hourOf(now);
    final start = end - (hours - 1) * Duration.millisecondsPerHour;
    final counts = hourly[appId] ?? const {};
    final totals = <String, int>{};
    final series = [
      for (var h = start; h <= end; h += Duration.millisecondsPerHour)
        {
          'hour': DateTime.fromMillisecondsSinceEpoch(
            h,
            isUtc: true,
          ).toIso8601String(),
          for (final type in _types) type: counts[h]?[type] ?? 0,
        },
    ];
    for (final bucket in series) {
      for (final type in _types) {
        totals[type] = (totals[type] ?? 0) + (bucket[type]! as int);
      }
    }

    final cutoff =
        now.millisecondsSinceEpoch - hours * Duration.millisecondsPerHour;
    final all = devices[appId]?.values ?? const <DeviceSeen>[];
    final active = all.where((d) => d.lastSeen >= cutoff).toList();
    final adoption = <String, int>{};
    final archs = <String, int>{};
    for (final d in active) {
      final key = '${d.release}#${d.patch ?? 0}';
      adoption[key] = (adoption[key] ?? 0) + 1;
      archs[d.arch] = (archs[d.arch] ?? 0) + 1;
    }
    final launches = totals['launch_success']! + totals['boot_failure']!;
    return {
      'window_hours': hours,
      'generated_at': now.toUtc().toIso8601String(),
      'series': series,
      'totals': totals,
      'devices': {'active': active.length, 'total': all.length},
      'crash_free_rate': launches == 0
          ? null
          : totals['launch_success']! / launches,
      'adoption': [
        for (final e in adoption.entries)
          {
            'release': e.key.split('#').first,
            'patch': int.parse(e.key.split('#').last) == 0
                ? null
                : int.parse(e.key.split('#').last),
            'devices': e.value,
          },
      ]..sort((a, b) => (b['devices']! as int).compareTo(a['devices']! as int)),
      'archs': [
        for (final e in archs.entries) {'arch': e.key, 'devices': e.value},
      ],
    };
  }

  Future<void> flush() async {
    _pending?.cancel();
    _pending = null;
    final cutoff = _hourOf(DateTime.now().subtract(retention));
    for (final app in hourly.values) {
      app.removeWhere((hour, _) => hour < cutoff);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'hourly': {
          for (final app in hourly.entries)
            app.key: {for (final h in app.value.entries) '${h.key}': h.value},
        },
        'devices': {
          for (final app in devices.entries)
            app.key: {
              for (final d in app.value.entries) d.key: d.value.toJson(),
            },
        },
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  static const _types = [
    checkType,
    'download',
    'install_success',
    'install_failure',
    'launch_success',
    'boot_failure',
    'uninstall',
  ];

  void _count(String appId, String type, DateTime at) {
    final bucket = (hourly[appId] ??= {})[_hourOf(at)] ??= {};
    bucket[type] = (bucket[type] ?? 0) + 1;
  }

  void _see(String appId, String clientId, DeviceSeen seen) =>
      (devices[appId] ??= {})[clientId] = seen;

  void _scheduleFlush() =>
      _pending ??= Timer(flushDelay, () => unawaited(flush()));

  static int _hourOf(DateTime at) {
    final ms = at.millisecondsSinceEpoch;
    return ms - ms % Duration.millisecondsPerHour;
  }
}
