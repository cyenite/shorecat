package dev.shorecat.code_push

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Build
import android.util.Log
import java.io.File

/**
 * Process-wide boot decision. The Flutter loader only honours shell args on
 * its first initialisation, so the choice is made once and every engine in
 * the process (activity recreation, add-to-app) reuses it.
 */
object ShorecatBoot {
    private const val TAG = "shorecat"
    private const val AOT_FLAG = "--aot-shared-library-name="

    @Volatile
    private var decision: BootState.Decision? = null

    @JvmStatic
    @Synchronized
    fun decide(context: Context): BootState.Decision {
        decision?.let { return it }
        val app = context.applicationContext
        val result = try {
            BootState(storageDir(app), releaseVersion(app)).decide()
        } catch (t: Throwable) {
            Log.e(TAG, "Boot decision failed; starting the base release", t)
            BootState.Decision()
        }
        result.crashedPatchNumber?.let { Log.w(TAG, "Patch $it crashed during boot; rolled back") }
        result.patchNumber?.let { Log.i(TAG, "Booting patch $it") }
        decision = result
        return result
    }

    /** The decision made for this process, or null when no host asked. */
    @JvmStatic
    fun current(): BootState.Decision? = decision

    /** Engine args for hosts that create their own FlutterEngine. */
    @JvmStatic
    fun engineArgs(context: Context): Array<String> {
        val path = decide(context).libraryPath ?: return emptyArray()
        return arrayOf(AOT_FLAG + path)
    }

    @JvmStatic
    fun storageDir(context: Context) = File(context.filesDir, "shorecat")

    /** Must match what the Dart side reports as the release version. */
    @JvmStatic
    fun releaseVersion(context: Context): String {
        val info = packageInfo(context)
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return "${info.versionName}+$code"
    }

    private fun packageInfo(context: Context): PackageInfo =
        context.packageManager.getPackageInfo(context.packageName, 0)
}
