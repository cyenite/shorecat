import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shorecat_core/shorecat_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory data;
  final children = <Process>[];

  setUp(() async {
    data = await Directory.systemTemp.createTemp('shorecat-runtime-');
  });
  tearDown(() async {
    for (final child in children) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    children.clear();
    await data.delete(recursive: true);
  });

  Future<_RunningServer> start(
    String entry, {
    String token = 'runtime-secret',
    List<String> arguments = const [],
  }) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        entry,
        if (entry.contains('shorecat_cli')) 'server',
        '--port',
        '0',
        ...arguments,
      ],
      environment: {
        'SHORECAT_DATA': data.path,
        'SHORECAT_PORT': 'invalid-env-port',
        'SHORECAT_ADMIN_TOKEN': token,
      },
    );
    children.add(process);
    final ready = Completer<Uri>();
    final output = StringBuffer();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          output.writeln(line);
          const prefix = 'shorecat server listening on ';
          if (line.startsWith(prefix) && !ready.isCompleted) {
            ready.complete(Uri.parse(line.substring(prefix.length)));
          }
        });
    process.stderr.transform(utf8.decoder).listen(output.write);
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Server exited $code: $output'));
        }
      }),
    );
    return _RunningServer(
      process,
      await ready.future.timeout(const Duration(seconds: 20)),
      output,
    );
  }

  for (final entry in [
    'bin/shorecat_server.dart',
    if (File('../shorecat_cli/bin/shorecat.dart').existsSync())
      '../shorecat_cli/bin/shorecat.dart',
  ]) {
    test(
      '$entry flushes telemetry on SIGTERM without logging credentials',
      () async {
        final server = await start(entry);
        final probe = await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/shorecat_server.dart',
          '--health-check',
          '--port',
          '${server.url.port}',
        ]);
        expect(probe.exitCode, 0, reason: '${probe.stderr}');
        final key = await PatchKeyPair.generate();
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final create = await client.postUrl(server.url.resolve('/api/v1/apps'));
        create.headers.set('authorization', 'Bearer runtime-secret');
        create.write(
          jsonEncode({
            'id': 'demo',
            'public_keys': [key.publicKey.encode()],
          }),
        );
        final created = await create.close();
        await created.drain<void>();
        expect(created.statusCode, 201);

        final check = await client.postUrl(
          server.url.resolve('/api/v1/patches/check'),
        );
        check.write(
          jsonEncode(
            const PatchCheckRequest(
              arch: Arch.arm64,
              appId: 'demo',
              channel: 'stable',
              clientId: 'runtime-device',
              releaseVersion: '1.0.0+1',
              platform: AppPlatform.android,
            ).toJson(),
          ),
        );
        final checked = await check.close();
        await checked.drain<void>();
        expect(checked.statusCode, 200);
        client.close(force: true);

        server.process.kill(ProcessSignal.sigterm);
        expect(
          await server.process.exitCode.timeout(const Duration(seconds: 10)),
          0,
        );
        expect(server.output.toString(), isNot(contains('runtime-secret')));
        final telemetry =
            jsonDecode(await File('${data.path}/telemetry.json').readAsString())
                as Map;
        expect(
          (telemetry['devices'] as Map)['demo'],
          contains('runtime-device'),
        );
      },
      skip: Platform.isWindows,
    );
  }

  test('generated credentials persist across SIGINT and restart', () async {
    final first = await start('bin/shorecat_server.dart', token: '');
    final file = File('${data.path}/admin-token');
    final token = await file.readAsString();
    expect(token.length, greaterThanOrEqualTo(32));
    first.process.kill(ProcessSignal.sigint);
    expect(
      await first.process.exitCode.timeout(const Duration(seconds: 10)),
      0,
    );
    expect(first.output.toString(), isNot(contains(token)));

    final second = await start(
      'bin/shorecat_server.dart',
      token: '',
      arguments: ['--show-admin-token'],
    );
    expect(await file.readAsString(), token);
    second.process.kill(ProcessSignal.sigint);
    expect(
      await second.process.exitCode.timeout(const Duration(seconds: 10)),
      0,
    );
    expect(second.output.toString(), contains('Admin token: $token'));
  }, skip: Platform.isWindows);

  test('health probe returns failure when nothing is listening', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/shorecat_server.dart',
      '--health-check',
      '--port',
      '$port',
    ]);
    expect(result.exitCode, 1);
  });

  test(
    'invalid container configuration fails before creating server state',
    () async {
      for (final arguments in [
        ['--port', '-1'],
        ['--public-url', 'https://updates.example.com/subpath'],
        ['--dashboard', '${data.path}/missing'],
      ]) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'bin/shorecat_server.dart', ...arguments],
          environment: {'SHORECAT_DATA': data.path},
        );
        expect(result.exitCode, 64, reason: '${result.stderr}');
        expect(File('${data.path}/admin-token').existsSync(), isFalse);
      }
    },
  );
}

class _RunningServer {
  final Uri url;
  final Process process;
  final StringBuffer output;

  const _RunningServer(this.process, this.url, this.output);
}
