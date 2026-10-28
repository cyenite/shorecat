import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shorecat_core/shorecat_core.dart';
import 'package:shorecat_server/shorecat_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dataDir;
  late ShorecatServer server;
  late _Client admin;
  late _Client anonymous;
  late PatchKeyPair keys;
  final random = Random(7);

  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('shorecat-server-test');
    server = await ShorecatServer.start(
      dataDir: dataDir,
      port: 0,
      isQuiet: true,
      adminToken: 'secret',
    );
    admin = _Client(server.url, token: 'secret');
    anonymous = _Client(server.url);
    keys = await PatchKeyPair.generate();
  });

  tearDown(() async {
    await server.close();
    await dataDir.delete(recursive: true);
  });

  Future<String> createApp({String id = 'demo'}) async {
    final res = await admin.json('POST', '/api/v1/apps', {
      'id': id,
      'name': 'Demo',
      'public_keys': [keys.publicKey.encode()],
    });
    expect(res.status, 201, reason: '${res.body}');
    return id;
  }

  Future<Map<String, Object?>> createRelease(Uint8List base) async {
    final blob = await admin.raw('POST', '/api/v1/blobs', base);
    final sha = (blob.body as Map)['sha256'] as String;
    expect(sha, sha256Hex(base));
    final res = await admin.json('POST', '/api/v1/apps/demo/releases', {
      'version': '1.0.0+1',
      'platform': 'android',
      'artifacts': {
        'aarch64': {'sha256': sha, 'size': base.length},
      },
    });
    expect(res.status, 201, reason: '${res.body}');
    return res.body as Map<String, Object?>;
  }

  Future<int> createPatch(
    String releaseId,
    Uint8List base,
    Uint8List target, {
    double rollout = 100,
    bool publish = true,
    PatchKeyPair? signer,
  }) async {
    final created = await admin.json(
      'POST',
      '/api/v1/releases/$releaseId/patches',
      {'notes': 'fix'},
    );
    final number = (created.body as Map)['number'] as int;
    final delta = Delta.create(base, target);
    final blob = await admin.raw('POST', '/api/v1/blobs', delta);
    final signature = await (signer ?? keys).sign(
      PatchSignaturePayload(
        patchNumber: number,
        arch: Arch.arm64,
        appId: 'demo',
        targetSha256: sha256Hex(target),
        releaseVersion: '1.0.0+1',
        platform: AppPlatform.android,
      ),
    );
    final put = await admin.json(
      'PUT',
      '/api/v1/releases/$releaseId/patches/$number/artifacts/aarch64',
      {'delta_sha256': (blob.body as Map)['sha256'], 'signature': signature},
    );
    if (put.status != 200) throw StateError('${put.body}');
    if (publish) {
      final res = await admin.json(
        'POST',
        '/api/v1/releases/$releaseId/patches/$number/publish',
        {'rollout_percentage': rollout},
      );
      expect(res.status, 200, reason: '${res.body}');
    }
    return number;
  }

  Future<PatchCheckResponse> check({
    String clientId = 'device-1',
    int? current,
  }) async {
    final res = await anonymous.json(
      'POST',
      '/api/v1/patches/check',
      PatchCheckRequest(
        currentPatchNumber: current,
        arch: Arch.arm64,
        appId: 'demo',
        channel: 'stable',
        clientId: clientId,
        releaseVersion: '1.0.0+1',
        platform: AppPlatform.android,
      ).toJson(),
    );
    expect(res.status, 200);
    return PatchCheckResponse.fromJson(res.body as Map<String, Object?>);
  }

  test('admin routes need the token', () async {
    expect((await anonymous.json('GET', '/api/v1/apps')).status, 401);
    expect(
      (await _Client(
        server.url,
        token: 'wrong',
      ).json('GET', '/api/v1/apps')).status,
      401,
    );
    expect((await admin.json('GET', '/api/v1/apps')).status, 200);
  });

  test('apps must register a signing key', () async {
    final res = await admin.json('POST', '/api/v1/apps', {'id': 'nokeys'});
    expect(res.status, 400);
  });

  test('publish, check, download and rebuild a patch', () async {
    await createApp();
    final base = bytes(50000);
    final target = Uint8List.fromList([
      ...base.sublist(0, 30000),
      1,
      2,
      3,
      ...base.sublist(30000),
    ]);
    final release = await createRelease(base);
    expect((await check()).isPatchAvailable, isFalse);

    await createPatch(release['id']! as String, base, target);
    final response = await check();
    expect(response.isPatchAvailable, isTrue);
    final patch = response.patch!;
    expect(patch.number, 1);
    expect(patch.hash, sha256Hex(target));
    expect(patch.baseHash, sha256Hex(base));
    expect(patch.notes, 'fix');

    final download = await anonymous.download(Uri.parse(patch.downloadUrl));
    expect(Delta.apply(base, download), target);
    expect(
      await PatchVerifier.verify(
        signature: patch.signature,
        payload: PatchSignaturePayload(
          patchNumber: 1,
          arch: Arch.arm64,
          appId: 'demo',
          targetSha256: patch.hash,
          releaseVersion: '1.0.0+1',
          platform: AppPlatform.android,
        ),
        trustedKeys: [keys.publicKey],
      ),
      isTrue,
    );

    expect((await check(current: 1)).isPatchAvailable, isFalse);
  });

  test('ranged downloads resume from an offset', () async {
    final blob = bytes(1000);
    final sha =
        ((await admin.raw('POST', '/api/v1/blobs', blob)).body
            as Map)['sha256'];
    final part = await anonymous.download(
      server.url.replace(path: '/api/v1/blobs/$sha'),
      headers: {'range': 'bytes=600-'},
    );
    expect(part, blob.sublist(600));
  });

  test('rejects deltas signed by an unknown key', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    final stranger = await PatchKeyPair.generate();
    expect(
      () => createPatch(
        release['id']! as String,
        base,
        bytes(2000),
        signer: stranger,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects deltas built against another base', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    expect(
      () => createPatch(release['id']! as String, bytes(2000), bytes(2000)),
      throwsA(isA<StateError>()),
    );
  });

  test('draft patches are never served', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    await createPatch(
      release['id']! as String,
      base,
      bytes(2000),
      publish: false,
    );
    expect((await check()).isPatchAvailable, isFalse);
  });

  test('staged rollout serves roughly the requested share', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    await createPatch(release['id']! as String, base, bytes(2000), rollout: 30);
    var offered = 0;
    for (var i = 0; i < 400; i++) {
      if ((await check(clientId: 'c$i')).isPatchAvailable) offered++;
    }
    expect(offered / 400, closeTo(0.3, 0.08));
  });

  test('rolling back steers devices to the previous good patch', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    final releaseId = release['id']! as String;
    await createPatch(releaseId, base, bytes(2000));
    await createPatch(releaseId, base, bytes(2000));
    expect((await check(current: 1)).patch!.number, 2);

    final res = await admin.json(
      'PATCH',
      '/api/v1/releases/$releaseId/patches/2',
      {'status': 'rolled_back'},
    );
    expect(res.status, 200);
    final response = await check(current: 2);
    expect(response.rolledBackPatchNumbers, [2]);
    expect(response.patch!.number, 1);
  });

  test('health gate rolls a crashing patch back for everyone', () async {
    await createApp();
    await admin.json('PATCH', '/api/v1/apps/demo', {
      'health_gate': {'min_launches': 10, 'max_failure_rate': 0.2},
    });
    final base = bytes(2000);
    final release = await createRelease(base);
    await createPatch(release['id']! as String, base, bytes(2000));

    Future<void> report(PatchEventType type, int i) => anonymous.json(
      'POST',
      '/api/v1/patches/events',
      PatchEvent(
        timestamp: 0,
        patchNumber: 1,
        arch: Arch.arm64,
        appId: 'demo',
        clientId: 'c$i',
        releaseVersion: '1.0.0+1',
        platform: AppPlatform.android,
        type: type,
      ).toJson(),
    );
    for (var i = 0; i < 6; i++) {
      await report(PatchEventType.launchSuccess, i);
    }
    for (var i = 0; i < 4; i++) {
      await report(PatchEventType.bootFailure, 100 + i);
    }

    final response = await check();
    expect(response.isPatchAvailable, isFalse);
    expect(response.rolledBackPatchNumbers, [1]);
    final detail = await admin.json('GET', '/api/v1/releases/${release['id']}');
    final patch = ((detail.body as Map)['patches'] as List).single as Map;
    expect(patch['status'], 'rolled_back');
    expect(patch['status_reason'], contains('Health gate'));
  });

  test('metrics report series, devices and adoption', () async {
    await createApp();
    final base = bytes(2000);
    final release = await createRelease(base);
    await createPatch(release['id']! as String, base, bytes(2000));
    await check(clientId: 'a');
    await check(clientId: 'b', current: 1);
    final yesterday = DateTime.now().subtract(const Duration(hours: 20));
    await anonymous.json(
      'POST',
      '/api/v1/patches/events',
      PatchEvent(
        timestamp: yesterday.millisecondsSinceEpoch,
        patchNumber: 1,
        arch: Arch.arm64,
        appId: 'demo',
        clientId: 'b',
        releaseVersion: '1.0.0+1',
        platform: AppPlatform.android,
        type: PatchEventType.launchSuccess,
      ).toJson(),
    );

    final res = await admin.json('GET', '/api/v1/apps/demo/metrics?hours=24');
    final metrics = res.body! as Map<String, Object?>;
    expect((metrics['series']! as List), hasLength(24));
    final totals = metrics['totals']! as Map<String, Object?>;
    expect(totals['check'], 2);
    expect(totals['launch_success'], 1);
    expect((metrics['devices']! as Map)['active'], 2);
    expect(metrics['crash_free_rate'], 1.0);
    final adoption = (metrics['adoption']! as List)
        .cast<Map<String, Object?>>();
    expect(adoption.map((a) => a['patch']), containsAll([null, 1]));
    expect(
      (await admin.json('GET', '/api/v1/apps/demo/metrics?hours=0')).status,
      400,
    );
  });

  test('answers CORS preflight for the dashboard', () async {
    final res = await anonymous.json('OPTIONS', '/api/v1/apps');
    expect(res.status, 200);
  });

  test('state survives a restart', () async {
    await createApp();
    await createRelease(bytes(100));
    await server.close();
    server = await ShorecatServer.start(
      dataDir: dataDir,
      port: 0,
      isQuiet: true,
      adminToken: 'secret',
    );
    admin = _Client(server.url, token: 'secret');
    final res = await admin.json('GET', '/api/v1/apps/demo');
    expect(((res.body as Map)['releases'] as List), hasLength(1));
  });
}

class _Response {
  final int status;
  final Object? body;

  _Response(this.status, this.body);
}

class _Client {
  final Uri base;
  final String? token;
  final HttpClient _http = HttpClient();

  _Client(this.base, {this.token});

  Future<_Response> json(String method, String path, [Object? body]) =>
      _send(method, path, body == null ? null : utf8.encode(jsonEncode(body)));

  Future<_Response> raw(String method, String path, List<int> body) =>
      _send(method, path, body);

  Future<Uint8List> download(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final request = await _http.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final builder = BytesBuilder();
    await response.forEach(builder.add);
    return builder.takeBytes();
  }

  Future<_Response> _send(String method, String path, List<int>? body) async {
    final request = await _http.openUrl(method, base.resolve(path));
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) request.add(body);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return _Response(
      response.statusCode,
      text.isEmpty ? null : jsonDecode(text),
    );
  }
}
