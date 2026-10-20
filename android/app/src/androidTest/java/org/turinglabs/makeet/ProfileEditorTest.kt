package org.turinglabs.makeet

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileEditorTest {
    companion object {
        @BeforeClass @JvmStatic fun englishFixture() {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync {
                if(android.os.Build.VERSION.SDK_INT >= 33) instrumentation.targetContext.getSystemService(android.app.LocaleManager::class.java).applicationLocales = android.os.LocaleList.forLanguageTags("en")
            }
        }
    }
    @get:Rule val ui = createAndroidComposeRule<ProfileTestActivity>()
    @Test fun selectedPhotoIsOrientedResizedAndStrippedOfMetadata() = kotlinx.coroutines.runBlocking {
        val source = java.io.File(ui.activity.cacheDir, "makeet-profile-qa.jpg")
        try {
            val bitmap = android.graphics.Bitmap.createBitmap(640, 320, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            canvas.drawColor(android.graphics.Color.BLUE)
            canvas.drawRect(0f, 0f, 320f, 320f, android.graphics.Paint().apply { color = android.graphics.Color.RED })
            source.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, it) }
            android.media.ExifInterface(source.path).apply {
                setAttribute(android.media.ExifInterface.TAG_ORIENTATION, "6")
                setAttribute(android.media.ExifInterface.TAG_ARTIST, "Makeet QA metadata")
                saveAttributes()
            }
            val normalized = ui.activity.model.normalizePhoto(android.net.Uri.fromFile(source))
            val bytes = android.util.Base64.decode(normalized, android.util.Base64.DEFAULT)
            val output = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            Assert.assertEquals(320, output.width); Assert.assertEquals(320, output.height)
            Assert.assertTrue(android.graphics.Color.red(output.getPixel(160, 40)) > 200)
            Assert.assertTrue(android.graphics.Color.blue(output.getPixel(160, 280)) > 200)
            val exif = android.media.ExifInterface(java.io.ByteArrayInputStream(bytes))
            Assert.assertNull(exif.getAttribute(android.media.ExifInterface.TAG_ARTIST))
            Assert.assertTrue(runCatching { ui.activity.model.normalizePhoto(android.net.Uri.fromFile(java.io.File(source.parentFile, "missing-photo"))) }.isFailure)
        } finally { source.delete() }
    }
    @Test fun profileSaveCancelAndConflictKeepStableNavigation() {
        ui.waitUntil(5000) { ui.onAllNodesWithContentDescription("Account").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithContentDescription("Account").performClick()
        ui.waitUntil(5000) { ui.onAllNodesWithText("Edit profile").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("Edit profile").performClick()
        ui.onNodeWithText("Your name").performTextReplacement("Changed QA")
        ui.onNodeWithText("Save", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { ui.onAllNodesWithText("Changed QA").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("Connections").assertExists()
        ui.onNodeWithText("Edit profile").performClick()
        ui.onNodeWithText("Your name").performTextReplacement("Cancelled QA")
        ui.onAllNodesWithContentDescription("Back").onLast().performClick()
        ui.onNodeWithText("Changed QA").assertExists()
        ui.activity.conflict = true
        ui.onNodeWithText("Edit profile").performClick()
        ui.onNodeWithText("Your name").performTextReplacement("Stale QA")
        ui.onNodeWithText("Save", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { ui.onAllNodesWithText("Your profile changed on another device. Reopen the editor to load the latest version.").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("OK").performClick()
        ui.onAllNodesWithContentDescription("Back").onLast().performClick()
        ui.onNodeWithText("Edit profile").performClick()
        ui.onNode(hasSetTextAction() and hasText("Remote QA")).assertExists()
        Assert.assertEquals("Remote QA", ui.activity.profile.getString("name"))
    }
}
