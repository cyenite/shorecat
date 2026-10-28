/// Over-the-air Dart code updates for Flutter Android apps.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shorecat_updater/shorecat_updater.dart';

import 'src/config.dart';

export 'package:shorecat_updater/shorecat_updater.dart'
    show PatchCheckResponse, UpdateResult, UpdateStatus;

export 'src/config.dart';

/// Entry point for apps. Call [initialize] in `main()`:
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Shorecat.initialize();
///   runApp(const MyApp());
/// }
/// ```
class Shorecat {
  final bool isHooked;
  final int? crashedPatchNumber;
  final Updater updater;
  final ShorecatConfig config;

  Shorecat._({
    required this.isHooked,
    required this.crashedPatchNumber,
    required this.updater,
    required this.config,
  });

  static const _channel = MethodChannel('dev.shorecat/code_push');
  static Shorecat? _instance;

  /// Null until [initialize] succeeds, and always null in debug and profile
  /// builds, where there is no AOT library to patch.
  static Shorecat? get instance => _instance;

  /// Opens the updater, clears the boot breadcrumb once the first frame is
  /// on screen, then (with `auto_update`) checks for a patch in the
  /// background. Returns null where code push does not apply.
  static Future<Shorecat?> initialize({
    bool? isAutoUpdate,
    void Function(UpdateResult result)? onUpdate,
  }) async {
    if (_instance != null) return _instance;
    if (!kReleaseMode || !Platform.isAndroid) {
      debugPrint('shorecat: code push only runs in Android release builds');
      return null;
    }
    WidgetsFlutterBinding.ensureInitialized();

    final ShorecatConfig config;
    final Map<String, Object?> env;
    try {
      config = ShorecatConfig.parse(
        await rootBundle.loadString('shorecat.yaml'),
      );
      env = (await _channel.invokeMapMethod<String, Object?>('environment'))!;
    } on Object catch (e) {
      debugPrint('shorecat: disabled, $e');
      return null;
    }

    final nativeLibraryDir = env['native_library_dir']! as String;
    final abi = _abiOf(nativeLibraryDir, (env['abis']! as List).cast<String>());
    final arch = Arch.fromAndroidAbi(abi);
    if (arch == null) {
      debugPrint('shorecat: unsupported ABI $abi');
      return null;
    }
    final apkPaths = (env['apk_paths']! as List).cast<String>();
    final updater = await Updater.open(
      UpdaterConfig(
        maxBootAttempts: config.maxBootAttempts,
        arch: arch,
        appId: config.appId,
        channel: config.channel,
        baseUrl: config.baseUrl,
        releaseVersion: env['release_version']! as String,
        storageDir: Directory(env['storage_dir']! as String),
        platform: AppPlatform.android,
        publicKeys: config.publicKeys,
        readBaseArtifact: () =>
            _readBaseArtifact(abi, nativeLibraryDir, apkPaths),
      ),
    );

    final isHooked = env['is_hooked'] == true;
    if (!isHooked) {
      debugPrint(
        'shorecat: MainActivity does not extend ShorecatFlutterActivity, '
        'so installed patches will never boot',
      );
    }
    final shorecat = Shorecat._(
      isHooked: isHooked,
      crashedPatchNumber: env['crashed_patch'] as int?,
      updater: updater,
      config: config,
    );
    _instance = shorecat;

    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) async {
      // Background work must never surface as an unhandled error in the app.
      try {
        await updater.reportLaunchSuccess();
        if (isAutoUpdate ?? config.isAutoUpdate) {
          final result = await updater.update();
          debugPrint('shorecat: $result');
          onUpdate?.call(result);
        }
      } on Object catch (e) {
        debugPrint('shorecat: background update failed, $e');
      }
    });
    return shorecat;
  }

  /// The patch running now, or null on the base release.
  int? get currentPatchNumber => updater.currentPatchNumber;

  /// The patch the next launch will run, or null for the base release.
  int? get nextPatchNumber => updater.nextPatchNumber;

  /// A newer patch is installed and waits for a restart.
  bool get isRestartRequired => updater.isNewPatchReadyToInstall;

  Future<PatchCheckResponse> checkForUpdate() => updater.checkForUpdate();

  Future<UpdateResult> update({
    void Function(int received, int total)? onProgress,
  }) => updater.update(onProgress: onProgress);

  /// Relaunches the app so an installed patch runs immediately. Use it for
  /// critical patches, ideally after asking the user.
  Future<void> restart() => _channel.invokeMethod<void>('restart');

  /// Static so the isolate closure captures only these strings. A closure
  /// inside [initialize] shares its context with the Updater, whose futures
  /// cannot cross an isolate boundary.
  static Future<Uint8List> _readBaseArtifact(
    String abi,
    String nativeLibraryDir,
    List<String> apkPaths,
  ) => Isolate.run(
    () => AndroidBaseArtifact.read(
      abi: abi,
      nativeLibraryDir: nativeLibraryDir,
      apkPaths: apkPaths,
    ),
  );

  static String _abiOf(String nativeLibraryDir, List<String> abis) {
    final dir = nativeLibraryDir.split('/').last;
    return switch (dir) {
      'arm64' => 'arm64-v8a',
      'arm' => 'armeabi-v7a',
      'x86_64' => 'x86_64',
      _ => abis.first,
    };
  }
}
