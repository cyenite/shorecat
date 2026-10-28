/// Self-hostable shorecat code push server.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'src/api.dart';
import 'src/store.dart';
import 'src/telemetry.dart';

export 'src/api.dart' show ShorecatApi;
export 'src/models.dart';
export 'src/store.dart' show Store;
export 'src/telemetry.dart' show Telemetry;

class ShorecatServer {
  final HttpServer http;
  final String adminToken;
  final Telemetry telemetry;

  ShorecatServer._(this.http, this.adminToken, this.telemetry);

  Uri get url => Uri.parse('http://${http.address.host}:${http.port}');

  static Future<ShorecatServer> start({
    required Directory dataDir,
    int port = 8080,
    bool isQuiet = false,
    Object host = '127.0.0.1',
    String? publicUrl,
    String? adminToken,
    Directory? dashboardDir,
  }) async {
    final store = await Store.open(dataDir);
    final telemetry = await Telemetry.open(dataDir);
    final token = adminToken ?? await _loadOrCreateToken(dataDir);
    final api = ShorecatApi(
      store: store,
      adminToken: token,
      publicUrl: publicUrl?.replaceAll(RegExp(r'/+$'), ''),
      dashboardDir: dashboardDir,
      telemetry: telemetry,
    );
    var pipeline = const Pipeline();
    if (!isQuiet) pipeline = pipeline.addMiddleware(logRequests());
    final server = await io.serve(pipeline.addHandler(api.handler), host, port);
    server.autoCompress = true;
    return ShorecatServer._(server, token, telemetry);
  }

  Future<void> close() async {
    await http.close(force: true);
    await telemetry.flush();
  }

  static Future<String> _loadOrCreateToken(Directory dataDir) async {
    final file = File(p.join(dataDir.path, 'admin-token'));
    if (await file.exists()) return (await file.readAsString()).trim();
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    await file.writeAsString(token);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
    return token;
  }
}
