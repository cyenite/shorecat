package dev.shorecat.code_push

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BootStateTest {
    private lateinit var root: File

    @BeforeTest
    fun setUp() {
        root = Files.createTempDirectory("shorecat-boot").toFile()
    }

    @AfterTest
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun pointers(vararg pairs: Pair<String, Any?>) {
        val json = JSONObject().put("release_version", "1.0.0+1")
        for ((k, v) in pairs) json.put(k, v ?: JSONObject.NULL)
        File(root, "pointers.json").writeText(json.toString())
    }

    private fun readPointers() = JSONObject(File(root, "pointers.json").readText())

    private fun install(number: Int, bytes: ByteArray = "patch $number".toByteArray()) {
        val dir = File(root, "patches/$number").apply { mkdirs() }
        File(dir, "libapp.so").writeBytes(bytes)
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        File(dir, "state.json").writeText(
            JSONObject().put("number", number).put("state", "installed").put("hash", hash).toString(),
        )
    }

    private fun state(number: Int) =
        JSONObject(File(root, "patches/$number/state.json").readText()).getString("state")

    private fun decide() = BootState(root, "1.0.0+1").decide(now = 1)

    @Test
    fun noStateBootsTheBase() {
        assertNull(decide().libraryPath)
    }

    @Test
    fun bootsTheInstalledPatchAndLeavesABreadcrumb() {
        install(1)
        pointers("next_boot" to 1)
        val decision = decide()
        assertEquals(1, decision.patchNumber)
        assertEquals(File(root, "patches/1/libapp.so").path, decision.libraryPath)
        val p = readPointers()
        assertEquals(1, p.getInt("currently_booting"))
        assertEquals(1, p.getInt("running"))
        assertEquals(1, p.getInt("boot_attempts"))
    }

    @Test
    fun aStaleBreadcrumbMarksThePatchBadAndFallsBack() {
        install(1)
        install(2)
        pointers("next_boot" to 2, "last_booted" to 1, "currently_booting" to 2, "boot_attempts" to 1)
        val decision = decide()
        assertEquals(2, decision.crashedPatchNumber)
        assertEquals(1, decision.patchNumber)
        assertEquals("bad", state(2))
        val events = JSONArray(File(root, "pending_events.json").readText())
        assertEquals("boot_failure", events.getJSONObject(0).getString("type"))
        assertEquals(2, events.getJSONObject(0).getInt("patch_number"))
    }

    @Test
    fun maxBootAttemptsAllowsARetry() {
        install(1)
        pointers("next_boot" to 1, "currently_booting" to 1, "boot_attempts" to 1, "max_boot_attempts" to 2)
        assertEquals(1, decide().patchNumber)
        assertEquals(2, readPointers().getInt("boot_attempts"))
    }

    @Test
    fun aTamperedArtifactIsNotBooted() {
        install(1)
        File(root, "patches/1/libapp.so").appendText("x")
        pointers("next_boot" to 1)
        assertNull(decide().libraryPath)
        assertEquals("bad", state(1))
        assertTrue(readPointers().isNull("next_boot"))
    }

    @Test
    fun anotherReleaseVersionBootsTheBase() {
        install(1)
        pointers("next_boot" to 1)
        assertNull(BootState(root, "2.0.0+2").decide().libraryPath)
    }
}
