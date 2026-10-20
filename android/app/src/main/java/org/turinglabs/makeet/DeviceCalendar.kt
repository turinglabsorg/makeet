package org.turinglabs.makeet

import android.Manifest
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import java.time.Instant

data class DeviceCalendar(val id: Long, val name: String, val account: String, val writable: Boolean)
data class CalendarEvent(val id: Long, val title: String, val start: Instant, val end: Instant, val calendarId: Long)

class DeviceCalendarService(private val context: Context) {
    private val resolver get() = context.contentResolver
    fun allowed() = listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
        .all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    fun calendars(): List<DeviceCalendar> {
        if (!allowed()) return emptyList()
        return resolver.query(CalendarContract.Calendars.CONTENT_URI, arrayOf("_id", "calendar_displayName", "account_name", "calendar_access_level"),
            "visible=1", null, "calendar_displayName")?.use { c -> buildList { while(c.moveToNext())
            add(DeviceCalendar(c.getLong(0), c.getString(1).orEmpty(), c.getString(2).orEmpty(), c.getInt(3) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)) } }.orEmpty()
    }
    fun events(start: Instant, end: Instant, selected: Set<Long>): List<CalendarEvent> {
        if (!allowed() || selected.isEmpty()) return emptyList()
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start.toEpochMilli()); ContentUris.appendId(builder, end.toEpochMilli())
        val placeholders = selected.joinToString(",") { "?" }
        return resolver.query(builder.build(), arrayOf("event_id", "title", "begin", "end", "calendar_id"),
            "calendar_id IN ($placeholders) AND (availability IS NULL OR availability != ?) AND (eventStatus IS NULL OR eventStatus != 2)", (selected.map { it.toString() } + CalendarContract.Events.AVAILABILITY_FREE.toString()).toTypedArray(), "begin")
            ?.use { c -> buildList { while(c.moveToNext()) add(CalendarEvent(c.getLong(0), c.getString(1).orEmpty(), Instant.ofEpochMilli(c.getLong(2)), Instant.ofEpochMilli(c.getLong(3)), c.getLong(4))) } }.orEmpty()
    }
    fun mark(p: Proposal) = "makeet://plan/${p.habit.id}-${p.start.epochSecond}"
    private fun ownEvents(from: Instant, to: Instant): Map<String, Long> {
        if (!allowed()) return emptyMap()
        return resolver.query(CalendarContract.Events.CONTENT_URI, arrayOf("_id", "customAppUri"),
            "customAppPackage=? AND dtstart>=? AND dtstart<? AND deleted=0", arrayOf(context.packageName, from.toEpochMilli().toString(), to.toEpochMilli().toString()), null)
            ?.use { c -> buildMap { while(c.moveToNext()) put(c.getString(1).orEmpty(), c.getLong(0)) } }.orEmpty()
    }
    fun plannedDays(from: Instant, to: Instant, habits: List<Habit>): Set<Pair<String, java.time.LocalDate>> =
        ownEvents(from, to).keys.mapNotNull { mark ->
            val tail = mark.removePrefix("makeet://plan/")
            val epoch = tail.substringAfterLast('-').toLongOrNull() ?: return@mapNotNull null
            val h = habits.firstOrNull { it.id == tail.substringBeforeLast('-') } ?: return@mapNotNull null
            h.id to h.date(Instant.ofEpochSecond(epoch))
        }.toSet()
    fun create(proposals: List<Proposal>, selected: Set<Long>, destination: Long, current: List<Habit>, now: Instant = Instant.now()): Int {
        require(allowed() && selected.isNotEmpty() && proposals.isNotEmpty())
        require(calendars().any { it.id == destination && it.writable })
        require(proposals.all { p -> p.start > now && current.any { it == p.habit } })
        val from = proposals.minOf { it.start }.minusSeconds(86400)
        val to = proposals.maxOf { it.end }.plusSeconds(86400)
        val existing = ownEvents(from, to)
        val planned = plannedDays(from, to, current)
        val new = proposals.filter { mark(it) !in existing && (it.habit.id to it.habit.date(it.start)) !in planned }
        val busy = events(from, to, selected + destination)
        require(new.none { p -> busy.any { p.start < it.end && p.end > it.start } }) { "calendar_conflict" }
        val operations = new.map { p -> ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI).withValues(ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, destination); put(CalendarContract.Events.TITLE, p.habit.name)
            put(CalendarContract.Events.DTSTART, p.start.toEpochMilli()); put(CalendarContract.Events.DTEND, p.end.toEpochMilli())
            put(CalendarContract.Events.EVENT_TIMEZONE, p.habit.zone); put(CalendarContract.Events.CUSTOM_APP_PACKAGE, context.packageName)
            put(CalendarContract.Events.CUSTOM_APP_URI, mark(p)); put(CalendarContract.Events.DESCRIPTION, l(context, "Time block planned by the app. Habit completion is logged separately."))
        }).build() }
        if (operations.isNotEmpty()) resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(operations))
        return operations.size
    }
    fun removeFuture(habitId: String, now: Instant = Instant.now()) {
        val own = ownEvents(now, now.plusSeconds(366L * 86400))
        val operations = own.filterKeys { it.startsWith("makeet://plan/$habitId-") }.values.map { id ->
            ContentProviderOperation.newDelete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)).build()
        }
        if (operations.isNotEmpty()) resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(operations))
    }
}
