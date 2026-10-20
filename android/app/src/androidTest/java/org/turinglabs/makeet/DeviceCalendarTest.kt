package org.turinglabs.makeet

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.*
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.junit.runners.model.Statement
import java.time.*
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class DeviceCalendarTest {
    private val ui = createComposeRule()
    @get:Rule val permissions: TestRule = RuleChain.outerRule(object: TestRule {
        override fun apply(base: Statement, description: Description) = object: Statement() {
            override fun evaluate() { Assume.assumeTrue(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone")); base.evaluate() }
        }
    }).around(GrantPermissionRule.grant(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)).around(ui)
    @Test fun confirmedCalendarWritesAreIdempotentAndRespectConflictsAndRecurrences() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val resolver = context.contentResolver
        val account = "makeet-qa-${UUID.randomUUID()}"
        val calendarsUri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, account)
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL).build()
        val uri = resolver.insert(calendarsUri, ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, account); put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, account); put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, "Makeet QA temporary")
            put(CalendarContract.Calendars.OWNER_ACCOUNT, account); put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.VISIBLE, 1); put(CalendarContract.Calendars.SYNC_EVENTS, 1); put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, "Europe/Rome")
        })!!
        val calendarId = ContentUris.parseId(uri)
        val displayScope = "calendar-qa-${UUID.randomUUID()}"
        try {
            val service = DeviceCalendarService(context)
            val zone = ZoneId.of("Europe/Rome")
            val start = LocalDate.now(zone).plusDays(1).atTime(18, 0).atZone(zone).toInstant()
            val habit = Habit(name = "QA calendar habit", unit = "times", zone = zone.id)
            val p = Proposal(habit, start, start.plusSeconds(1200), false)
            Assert.assertEquals(1, service.create(listOf(p), setOf(calendarId), calendarId, listOf(habit)))
            Assert.assertEquals(0, service.create(listOf(p), setOf(calendarId), calendarId, listOf(habit)))
            Assert.assertTrue(service.plannedDays(start.minusSeconds(86400), start.plusSeconds(86400), listOf(habit)).contains(habit.id to habit.date(start)))
            Assert.assertEquals(1, service.events(start.minusSeconds(60), start.plusSeconds(1260), setOf(calendarId)).size)
            Assert.assertFalse(HabitEngine.progress(habit, emptyList(), habit.date(start)).complete)
            val busyStart = start.plusSeconds(7200)
            resolver.insert(CalendarContract.Events.CONTENT_URI, ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId); put(CalendarContract.Events.TITLE, "QA existing appointment")
                put(CalendarContract.Events.DTSTART, busyStart.toEpochMilli()); put(CalendarContract.Events.DTEND, busyStart.plusSeconds(3600).toEpochMilli()); put(CalendarContract.Events.EVENT_TIMEZONE, zone.id)
            })!!
            val other = habit.copy(id = UUID.randomUUID().toString())
            Assert.assertTrue(runCatching { service.create(listOf(Proposal(other, busyStart, busyStart.plusSeconds(1200), false)), setOf(calendarId), calendarId, listOf(other)) }.isFailure)
            Assert.assertTrue(runCatching { service.create(listOf(p.copy(start = start.plusSeconds(86400), end = start.plusSeconds(87600))), emptySet(), calendarId, listOf(habit)) }.isFailure)
            val freeStart = start.plusSeconds(2 * 86400)
            resolver.insert(CalendarContract.Events.CONTENT_URI, ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId); put(CalendarContract.Events.TITLE, "QA free appointment")
                put(CalendarContract.Events.DTSTART, freeStart.toEpochMilli()); put(CalendarContract.Events.DTEND, freeStart.plusSeconds(1200).toEpochMilli())
                put(CalendarContract.Events.EVENT_TIMEZONE, zone.id); put(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_FREE)
            })!!
            val free = service.events(freeStart.minusSeconds(1), freeStart.plusSeconds(1201), setOf(calendarId)).single { it.title == "QA free appointment" }
            Assert.assertFalse(free.blocking)
            Assert.assertEquals(1, service.create(listOf(p.copy(start = freeStart, end = freeStart.plusSeconds(1200))), setOf(calendarId), calendarId, listOf(habit)))
            context.getSharedPreferences("makeet.calendar.$displayScope", android.content.Context.MODE_PRIVATE).edit()
                .putStringSet("sources", setOf(calendarId.toString())).commit()
            ui.setContent { MaterialTheme { CalendarDayEvents(freeStart.atZone(ZoneId.systemDefault()).toLocalDate(), displayScope) } }
            ui.waitUntil(5000) { ui.onAllNodesWithText("QA free appointment", substring = true).fetchSemanticsNodes().isNotEmpty() }
            ui.onNodeWithText("QA free appointment", substring = true).assertIsDisplayed()
            resolver.insert(CalendarContract.Events.CONTENT_URI, ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId); put(CalendarContract.Events.TITLE, "QA recurring appointment")
                put(CalendarContract.Events.DTSTART, start.minusSeconds(3600).toEpochMilli()); put(CalendarContract.Events.DURATION, "PT30M")
                put(CalendarContract.Events.RRULE, "FREQ=DAILY;COUNT=3"); put(CalendarContract.Events.EVENT_TIMEZONE, zone.id)
            })!!
            val recurring = service.events(start.minusSeconds(7200), start.plusSeconds(3*86400), setOf(calendarId)).filter { it.title == "QA recurring appointment" }
            Assert.assertEquals(3, recurring.size)
            Assert.assertEquals(3, recurring.map { it.start }.distinct().size)
            service.removeFuture(habit.id)
            val retained = service.events(start.minusSeconds(7200), start.plusSeconds(3*86400), setOf(calendarId))
            Assert.assertFalse(retained.any { it.title == habit.name })
            Assert.assertEquals(1, retained.count { it.title == "QA existing appointment" })
            Assert.assertEquals(3, retained.count { it.title == "QA recurring appointment" })
            Assert.assertEquals(1, retained.count { it.title == "QA free appointment" })
        } finally {
            resolver.delete(ContentUris.withAppendedId(calendarsUri, calendarId), null, null)
            context.deleteSharedPreferences("makeet.calendar.$displayScope")
        }
    }
}
