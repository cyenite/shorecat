import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:shorecat_core/shorecat_core.dart';

import 'state.dart';

class UpdaterConfig {
  final int maxBootAttempts;
  final Arch arch;
  final String appId;
  final String channel;
  final String baseUrl;
  final String releaseVersion;
  final Duration timeout;
  final Directory storageDir;
  final AppPlatform platform;
  final List<PatchPublicKey> publicKeys;
  final Future<Uint8List> Function() readBaseArtifact;

  const UpdaterConfig({
    this.maxBootAttempts = 1,
    required this.arch,
    required this.appId,
    this.channel = 'stable',
    required this.baseUrl,
    required this.releaseVersion,
    this.timeout = const Duration(seconds: 30),
    required this.storageDir,
    required this.platform,
    required this.publicKeys,
    required this.readBaseArtifact,
  });
}

enum UpdateStatus {
  upToDate('No new patch'),
  installed('Patch installed, applies on next launch'),
  rolledBack('A rolled back patch was removed'),
  failed('Update failed');

  final String label;

  const UpdateStatus(this.label);
}

class UpdateResult {
  final int? patchNumber;
  final bool isCritical;
  final String? message;
  final UpdateStatus status;

  const UpdateResult({
    this.patchNumber,
    this.isCritical = false,
    this.message,
    required this.status,
  });

  @override
  String toString() =>
      '${status.label}${patchNumber == null ? '' : ' (patch $patchNumber)'}'
      '${message == null ? '' : ': $message'}';
}

/// What the boot hook decided for this process.
class BootDecision {
  final int? patchNumber;
  final String? libraryPath;
  final int? crashedPatchNumber;

  const BootDecision({
    this.patchNumber,
    this.libraryPath,
    this.crashedPatchNumber,
  });
}

class UpdaterException implements Exception {
  final String message;

  UpdaterException(this.message);

  @override
  String toString() => 'UpdaterException: $message';
}

class Updater {
  final String clientId;
  final UpdaterConfig config;
  final HttpClient _http;
  Pointers _pointers;
  Future<UpdateResult>? _inFlight;

  Updater._(this.clientId, this.config, this._http, this._pointers);

  static const artifactName = 'libapp.so';

  static Future<Updater> open(UpdaterConfig config, {HttpClient? http}) async {
    final root = config.storageDir;
    await Directory('${root.path}/patches').create(recursive: true);

    final idFile = File('${root.path}/client_id');
    var clientId = await idFile.exists()
        ? (await idFile.readAsString()).trim()
        : '';
    if (clientId.isEmpty) {
      clientId = _uuid();
      await idFile.writeAsString(clientId, flush: true);
    }

    final pointersFile = File('${root.path}/pointers.json');
    final json = await readJson(pointersFile);
    var pointers = json == null ? const Pointers() : Pointers.fromJson(json);
    if (pointers.releaseVersion != config.releaseVersion) {
      // A store update replaced the base; every patch was built for the old one.
      await Directory('${root.path}/patches').delete(recursive: true);
      await Directory('${root.path}/patches').create();
      pointers = Pointers(releaseVersion: config.releaseVersion);
    }
    pointers = pointers.copyWith(maxBootAttempts: config.maxBootAttempts);
    await writeJsonAtomic(pointersFile, pointers.toJson());

    final client = (http ?? HttpClient())..connectionTimeout = config.timeout;
    return Updater._(clientId, config, client, pointers);
  }

  /// The patch this process is running, or null on the base release.
  int? get currentPatchNumber => _pointers.running;

  /// The patch the next launch will boot, or null for the base release.
  int? get nextPatchNumber => _pointers.nextBoot;

  bool get isNewPatchReadyToInstall =>
      _pointers.nextBoot != null && _pointers.nextBoot != _pointers.running;

  File artifactOf(int number) =>
      File('${config.storageDir.path}/patches/$number/$artifactName');

