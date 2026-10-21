package org.turinglabs.makeet

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PasswordAccessTest {
    companion object {
        @BeforeClass @JvmStatic fun englishFixture() {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync {
                val context = instrumentation.targetContext
                Assume.assumeTrue(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
                Assume.assumeFalse(java.io.File(context.noBackupFilesDir, "makeet-session").exists())
                if(android.os.Build.VERSION.SDK_INT >= 33) context.getSystemService(android.app.LocaleManager::class.java).applicationLocales = android.os.LocaleList.forLanguageTags("en")
                else androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags("en"))
            }
        }
    }
    @get:Rule val ui = createAndroidComposeRule<PasswordTestActivity>()
    private fun openPassword() {
        ui.onNodeWithContentDescription("Account").performClick()
        ui.waitUntil(5000) { ui.onAllNodesWithText("Sign in with password").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("Sign in with password").performScrollTo().performClick()
    }
    private fun input(label: String, value: String) { ui.onNodeWithText(label).performScrollTo().performTextReplacement(value) }
    private fun click(label: String) { ui.onNodeWithText(label, useUnmergedTree = true).performScrollTo().performClick() }
    @Test fun registerRetryCodeRecreateLogoutAndRecover() {
        openPassword()
        click("Create account")
        input("Username", "native.user")
        input("Recovery email", "qa@example.invalid")
        input("Password", "native fixture password 123")
        input("Repeat password", "native fixture password 123")
        click("Send code")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Verification code").fetchSemanticsNodes().isNotEmpty() }
        input("Verification code", "00000000"); click("Confirm code")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Check your details or code and try again. Your archive is retained.").fetchSemanticsNodes().isNotEmpty() }
        input("Verification code", "12345678"); click("Confirm code")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Edit profile").fetchSemanticsNodes().isNotEmpty() }
        ui.activityRule.scenario.recreate()
        ui.waitForIdle()
        ui.onNodeWithText("Edit profile").assertExists()
        click("Sign out")
        click("Sign in with password"); click("Forgot password")
        input("Username or email", "native.user"); click("Send code")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Verification code").fetchSemanticsNodes().isNotEmpty() }
        input("Verification code", "12345678")
        input("Password", "replacement fixture password 456")
        input("Repeat password", "replacement fixture password 456")
        click("Confirm code")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Edit profile").fetchSemanticsNodes().isNotEmpty() }
    }
    @Test fun wrongPasswordAndCancelledRegistrationRetainLocalArchive() {
        openPassword()
        input("Username or email", "missing.user"); input("Password", "wrong fixture password")
        click("Sign in")
        ui.waitUntil(5000) { ui.onAllNodesWithText("Check your details or code and try again. Your archive is retained.").fetchSemanticsNodes().isNotEmpty() }
        click("Create account"); input("Username", "cancelled.user")
        ui.onAllNodesWithContentDescription("Back").onLast().performClick()
        ui.onNodeWithText("Your private archive, synced for free.").assertExists()
        ui.onAllNodesWithText("Edit profile").assertCountEquals(0)
    }
}
