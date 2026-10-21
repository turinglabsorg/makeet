package org.turinglabs.makeet

import org.json.JSONObject
import java.time.*
import java.util.UUID
import kotlin.math.abs

enum class Goal(val wire: String) { MINIMUM("at_least"), LIMIT("at_most") }

data class Habit(
    val id: String = UUID.randomUUID().toString(),
    val name: String, val symbol: String = "leaf.fill", val color: Int = 0,
    val target: Double = 1.0, val step: Double = 1.0, val unit: String,
    val createdAt: Instant = Instant.now(), val zone: String = ZoneId.systemDefault().id,
    val hour: Int = 18, val duration: Int = 20, val archived: Boolean = false,
    val weekdays: Int = 127, val goal: Goal = Goal.MINIMUM, val negative: Boolean = false
) {
    fun valid(): Boolean = name.isNotBlank() && name.toByteArray().size <= 200 &&
        unit.isNotBlank() && unit.toByteArray().size <= 50 && symbol.toByteArray().size <= 80 &&
        color in 0..3 && target.isFinite() && (target > 0 || goal == Goal.LIMIT && target == 0.0) &&
        step.isFinite() && step > 0 && hour in 0..23 && duration in 5..240 && weekdays in 1..127 &&
        runCatching { ZoneId.of(zone) }.isSuccess
    fun date(at: Instant) = at.atZone(ZoneId.of(zone)).toLocalDate()
    fun scheduled(day: LocalDate) = day >= date(createdAt) && weekdays and (1 shl (day.dayOfWeek.value - 1)) != 0
    fun data() = JSONObject().put("name", name).put("symbol", symbol).put("color_index", color)
        .put("target", target).put("step", step).put("unit", unit).put("created_at", createdAt.toString())
        .put("time_zone_id", zone).put("preferred_hour", hour).put("duration_minutes", duration)
        .put("archived", archived).put("weekday_mask", weekdays).put("goal", goal.wire).put("allows_negative", negative)
    companion object {
        fun read(id: String, d: JSONObject) = Habit(id, d.getString("name"), d.getString("symbol"),
            d.getInt("color_index"), d.getDouble("target"), d.getDouble("step"), d.getString("unit"),
            Instant.parse(d.getString("created_at")), d.getString("time_zone_id"), d.getInt("preferred_hour"),
            d.getInt("duration_minutes"), d.getBoolean("archived"), d.optInt("weekday_mask", 127),
            if (d.optString("goal") == "at_most") Goal.LIMIT else Goal.MINIMUM, d.optBoolean("allows_negative"))
    }
}

data class Activity(val id: String = UUID.randomUUID().toString(), val habitId: String,
                    val amount: Double, val timestamp: Instant = Instant.now(), val source: String = "android") {
    fun data() = JSONObject().put("habit_id", habitId).put("amount", amount)
        .put("timestamp", timestamp.toString()).put("source", source)
    companion object { fun read(id: String, d: JSONObject) = Activity(id, d.getString("habit_id"),
        d.getDouble("amount"), Instant.parse(d.getString("timestamp")), d.getString("source")) }
}

data class Progress(val amount: Double, val logged: Boolean, val complete: Boolean, val fraction: Double, val malus: Double)
data class Statistics(val total: Double, val average: Double, val completed: Int, val expected: Int,
                      val currentStreak: Int, val bestStreak: Int, val daily: List<Pair<LocalDate, Progress>>, val hours: List<Int>)

