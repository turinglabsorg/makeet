package org.turinglabs.makeet

import android.Manifest
import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

data class CalendarSelection(val ids: Set<Long>, val destination: Long?)
fun selectedCalendars(context: Context, scope: String): CalendarSelection {
    val p = context.getSharedPreferences("makeet.calendar.$scope", Context.MODE_PRIVATE)
    return CalendarSelection(p.getStringSet("sources", emptySet()).orEmpty().mapNotNull { it.toLongOrNull() }.toSet(), p.getLong("destination", -1).takeIf { it >= 0 })
}
@Composable fun calendarGeneration(): Int {
    val context = LocalContext.current
    var generation by remember { mutableIntStateOf(0) }
    val hasPermission = DeviceCalendarService(context).allowed()
    DisposableEffect(context, hasPermission) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) { override fun onChange(selfChange: Boolean) { generation++ } }
        if(hasPermission) context.contentResolver.registerContentObserver(CalendarContract.CONTENT_URI, true, observer)
        onDispose { if(hasPermission) context.contentResolver.unregisterContentObserver(observer) }
    }
    return generation
}
@Composable fun CalendarConnections(account: String) {
    val context = LocalContext.current; val service = remember { DeviceCalendarService(context) }
    var calendars by remember { mutableStateOf(service.calendars()) }
    var selection by remember(account) { mutableStateOf(selectedCalendars(context, account)) }
    var asked by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { calendars = service.calendars(); asked = true }
    CardBox {
        Text(t("System calendars"), style = MaterialTheme.typography.titleLarge)
        Text(t("Makeet reads only the calendars you select. Events added after your confirmation are synchronized by the calendar account on this device."))
        if(!service.allowed()) {
            Button({ permission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) }) { Text(t("Allow calendar access")) }
            if(asked) Text(t("Calendar access wasn’t granted. You can enable it in Settings."))
        } else {
            if(calendars.isEmpty()) Text(t("No calendars are configured on this device. Add an account in your calendar app, then refresh."))
            TextButton({ calendars = service.calendars() }) { Text(t("Refresh")) }
            Text(t("Consider commitments in"))
            calendars.forEach { calendar -> Row { Checkbox(calendar.id in selection.ids, { checked ->
                val ids = if(checked) selection.ids + calendar.id else selection.ids - calendar.id
                context.getSharedPreferences("makeet.calendar.$account", Context.MODE_PRIVATE).edit().putStringSet("sources", ids.map { it.toString() }.toSet()).apply()
                selection = selection.copy(ids = ids)
            }); Column { Text(calendar.name); Text(calendar.account, style = MaterialTheme.typography.bodySmall) } } }
            Text(t("Create blocks in"))
            calendars.filter { it.writable }.forEach { calendar -> Row { RadioButton(selection.destination == calendar.id, {
                context.getSharedPreferences("makeet.calendar.$account", Context.MODE_PRIVATE).edit().putLong("destination", calendar.id).apply()
                selection = selection.copy(destination = calendar.id)
            }); Text(calendar.name) } }
        }
    }
}
@Composable fun CalendarDayEvents(day: LocalDate, account: String) {
    val context = LocalContext.current; val generation = calendarGeneration()
    var events by remember { mutableStateOf<List<CalendarEvent>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    val service = remember { DeviceCalendarService(context) }
    LaunchedEffect(day, account, generation) {
        failed = false
        runCatching { withContext(Dispatchers.IO) { val start = day.atStartOfDay(ZoneId.systemDefault()).toInstant(); service.events(start, day.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant(), selectedCalendars(context, account).ids) } }
            .onSuccess { events = it }.onFailure { failed = true; events = emptyList() }
    }
    if(service.allowed() && selectedCalendars(context, account).ids.isNotEmpty()) CardBox {
        Text(t("Events for the day"), style = MaterialTheme.typography.titleMedium)
        if(failed) Text(t("Couldn’t complete the action")) else if(events.isEmpty()) Text(t("No events in the selected calendars."))
        events.forEach { Text(it.start.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)) + " · " + it.title) }
    }
}
@Composable fun Planner(state: ScreenState, model: MakeetModel, connections: () -> Unit) {
    val context = LocalContext.current; val scope = rememberCoroutineScope(); val generation = calendarGeneration()
    val service = remember { DeviceCalendarService(context) }; val account = state.user?.id ?: "local"
    var horizon by rememberSaveable { mutableIntStateOf(7) }; var refresh by remember { mutableIntStateOf(0) }
    var proposals by remember { mutableStateOf<List<Proposal>>(emptyList()) }
    var review by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }; var added by remember { mutableStateOf(false) }
    val selection = selectedCalendars(context, account)
    val connected = service.allowed() && selection.ids.isNotEmpty() && selection.destination != null
    val realHabits = state.habits.filter { it.id !in state.demoIds }
    val previewOnly = realHabits.isEmpty() && state.demo
    val planningHabits = if(previewOnly) state.habits else realHabits
    LaunchedEffect(planningHabits, state.activities, horizon, generation, refresh, connected) {
        error = false
        runCatching { withContext(Dispatchers.IO) {
            val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()
            val events = service.events(start, start.plusSeconds((horizon + 2) * 86400L), selection.ids + listOfNotNull(selection.destination))
            val planned = service.plannedDays(start.minusSeconds(86400), start.plusSeconds((horizon + 2) * 86400L), planningHabits)
            ScheduleEngine.propose(planningHabits, state.activities, events.filter { it.blocking }.map { Busy(it.start, it.end) }, horizon, planned = planned)
        } }.onSuccess { proposals = it }.onFailure { proposals = emptyList(); error = true }
    }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { Text(t("A plan built around your progress, chosen days, and calendar events.")) }
        item { Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf(1, 7, 14, 28).forEach { n -> FilterChip(horizon == n, { horizon = n; added = false }, { Text(if(n == 1) t("Today") else n.toString()) }) } } }
        if(previewOnly) item { Text(t("Illustrative preview")) }
        if(!connected && !previewOnly) item { CardBox { Text(t("Connect your calendar to find free slots. Without access, suggested times may overlap with your commitments.")); Button(connections) { Text(t("Connect calendar")) } } }
        if(error) item { Text(t("Couldn’t complete the action"), color = MaterialTheme.colorScheme.error) }
        if(added) item { Text(t("Added to calendar"), color = MaterialTheme.colorScheme.primary) }
        item { Text(t(if(horizon == 1) "What you have to do today" else "What you have to do in the coming days"), style = MaterialTheme.typography.headlineSmall) }
        items(proposals) { p -> CardBox { Text(p.habit.name, style = MaterialTheme.typography.titleLarge); Text(p.start.atZone(ZoneId.of(p.habit.zone)).format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT))); Text(t(if(connected) "Free slot in your selected calendars." else "Suggested time: calendar not connected."), style = MaterialTheme.typography.bodySmall) } }
        if(proposals.isEmpty()) item { Text(t("All selected days are already planned, completed, or have no free time between 7 AM and 10 PM. You can change the period or preferences.")) }
        item { TextButton({ refresh++; added = false }) { Text(t("Refresh suggestions")) }; if(connected && !previewOnly && proposals.isNotEmpty()) Button({ review = true }, Modifier.fillMaxWidth()) { Text(t("Review and add all")) } }
    }
    if(review) AlertDialog(onDismissRequest = { if(!busy) review = false }, title = { Text(t("Confirm your plan")) }, text = { LazyColumn { item { Text(t("Each habit gets at most one block per scheduled day. Existing future events are kept.")) }; items(proposals) { p -> Text(p.habit.name + " · " + p.start.atZone(ZoneId.of(p.habit.zone)).format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)), Modifier.padding(vertical = 8.dp)) } } },
        confirmButton = { TextButton({ scope.launch { busy = true; error = false; runCatching { model.createCalendarEvents(proposals, selection, account) }.onSuccess { added = true; review = false; refresh++ }.onFailure { error = true; review = false }; busy = false } }, enabled = !busy) { Text(t("Confirm and create events")) } }, dismissButton = { TextButton({ review = false }, enabled = !busy) { Text(t("Cancel")) } })
}
