import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorecat_core/shorecat_core.dart';
import 'package:shorecat_server/shorecat_server.dart';

import '../log.dart';
import 'base.dart';

class DiffCommand extends ShorecatCommand {
  @override
  final name = 'diff';

  @override
  final description =
      'Create a delta between two files: shorecat diff <base> <target> -o <delta>.';

  DiffCommand() {
    argParser
      ..addOption('output', abbr: 'o', mandatory: true)
      ..addOption(
        'compression',
        allowed: ['auto', for (final c in Compression.values) c.name],
        defaultsTo: 'auto',
      );
  }

  @override
  Future<int> run() async {
    if (rest.length != 2) {
      throw UsageException('Need <base> and <target>', usage);
    }
    final base = await File(rest[0]).readAsBytes();
    final target = await File(rest[1]).readAsBytes();
    final watch = Stopwatch()..start();
    final compression = option('compression')!;
    final delta = compression == 'auto'
        ? Delta.createSmallest(base, target)
        : Delta.create(
            base,
            target,
            compression: Compression.values.byName(compression),
          );
    await File(option('output')!).writeAsBytes(delta);
    final header = DeltaHeader.parse(delta);
    Log.success(
      '${formatBytes(base.length)} -> ${formatBytes(target.length)}: '
      '${formatBytes(delta.length)} delta (${header.compression.name}, '
      '${watch.elapsedMilliseconds} ms)',
    );
    return 0;
  }
}

class ApplyCommand extends ShorecatCommand {
  @override
  final name = 'apply';

  @override
  final description =
      'Rebuild a file from a base and a delta: shorecat apply <base> <delta> -o <out>.';

  ApplyCommand() {
    argParser.addOption('output', abbr: 'o', mandatory: true);
  }

  @override
  Future<int> run() async {
    if (rest.length != 2) {
      throw UsageException('Need <base> and <delta>', usage);
    }
    final target = Delta.apply(
      await File(rest[0]).readAsBytes(),
      await File(rest[1]).readAsBytes(),
    );
    await File(option('output')!).writeAsBytes(target);
    Log.success(
      'Wrote ${formatBytes(target.length)}, sha256 ${sha256Hex(target)} verified.',
    );
    return 0;
  }
}

class InspectCommand extends ShorecatCommand {
  @override
  final name = 'inspect';

  @override
  final description = 'Print the header of a shorecat delta.';

  @override
  Future<int> run() async {
    if (rest.length != 1) throw UsageException('Need <delta>', usage);
    final bytes = await File(rest.single).readAsBytes();
    final h = DeltaHeader.parse(bytes);
    Log.info('''format       ${DeltaHeader.magic} v${DeltaHeader.version}
compression  ${h.compression.name}
base         ${formatBytes(h.baseLength)}  ${h.baseSha256}
target       ${formatBytes(h.targetLength)}  ${h.targetSha256}
sections     control ${formatBytes(h.controlLength)}, diff ${formatBytes(h.diffLength)}, extra ${formatBytes(h.extraLength)}
total        ${formatBytes(bytes.length)}''');
    return 0;
  }
}

class ServerCommand extends ShorecatCommand {
  @override
  final name = 'server';

  @override
  final description = 'Run a shorecat server.';

  ServerCommand() {
    argParser
      ..addOption('data', defaultsTo: 'shorecat-data')
      ..addOption('host', defaultsTo: '127.0.0.1')
      ..addOption('port', defaultsTo: '8080')
      ..addOption(
        'public-url',
        help: 'Base URL devices use to download patches.',
      )
      ..addOption(
        'dashboard',
        help: 'Built dashboard (flutter build web) to serve at /.',
      );
  }

  @override
  Future<int> run() async {
    final server = await ShorecatServer.start(
      dataDir: Directory(option('data')!),
      port: intArg(option('port')!, 'Port'),
      host: option('host')!,
      publicUrl: option('public-url'),
      adminToken: Platform.environment['SHORECAT_ADMIN_TOKEN'],
      dashboardDir: option('dashboard') == null
          ? null
          : Directory(option('dashboard')!),
    );
    Log.success('shorecat server on ${server.url}');
    Log.detail('Dashboard:   ${server.url}/');
    Log.detail('Admin token: ${server.adminToken}');
    Log.detail(
      'Log in with: shorecat login --server ${server.url} --token ${server.adminToken}',
    );
    final done = Completer<int>();
    ProcessSignal.sigint.watch().listen((_) async {
      await server.close();
      if (!done.isCompleted) done.complete(0);
    });
    return done.future;
  }
}
