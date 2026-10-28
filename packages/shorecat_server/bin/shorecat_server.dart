import 'dart:io';

import 'package:args/args.dart';
import 'package:shorecat_server/shorecat_server.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('data', defaultsTo: 'shorecat-data', help: 'Storage directory.')
    ..addOption('host', defaultsTo: '127.0.0.1', help: 'Interface to bind.')
    ..addOption('port', defaultsTo: '8080')
    ..addOption(
      'public-url',
      help: 'Base URL devices use to download patches (behind a proxy).',
    )
    ..addOption(
      'dashboard',
      help: 'Built dashboard (flutter build web) to serve at /.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  if (args.flag('help')) {
    stdout.writeln('Usage: shorecat_server [options]\n\n${parser.usage}');
    return;
  }

  final server = await ShorecatServer.start(
    dataDir: Directory(args.option('data')!),
    port: int.parse(args.option('port')!),
    host: args.option('host')!,
    publicUrl: args.option('public-url'),
    adminToken: Platform.environment['SHORECAT_ADMIN_TOKEN'],
    dashboardDir: args.option('dashboard') == null
        ? null
        : Directory(args.option('dashboard')!),
  );
  stdout
    ..writeln('shorecat server listening on ${server.url}')
    ..writeln('Dashboard: ${server.url}/')
    ..writeln('Admin token: ${server.adminToken}');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}
