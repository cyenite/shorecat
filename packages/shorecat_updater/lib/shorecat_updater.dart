/// Pure Dart shorecat updater.
library;

export 'package:shorecat_core/shorecat_core.dart'
    show AppPlatform, Arch, PatchCheckResponse, PatchPublicKey;

export 'src/android_artifact.dart';
export 'src/state.dart' show Pointers, PatchState;
export 'src/updater.dart';
