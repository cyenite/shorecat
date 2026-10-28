import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shorecat_core/shorecat_core.dart';

import 'dashboard.dart';
import 'models.dart';
import 'store.dart';
import 'telemetry.dart';

class ApiException implements Exception {
  final int status;
  final String message;

  ApiException(this.status, this.message);
}

class ShorecatApi {
  final Store store;
  final String adminToken;
  final String? publicUrl;
  final Directory? dashboardDir;
  final Telemetry telemetry;
  final Random _random = Random.secure();

  ShorecatApi({
    required this.store,
    required this.adminToken,
    this.publicUrl,
    this.dashboardDir,
    required this.telemetry,
  });

  Handler get handler {
    final dashboard = dashboardDir;
    final public = Router()
      ..get('/', (Request request) {
        if (dashboard != null) {
          return Response.ok(
            File('${dashboard.path}/index.html').openRead(),
            headers: _html,
          );
        }
        return Response.ok(dashboardHtml, headers: _html);
      })
      ..get('/healthz', (_) => _json({'ok': true}))
      ..post('/api/v1/patches/check', _check)
      ..post('/api/v1/patches/events', _event)
      ..get('/api/v1/blobs/<sha>', _downloadBlob);

    final admin = Router()
      ..get('/api/v1/apps', _listApps)
      ..post('/api/v1/apps', _createApp)
      ..get('/api/v1/apps/<appId>', _getApp)
      ..patch('/api/v1/apps/<appId>', _updateApp)
      ..get('/api/v1/apps/<appId>/metrics', _metrics)
      ..get('/api/v1/apps/<appId>/releases', _listReleases)
      ..post('/api/v1/apps/<appId>/releases', _createRelease)
      ..post('/api/v1/blobs', _uploadBlob)
      ..get('/api/v1/releases/<releaseId>', _getRelease)
      ..post('/api/v1/releases/<releaseId>/patches', _createPatch)
      ..put(
        '/api/v1/releases/<releaseId>/patches/<number>/artifacts/<arch>',
        _putPatchArtifact,
      )
      ..post('/api/v1/releases/<releaseId>/patches/<number>/publish', _publish)
      ..patch('/api/v1/releases/<releaseId>/patches/<number>', _updatePatch)
      ..get('/api/v1/events', _recentEvents);

    var cascade = Cascade().add(public.call);
    if (dashboard != null) {
      // Before the admin routes, whose auth would answer 401 for any asset.
      cascade = cascade.add(createStaticHandler(dashboard.path));
    }
    cascade = cascade.add(
      const Pipeline().addMiddleware(_auth()).addHandler(admin.call),
    );
    return const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_errors())
        .addHandler(cascade.handler);
  }

  Future<Response> _check(Request request) async {
    final PatchCheckRequest check;
    try {
      check = PatchCheckRequest.fromJson(await _body(request));
    } on FormatException catch (e) {
      throw ApiException(400, e.message);
    }
    final release = store.release(
      check.appId,
      check.releaseVersion,
      check.platform.wireName,
    );
    if (store.app(check.appId) != null) {
      telemetry.recordCheck(check, DateTime.now());
    }
    if (release == null) {
      return _json(const PatchCheckResponse(isPatchAvailable: false).toJson());
    }

    final patches = store.patchesOf(release.id);
    final rolledBack = [
      for (final x in patches)
        if (x.status == PatchStatus.rolledBack) x.number,
    ];
    final eligible = patches.where(
      (x) =>
          x.status.isServable &&
          x.channel == check.channel &&
          x.artifacts.containsKey(check.arch) &&
          Rollout.includes(
            percentage: x.rolloutPercentage,
            clientId: check.clientId,
            salt: x.id,
          ),
    );
    final best = eligible.isEmpty ? null : eligible.last;
    final current = check.currentPatchNumber;
    final isOffered =
        best != null &&
        best.number != current &&
        (current == null ||
            best.number > current ||
            rolledBack.contains(current));

    AvailablePatch? offer;
    if (isOffered) {
      final artifact = best.artifacts[check.arch]!;
      offer = AvailablePatch(
        number: best.number,
        deltaSize: artifact.deltaSize,
        isCritical: best.isCritical,
        hash: artifact.hash,
        notes: best.notes,
        baseHash: artifact.baseHash,
        signature: artifact.signature,
        downloadUrl: '${_origin(request)}/api/v1/blobs/${artifact.deltaSha256}',
      );
    }
    return _json(
      PatchCheckResponse(
        isPatchAvailable: offer != null,
        patch: offer,
        rolledBackPatchNumbers: rolledBack,
      ).toJson(),
    );
  }

  Future<Response> _event(Request request) async {
    final body = await _body(request);
    final PatchEvent event;
    try {
      event = PatchEvent.fromJson(
        body['event'] as Map<String, Object?>? ?? body,
      );
    } on Object catch (e) {
      throw ApiException(400, 'Invalid event: $e');
    }
    if (store.app(event.appId) != null) {
      telemetry.recordEvent(event, DateTime.now());
    }
    await store.transaction(() {
      final release = store.release(
        event.appId,
        event.releaseVersion,
        event.platform.wireName,
      );
      if (release == null) return;
      final patch = store
          .patchesOf(release.id)
          .where((x) => x.number == event.patchNumber)
          .firstOrNull;
      if (patch == null) return;

      final stats = Map.of(patch.stats)
        ..update(event.type, (n) => n + 1, ifAbsent: () => 1);
      var updated = patch.copyWith(stats: stats);
      final gate = store.app(event.appId)?.healthGate ?? const HealthGate();
      if (gate.isEnabled &&
          updated.status == PatchStatus.active &&
          updated.launches >= gate.minLaunches &&
          updated.failureRate > gate.maxFailureRate) {
        updated = updated.copyWith(
          status: PatchStatus.rolledBack,
          statusReason:
              'Health gate: ${(updated.failureRate * 100).toStringAsFixed(1)}% '
              'boot failures over ${updated.launches} launches',
        );
      }
      store
        ..replacePatch(updated)
        ..recordEvent({...event.toJson(), 'received_at': _now()});
    });
    return Response(202);
  }

  Future<Response> _downloadBlob(Request request, String sha) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw ApiException(400, 'Bad blob id');
    }
    final file = store.blobFile(sha);
    if (!await file.exists()) throw ApiException(404, 'No such blob');
    final length = await file.length();
    final headers = {
      'content-type': 'application/octet-stream',
      'accept-ranges': 'bytes',
      'cache-control': 'public, max-age=31536000, immutable',
      'etag': '"$sha"',
    };

    final range = RegExp(
      r'^bytes=(\d+)-(\d*)$',
    ).firstMatch(request.headers['range'] ?? '');
    if (range == null) {
      return Response.ok(
        file.openRead(),
        headers: {...headers, 'content-length': '$length'},
      );
    }
    final start = int.parse(range.group(1)!);
    final end = range.group(2)!.isEmpty
        ? length - 1
        : min(int.parse(range.group(2)!), length - 1);
    if (start >= length || start > end) {
      return Response(416, headers: {'content-range': 'bytes */$length'});
    }
    return Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        ...headers,
        'content-length': '${end - start + 1}',
        'content-range': 'bytes $start-$end/$length',
      },
    );
  }

  Response _metrics(Request request, String appId) {
    _requireApp(appId);
    final hours =
        int.tryParse(request.url.queryParameters['hours'] ?? '') ?? 24;
    if (hours < 1 || hours > 24 * 31) {
      throw ApiException(400, 'hours must be within 1..744');
    }
    return _json(telemetry.metrics(appId, hours: hours, now: DateTime.now()));
  }

  Response _listApps(Request request) => _json({
    'apps': [for (final a in store.apps) a.toJson()],
  });

  Future<Response> _createApp(Request request) async {
    final body = await _body(request);
    final keys = _publicKeys(body['public_keys']);
    if (keys.isEmpty) {
      throw ApiException(
        400,
        'An app needs at least one patch signing public key',
      );
    }
    final id = body['id'] as String? ?? _id();
    if (!RegExp(r'^[a-zA-Z0-9._-]{3,64}$').hasMatch(id)) {
      throw ApiException(400, 'App id must be 3-64 of [a-zA-Z0-9._-]');
    }
    final app = await store.transaction(() {
      if (store.app(id) != null) throw ApiException(409, 'App $id exists');
      final app = AppRecord(
        id: id,
        name: body['name'] as String? ?? id,
        createdAt: _now(),
        publicKeys: keys,
      );
      store.apps.add(app);
      return app;
    });
    return _json(app.toJson(), status: 201);
  }

  Response _getApp(Request request, String appId) {
    final app = _requireApp(appId);
    return _json({
      ...app.toJson(),
      'releases': [
        for (final r in store.releases.where((r) => r.appId == appId))
          _releaseJson(r),
      ],
    });
  }

  Future<Response> _updateApp(Request request, String appId) async {
    final body = await _body(request);
    final app = await store.transaction(() {
      final app = _requireApp(appId);
      final keys = body.containsKey('public_keys')
          ? _publicKeys(body['public_keys'])
          : null;
      if (keys != null && keys.isEmpty) {
        throw ApiException(400, 'Refusing to remove every signing key');
      }
      final gate = body['health_gate'];
      final updated = app.copyWith(
        name: body['name'] as String?,
        publicKeys: keys,
        healthGate: gate is Map<String, Object?>
            ? HealthGate.fromJson({...app.healthGate.toJson(), ...gate})
            : null,
      );
      store.replaceApp(updated);
      return updated;
    });
    return _json(app.toJson());
  }

  Response _listReleases(Request request, String appId) {
    _requireApp(appId);
    final version = request.url.queryParameters['version'];
    final platform = request.url.queryParameters['platform'];
    return _json({
      'releases': [
        for (final r in store.releases)
          if (r.appId == appId &&
              (version == null || r.version == version) &&
              (platform == null || r.platform.wireName == platform))
            _releaseJson(r),
      ],
    });
  }

  Future<Response> _createRelease(Request request, String appId) async {
    final body = await _body(request);
    final version = body['version'];
    if (version is! String || version.isEmpty) {
      throw ApiException(400, 'Missing version');
    }
    final platform = _parse(() => AppPlatform.parse('${body['platform']}'));
    final artifacts = <Arch, ReleaseArtifact>{};
    for (final e
        in (body['artifacts'] as Map<String, Object?>? ?? {}).entries) {
      final artifact = _parse(
        () => ReleaseArtifact.fromJson(e.value! as Map<String, Object?>),
      );
      if (!await store.blobFile(artifact.sha256).exists()) {
        throw ApiException(400, 'Upload blob ${artifact.sha256} first');
      }
      artifacts[_parse(() => Arch.parse(e.key))] = artifact;
    }
    if (artifacts.isEmpty) throw ApiException(400, 'A release needs artifacts');

    final release = await store.transaction(() {
      _requireApp(appId);
      if (store.release(appId, version, platform.wireName) != null) {
        throw ApiException(
          409,
          'Release $version (${platform.wireName}) already exists',
        );
      }
      final release = ReleaseRecord(
        id: _id(),
        appId: appId,
        version: version,
        createdAt: _now(),
        flutterVersion: body['flutter_version'] as String?,
        platform: platform,
        artifacts: artifacts,
        manifest: body['manifest'] as Map<String, Object?>? ?? const {},
      );
      store.releases.add(release);
      return release;
    });
    return _json(_releaseJson(release), status: 201);
  }

  Future<Response> _uploadBlob(Request request) async {
    final blob = await store.putBlob(request.read());
    return _json({'sha256': blob.sha256, 'size': blob.size}, status: 201);
  }

  Response _getRelease(Request request, String releaseId) =>
      _json(_releaseJson(_requireRelease(releaseId)));

  Future<Response> _createPatch(Request request, String releaseId) async {
    final body = await _body(request);
    final patch = await store.transaction(() {
      final release = _requireRelease(releaseId);
      final existing = store.patchesOf(release.id);
      final patch = PatchRecord(
        number: existing.isEmpty ? 1 : existing.last.number + 1,
        isCritical: body['is_critical'] as bool? ?? false,
        rolloutPercentage: _percentage(body['rollout_percentage']) ?? 100,
        id: _id(),
        channel: body['channel'] as String? ?? 'stable',
        notes: body['notes'] as String?,
        createdAt: _now(),
        releaseId: release.id,
      );
      store.patches.add(patch);
      return patch;
    });
    return _json(patch.toJson(), status: 201);
  }

  Future<Response> _putPatchArtifact(
    Request request,
    String releaseId,
    String number,
    String arch,
  ) async {
    final body = await _body(request);
    final target = _parse(() => Arch.parse(arch));
    final deltaSha256 = body['delta_sha256'];
    final signature = body['signature'];
    if (deltaSha256 is! String || signature is! String) {
      throw ApiException(400, 'Need delta_sha256 and signature');
    }
    final release = _requireRelease(releaseId);
    final app = _requireApp(release.appId);
    final patch = _requirePatch(release.id, number);
    final base = release.artifacts[target];
    if (base == null) {
      throw ApiException(400, 'Release has no ${target.wireName} artifact');
    }

    final blob = store.blobFile(deltaSha256);
    if (!await blob.exists()) {
      throw ApiException(400, 'Upload delta blob $deltaSha256 first');
    }
    final DeltaHeader header;
    try {
      header = DeltaHeader.parse(
        Uint8List.fromList(
          await blob.openRead(0, DeltaHeader.size).expand((c) => c).toList(),
        ),
      );
    } on DeltaException catch (e) {
      throw ApiException(400, e.message);
    }
    if (header.baseSha256 != base.sha256) {
      throw ApiException(
        400,
        'Delta was built against ${header.baseSha256}, but the release '
        '${target.wireName} artifact is ${base.sha256}',
      );
    }
    final isSigned = await PatchVerifier.verify(
      signature: signature,
      payload: PatchSignaturePayload(
        patchNumber: patch.number,
        arch: target,
        appId: app.id,
        targetSha256: header.targetSha256,
        releaseVersion: release.version,
        platform: release.platform,
      ),
      trustedKeys: app.trustedKeys,
    );
    if (!isSigned) {
      throw ApiException(
        400,
        'Signature does not verify against any of the app public keys',
      );
    }

    final deltaSize = await blob.length();
    final updated = await store.transaction(() {
      final current = _requirePatch(release.id, number);
      if (current.status != PatchStatus.draft) {
        throw ApiException(409, 'Patch ${current.number} is already published');
      }
      final updated = current.copyWith(
        artifacts: {
          ...current.artifacts,
          target: PatchArtifact(
            deltaSize: deltaSize,
            hash: header.targetSha256,
            baseHash: header.baseSha256,
            signature: signature,
            deltaSha256: deltaSha256,
          ),
        },
      );
      store.replacePatch(updated);
      return updated;
    });
    return _json(updated.toJson());
  }

  Future<Response> _publish(
    Request request,
    String releaseId,
    String number,
  ) async {
    final body = await _body(request);
    final updated = await store.transaction(() {
      final release = _requireRelease(releaseId);
      final patch = _requirePatch(release.id, number);
      if (patch.artifacts.isEmpty) {
        throw ApiException(400, 'Patch ${patch.number} has no artifacts');
      }
      final updated = patch.copyWith(
        status: PatchStatus.active,
        rolloutPercentage: _percentage(body['rollout_percentage']),
      );
      store.replacePatch(updated);
      return updated;
    });
    return _json(updated.toJson());
  }

  Future<Response> _updatePatch(
    Request request,
    String releaseId,
    String number,
  ) async {
    final body = await _body(request);
    final updated = await store.transaction(() {
      final release = _requireRelease(releaseId);
      final patch = _requirePatch(release.id, number);
      final status = body['status'] is String
          ? _parse(() => PatchStatus.parse(body['status']! as String))
          : null;
      if (status == PatchStatus.draft) {
        throw ApiException(400, 'A published patch cannot return to draft');
      }
      if (status != null && patch.status == PatchStatus.draft) {
        throw ApiException(400, 'Publish the patch before changing status');
      }
      final updated = patch.copyWith(
        isCritical: body['is_critical'] as bool?,
        rolloutPercentage: _percentage(body['rollout_percentage']),
        channel: body['channel'] as String?,
        notes: body['notes'] as String?,
        statusReason: status == null
            ? null
            : body['reason'] as String? ?? 'Set to ${status.wireName} by admin',
        status: status,
      );
      store.replacePatch(updated);
      return updated;
    });
    return _json(updated.toJson());
  }

  Response _recentEvents(Request request) {
    final appId = request.url.queryParameters['app_id'];
    return _json({
      'events': [
        for (final e in store.recentEvents.reversed)
          if (appId == null || e['app_id'] == appId) e,
      ],
    });
  }

  Map<String, Object?> _releaseJson(ReleaseRecord release) => {
    ...release.toJson(),
    'patches': [for (final x in store.patchesOf(release.id)) x.toJson()],
  };

  AppRecord _requireApp(String appId) =>
      store.app(appId) ?? (throw ApiException(404, 'No app $appId'));

  ReleaseRecord _requireRelease(String id) =>
      store.releases.where((r) => r.id == id).firstOrNull ??
      (throw ApiException(404, 'No release $id'));

  PatchRecord _requirePatch(String releaseId, String number) {
    final n = int.tryParse(number);
    return store.patchesOf(releaseId).where((x) => x.number == n).firstOrNull ??
        (throw ApiException(404, 'No patch $number'));
  }

  List<String> _publicKeys(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final k in raw)
        _parse(() => PatchPublicKey.parse(k as String).encode()),
    ];
  }

  double? _percentage(Object? raw) {
    if (raw == null) return null;
    if (raw is! num || raw < 0 || raw > 100) {
      throw ApiException(400, 'rollout_percentage must be within 0..100');
    }
    return raw.toDouble();
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on ApiException {
      rethrow;
    } on Object catch (e) {
      throw ApiException(400, '$e');
    }
  }

  String _origin(Request request) {
    if (publicUrl != null) return publicUrl!;
    final uri = request.requestedUri;
    return '${uri.scheme}://${uri.authority}';
  }

  String _id() => [
    for (var i = 0; i < 8; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  Middleware _auth() =>
      (inner) => (request) {
        final header = request.headers['authorization'] ?? '';
        final token = header.startsWith('Bearer ') ? header.substring(7) : '';
        if (!_constantTimeEquals(token, adminToken)) {
          return _json({'error': 'Unauthorized'}, status: 401);
        }
        return inner(request);
      };

  /// Admin calls carry a bearer token, never cookies, so any origin may make
  /// them; this lets the dashboard run from `flutter run -d chrome`.
  Middleware _cors() =>
      (inner) => (request) async {
        const headers = {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'authorization, content-type, range',
          'access-control-allow-methods': 'GET, POST, PUT, PATCH, OPTIONS',
        };
        if (request.method == 'OPTIONS') {
          return Response.ok(null, headers: headers);
        }
        final response = await inner(request);
        return response.change(headers: headers);
      };

  Middleware _errors() =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } on ApiException catch (e) {
          return _json({'error': e.message}, status: e.status);
        }
      };
}

const _html = {'content-type': 'text/html; charset=utf-8'};

Future<Map<String, Object?>> _body(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return {};
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw ApiException(400, 'Body is not JSON');
  }
  if (json is! Map<String, Object?>) {
    throw ApiException(400, 'Body must be a JSON object');
  }
  return json;
}

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

String _now() => DateTime.now().toUtc().toIso8601String();

bool _constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0 && x.isNotEmpty;
}