object HabitEngine {
    fun total(values: Iterable<Double>): Double {
        var sum = 0.0; var magnitude = 0.0
        values.filter { it.isFinite() }.forEach { sum += it; magnitude += abs(it) }
        return if(abs(sum) <= Math.ulp(magnitude) * 8) 0.0 else sum
    }
    fun progress(habit: Habit, activities: List<Activity>, day: LocalDate): Progress {
        val entries = activities.filter { it.habitId == habit.id && it.amount.isFinite() && habit.date(it.timestamp) == day }
        val amount = total(entries.map { it.amount })
        val complete = if (habit.goal == Goal.LIMIT) entries.isNotEmpty() && amount <= habit.target else amount >= habit.target
        val fraction = if (habit.goal == Goal.LIMIT) if(complete) 1.0 else if(entries.isNotEmpty() && habit.target > 0 && amount > 0) (habit.target / amount).coerceIn(0.0, 1.0) else 0.0 else (amount / habit.target).coerceIn(0.0, 1.0)
        return Progress(amount, entries.isNotEmpty(), complete, fraction,
            if (habit.goal == Goal.LIMIT) (amount - habit.target).coerceAtLeast(0.0) else (-amount).coerceAtLeast(0.0))
    }
    fun statistics(habit: Habit, activities: List<Activity>, days: Int, now: Instant = Instant.now()): Statistics {
        val today = habit.date(now)
        val start = maxOf(today.minusDays(days.toLong() - 1), habit.date(habit.createdAt))
        val grouped = activities.filter { it.habitId == habit.id && it.amount.isFinite() }
            .groupBy { habit.date(it.timestamp) }
        val daily = if (start > today) emptyList() else generateSequence(start) { it.plusDays(1) }
            .takeWhile { it <= today }.map { it to progress(habit, grouped[it].orEmpty(), it) }.toList()
        val eligible = daily.filter { habit.scheduled(it.first) }
        var best = 0; var streak = 0
        if (habit.date(habit.createdAt) <= today) generateSequence(habit.date(habit.createdAt)) { it.plusDays(1) }
            .takeWhile { it <= today }.filter { habit.scheduled(it) }.forEach { day ->
                val progress = progress(habit, grouped[day].orEmpty(), day)
                if (progress.complete) { streak++; best = maxOf(best, streak) }
                else if (day != today || habit.goal == Goal.LIMIT && progress.logged) streak = 0
            }
        val sum = total(daily.map { it.second.amount })
        val hours = MutableList(24) { 0 }
        activities.filter { it.habitId == habit.id && it.amount.isFinite() && habit.date(it.timestamp) in start..today }
            .forEach { hours[it.timestamp.atZone(ZoneId.of(habit.zone)).hour]++ }
        return Statistics(sum, if (daily.isEmpty()) 0.0 else sum / daily.size, eligible.count { it.second.complete },
            eligible.size, streak, best, daily, hours)
    }
    fun adjusted(habit: Habit, current: Double, delta: Double) =
        total(listOf(current, delta)).let { if (habit.negative) it else it.coerceAtLeast(0.0) }
}

data class Busy(val start: Instant, val end: Instant)
data class Proposal(val habit: Habit, val start: Instant, val end: Instant, val learned: Boolean)

object ScheduleEngine {
    fun propose(habits: List<Habit>, activities: List<Activity>, busy: List<Busy>, horizon: Int,
                now: Instant = Instant.now(), planned: Set<Pair<String, LocalDate>> = emptySet()): List<Proposal> {
        require(horizon in listOf(1, 7, 14, 28))
        val result = mutableListOf<Proposal>()
        val active = habits.filter { !it.archived && it.goal == Goal.MINIMUM }
        val preferences = active.associate { h ->
            val today = h.date(now)
            val history = activities.filter { it.habitId == h.id && it.amount.isFinite() && it.amount > 0 && h.date(it.timestamp) < today && h.date(it.timestamp) >= today.minusDays(28) }
            val learned = history.size >= 5
            val preferred = if (learned) history.groupingBy { it.timestamp.atZone(ZoneId.of(h.zone)).hour }.eachCount()
                .entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).first().key else h.hour
            h.id to (preferred to learned)
        }
        repeat(horizon) { offset ->
            active.forEach { h ->
                val zone = ZoneId.of(h.zone)
                val day = h.date(now).plusDays(offset.toLong())
                if (!h.scheduled(day) || (h.id to day) in planned || HabitEngine.progress(h, activities, day).complete) return@forEach
                val (preferred, learned) = preferences.getValue(h.id)
                val candidates = (7 * 60..22 * 60 - h.duration step 15).sortedBy { abs(it - preferred * 60) }
                val start = candidates.map { day.atTime(it / 60, it % 60).atZone(zone).toInstant() }.firstOrNull { start ->
                    val end = start.plusSeconds(h.duration * 60L)
                    start > now && busy.none { start < it.end && end > it.start } && result.none { start < it.end && end > it.start }
                }
                if (start != null) result += Proposal(h, start, start.plusSeconds(h.duration * 60L), learned)
            }
        }
        return result.sortedBy { it.start }
    }
}
