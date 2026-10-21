package org.turinglabs.makeet

import android.content.Intent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PasswordEnrollmentTest {
    @get:Rule val ui = createEmptyComposeRule()
    @Test fun existingAccountEnrollsAndReopensCredentials() {
        val instrumentation = InstrumentationRegistry.getInstrumentation(); val context = instrumentation.targetContext
        Assume.assumeTrue(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
        Assume.assumeFalse(java.io.File(context.noBackupFilesDir, "makeet-session").exists())
        instrumentation.runOnMainSync {
            if(android.os.Build.VERSION.SDK_INT >= 33) context.getSystemService(android.app.LocaleManager::class.java).applicationLocales = android.os.LocaleList.forLanguageTags("en")
            else androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(androidx.core.os.LocaleListCompat.forLanguageTags("en"))
        }
        ActivityScenario.launch<PasswordTestActivity>(Intent(context, PasswordTestActivity::class.java).putExtra("password_account_fixture", true)).use {
            ui.onNodeWithContentDescription("Account").performClick()
            ui.waitUntil(5000) { ui.onAllNodesWithText("Username and password").fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText("Username and password").performScrollTo().performClick()
            fun input(label: String, value: String) { ui.onNodeWithText(label).performScrollTo().performTextReplacement(value) }
            input("Username", "provider.user"); input("Recovery email", "qa@example.invalid")
            input("Password", "provider fixture password 123"); input("Repeat password", "provider fixture password 123")
            ui.onNodeWithText("Send code").performScrollTo().performClick()
            ui.waitUntil(5000) { ui.onAllNodesWithText("Verification code").fetchSemanticsNodes().isNotEmpty() }
            input("Verification code", "12345678")
            ui.onNodeWithText("Confirm code").performScrollTo().performClick()
            ui.waitUntil(5000) { ui.onAllNodesWithText("Credentials saved. You can use them on your other device too.").fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText("Done").performClick()
            ui.onNodeWithText("Edit profile").assertExists()
            ui.onNodeWithText("Username and password").performScrollTo().performClick()
            ui.waitUntil(5000) { ui.onAllNodesWithText("provider.user").fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText("provider.user").assertExists()
        }
    }
}
