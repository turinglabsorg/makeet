package org.turinglabs.makeet

import org.junit.Assert.*
import org.junit.Test
import java.time.*

class HabitEngineTest {
    private val now = Instant.parse("2026-10-20T12:00:00Z")
    private val habit = Habit(name = "Read", unit = "pages", createdAt = now.minusSeconds(10 * 86400), zone = "Europe/Rome")
    private val today = habit.date(now)
    @Test fun zeroLimitRequiresConfirmationAndShowsMalus() {
        val h = habit.copy(target = 0.0, goal = Goal.LIMIT)
        assertTrue(h.valid())
        assertFalse(HabitEngine.progress(h, emptyList(), today).complete)
        val zero = Activity(habitId = h.id, amount = 0.0, timestamp = now)
        assertTrue(HabitEngine.progress(h, listOf(zero), today).complete)
        val excess = zero.copy(amount = 2.0)
        assertEquals(2.0, HabitEngine.progress(h, listOf(excess), today).malus, 0.0)
        assertFalse(HabitEngine.progress(h, listOf(excess), today).complete)
    }
    @Test fun decimalCancellationIsExact() {
        assertEquals(0.0, HabitEngine.total(listOf(.1, .2, -.3)), 0.0)
        assertEquals(0.0, HabitEngine.total(listOf(1.0, -1.0 + Math.ulp(1.0))), 0.0)
    }
    @Test fun negativeValuesRequireExplicitOptIn() {
        assertEquals(0.0, HabitEngine.adjusted(habit, 0.0, -1.0), 0.0)
        assertEquals(-1.0, HabitEngine.adjusted(habit.copy(negative = true), 0.0, -1.0), 0.0)
    }
    @Test fun weekdaysAreMondayFirstAndDoNotCountRestDays() {
        val h = habit.copy(weekdays = 1 or 2 or 8, createdAt = Instant.parse("2026-10-19T00:00:00Z"))
        assertTrue(h.scheduled(LocalDate.parse("2026-10-19")))
        assertTrue(h.scheduled(LocalDate.parse("2026-10-20")))
        assertFalse(h.scheduled(LocalDate.parse("2026-10-21")))
        assertTrue(h.scheduled(LocalDate.parse("2026-10-22")))
        assertEquals(3, HabitEngine.statistics(h, emptyList(), 7, Instant.parse("2026-10-25T12:00:00Z")).expected)
    }
    @Test fun unfinishedTodayPreservesYesterdayStreak() {
        val h = habit.copy(createdAt = now.minusSeconds(86400))
        val entry = Activity(habitId = h.id, amount = 1.0, timestamp = now.minusSeconds(86400))
        assertEquals(1, HabitEngine.statistics(h, listOf(entry), 7, now).currentStreak)
    }
    @Test fun futureHabitsHaveNoFailedDays() {
        val h = habit.copy(createdAt = now.plusSeconds(86400))
        val result = HabitEngine.statistics(h, emptyList(), 28, now)
        assertEquals(0, result.expected); assertTrue(result.daily.isEmpty())
    }
    @Test fun habitTimeZoneControlsDayBoundaries() {
        val h = habit.copy(zone = "America/Los_Angeles")
        assertEquals(LocalDate.parse("2026-10-19"), h.date(Instant.parse("2026-10-20T01:00:00Z")))
    }
    @Test fun schedulerAvoidsBusyPeriodsAndOtherProposals() {
        val h = habit.copy(hour = 16)
        val busy = Busy(Instant.parse("2026-10-20T14:00:00Z"), Instant.parse("2026-10-20T15:00:00Z"))
        val result = ScheduleEngine.propose(listOf(h, h.copy(id = java.util.UUID.randomUUID().toString())), emptyList(), listOf(busy), 1, now)
        assertEquals(2, result.size)
        result.forEach { assertFalse(it.start < busy.end && it.end > busy.start) }
        assertTrue(result[0].end <= result[1].start)
    }
    @Test fun schedulerExcludesLimitsAndHonorsWeekdaysAcrossFutureHorizon() {
        val h = habit.copy(weekdays = 1 or 2 or 8)
        val result = ScheduleEngine.propose(listOf(h, habit.copy(goal = Goal.LIMIT, target = 0.0)), emptyList(), emptyList(), 28, now)
        assertTrue(result.size > 1)
        assertTrue(result.all { it.habit.id == h.id && h.scheduled(h.date(it.start)) })
        assertTrue(result.all { it.start > now && h.date(it.start) < today.plusDays(28) })
    }
    @Test fun backwardCompatibleJSONPreservesGoalAndWeekdays() {
        val h = habit.copy(target = 0.0, goal = Goal.LIMIT, negative = true, weekdays = 11)
        assertEquals(h, Habit.read(h.id, h.data()))
        val old = habit.data().apply { remove("goal"); remove("allows_negative"); remove("weekday_mask") }
        val decoded = Habit.read(habit.id, old)
        assertEquals(Goal.MINIMUM, decoded.goal); assertFalse(decoded.negative); assertEquals(127, decoded.weekdays)
    }
    @Test fun explicitLimitViolationBreaksTodayStreakButUnknownTodayDoesNot() {
        val h = habit.copy(target = 0.0, goal = Goal.LIMIT, createdAt = now.minusSeconds(86400))
        val yesterday = Activity(habitId = h.id, amount = 0.0, timestamp = now.minusSeconds(86400))
        assertEquals(1, HabitEngine.statistics(h, listOf(yesterday), 7, now).currentStreak)
        val violation = yesterday.copy(id = java.util.UUID.randomUUID().toString(), amount = 1.0, timestamp = now)
        assertEquals(0, HabitEngine.statistics(h, listOf(yesterday, violation), 7, now).currentStreak)
    }
    @Test fun hourlyRegistrationsIncludeExplicitZeroAndIgnoreInvalidAmounts() {
        val h = habit.copy(goal = Goal.LIMIT, target = 2.0)
        val entries = listOf(Activity(habitId = h.id, amount = 0.0, timestamp = now), Activity(habitId = h.id, amount = Double.NaN, timestamp = now))
        assertEquals(1, HabitEngine.statistics(h, entries, 7, now).hours.sum())
        assertEquals(.5, HabitEngine.progress(h, listOf(entries.first().copy(amount = 4.0)), today).fraction, 0.0)
    }
    @Test fun learnedHourUsesFiveRegistrationsBeforeTodayLikeTheAppleClient() {
        val time = today.minusDays(1).atTime(15, 0).atZone(ZoneId.of(habit.zone)).toInstant()
        val history = (0..4).map { Activity(habitId = habit.id, amount = 1.0, timestamp = time.plusSeconds(it.toLong())) }
        val proposal = ScheduleEngine.propose(listOf(habit), history, emptyList(), 1, now).single()
        assertTrue(proposal.learned)
        assertEquals(15, proposal.start.atZone(ZoneId.of(habit.zone)).hour)
    }
}
