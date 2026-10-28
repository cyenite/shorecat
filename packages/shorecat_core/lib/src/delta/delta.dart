import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'suffix_array.dart';

enum Compression {
  none(0),
  zlib(1),
  bzip2(2),
  zstd(3);

  final int id;

  const Compression(this.id);

  static Compression fromId(int id) => values.firstWhere(
    (c) => c.id == id,
    orElse: () => throw DeltaException('Unknown compression id $id'),
  );

  Uint8List encode(Uint8List bytes) => switch (this) {
    none => bytes,
    zlib => const ZLibEncoder().encodeBytes(bytes, level: 9),
    bzip2 => BZip2Encoder().encodeBytes(bytes),
    zstd => ZstdEncoder().encodeBytes(bytes, level: 19),
  };

  Uint8List decode(Uint8List bytes) => switch (this) {
    none => bytes,
    zlib => const ZLibDecoder().decodeBytes(bytes),
    bzip2 => BZip2Decoder().decodeBytes(bytes),
    zstd => ZstdDecoder().decodeBytes(bytes),
  };
}

class DeltaException implements Exception {
  final String message;

  DeltaException(this.message);

  @override
  String toString() => 'DeltaException: $message';
}

/// Fixed-size header of a `SCDELTA1` file. Carrying both hashes lets a device
/// refuse a patch built against a different base before doing any work, and
/// prove the rebuilt artifact is exactly what was signed.
class DeltaHeader {
  final int baseLength;
  final int extraLength;
  final int targetLength;
  final int controlLength;
  final int diffLength;
  final String baseSha256;
  final String targetSha256;
  final Compression compression;

  const DeltaHeader({
    required this.baseLength,
    required this.extraLength,
    required this.targetLength,
    required this.controlLength,
    required this.diffLength,
    required this.baseSha256,
    required this.targetSha256,
    required this.compression,
  });

  static const magic = 'SCDELTA1';
  static const version = 1;
  static const size = 114;

  factory DeltaHeader.parse(Uint8List bytes) {
    if (bytes.length < size) throw DeltaException('Delta is truncated');
    if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != magic) {
      throw DeltaException('Not a shorecat delta (bad magic)');
    }
    if (bytes[8] != version) {
      throw DeltaException('Unsupported delta version ${bytes[8]}');
    }
    final data = ByteData.sublistView(bytes);
    return DeltaHeader(
      baseLength: data.getUint64(10, Endian.little),
      extraLength: data.getUint64(106, Endian.little),
      targetLength: data.getUint64(18, Endian.little),
      controlLength: data.getUint64(90, Endian.little),
      diffLength: data.getUint64(98, Endian.little),
      baseSha256: _hex(bytes.sublist(26, 58)),
      targetSha256: _hex(bytes.sublist(58, 90)),
      compression: Compression.fromId(bytes[9]),
    );
  }

  Uint8List toBytes() {
    final bytes = Uint8List(size);
    final data = ByteData.sublistView(bytes);
    bytes.setAll(0, ascii.encode(magic));
    bytes[8] = version;
    bytes[9] = compression.id;
    data.setUint64(10, baseLength, Endian.little);
    data.setUint64(18, targetLength, Endian.little);
    bytes.setAll(26, _unhex(baseSha256));
    bytes.setAll(58, _unhex(targetSha256));
    data.setUint64(90, controlLength, Endian.little);
    data.setUint64(98, diffLength, Endian.little);
    data.setUint64(106, extraLength, Endian.little);
    return bytes;
  }
}

/// bsdiff-style binary delta with separately compressed control, diff and
/// extra streams, wrapped in a header that pins both endpoints by SHA-256.
abstract final class Delta {
  static Uint8List create(
    Uint8List base,
    Uint8List target, {
    Compression compression = Compression.zstd,
  }) => _assemble(_diff(base, target), compression);

  /// Builds the delta streams once, compresses them every supported way and
  /// keeps the smallest result.
  static Uint8List createSmallest(Uint8List base, Uint8List target) {
    final streams = _diff(base, target);
    Uint8List? best;
    for (final compression in Compression.values) {
      final candidate = _assemble(streams, compression);
      if (best == null || candidate.length < best.length) best = candidate;
    }
    return best!;
  }

