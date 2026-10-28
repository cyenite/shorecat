import 'package:flutter/foundation.dart';

import '../shorecat_code_push.dart';

/// Restart state and actions for an update UI, built-in or your own.
///
/// Listen to it, show your UI while [isVisible], and call [restart] or [defer]
/// from your buttons. [ShorecatUpdateBuilder] and the `builder` of
/// [ShorecatUpdatePrompt] create and dispose one for you.
class ShorecatUpdateController extends ChangeNotifier {
  bool _isDisposed = false;
  bool _isRestarting = false;
  int? _failedPatchNumber;
  int? _deferredPatchNumber;
  final Shorecat? shorecat;

  /// Save work or ask for confirmation; return false to cancel the restart.
  /// Exceptions set [hasRestartFailed] so the user can try again.
  final Future<bool> Function()? onBeforeRestart;

  /// Uses [Shorecat.instance] unless [shorecat] is given.
  ShorecatUpdateController({Shorecat? shorecat, this.onBeforeRestart})
    : shorecat = shorecat ?? Shorecat.instance {
    this.shorecat?.addListener(notifyListeners);
  }

  /// A verified patch is installed and a restart would boot it, whether or not
  /// the user deferred it.
  bool get isRestartRequired =>
      !_isDisposed && shorecat?.isHooked == true && shorecat!.isRestartRequired;

  /// The patch a restart would boot, or null when none is waiting.
  int? get patchNumber => isRestartRequired ? shorecat!.nextPatchNumber : null;

  /// The user chose Later for the waiting patch. A newer patch clears this.
  bool get isDeferred =>
      isRestartRequired && _deferredPatchNumber == shorecat!.nextPatchNumber;

  /// A prompt should be showing: a patch is waiting and was not deferred.
  bool get isVisible => isRestartRequired && !isDeferred;

  /// [onBeforeRestart] or the platform restart is in progress.
  bool get isRestarting => _isRestarting;

  /// The last restart of the waiting patch failed; offer a retry.
  bool get hasRestartFailed =>
      _failedPatchNumber != null &&
      _failedPatchNumber == shorecat?.nextPatchNumber;

  /// Hides prompts for the waiting patch. It still applies on the next launch.
  void defer() {
    if (_isDisposed || _isRestarting) return;
    _deferredPatchNumber = shorecat?.nextPatchNumber;
    notifyListeners();
  }

  /// Runs [onBeforeRestart], then relaunches the app into the waiting patch.
  /// Works after [defer], for example from a settings screen. Does nothing
  /// when no patch is waiting or a restart is already in progress.
  Future<void> restart() async {
    if (!isRestartRequired || _isRestarting) return;
    final patchNumber = shorecat!.nextPatchNumber;
    _isRestarting = true;
    _failedPatchNumber = null;
    notifyListeners();
    try {
      final canRestart = await onBeforeRestart?.call() ?? true;
      if (_isDisposed) return;
      if (!canRestart ||
          !isRestartRequired ||
          shorecat!.nextPatchNumber != patchNumber) {
        _isRestarting = false;
        notifyListeners();
        return;
      }
      await shorecat!.restart();
    } on Object {
      if (_isDisposed) return;
      _isRestarting = false;
      _failedPatchNumber = patchNumber;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    shorecat?.removeListener(notifyListeners);
    super.dispose();
  }
}