  /// Boot decision for hosts that run Dart before choosing the AOT library
  /// (tests, desktop embedders). Android does the same in `ShorecatBoot.kt`
  /// before the engine starts; the two must stay in step.
  Future<BootDecision> beginLaunch() async {
    var p = _pointers;
    int? crashed;
    final stale = p.currentlyBooting;
    if (stale != null) {
      if (p.bootAttempts >= p.maxBootAttempts) {
        crashed = stale;
        await _markBad(stale, BadReason.bootCrash);
        await _queueEvent(
          PatchEventType.bootFailure,
          stale,
          'Crashed during boot',
        );
        p = p.copyWith(
          currentlyBooting: null,
          bootAttempts: 0,
          nextBoot: p.nextBoot == stale ? null : p.nextBoot,
          lastBooted: p.lastBooted == stale ? null : p.lastBooted,
        );
      } else {
        p = p.copyWith(currentlyBooting: null);
      }
    }

    for (final candidate in [p.nextBoot, p.lastBooted]) {
      if (candidate == null) continue;
      if (await _isBootable(candidate)) {
        p = p.copyWith(
          running: candidate,
          nextBoot: candidate,
          currentlyBooting: candidate,
          bootAttempts: (candidate == stale ? p.bootAttempts : 0) + 1,
          bootStartedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _savePointers(p);
        return BootDecision(
          patchNumber: candidate,
          libraryPath: artifactOf(candidate).path,
          crashedPatchNumber: crashed,
        );
      }
      await _markBad(candidate, BadReason.hashMismatch);
      p = p.copyWith(
        nextBoot: p.nextBoot == candidate ? null : p.nextBoot,
        lastBooted: p.lastBooted == candidate ? null : p.lastBooted,
      );
    }

    p = p.copyWith(running: null, nextBoot: null, bootAttempts: 0);
    await _savePointers(p);
    return BootDecision(crashedPatchNumber: crashed);
  }

  /// Clears the boot breadcrumb. Call once the app has drawn its first
  /// frame: a crash anywhere before that counts against the patch.
  Future<void> reportLaunchSuccess() async {
    final booting = _pointers.currentlyBooting;
    if (booting == null) return;
    await _savePointers(
      _pointers.copyWith(
        lastBooted: booting,
        currentlyBooting: null,
        bootAttempts: 0,
        bootStartedAt: null,
      ),
    );
    await _queueEvent(PatchEventType.launchSuccess, booting, null);
    await _cleanUp();
    unawaited(flushEvents());
  }

  /// The patch could not be loaded at all; never try it again.
  Future<void> reportLaunchFailure() async {
    final booting = _pointers.currentlyBooting ?? _pointers.running;
    if (booting == null) return;
    await _markBad(booting, BadReason.launchFailure);
    await _queueEvent(
      PatchEventType.bootFailure,
      booting,
      'Patch failed to load',
    );
    await _savePointers(
      _pointers.copyWith(
        running: null,
        currentlyBooting: null,
        bootAttempts: 0,
        nextBoot: _pointers.nextBoot == booting
            ? _pointers.lastBooted
            : _pointers.nextBoot,
        lastBooted: _pointers.lastBooted == booting
            ? null
            : _pointers.lastBooted,
      ),
    );
  }

  Future<PatchCheckResponse> checkForUpdate() async {
    final request = PatchCheckRequest(
      currentPatchNumber: _pointers.nextBoot ?? _pointers.running,
      arch: config.arch,
      appId: config.appId,
      channel: config.channel,
      clientId: clientId,
      releaseVersion: config.releaseVersion,
      platform: config.platform,
    );
    final json = await _postJson('/api/v1/patches/check', request.toJson());
    return PatchCheckResponse.fromJson(json! as Map<String, Object?>);
  }

  /// Checks, downloads, verifies and installs the newest patch. Concurrent
  /// callers share one run.
  Future<UpdateResult> update({
    void Function(int received, int total)? onProgress,
  }) {
    return _inFlight ??= _update(
      onProgress,
    ).whenComplete(() => _inFlight = null);
  }

  Future<UpdateResult> _update(void Function(int, int)? onProgress) async {
    unawaited(flushEvents());
    final PatchCheckResponse response;
    try {
      response = await checkForUpdate();
    } on Object catch (e) {
      return UpdateResult(
        status: UpdateStatus.failed,
        message: 'Check failed: $e',
      );
    }

    final bool isRolledBack;
    try {
      isRolledBack = await _applyRollbacks(response.rolledBackPatchNumbers);
    } on Object catch (e) {
      return UpdateResult(
        status: UpdateStatus.failed,
        message: 'Rollback failed: $e',
      );
    }
    final patch = response.patch;
    if (!response.isPatchAvailable || patch == null) {
      return UpdateResult(
        status: isRolledBack ? UpdateStatus.rolledBack : UpdateStatus.upToDate,
      );
    }

    final record = await _record(patch.number);
    if (record?.state == PatchState.bad) {
      return UpdateResult(
        patchNumber: patch.number,
        message: 'Patch previously failed on this device (${record!.reason})',
        status: UpdateStatus.upToDate,
      );
    }
    if (record?.state == PatchState.installed &&
        _pointers.nextBoot == patch.number) {
      return UpdateResult(
        patchNumber: patch.number,
        isCritical: patch.isCritical,
        message: 'Already installed',
        status: UpdateStatus.installed,
      );
    }

    try {
      await _install(patch, onProgress);
    } on Object catch (e) {
      final isPermanent = e is DeltaException || e is UpdaterException;
      if (e is DeltaException) {
        await _markBad(patch.number, BadReason.installFailed, '$e');
      }
      await _queueEvent(PatchEventType.installFailure, patch.number, '$e');
      unawaited(flushEvents());
      return UpdateResult(
        patchNumber: patch.number,
        message: isPermanent ? '$e' : 'Will retry: $e',
        status: UpdateStatus.failed,
      );
    }

    await _queueEvent(PatchEventType.installSuccess, patch.number, null);
    unawaited(flushEvents());
    return UpdateResult(
      patchNumber: patch.number,
      isCritical: patch.isCritical,
      status: UpdateStatus.installed,
    );
  }

  Future<void> _install(
    AvailablePatch patch,
    void Function(int, int)? onProgress,
  ) async {
    final isSigned = await PatchVerifier.verify(
      signature: patch.signature,
      payload: PatchSignaturePayload(
        patchNumber: patch.number,
        arch: config.arch,
        appId: config.appId,
        targetSha256: patch.hash,
        releaseVersion: config.releaseVersion,
        platform: config.platform,
      ),
      trustedKeys: config.publicKeys,
    );
    if (!isSigned) {
      throw UpdaterException('Patch ${patch.number} signature is not trusted');
    }

    final dir = Directory('${config.storageDir.path}/patches/${patch.number}');
    await dir.create(recursive: true);
    await _writeRecord(
      PatchRecord(
        number: patch.number,
        hash: patch.hash,
        state: PatchState.downloading,
      ),
    );
    final deltaFile = File('${dir.path}/delta.partial');
    await _download(
      Uri.parse(patch.downloadUrl),
      deltaFile,
      patch.deltaSize,
      onProgress,
    );
    await _queueEvent(PatchEventType.download, patch.number, null);

    final delta = await deltaFile.readAsBytes();
    final header = DeltaHeader.parse(delta);
    if (header.targetSha256 != patch.hash) {
      throw DeltaException('Delta target does not match the signed hash');
    }
    final base = await config.readBaseArtifact();
    if (base.length != header.baseLength || sha256Hex(base) != patch.baseHash) {
      throw UpdaterException(
        'This install\'s base artifact differs from the release the patch '
        'was built for',
      );
    }

    final target = await _applyInIsolate(base, delta);
    final tmp = File('${dir.path}/$artifactName.tmp');
    await tmp.writeAsBytes(target, flush: true);
    await tmp.rename(artifactOf(patch.number).path);
    await deltaFile.delete();

    await _writeRecord(
      PatchRecord(
        number: patch.number,
        hash: patch.hash,
        state: PatchState.installed,
      ),
    );
    await _savePointers(_pointers.copyWith(nextBoot: patch.number));
  }

  Future<void> _download(
    Uri uri,
    File file,
    int expectedSize,
    void Function(int, int)? onProgress,
  ) async {
    var offset = await file.exists() ? await file.length() : 0;
    if (expectedSize > 0 && offset > expectedSize) {
      await file.delete();
      offset = 0;
    }
    if (expectedSize > 0 && offset == expectedSize) return;

    final request = await _http.getUrl(uri).timeout(config.timeout);
    if (offset > 0) request.headers.set('range', 'bytes=$offset-');
    final response = await request.close().timeout(config.timeout);
    if (response.statusCode == 200) {
      offset = 0;
    } else if (response.statusCode != 206) {
      await response.drain<void>();
      throw HttpException(
        'Download failed with ${response.statusCode}',
        uri: uri,
      );
    }
    final sink = file.openWrite(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var received = offset;
    try {
      await for (final chunk in response.timeout(config.timeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, expectedSize);
      }
    } finally {
      await sink.close();
    }
    if (expectedSize > 0 && received != expectedSize) {
      throw HttpException(
        'Download ended at $received of $expectedSize bytes',
        uri: uri,
      );
    }
  }

  Future<bool> _applyRollbacks(List<int> rolledBack) async {
    var isChanged = false;
    var p = _pointers;
    for (final n in rolledBack) {
      final dir = Directory('${config.storageDir.path}/patches/$n');
      final record = await _record(n);
      if (record == null || record.state == PatchState.bad) continue;
      isChanged = true;
      if (n != p.running) await dir.delete(recursive: true);
      if (p.lastBooted == n) p = p.copyWith(lastBooted: null);
      if (p.nextBoot == n) p = p.copyWith(nextBoot: p.lastBooted);
      await _queueEvent(PatchEventType.uninstall, n, 'Rolled back by server');
    }
    if (isChanged) await _savePointers(p);
    return isChanged;
  }

  Future<void> _cleanUp() async {
    final keep = {_pointers.running, _pointers.nextBoot, _pointers.lastBooted};
    final patches = Directory('${config.storageDir.path}/patches');
    await for (final entity in patches.list()) {
      final n = int.tryParse(
        entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      );
      if (entity is! Directory || n == null || keep.contains(n)) continue;
      final record = await _record(n);
      if (record?.state == PatchState.bad) {
        final artifact = artifactOf(n);
        if (await artifact.exists()) await artifact.delete();
      } else if (record?.state != PatchState.downloading) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<bool> _isBootable(int number) async {
    final record = await _record(number);
    if (record?.state != PatchState.installed) return false;
    final file = artifactOf(number);
    if (!await file.exists()) return false;
    return sha256Hex(await file.readAsBytes()) == record!.hash;
  }

  Future<PatchRecord?> _record(int number) async {
    final json = await readJson(
      File('${config.storageDir.path}/patches/$number/state.json'),
    );
    return json == null ? null : PatchRecord.fromJson(json);
  }

  Future<void> _writeRecord(PatchRecord record) => writeJsonAtomic(
    File('${config.storageDir.path}/patches/${record.number}/state.json'),
    record.toJson(),
  );

  Future<void> _markBad(int number, BadReason reason, [String? detail]) async {
    final existing = await _record(number);
    await _writeRecord(
      PatchRecord(
        number: number,
        hash: existing?.hash ?? '',
        reason: detail == null
            ? reason.wireName
            : '${reason.wireName}: $detail',
        state: PatchState.bad,
      ),
    );
  }

  Future<void> _savePointers(Pointers pointers) async {
    _pointers = pointers;
    await writeJsonAtomic(
      File('${config.storageDir.path}/pointers.json'),
      pointers.toJson(),
    );
  }

  File get _eventsFile => File('${config.storageDir.path}/pending_events.json');

  Future<List<Map<String, Object?>>> _pendingEvents() async {
    if (!await _eventsFile.exists()) return [];
    try {
      final json = jsonDecode(await _eventsFile.readAsString());
      return [for (final e in json as List) e as Map<String, Object?>];
    } on Object {
      return [];
    }
  }

  /// Serialises every read-modify-write of `pending_events.json`.
  Future<T> _eventLock<T>(Future<T> Function() body) {
    final result = _eventTail.then((_) => body());
    _eventTail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _eventTail = Future.value();

  Future<void> _queueEvent(PatchEventType type, int patch, String? message) =>
      _eventLock(() async {
        final events = await _pendingEvents();
        events.add({
          'type': type.wireName,
          'patch_number': patch,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'message': ?message,
        });
        await writeJsonAtomic(
          _eventsFile,
          events.length > 100 ? events.sublist(events.length - 100) : events,
        );
      });

  Future<void>? _flushing;

  /// Sends queued events, including the ones the native boot hook wrote.
  /// Unsent events stay queued for the next attempt.
  /// Never throws: it is often fired without awaiting, and an unsent event
  /// simply stays queued.
  Future<void> flushEvents() => _flushing ??= _flush()
      .catchError((Object _) {})
      .whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    // Take the queue under the lock, send without holding it, and put back
    // whatever failed, ahead of anything queued meanwhile.
    final events = await _eventLock(() async {
      final events = await _pendingEvents();
      if (events.isNotEmpty) await writeJsonAtomic(_eventsFile, const []);
      return events;
    });
    if (events.isEmpty) return;
    final failed = <Map<String, Object?>>[];
    for (final event in events) {
      try {
        await _postJson('/api/v1/patches/events', {
          ...event,
          'app_id': config.appId,
          'client_id': clientId,
          'release_version': config.releaseVersion,
          'platform': config.platform.wireName,
          'arch': config.arch.wireName,
        });
      } on Object {
        failed.add(event);
      }
    }
    if (failed.isEmpty) return;
    await _eventLock(() async {
      await writeJsonAtomic(_eventsFile, [
        ...failed,
        ...await _pendingEvents(),
      ]);
    });
  }

  Future<Object?> _postJson(String path, Object body) async {
    final uri = Uri.parse(
      '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}$path',
    );
    final request = await _http.postUrl(uri).timeout(config.timeout);
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(config.timeout);
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: $text', uri: uri);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  void close() => _http.close(force: true);
}

/// Top level so the isolate closure captures only the two buffers.
Future<Uint8List> _applyInIsolate(Uint8List base, Uint8List delta) =>
    Isolate.run(() => Delta.apply(base, delta));

String _uuid() {
  final random = Random.secure();
  final b = List.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
