import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../shorecat_server.dart';

void addServerOptions(ArgParser parser) {
  parser
    ..addOption('data', help: 'Storage directory (SHORECAT_DATA).')
    ..addOption('host', help: 'Interface to bind (SHORECAT_HOST).')
    ..addOption('port', help: 'Listen port (SHORECAT_PORT).')
    ..addOption(
      'public-url',
      help: 'Public download origin (SHORECAT_PUBLIC_URL).',
    )
    ..addOption('dashboard', help: 'Built dashboard (SHORECAT_DASHBOARD).')
    ..addFlag(
      'health-check',
      negatable: false,
      help: 'Probe the local health endpoint and exit.',
    )
    ..addFlag(
      'show-admin-token',
      negatable: false,
      help: 'Explicitly print the admin token at startup.',
    );
}

Future<int> runServer(ArgResults args) async {
  final env = Platform.environment;
  String value(String name, String variable, String fallback) =>
      args.option(name) ?? env[variable] ?? fallback;
  final rawPort = value('port', 'SHORECAT_PORT', '8080');
  final port = int.tryParse(rawPort);
  if (port == null || port < 0 || port > 65535) {
    throw FormatException('Port must be between 0 and 65535: $rawPort');
  }
  final host = value('host', 'SHORECAT_HOST', '127.0.0.1');
  if (args.flag('health-check')) return _healthCheck(host, port);

  final token = env['SHORECAT_ADMIN_TOKEN']?.trim();
  final publicUrl = value('public-url', 'SHORECAT_PUBLIC_URL', '');
  final dashboard = value('dashboard', 'SHORECAT_DASHBOARD', '');
  if (publicUrl.isNotEmpty) {
    final uri = Uri.tryParse(publicUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Public URL must be an HTTP(S) origin.');
    }
  }
  if (dashboard.isNotEmpty &&
      !File(p.join(dashboard, 'index.html')).existsSync()) {
    throw const FormatException('Dashboard directory must contain index.html.');
  }
  final data = Directory(value('data', 'SHORECAT_DATA', 'shorecat-data'));
  final server = await ShorecatServer.start(
    dataDir: data,
    port: port,
    host: host,
    publicUrl: publicUrl.isEmpty ? null : publicUrl,
    adminToken: token == null || token.isEmpty ? null : token,
    dashboardDir: dashboard.isEmpty ? null : Directory(dashboard),
  );
  final done = Completer<void>();
  final signals = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  final subscriptions = [
    for (final signal in signals)
      signal.watch().listen((_) {
        if (!done.isCompleted) done.complete();
      }),
  ];
  stdout
    ..writeln('shorecat server listening on ${server.url}')
    ..writeln('Dashboard: ${publicUrl.isEmpty ? server.url : publicUrl}/');
  if (args.flag('show-admin-token')) {
    stdout.writeln('Admin token: ${server.adminToken}');
  } else {
    stdout.writeln(
      token == null || token.isEmpty
          ? 'Admin token stored in ${p.join(data.path, 'admin-token')}'
          : 'Admin token configured through SHORECAT_ADMIN_TOKEN.',
    );
  }
  try {
    await done.future;
    await server.close();
    return 0;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

Future<int> _healthCheck(String host, int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  final address = switch (host) {
    '0.0.0.0' => '127.0.0.1',
    '::' => '::1',
    _ => host,
  };
  try {
    final request = await client.getUrl(
      Uri(scheme: 'http', host: address, port: port, path: '/healthz'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>().timeout(const Duration(seconds: 3));
    return response.statusCode == HttpStatus.ok ? 0 : 1;
  } on Exception {
    return 1;
  } finally {
    client.close(force: true);
  }
}
