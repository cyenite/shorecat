package dev.shorecat.code_push

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

/**
 * Drop-in replacement for FlutterActivity that boots the installed patch.
 * The engine stays owned by Flutter's activity delegate; only the AOT
 * library it loads changes.
 */
open class ShorecatFlutterActivity : FlutterActivity() {
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        ShorecatBoot.engineArgs(this).forEach(args::add)
        return args
    }
}
