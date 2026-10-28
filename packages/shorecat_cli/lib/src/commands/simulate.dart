import 'dart:convert';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:shorecat_core/shorecat_core.dart';

import '../client.dart';
import '../config.dart';
import '../log.dart';
import 'base.dart';

/// Replays plausible device traffic through the public device API, so a
/// dashboard has history to draw. It feeds real patch stats, and so the
/// health gate: point it at a demo app, not one with real users.
class SimulateCommand extends ShorecatCommand {
  @override
  final name = 'simulate';

  @override
  final description =
      'Send simulated device traffic for a demo app (fills the dashboard).';

  SimulateCommand() {
    argParser
      ..addOption('server', help: 'Defaults to base_url in shorecat.yaml.')
      ..addOption('app', help: 'Defaults to app_id in shorecat.yaml.')
      ..addOption('token', help: 'Admin token; defaults to the saved login.')
      ..addOption('devices', defaultsTo: '250')
      ..addOption('days', defaultsTo: '7')
      ..addOption('seed', defaultsTo: '42');
  }

  @override
  Future<int> run() async {
    final project = ProjectConfig.fileIn(this.project).existsSync()
        ? config
        : null;
    final server = (option('server') ?? project?.baseUrl)?.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final appId = option('app') ?? project?.appId;
    if (server == null || appId == null) {
      throw UsageException(
        'Pass --server and --app, or run inside an initialised project.',
        usage,
      );
    }
    final token = option('token') ?? user.tokenFor(server);
    if (token == null) throw CliException('Not logged in to $server');

    final random = Random(intArg(option('seed')!, 'Seed'));
    final deviceCount = intArg(option('devices')!, 'Devices');
    final days = intArg(option('days')!, 'Days');
    final admin = ShorecatClient(baseUrl: server, token: token);
    final http.Client web = http.Client();
    try {
      final releases = await admin.releases(appId, platform: 'android');
      if (releases.isEmpty) {
        throw CliException('$appId has no Android releases to simulate');
      }

      final now = DateTime.now();
      final start = now.subtract(Duration(days: days));
      var sent = 0;
      Future<void> post(String path, Map<String, Object?> body) async {
        await web.post(
          Uri.parse('$server$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        );
        sent++;
      }

      for (var i = 0; i < deviceCount; i++) {
        final release =
            releases[random.nextDouble() < 0.8
                ? releases.length - 1
                : random.nextInt(releases.length)];
        final version = release['version']! as String;
        final archRoll = random.nextDouble();
        final arch = archRoll < 0.8
            ? Arch.arm64
            : (archRoll < 0.95 ? Arch.arm32 : Arch.x64);
        final clientId = 'sim-$appId-$i';
        final patches = [
          for (final p in (release['patches']! as List).cast<Json>())
            if (p['status'] != 'draft' &&
                (p['artifacts']! as Json).containsKey(arch.wireName))
              p,
        ];

        PatchEvent event(PatchEventType type, int patch, DateTime at) =>
            PatchEvent(
              timestamp: at.millisecondsSinceEpoch,
              patchNumber: patch,
              arch: arch,
              appId: appId,
              clientId: clientId,
              releaseVersion: version,
              platform: AppPlatform.android,
              type: type,
            );

        var at = start.add(
          Duration(minutes: random.nextInt(days * 24 * 60 ~/ 2)),
        );
        int? running;
        final bad = <int>{};
        for (final patch in patches) {
          final number = patch['number']! as int;
          final isIncluded = Rollout.includes(
            percentage: (patch['rollout_percentage']! as num).toDouble(),
            clientId: clientId,
            salt: patch['id']! as String,
          );
          if (!isIncluded) continue;
          at = at.add(Duration(minutes: 30 + random.nextInt(36 * 60)));
          if (at.isAfter(now)) break;
          await post(
            '/api/v1/patches/events',
            event(PatchEventType.download, number, at).toJson(),
          );
          await post(
            '/api/v1/patches/events',
            event(PatchEventType.installSuccess, number, at).toJson(),
          );
          final stats = patch['stats']! as Json;
          final crashRate = (stats['boot_failure'] as int? ?? 0) > 0
              ? 0.45
              : 0.006;
          final launchAt = at.add(Duration(minutes: 5 + random.nextInt(240)));
          if (launchAt.isAfter(now)) continue;
          if (random.nextDouble() < crashRate) {
            bad.add(number);
            await post(
              '/api/v1/patches/events',
              event(PatchEventType.bootFailure, number, launchAt).toJson(),
            );
          } else {
            running = number;
          }
        }

        for (
          var t = at;
          t.isBefore(now);
          t = t.add(Duration(minutes: 240 + random.nextInt(900)))
        ) {
          if (running != null && !bad.contains(running)) {
            await post(
              '/api/v1/patches/events',
              event(PatchEventType.launchSuccess, running, t).toJson(),
            );
          }
        }
        if (random.nextDouble() < 0.85) {
          await post(
            '/api/v1/patches/check',
            PatchCheckRequest(
              currentPatchNumber: running,
              arch: arch,
              appId: appId,
              channel: 'stable',
              clientId: clientId,
              releaseVersion: version,
              platform: AppPlatform.android,
            ).toJson(),
          );
        }
        if ((i + 1) % 50 == 0) Log.detail('${i + 1} devices, $sent requests');
      }
      Log.success(
        'Simulated $deviceCount devices over $days days ($sent requests).',
      );
      return 0;
    } finally {
      admin.close();
      web.close();
    }
  }
}