  static Uint8List _assemble(_Streams streams, Compression compression) {
    final diff = compression.encode(streams.diff);
    final extra = compression.encode(streams.extra);
    final control = compression.encode(streams.control);
    final header = DeltaHeader(
      baseLength: streams.baseLength,
      extraLength: extra.length,
      targetLength: streams.targetLength,
      controlLength: control.length,
      diffLength: diff.length,
      baseSha256: streams.baseSha256,
      targetSha256: streams.targetSha256,
      compression: compression,
    );
    return (BytesBuilder(copy: false)
          ..add(header.toBytes())
          ..add(control)
          ..add(diff)
          ..add(extra))
        .takeBytes();
  }

  static Uint8List apply(Uint8List base, Uint8List delta) {
    final header = DeltaHeader.parse(delta);
    if (base.length != header.baseLength) {
      throw DeltaException(
        'Base is ${base.length} bytes, delta expects ${header.baseLength}',
      );
    }
    final baseSha256 = sha256.convert(base).toString();
    if (baseSha256 != header.baseSha256) {
      throw DeltaException(
        'Base hash $baseSha256 does not match delta base ${header.baseSha256}',
      );
    }

    var offset = DeltaHeader.size;
    Uint8List section(int length) {
      if (offset + length > delta.length) {
        throw DeltaException('Delta is truncated');
      }
      final bytes = Uint8List.sublistView(delta, offset, offset + length);
      offset += length;
      return header.compression.decode(bytes);
    }

    final control = _Reader(section(header.controlLength));
    final diff = section(header.diffLength);
    final extra = section(header.extraLength);
    final target = Uint8List(header.targetLength);

    var diffPos = 0;
    var extraPos = 0;
    var basePos = 0;
    var targetPos = 0;
    while (targetPos < target.length) {
      final addLength = control.readVarint();
      final copyLength = control.readVarint();
      final seek = control.readSignedVarint();
      if (targetPos + addLength > target.length ||
          diffPos + addLength > diff.length) {
        throw DeltaException('Corrupt delta: add overruns target');
      }
      for (var i = 0; i < addLength; i++) {
        final b = basePos + i;
        final old = b >= 0 && b < base.length ? base[b] : 0;
        target[targetPos + i] = (old + diff[diffPos + i]) & 0xff;
      }
      targetPos += addLength;
      basePos += addLength;
      diffPos += addLength;

      if (targetPos + copyLength > target.length ||
          extraPos + copyLength > extra.length) {
        throw DeltaException('Corrupt delta: copy overruns target');
      }
      target.setRange(targetPos, targetPos + copyLength, extra, extraPos);
      targetPos += copyLength;
      extraPos += copyLength;
      basePos += seek;
    }

    final targetSha256 = sha256.convert(target).toString();
    if (targetSha256 != header.targetSha256) {
      throw DeltaException(
        'Rebuilt artifact hash $targetSha256 does not match '
        '${header.targetSha256}',
      );
    }
    return target;
  }

  static _Streams _diff(Uint8List base, Uint8List target) {
    final index = suffixSort(base);
    final control = _Writer();
    final diff = BytesBuilder(copy: false);
    final extra = BytesBuilder(copy: false);
    final baseSize = base.length;
    final targetSize = target.length;

    var pos = 0;
    var len = 0;
    var scan = 0;
    var lastPos = 0;
    var lastScan = 0;
    var lastOffset = 0;

    while (scan < targetSize) {
      var oldScore = 0;
      scan += len;
      var scsc = scan;
      while (scan < targetSize) {
        final match = _search(index, base, target, scan, 0, baseSize);
        len = match.length;
        pos = match.position;
        for (; scsc < scan + len; scsc++) {
          if (scsc + lastOffset < baseSize &&
              base[scsc + lastOffset] == target[scsc]) {
            oldScore++;
          }
        }
        if ((len == oldScore && len != 0) || len > oldScore + 8) break;
        if (scan + lastOffset < baseSize &&
            base[scan + lastOffset] == target[scan]) {
          oldScore--;
        }
        scan++;
      }

      if (len != oldScore || scan == targetSize) {
        var s = 0;
        var sf = 0;
        var lenF = 0;
        for (var i = 0; lastScan + i < scan && lastPos + i < baseSize;) {
          if (base[lastPos + i] == target[lastScan + i]) s++;
          i++;
          if (s * 2 - i > sf * 2 - lenF) {
            sf = s;
            lenF = i;
          }
        }

        var lenB = 0;
        if (scan < targetSize) {
          s = 0;
          var sb = 0;
          for (var i = 1; scan >= lastScan + i && pos >= i; i++) {
            if (base[pos - i] == target[scan - i]) s++;
            if (s * 2 - i > sb * 2 - lenB) {
              sb = s;
              lenB = i;
            }
          }
        }

        if (lastScan + lenF > scan - lenB) {
          final overlap = (lastScan + lenF) - (scan - lenB);
          s = 0;
          var ss = 0;
          var lenS = 0;
          for (var i = 0; i < overlap; i++) {
            if (target[lastScan + lenF - overlap + i] ==
                base[lastPos + lenF - overlap + i]) {
              s++;
            }
            if (target[scan - lenB + i] == base[pos - lenB + i]) s--;
            if (s > ss) {
              ss = s;
              lenS = i + 1;
            }
          }
          lenF += lenS - overlap;
          lenB -= lenS;
        }

        final diffChunk = Uint8List(lenF);
        for (var i = 0; i < lenF; i++) {
          diffChunk[i] = (target[lastScan + i] - base[lastPos + i]) & 0xff;
        }
        diff.add(diffChunk);
        final extraLength = (scan - lenB) - (lastScan + lenF);
        extra.add(
          Uint8List.sublistView(
            target,
            lastScan + lenF,
            lastScan + lenF + extraLength,
          ),
        );

        control
          ..writeVarint(lenF)
          ..writeVarint(extraLength)
          ..writeSignedVarint((pos - lenB) - (lastPos + lenF));

        lastScan = scan - lenB;
        lastPos = pos - lenB;
        lastOffset = pos - scan;
      }
    }

    return _Streams(
      baseLength: baseSize,
      targetLength: targetSize,
      control: control.takeBytes(),
      diff: diff.takeBytes(),
      extra: extra.takeBytes(),
      baseSha256: sha256.convert(base).toString(),
      targetSha256: sha256.convert(target).toString(),
    );
  }

