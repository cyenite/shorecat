import 'dart:math';
import 'dart:typed_data';

import 'package:shorecat_core/shorecat_core.dart';
import 'package:shorecat_core/src/delta/suffix_array.dart';
import 'package:test/test.dart';

void main() {
  final random = Random(42);

  Uint8List randomBytes(int length, {int alphabet = 256}) => Uint8List.fromList(
    List.generate(length, (_) => random.nextInt(alphabet)),
  );

  Uint8List mutate(Uint8List base) {
    final out = List<int>.of(base);
    for (var edit = 0; edit < 1 + random.nextInt(12); edit++) {
      final at = out.isEmpty ? 0 : random.nextInt(out.length);
      switch (random.nextInt(4)) {
        case 0:
          out.insertAll(at, randomBytes(random.nextInt(64)));
        case 1:
          out.removeRange(at, min(out.length, at + random.nextInt(64)));
        case 2:
          for (var i = at; i < min(out.length, at + 32); i++) {
            out[i] = (out[i] + 1) & 0xff;
          }
        default:
          if (out.length > 200) {
            final start = random.nextInt(out.length - 100);
            out.insertAll(at, out.sublist(start, start + 100));
          }
      }
    }
    return Uint8List.fromList(out);
  }

  group('suffixSort', () {
    test('orders suffixes like a naive sort', () {
      for (var round = 0; round < 50; round++) {
        final data = randomBytes(
          random.nextInt(300),
          alphabet: 1 + random.nextInt(4),
        );
        final expected = List.generate(data.length + 1, (i) => i)
          ..sort((a, b) {
            final n = min(data.length - a, data.length - b);
            for (var i = 0; i < n; i++) {
              final d = data[a + i] - data[b + i];
              if (d != 0) return d;
            }
            return (data.length - a) - (data.length - b);
          });
        expect(suffixSort(data).toList(), expected);
      }
    });
  });

  group('Delta', () {
    test('round trips random edits with every compression', () {
      for (var round = 0; round < 40; round++) {
        final base = randomBytes(
          random.nextInt(4000),
          alphabet: 1 + random.nextInt(255),
        );
        final target = mutate(base);
        final compression =
            Compression.values[round % Compression.values.length];
        final delta = Delta.create(base, target, compression: compression);
        expect(Delta.apply(base, delta), target, reason: 'round $round');
      }
    });

    test('handles empty inputs', () {
      final empty = Uint8List(0);
      final some = randomBytes(100);
      expect(Delta.apply(empty, Delta.create(empty, some)), some);
      expect(Delta.apply(some, Delta.create(some, empty)), empty);
      expect(Delta.apply(empty, Delta.create(empty, empty)), empty);
    });

    test('a one byte change to a large file yields a tiny delta', () {
      final base = randomBytes(1 << 20);
      final target = Uint8List.fromList([...base, 7]);
      target[500000] ^= 0xff;
      final delta = Delta.createSmallest(base, target);
      expect(delta.length, lessThan(DeltaHeader.size + 128));
      expect(Delta.apply(base, delta), target);
    });

    test('handles long runs of identical bytes', () {
      final base = Uint8List(200000);
      final target = Uint8List(200100)..[150000] = 1;
      expect(Delta.apply(base, Delta.create(base, target)), target);
    });

    test('refuses the wrong base', () {
      final base = randomBytes(1000);
      final delta = Delta.create(base, mutate(base));
      final other = Uint8List.fromList(base)..[10] ^= 1;
      expect(() => Delta.apply(other, delta), throwsA(isA<DeltaException>()));
    });

    test('detects a tampered payload', () {
      final base = randomBytes(5000);
      final target = mutate(base);
      final delta = Delta.create(base, target, compression: Compression.none);
      delta[delta.length - 1] ^= 0x55;
      expect(() => Delta.apply(base, delta), throwsA(isA<DeltaException>()));
    });

    test('header records both endpoints', () {
      final base = randomBytes(100);
      final target = mutate(base);
      final header = DeltaHeader.parse(Delta.create(base, target));
      expect(header.baseLength, base.length);
      expect(header.targetLength, target.length);
      expect(header.baseSha256, sha256Hex(base));
      expect(header.targetSha256, sha256Hex(target));
    });
  });
}
