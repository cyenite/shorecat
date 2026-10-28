import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:shorecat_cli/shorecat_cli.dart';
import 'package:shorecat_core/shorecat_core.dart';
import 'package:test/test.dart';

void main() {
  group('addAsset', () {
    test('adds an assets list under flutter:', () {
      const pubspec = 'name: app\n\nflutter:\n  uses-material-design: true\n';
      expect(
        addAsset(pubspec, 'shorecat.yaml'),
        'name: app\n\nflutter:\n  assets:\n    - shorecat.yaml\n  uses-material-design: true\n',
      );
    });

    test('appends to an existing assets list', () {
      const pubspec = 'flutter:\n  assets:\n    - images/\n';
      expect(
        addAsset(pubspec, 'shorecat.yaml'),
        'flutter:\n  assets:\n    - shorecat.yaml\n    - images/\n',
      );
    });

    test('ignores the flutter sdk dependency and creates the section', () {
      const pubspec = 'dependencies:\n  flutter:\n    sdk: flutter\n';
      expect(
        addAsset(pubspec, 'shorecat.yaml'),
        endsWith('flutter:\n  assets:\n    - shorecat.yaml\n'),
      );
    });

    test('is a no-op when already listed', () {
      expect(
        addAsset('flutter:\n  assets:\n    - shorecat.yaml\n', 'shorecat.yaml'),
        isNull,
      );
    });
  });

  group('AndroidBuild', () {
    late Directory temp;

    setUp(
      () async =>
          temp = await Directory.systemTemp.createTemp('shorecat-cli-test'),
    );
    tearDown(() => temp.delete(recursive: true));

    File zip(String name, Map<String, List<int>> entries) {
      final archive = Archive();
      entries.forEach(
        (path, bytes) =>
            archive.addFile(ArchiveFile(path, bytes.length, bytes)),
      );
      return File('${temp.path}/$name')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    }

    test(
      'reads libapp.so per ABI from an app bundle and fingerprints the rest',
      () {
        final build = AndroidBuild.read(
          zip('app.aab', {
            'base/lib/arm64-v8a/libapp.so': [1, 2, 3],
            'base/lib/x86_64/libapp.so': [4, 5],
            'base/lib/arm64-v8a/libflutter.so': [9],
            'base/dex/classes.dex': [7],
            'BUNDLE-METADATA/x': [1],
            'META-INF/CERT.SF': [1],
          }),
          ArtifactType.aab,
        );
        expect(build.libraries[Arch.arm64], Uint8List.fromList([1, 2, 3]));
        expect(build.libraries[Arch.x64], Uint8List.fromList([4, 5]));
        expect(
          build.fingerprint.keys,
          unorderedEquals(['lib/arm64-v8a/libflutter.so', 'dex/classes.dex']),
        );
      },
    );

    test('classifies changes a patch cannot carry', () {
      final changes = AndroidBuild.compare(
        {
          'classes.dex': 1,
          'assets/flutter_assets/a.png': 1,
          'lib/arm64-v8a/libfoo.so': 1,
          'x': 1,
        },
        {
          'classes.dex': 2,
          'assets/flutter_assets/a.png': 1,
          'assets/flutter_assets/b.png': 1,
          'x': 1,
        },
      );
      expect(changes[ChangeKind.android], ['changed classes.dex']);
      expect(changes[ChangeKind.assets], ['added assets/flutter_assets/b.png']);
      expect(changes[ChangeKind.native], ['removed lib/arm64-v8a/libfoo.so']);
      expect(changes.containsKey(ChangeKind.other), isFalse);
    });
  });
}