  static ({int length, int position}) _search(
    Int32List index,
    Uint8List base,
    Uint8List target,
    int targetStart,
    int start,
    int end,
  ) {
    var st = start;
    var en = end;
    while (en - st >= 2) {
      final mid = st + (en - st) ~/ 2;
      if (_compare(base, index[mid], target, targetStart) < 0) {
        st = mid;
      } else {
        en = mid;
      }
    }
    final x = _matchLength(base, index[st], target, targetStart);
    final y = _matchLength(base, index[en], target, targetStart);
    return x > y
        ? (length: x, position: index[st])
        : (length: y, position: index[en]);
  }

  static int _matchLength(Uint8List a, int aStart, Uint8List b, int bStart) {
    var i = 0;
    while (aStart + i < a.length &&
        bStart + i < b.length &&
        a[aStart + i] == b[bStart + i]) {
      i++;
    }
    return i;
  }

  /// Lexicographic order of the base suffix against the remaining target.
  /// When one is a prefix of the other, the shorter sorts first. Reference
  /// bsdiff compares only the common length and treats a prefix as equal,
  /// which on zero-filled runs drives every search to a one byte match and
  /// makes the diff quadratic.
  static int _compare(Uint8List a, int aStart, Uint8List b, int bStart) {
    final aRemaining = a.length - aStart;
    final bRemaining = b.length - bStart;
    final n = aRemaining < bRemaining ? aRemaining : bRemaining;
    for (var i = 0; i < n; i++) {
      final d = a[aStart + i] - b[bStart + i];
      if (d != 0) return d;
    }
    return aRemaining - bRemaining;
  }
}

class _Streams {
  final int baseLength;
  final int targetLength;
  final String baseSha256;
  final String targetSha256;
  final Uint8List diff;
  final Uint8List extra;
  final Uint8List control;

  const _Streams({
    required this.baseLength,
    required this.targetLength,
    required this.baseSha256,
    required this.targetSha256,
    required this.diff,
    required this.extra,
    required this.control,
  });
}

class _Writer {
  final BytesBuilder _builder = BytesBuilder();

  void writeVarint(int value) {
    var v = value;
    while (v >= 0x80) {
      _builder.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _builder.addByte(v);
  }

  void writeSignedVarint(int value) =>
      writeVarint(value >= 0 ? value << 1 : ((-value) << 1) - 1);

  Uint8List takeBytes() => _builder.takeBytes();
}

class _Reader {
  final Uint8List _bytes;
  int _offset = 0;

  _Reader(this._bytes);

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (true) {
      if (_offset >= _bytes.length) {
        throw DeltaException('Corrupt delta: control stream ended early');
      }
      final b = _bytes[_offset++];
      result |= (b & 0x7f) << shift;
      if (b < 0x80) return result;
      shift += 7;
      if (shift > 56) throw DeltaException('Corrupt delta: varint too long');
    }
  }

  int readSignedVarint() {
    final v = readVarint();
    return v.isEven ? v >> 1 : -((v + 1) >> 1);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
