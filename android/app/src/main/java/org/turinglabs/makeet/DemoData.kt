package org.turinglabs.makeet

import android.content.Context
import org.json.JSONArray
import java.time.*

object DemoData {
    fun seed(store: HabitStore, context: Context) = store.transaction {
        check(store.scope == "local" && store.habits().isEmpty())
        val today = LocalDate.now()
        val zone = ZoneId.systemDefault()
        val start = today.minusDays(28).atStartOfDay(zone).toInstant()
        val habits = listOf(
            Habit(name = l(context, "Drink water"), unit = l(context, "glasses"), symbol = "drop.fill", target = 6.0, hour = 10, createdAt = start),
            Habit(name = l(context, "Read"), unit = l(context, "pages"), symbol = "book.fill", color = 1, target = 20.0, step = 5.0, weekdays = 11, hour = 18, createdAt = start),
            Habit(name = l(context, "Move"), unit = l(context, "minutes"), symbol = "figure.walk", color = 2, target = 30.0, step = 5.0, hour = 19, createdAt = start),
            Habit(name = l(context, "Distractions"), unit = l(context, "times"), symbol = "emoji:📱", color = 3, target = 0.0, goal = Goal.LIMIT, createdAt = start)
        )
        habits.forEachIndexed { index, h ->
            store.save(h)
            repeat(29) { offset ->
                val day = today.minusDays(28L - offset)
                if(h.scheduled(day)) {
                    val fraction = if(day == today) listOf(.5, .25, .5, 1.0)[index] else listOf(1.0, 1.0, .5, 0.0, 1.25)[(offset + index) % 5]
                    val amount = if(h.goal == Goal.LIMIT) if((offset + index) % 8 == 0) 1.0 else 0.0 else h.target * fraction
                    if(fraction > 0) store.importActivity(Activity(habitId = h.id, amount = amount,
                        timestamp = day.atTime(if(day == today) 0 else h.hour, 0).atZone(zone).toInstant(), source = "android_demo"))
                }
            }
        }
        store.setMeta("demo_ids", JSONArray(habits.map { it.id }).toString())
    }
}
