package org.turinglabs.makeet

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class StoreScreenshotsTest {
    @get:Rule val ui = createEmptyComposeRule()
    @Test fun captureRealLocalizedScreensWithExplicitlyLabeledDemoData() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("makeet_store_assets") == "true")
        Assume.assumeTrue(android.os.Build.MODEL.contains("sdk_gphone"))
        val context = instrumentation.targetContext
        Assume.assumeFalse(File(context.noBackupFilesDir, "makeet-session").exists())
        for(tag in listOf("en", "it", "fr", "de", "es")) {
            context.deleteDatabase("makeet-local.db")
            context.getSharedPreferences("makeet", Context.MODE_PRIVATE).edit().clear().putBoolean("onboarding.android.v1", true).commit()
            instrumentation.runOnMainSync { context.getSystemService(android.app.LocaleManager::class.java).applicationLocales = android.os.LocaleList.forLanguageTags(tag) }
            val localized = context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(tag)) })
            fun label(key: String) = localized.getString(Strings.resources.getValue(key))
            ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use {
                ui.waitUntil(5000) { ui.onAllNodesWithText(label("Explore with demo data")).fetchSemanticsNodes().isNotEmpty() }
                ui.onNodeWithText(label("Explore with demo data")).performClick()
                ui.waitUntil(5000) { ui.onAllNodesWithText(label("Demo data")).fetchSemanticsNodes().isNotEmpty() }
                for((screen, key) in listOf("today" to "Today", "calendar" to "Calendar", "trends" to "Trends", "plan" to "Your plan")) {
                    if(screen != "today") ui.onNodeWithText(label(key)).performClick()
                    ui.waitForIdle()
                    ui.onNodeWithText(label("Demo data")).assertIsDisplayed()
                    instrumentation.waitForIdleSync()
                    instrumentation.uiAutomation.waitForIdle(300, 3000)
                    val bitmap = instrumentation.uiAutomation.takeScreenshot()
                    File(context.getExternalFilesDir(null), "store-$tag-$screen.png").outputStream().use { output -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, output) }
                }
            }
        }
        context.deleteDatabase("makeet-local.db")
    }
}
