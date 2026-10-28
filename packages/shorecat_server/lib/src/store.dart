import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// JSON file database. Every mutation runs through [transaction], which
/// serialises writers and persists with write-then-rename so a crash never
/// leaves a half written `db.json`.
class Store {
  final Directory root;
  final List<AppRecord> apps;
  final List<PatchRecord> patches;
  final List<ReleaseRecord> releases;
  final List<Map<String, Object?>> recentEvents;
  Future<void> _tail = Future.value();

  Store._(this.root, this.apps, this.patches, this.releases, this.recentEvents);

  static const recentEventLimit = 500;

  static Future<Store> open(Directory root) async {
    await Directory(p.join(root.path, 'blobs')).create(recursive: true);
    final file = File(p.join(root.path, 'db.json'));
    if (!await file.exists()) return Store._(root, [], [], [], []);
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    List<Map<String, Object?>> list(String key) => [
      for (final e in json[key] as List? ?? []) e as Map<String, Object?>,
    ];
    return Store._(
      root,
      list('apps').map(AppRecord.fromJson).toList(),
      list('patches').map(PatchRecord.fromJson).toList(),
      list('releases').map(ReleaseRecord.fromJson).toList(),
      list('recent_events'),
    );
  }

  Future<T> transaction<T>(FutureOr<T> Function() body) {
    final result = _tail.then((_) async {
      final value = await body();
      await _persist();
      return value;
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> flush() => _tail;

  AppRecord? app(String id) => apps.where((a) => a.id == id).firstOrNull;

  ReleaseRecord? release(String appId, String version, String platform) =>
      releases
          .where(
            (r) =>
                r.appId == appId &&
                r.version == version &&
                r.platform.wireName == platform,
          )
          .firstOrNull;

  List<PatchRecord> patchesOf(String releaseId) =>
      patches.where((x) => x.releaseId == releaseId).toList()
        ..sort((a, b) => a.number.compareTo(b.number));

  void replaceApp(AppRecord app) =>
      apps[apps.indexWhere((a) => a.id == app.id)] = app;

  void replacePatch(PatchRecord patch) =>
      patches[patches.indexWhere((x) => x.id == patch.id)] = patch;

  void recordEvent(Map<String, Object?> event) {
    recentEvents.add(event);
    if (recentEvents.length > recentEventLimit) {
      recentEvents.removeRange(0, recentEvents.length - recentEventLimit);
    }
  }

  File blobFile(String sha256) =>
      File(p.join(root.path, 'blobs', sha256.substring(0, 2), sha256));

  /// Streams an upload to disk while hashing it, then moves it to its
  /// content address. The caller learns the hash, so it cannot lie about it.
  Future<({String sha256, int size})> putBlob(Stream<List<int>> body) async {
    final tmp = File(
      p.join(
        root.path,
        'blobs',
        '.upload-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final sink = tmp.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var size = 0;
    try {
      await for (final chunk in body) {
        size += chunk.length;
        hasher.add(chunk);
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    final hash = digestSink.value.toString();
    final target = blobFile(hash);
    await target.parent.create(recursive: true);
    await tmp.rename(target.path);
    return (sha256: hash, size: size);
  }

  Future<void> _persist() async {
    final file = File(p.join(root.path, 'db.json'));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'apps': [for (final a in apps) a.toJson()],
        'releases': [for (final r in releases) r.toJson()],
        'patches': [for (final x in patches) x.toJson()],
        'recent_events': recentEvents,
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
