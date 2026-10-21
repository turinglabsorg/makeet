package org.turinglabs.makeet

import android.content.Context
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.*
import org.junit.runner.RunWith
import java.time.Instant
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class WidgetScopeTest {
    @Test fun widgetIntentsConfirmZeroApplySignedStepsAndRejectAnotherAccount() {
        Assume.assumeTrue(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = UUID.randomUUID().toString()
        val other = UUID.randomUUID().toString()
        val preferences = context.getSharedPreferences("makeet", Context.MODE_PRIVATE)
        val previous = preferences.getString("scope", "local")
        val store = HabitStore(context, scope)
        try {
            val limit = Habit(name = "QA widget limit", unit = "times", target = 0.0, goal = Goal.LIMIT)
            val balance = Habit(name = "QA widget balance", unit = "times", negative = true)
            store.save(limit); store.save(balance)
            preferences.edit().putString("scope", scope).commit()
            fun intent(h: Habit, direction: Int) = Intent(context, MakeetWidget::class.java).setAction("org.turinglabs.makeet.LOG")
                .putExtra("scope", scope).putExtra("habit", h.id).putExtra("direction", direction)
            MakeetWidget().onReceive(context, intent(limit, 0))
            Assert.assertTrue(HabitEngine.progress(limit, store.activities(), limit.date(Instant.now())).complete)
            MakeetWidget().onReceive(context, intent(balance, -1))
            Assert.assertEquals(-1.0, HabitEngine.progress(balance, store.activities(), balance.date(Instant.now())).amount, 0.0)
            preferences.edit().putString("scope", other).commit()
            MakeetWidget().onReceive(context, intent(balance, -1))
            Assert.assertEquals(-1.0, HabitEngine.progress(balance, store.activities(), balance.date(Instant.now())).amount, 0.0)
        } finally {
            store.close(); context.deleteDatabase("makeet-$scope.db"); context.deleteDatabase("makeet-$other.db")
            preferences.edit().putString("scope", previous).commit()
        }
    }
}
