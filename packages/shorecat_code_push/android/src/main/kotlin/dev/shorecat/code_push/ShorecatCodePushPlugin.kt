package dev.shorecat.code_push

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ShorecatCodePushPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.shorecat/code_push")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "environment" -> result.success(environment())
            "restart" -> {
                result.success(null)
                restart()
            }
            else -> result.notImplemented()
        }
    }

    private fun environment(): Map<String, Any?> {
        val info = context.applicationInfo
        // Never decide here: the engine is already running the base library.
        val decision = ShorecatBoot.current()
        return mapOf(
            "storage_dir" to ShorecatBoot.storageDir(context).path,
            "release_version" to ShorecatBoot.releaseVersion(context),
            "native_library_dir" to info.nativeLibraryDir,
            "apk_paths" to listOf(info.sourceDir) + (info.splitSourceDirs?.toList() ?: emptyList()),
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "booted_patch" to decision?.patchNumber,
            "crashed_patch" to decision?.crashedPatchNumber,
            "is_hooked" to (decision != null),
        )
    }

    /** Relaunches the app so a freshly installed patch takes effect now. */
    private fun restart() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(Intent.makeRestartActivityTask(intent.component))
        Runtime.getRuntime().exit(0)
    }
}
