import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shorecat_core/shorecat_core.dart';
import 'package:shorecat_server/shorecat_server.dart';
import 'package:shorecat_updater/shorecat_updater.dart';
import 'package:shorecat_updater/src/state.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ShorecatServer server;
  late _Admin admin;
  late PatchKeyPair keys;
  late Uint8List base;
  late String releaseId;
  final random = Random(3);

  Uint8List edit(Uint8List from, int seed) {
    final out = List<int>.of(from);
    for (var i = 0; i < 20; i++) {
      out[(seed * 7919 + i * 104729) % out.length] ^= seed;
    }
    return Uint8List.fromList(out);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shorecat-updater-test');
    server = await ShorecatServer.start(
      dataDir: Directory('${temp.path}/server'),
      port: 0,
      isQuiet: true,
      adminToken: 't',
    );
    admin = _Admin(server.url);
    keys = await PatchKeyPair.generate();
    base = Uint8List.fromList(
      List.generate(64 * 1024, (_) => random.nextInt(256)),
    );
    await admin.send('POST', '/api/v1/apps', {
      'id': 'demo',
      'public_keys': [keys.publicKey.encode()],
    });
    final sha = await admin.blob(base);
    final release = await admin.send('POST', '/api/v1/apps/demo/releases', {
      'version': '1.0.0+1',
      'platform': 'android',
      'artifacts': {
        'aarch64': {'sha256': sha, 'size': base.length},
      },
    });
    releaseId = release['id']! as String;
  });

  tearDown(() async {
    await server.close();
    await temp.delete(recursive: true);
  });

  Future<Uint8List> publish(int seed, {PatchKeyPair? signer}) async {
    final target = edit(base, seed);
    final created = await admin.send(
      'POST',
      '/api/v1/releases/$releaseId/patches',
      {},
    );
    final number = created['number']! as int;
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
    await admin.send(
      'PUT',
      '/api/v1/releases/$releaseId/patches/$number/artifacts/aarch64',
      {
        'delta_sha256': await admin.blob(Delta.create(base, target)),
        'signature': signature,
      },
    );
    await admin.send(
      'POST',
      '/api/v1/releases/$releaseId/patches/$number/publish',
      {},
    );
    return target;
  }

  Future<Updater> device({
    String release = '1.0.0+1',
    int maxBootAttempts = 1,
    List<PatchPublicKey>? trusted,
  }) => Updater.open(
    UpdaterConfig(
      maxBootAttempts: maxBootAttempts,
      arch: Arch.arm64,
      appId: 'demo',
      baseUrl: server.url.toString(),
      releaseVersion: release,
      storageDir: Directory('${temp.path}/device'),
      platform: AppPlatform.android,
      publicKeys: trusted ?? [keys.publicKey],
      readBaseArtifact: () async => base,
    ),
  );

  Future<Map<String, Object?>> serverPatch(int number) async {
    final release = await admin.send(
      'GET',
      '/api/v1/releases/$releaseId',
      null,
    );
    return (release['patches']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((p) => p['number'] == number);
  }

  test('installs a patch that boots on the next launch', () async {
    final target = await publish(1);
    final first = await device();
    expect((await first.beginLaunch()).patchNumber, isNull);
    await first.reportLaunchSuccess();

    final result = await first.update();
    expect(result.status, UpdateStatus.installed);
    expect(result.patchNumber, 1);
    expect(first.currentPatchNumber, isNull);
    expect(first.isNewPatchReadyToInstall, isTrue);
    expect(await first.artifactOf(1).readAsBytes(), target);
    expect((await first.update()).status, UpdateStatus.upToDate);
    expect(first.isNewPatchReadyToInstall, isTrue);
    first.close();

    final second = await device();
    final boot = await second.beginLaunch();
    expect(boot.patchNumber, 1);
    expect(boot.libraryPath, second.artifactOf(1).path);
    expect(second.currentPatchNumber, 1);
    await second.reportLaunchSuccess();
    await second.flushEvents();
    expect((await second.update()).status, UpdateStatus.upToDate);
    second.close();

    final stats = (await serverPatch(1))['stats']! as Map;
    expect(stats['install_success'], 1);
    expect(stats['launch_success'], 1);
  });

  test(
    'a crash during boot rolls back to the base and never retries',
    () async {
      await publish(1);
      final first = await device();
      await first.beginLaunch();
      await first.update();
      first.close();

      final crashing = await device();
      expect((await crashing.beginLaunch()).patchNumber, 1);
      crashing.close();

      final recovered = await device();
      final boot = await recovered.beginLaunch();
      expect(boot.patchNumber, isNull);
      expect(boot.crashedPatchNumber, 1);
      await recovered.flushEvents();
      final again = await recovered.update();
      expect(again.status, UpdateStatus.upToDate);
      expect(again.message, contains('previously failed'));
      recovered.close();

      expect(((await serverPatch(1))['stats']! as Map)['boot_failure'], 1);
    },
  );

  test('a crash falls back to the last patch that booted', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device();
    expect((await d.beginLaunch()).patchNumber, 1);
    await d.reportLaunchSuccess();

    await publish(2);
    expect((await d.update()).patchNumber, 2);
    d.close();
    d = await device();
    expect((await d.beginLaunch()).patchNumber, 2);
    d.close();

    d = await device();
    final boot = await d.beginLaunch();
    expect(boot.crashedPatchNumber, 2);
    expect(boot.patchNumber, 1);
    d.close();
  });

  test('maxBootAttempts allows a retry before giving up', () async {
    await publish(1);
    var d = await device(maxBootAttempts: 2);
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device(maxBootAttempts: 2);
    expect((await d.beginLaunch()).patchNumber, 1);
    d.close();
    d = await device(maxBootAttempts: 2);
    expect((await d.beginLaunch()).patchNumber, 1, reason: 'one retry');
    d.close();
    d = await device(maxBootAttempts: 2);
    final boot = await d.beginLaunch();
    expect(boot.patchNumber, isNull);
    expect(boot.crashedPatchNumber, 1);
    d.close();
  });

  test('a server rollback removes the patch', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device();
    expect((await d.beginLaunch()).patchNumber, 1);
    await d.reportLaunchSuccess();

    await admin.send('PATCH', '/api/v1/releases/$releaseId/patches/1', {
      'status': 'rolled_back',
    });
    expect((await d.update()).status, UpdateStatus.rolledBack);
    expect(d.nextPatchNumber, isNull);
    d.close();
    d = await device();
    expect((await d.beginLaunch()).patchNumber, isNull);
    d.close();
  });

  test('refuses patches signed by an untrusted key', () async {
    await publish(1);
    final stranger = await PatchKeyPair.generate();
    final d = await device(trusted: [stranger.publicKey]);
    await d.beginLaunch();
    final result = await d.update();
    expect(result.status, UpdateStatus.failed);
    expect(result.message, contains('signature'));
    expect(d.nextPatchNumber, isNull);
    d.close();
  });

  test('a tampered artifact on disk is not booted', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    final file = d.artifactOf(1);
    final bytes = await file.readAsBytes();
    bytes[100] ^= 1;
    await file.writeAsBytes(bytes);
    d.close();

    d = await device();
    expect((await d.beginLaunch()).patchNumber, isNull);
    d.close();
  });

  test('a new store release discards old patches', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device(release: '1.0.1+2');
    expect(d.nextPatchNumber, isNull);
    expect((await d.beginLaunch()).patchNumber, isNull);
    d.close();
  });

  test('upgrading from patch 1 to 2 cleans up patch 1 after success', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device();
    await d.beginLaunch();
    await d.reportLaunchSuccess();
    await publish(2);
    await d.update();
    d.close();
    d = await device();
    expect((await d.beginLaunch()).patchNumber, 2);
    await d.reportLaunchSuccess();
    expect(await d.artifactOf(1).exists(), isFalse);
    expect(await d.artifactOf(2).exists(), isTrue);
    d.close();
  });

  test('concurrent atomic writes to one file never collide', () async {
    final file = File('${temp.path}/race.json');
    await Future.wait([
      for (var i = 0; i < 50; i++) writeJsonAtomic(file, {'i': i}),
    ]);
    expect(jsonDecode(await file.readAsString()), isA<Map<String, Object?>>());
  });

  test('server rollback works while events are being flushed', () async {
    await publish(1);
    var d = await device();
    await d.beginLaunch();
    await d.update();
    d.close();
    d = await device();
    await d.beginLaunch();
    await d.reportLaunchSuccess();
    await admin.send('PATCH', '/api/v1/releases/$releaseId/patches/1', {
      'status': 'rolled_back',
    });
    final flushes = [d.flushEvents(), d.flushEvents()];
    final result = await d.update();
    await Future.wait(flushes);
    expect(result.status, UpdateStatus.rolledBack);
    expect(d.nextPatchNumber, isNull);
    d.close();
  });

  test('resumes a partial download', () async {
    final target = await publish(1);
    final d = await device();
    await d.beginLaunch();
    final check = await d.checkForUpdate();
    final full = await admin.download(Uri.parse(check.patch!.downloadUrl));
    final partial = File('${temp.path}/device/patches/1/delta.partial');
    await partial.create(recursive: true);
    await partial.writeAsBytes(full.sublist(0, full.length ~/ 2));
    final sizes = <int>[];
    final result = await d.update(
      onProgress: (received, _) => sizes.add(received),
    );
    expect(result.status, UpdateStatus.installed);
    expect(sizes.first, greaterThan(full.length ~/ 2));
    expect(await d.artifactOf(1).readAsBytes(), target);
    d.close();
  });
}

class _Admin {
  final Uri base;
  final HttpClient _http = HttpClient();

  _Admin(this.base);

  Future<Map<String, Object?>> send(
    String method,
    String path,
    Object? body,
  ) async {
    final request = await _http.openUrl(method, base.replace(path: path));
    request.headers.set('authorization', 'Bearer t');
    if (body != null) request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) throw StateError('$path: $text');
    return jsonDecode(text) as Map<String, Object?>;
  }

  Future<String> blob(List<int> bytes) async {
    final request = await _http.postUrl(base.replace(path: '/api/v1/blobs'));
    request.headers.set('authorization', 'Bearer t');
    request.add(bytes);
    final response = await request.close();
    final json =
        jsonDecode(await response.transform(utf8.decoder).join()) as Map;
    return json['sha256'] as String;
  }

  Future<Uint8List> download(Uri uri) async {
    final response = await (await _http.getUrl(uri)).close();
    final builder = BytesBuilder();
    await response.forEach(builder.add);
    return builder.takeBytes();
  }
}
