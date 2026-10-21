package org.turinglabs.makeet

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import org.junit.*
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class MakeetUITest {
    @get:Rule val ui = createEmptyComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private var scenario: ActivityScenario<MainActivity>? = null
    @Before fun isolatedEmulatorOnly() {
        Assume.assumeTrue(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
        Assume.assumeFalse(File(context.noBackupFilesDir, "makeet-session").exists())
        context.deleteDatabase("makeet-local.db")
        context.getSharedPreferences("makeet", Context.MODE_PRIVATE).edit().clear().commit()
        instrumentation.runOnMainSync {
            if(android.os.Build.VERSION.SDK_INT >= 33) context.getSystemService(android.app.LocaleManager::class.java).applicationLocales = android.os.LocaleList.forLanguageTags("en")
            else AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("en"))
        }
    }
    @After fun close() { scenario?.close() }
    private fun launch() {
        scenario = ActivityScenario.launch(Intent(context, MainActivity::class.java))
        ui.waitForIdle()
    }
    private fun finishOnboarding() {
        ui.onNodeWithText("Continue", useUnmergedTree = true).performClick()
        ui.onNodeWithText("Continue on this device").assertIsNotEnabled()
        ui.onNodeWithText("Only on this device").performClick()
        ui.onNodeWithText("Continue on this device").performClick()
        ui.onNodeWithText("Let’s begin").performClick()
    }
    private fun screenshot(name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        File(context.getExternalFilesDir(null), "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    @Test fun onboardingCreateWeekdaysZeroLimitEditArchiveRestoreDelete() {
        launch(); screenshot("onboarding-en"); finishOnboarding()
        ui.onNodeWithContentDescription("New habit").performClick()
        ui.onNodeWithText("Your habit").performTextInput("QA Beers")
        ui.onNodeWithContentDescription("Wednesday").performClick()
        ui.onNodeWithContentDescription("Saturday").performClick()
        ui.onNodeWithContentDescription("Sunday").performClick()
        ui.onNodeWithText("Do not exceed").performScrollTo().performClick()
        ui.onNodeWithText("Daily target").performScrollTo().performTextReplacement("0")
        screenshot("create-limit-en")
        ui.onNodeWithText("Create", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { runCatching { HabitStore(context, "local").use { it.habits().size == 1 } }.getOrDefault(false) }
        HabitStore(context, "local").use { store -> val h = store.habits().single(); Assert.assertEquals(Goal.LIMIT, h.goal); Assert.assertEquals(0.0, h.target, 0.0); Assert.assertEquals(27, h.weekdays) }
        // The current test day may be a rest day: Calendar remains the stable path to every habit.
        ui.onNodeWithText("Trends").performClick()
        ui.onNodeWithText("QA Beers").performClick()
        ui.onNodeWithText("Edit habit").performClick()
        ui.onNodeWithText("Your habit").performTextReplacement("QA Beer limit")
        ui.onNodeWithText("Save", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { it.habits().single().name == "QA Beer limit" } }
        ui.onNodeWithText("Archive", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { it.habits().single().archived } }
        ui.onNodeWithText("Restore", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { !it.habits().single().archived } }
        ui.onNodeWithTag("habit-details").performScrollToNode(hasText("Delete permanently"))
        ui.onNodeWithText("Delete permanently").performClick()
        ui.onNodeWithText("Cancel", useUnmergedTree = true).performClick()
        Assert.assertEquals(1, HabitStore(context, "local").use { it.habits().size })
        ui.onNodeWithTag("habit-details").performScrollToNode(hasText("Delete permanently"))
        ui.onNodeWithText("Delete permanently").performClick()
        ui.onNodeWithText("Delete habit and progress").performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { it.habits().isEmpty() } }
    }
    @Test fun signedProgressCalendarSaveCancelAndReopen() {
        context.getSharedPreferences("makeet", Context.MODE_PRIVATE).edit().putBoolean("onboarding.android.v1", true).commit()
        val h = Habit(name = "QA Balance", unit = "times", negative = true, createdAt = Instant.now().minusSeconds(86400 * 3))
        HabitStore(context, "local").use { it.save(h) }
        launch()
        ui.onNodeWithContentDescription("Remove a step").performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { HabitEngine.progress(h, it.activities(), h.date(Instant.now())).amount == -1.0 } }
        ui.waitUntil(5000) { ui.onAllNodesWithText("-1 / 1").fetchSemanticsNodes().isNotEmpty() }
        screenshot("today-signed-en")
        ui.onNodeWithText("Calendar", useUnmergedTree = true).performClick()
        ui.onNodeWithText("Edit progress").performScrollTo().performClick()
        ui.onNodeWithContentDescription("Remove a step").performClick()
        ui.onNodeWithText("Cancel", useUnmergedTree = true).performClick()
        Assert.assertEquals(-1.0, HabitStore(context, "local").use { HabitEngine.progress(h, it.activities(), h.date(Instant.now())).amount }, 0.0)
        ui.onNodeWithText("Edit progress").performScrollTo().performClick()
        ui.onNodeWithContentDescription("Remove a step").performClick()
        ui.onNodeWithText("Save", useUnmergedTree = true).performClick()
        ui.waitUntil(5000) { HabitStore(context, "local").use { HabitEngine.progress(h, it.activities(), h.date(Instant.now())).amount == -2.0 } }
        scenario!!.recreate(); ui.waitForIdle()
        screenshot("calendar-signed-en")
        Assert.assertEquals(-2.0, HabitStore(context, "local").use { HabitEngine.progress(h, it.activities(), h.date(Instant.now())).amount }, 0.0)
    }
    @Test fun fiveLanguageWelcomeAndNativeLanguageChoice() {
        launch()
        var previous = "en"
        for((tag, label) in listOf("en" to "English", "it" to "Italiano", "fr" to "Français", "de" to "Deutsch", "es" to "Español")) {
            if(tag != "en") {
                val old = context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(previous)) })
                ui.onNodeWithText(old.getString(Strings.resources.getValue("Language"))).performClick()
                ui.onNodeWithText(label).performClick()
            }
            val localized = context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(tag)) })
            val expected = localized.getString(Strings.resources.getValue("Make room in your day"))
            ui.waitUntil(5000) { ui.onAllNodesWithText(expected).fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText(expected).assertExists()
            screenshot("onboarding-$tag")
            previous = tag
        }
    }
    @Test fun explicitDemoNeverImportsSamplesAndClearsOnlyExamples() {
        launch(); finishOnboarding()
        ui.onNodeWithText("Explore with demo data").performClick()
        ui.waitUntil(5000) { ui.onAllNodesWithText("Demo data").fetchSemanticsNodes().isNotEmpty() }
        val account = java.util.UUID.randomUUID().toString()
        HabitStore(context, "local").use { local ->
            Assert.assertEquals(4, local.demoIDs().size)
            val real = Habit(name = "Real QA habit", unit = "times")
            local.save(real); local.log(real.id, 1.0)
            HabitStore(context, account).use { destination ->
                destination.importFromLocal(local)
                Assert.assertEquals(listOf(real.id), destination.habits().map { it.id })
                Assert.assertEquals(1, destination.activities().size)
                Assert.assertTrue(destination.demoIDs().isEmpty())
            }
            local.clearDemo()
            Assert.assertEquals(listOf(real.id), local.habits().map { it.id })
            Assert.assertEquals(1, local.activities().size)
            Assert.assertTrue(local.demoIDs().isEmpty())
        }
        context.deleteDatabase("makeet-$account.db")
    }
}
