import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// Locates the release's own `libapp.so` on an Android install, which is the
/// base every delta is applied to.
///
/// With `extractNativeLibs=false` (the default since AGP 3.6) the library is
/// never unpacked; it lives stored inside the base or ABI split APK, so the
/// APKs are searched after the native library directory.
abstract final class AndroidBaseArtifact {
  static Future<Uint8List> read({
    required String abi,
    required String nativeLibraryDir,
    required List<String> apkPaths,
  }) async {
    final extracted = File('$nativeLibraryDir/libapp.so');
    if (await extracted.exists()) return extracted.readAsBytes();

    final entry = 'lib/$abi/libapp.so';
    for (final path in apkPaths) {
      final input = InputFileStream(path);
      try {
        final file = ZipDecoder().decodeStream(input).findFile(entry);
        final bytes = file?.readBytes();
        if (bytes != null) return Uint8List.fromList(bytes);
      } finally {
        await input.close();
      }
    }
    throw StateError(
      'No $entry in $nativeLibraryDir or ${apkPaths.join(', ')}',
    );
  }
}
