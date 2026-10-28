import 'update_prompt.dart';

/// Offers a user-controlled restart once a verified patch is ready to boot.
/// Place inside a Material app, for example above a Scaffold's body content.
class ShorecatUpdateBanner extends ShorecatUpdatePrompt {
  const ShorecatUpdateBanner({
    super.key,
    super.title,
    super.message,
    super.laterLabel,
    super.restartLabel,
    super.restartingLabel,
    super.restartErrorMessage,
    super.shorecat,
    super.onBeforeRestart,
  });
}
