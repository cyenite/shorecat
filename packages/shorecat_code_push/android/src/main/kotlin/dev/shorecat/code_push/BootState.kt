package dev.shorecat.code_push

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Chooses the AOT library for this process before the Flutter engine starts.
 *
 * This is a port of `Updater.beginLaunch` in the shorecat_updater Dart
 * package and must stay in step with it: both read and write the same
 * `pointers.json`, `patches/<n>/state.json` and `pending_events.json`.
 * It has no Android dependencies so it can be unit tested on the JVM.
 */
class BootState(private val root: File, private val releaseVersion: String) {
    data class Decision(
        val patchNumber: Int? = null,
        val libraryPath: String? = null,
        val crashedPatchNumber: Int? = null,
    )

    private val pointersFile = File(root, "pointers.json")

    fun decide(now: Long = System.currentTimeMillis()): Decision {
        if (!pointersFile.exists()) return Decision()
        val p = JSONObject(pointersFile.readText())
        // The Dart updater wipes patches for a new store release on its next start.
        if (p.optString("release_version") != releaseVersion) return Decision()

        var crashed: Int? = null
        val stale = p.intOrNull("currently_booting")
        if (stale != null) {
            if (p.optInt("boot_attempts", 0) >= p.optInt("max_boot_attempts", 1)) {
                crashed = stale
                markBad(stale, "boot_crash")
                queueEvent("boot_failure", stale, "Crashed during boot")
                p.putNullable("currently_booting", null)
                p.put("boot_attempts", 0)
                if (p.intOrNull("next_boot") == stale) p.putNullable("next_boot", null)
                if (p.intOrNull("last_booted") == stale) p.putNullable("last_booted", null)
            } else {
                p.putNullable("currently_booting", null)
            }
        }

        for (candidate in listOf(p.intOrNull("next_boot"), p.intOrNull("last_booted"))) {
            if (candidate == null) continue
            if (isBootable(candidate)) {
                val attempts = (if (candidate == stale) p.optInt("boot_attempts", 0) else 0) + 1
                p.put("running", candidate)
                p.put("next_boot", candidate)
                p.put("currently_booting", candidate)
                p.put("boot_attempts", attempts)
                p.put("boot_started_at", now)
                writeAtomic(pointersFile, p.toString())
                return Decision(candidate, artifactOf(candidate).path, crashed)
            }
            markBad(candidate, "hash_mismatch")
            if (p.intOrNull("next_boot") == candidate) p.putNullable("next_boot", null)
            if (p.intOrNull("last_booted") == candidate) p.putNullable("last_booted", null)
        }

        p.putNullable("running", null)
        p.putNullable("next_boot", null)
        p.put("boot_attempts", 0)
        writeAtomic(pointersFile, p.toString())
        return Decision(crashedPatchNumber = crashed)
    }

    fun artifactOf(number: Int) = File(root, "patches/$number/libapp.so")

    private fun stateFile(number: Int) = File(root, "patches/$number/state.json")

    private fun isBootable(number: Int): Boolean {
        val state = stateFile(number)
        if (!state.exists()) return false
        val record = JSONObject(state.readText())
        if (record.optString("state") != "installed") return false
        val artifact = artifactOf(number)
        return artifact.exists() && sha256(artifact) == record.optString("hash")
    }

    private fun markBad(number: Int, reason: String) {
        val state = stateFile(number)
        val hash = if (state.exists()) JSONObject(state.readText()).optString("hash") else ""
        val record = JSONObject()
            .put("number", number)
            .put("state", "bad")
            .put("hash", hash)
            .put("reason", reason)
        writeAtomic(state, record.toString())
    }

    private fun queueEvent(type: String, patchNumber: Int, message: String) {
        val file = File(root, "pending_events.json")
        val events = if (file.exists()) {
            runCatching { JSONArray(file.readText()) }.getOrDefault(JSONArray())
        } else {
            JSONArray()
        }
        events.put(
            JSONObject()
                .put("type", type)
                .put("patch_number", patchNumber)
                .put("timestamp", System.currentTimeMillis())
                .put("message", message),
        )
        writeAtomic(file, events.toString())
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun writeAtomic(file: File, text: String) {
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.outputStream().use { out ->
            out.write(text.toByteArray())
            out.fd.sync()
        }
        if (!tmp.renameTo(file)) throw IllegalStateException("Could not replace ${file.path}")
    }

    private fun JSONObject.intOrNull(key: String): Int? = if (isNull(key)) null else getInt(key)

    private fun JSONObject.putNullable(key: String, value: Int?) {
        put(key, value ?: JSONObject.NULL)
    }
}
