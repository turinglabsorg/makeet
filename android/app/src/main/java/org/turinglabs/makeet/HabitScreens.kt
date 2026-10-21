package org.turinglabs.makeet

import android.app.DatePickerDialog
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import java.time.*
import java.time.format.TextStyle
import java.util.Locale
import kotlinx.coroutines.launch

@Composable fun HabitEditor(original: Habit?, close: () -> Unit, save: (Habit) -> Unit) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    var name by rememberSaveable { mutableStateOf(original?.name.orEmpty()) }
    var unit by rememberSaveable { mutableStateOf(original?.unit ?: l(context, "times")) }
    var target by rememberSaveable { mutableStateOf((original?.target ?: 1.0).toString()) }
    var amount by rememberSaveable { mutableStateOf((original?.step ?: 1.0).toString()) }
    var limit by rememberSaveable { mutableStateOf(original?.goal == Goal.LIMIT) }
    var negative by rememberSaveable { mutableStateOf(original?.negative ?: false) }
    var weekdays by rememberSaveable { mutableIntStateOf(original?.weekdays ?: 127) }
    var symbol by rememberSaveable { mutableStateOf(original?.symbol ?: "leaf.fill") }
    var emoji by rememberSaveable { mutableStateOf(original?.symbol?.startsWith("emoji:") ?: false) }
    var emojiValue by rememberSaveable { mutableStateOf(if(emoji) original!!.symbol.removePrefix("emoji:") else "🌱") }
    var color by rememberSaveable { mutableIntStateOf(original?.color ?: 0) }
    var hour by rememberSaveable { mutableIntStateOf(original?.hour ?: 18) }
    var duration by rememberSaveable { mutableIntStateOf(original?.duration ?: 20) }
    var start by rememberSaveable { mutableStateOf(original?.date(original.createdAt)?.toString() ?: LocalDate.now().toString()) }
    fun parsed(value: String) = value.replace(',', '.').toDoubleOrNull()
    val em = if(emoji) "emoji:" + emojiValue.trim() else symbol
    val startDay = runCatching { LocalDate.parse(start) }.getOrNull()
    val created = if(original != null && startDay == original.date(original.createdAt)) original.createdAt else startDay?.atStartOfDay(ZoneId.of(original?.zone ?: ZoneId.systemDefault().id))?.toInstant() ?: Instant.now()
    val draft = Habit(id = original?.id ?: rememberSaveable { java.util.UUID.randomUUID().toString() }, name = name.trim(), unit = unit.trim(),
        target = parsed(target) ?: Double.NaN, step = parsed(amount) ?: Double.NaN, goal = if(limit) Goal.LIMIT else Goal.MINIMUM,
        negative = negative, weekdays = weekdays, symbol = em, color = color, createdAt = created, hour = hour, duration = duration,
        zone = original?.zone ?: ZoneId.systemDefault().id, archived = original?.archived ?: false)
    val emojiValid = !emoji || validEmoji(emojiValue.trim())
    FullScreen(t(if(original == null) "New habit" else "Edit habit"), close, actions = { TextButton(onClick = { save(draft) }, enabled = draft.valid() && emojiValid && startDay != null) { Text(t(if(original == null) "Create" else "Save")) } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            CardBox {
                OutlinedTextField(name, { name = it }, label = { Text(t("Your habit")) }, placeholder = { Text(t("For example: drink water")) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(!emoji, { emoji = false }, { Text(t("Icon")) }); FilterChip(emoji, { emoji = true }, { Text(t("Emoji")) }) }
                if(emoji) OutlinedTextField(emojiValue, { emojiValue = it }, label = { Text(t("One emoji")) }, isError = !emojiValid, modifier = Modifier.fillMaxWidth())
                else Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { listOf("leaf.fill", "drop.fill", "book.fill", "figure.walk", "cup.and.saucer.fill", "heart.fill").forEach { mark ->
                    OutlinedIconButton(onClick = { symbol = mark }, modifier = Modifier.weight(1f), border = BorderStroke(if(symbol == mark) 2.dp else 0.dp, MaterialTheme.colorScheme.primary)) { HabitMark(draft.copy(symbol = mark)) }
                } }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { Text(t("Color")); HabitColors.forEachIndexed { i, c ->
                    Surface(Modifier.size(44.dp).clickable { color = i }, color = c, shape = CircleShape) { if(i == color) Icon(Icons.Default.Check, t("Color"), tint = Color.White, modifier = Modifier.padding(10.dp)) }
                } }
            }
            CardBox {
                Text(t("Which days?"), style = MaterialTheme.typography.titleMedium)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) { DayOfWeek.entries.forEach { day ->
                    val bit = 1 shl (day.value - 1); val selected = weekdays and bit != 0
                    val label = day.getDisplayName(TextStyle.FULL, configuration.locales[0])
                    Surface(Modifier.weight(1f).heightIn(min = 48.dp).semantics { contentDescription = label; this.selected = selected }.clickable { if(!selected || weekdays != bit) weekdays = weekdays xor bit }, shape = CircleShape, color = if(selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant) {
                        Box(contentAlignment = Alignment.Center) { Text(day.getDisplayName(TextStyle.NARROW_STANDALONE, configuration.locales[0]), color = if(selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                } }
                TextButton(onClick = { val day = LocalDate.parse(start); DatePickerDialog(context, { _, y, m, d -> start = LocalDate.of(y, m + 1, d).toString() }, day.year, day.monthValue - 1, day.dayOfMonth).show() }) { Text(t("Start date") + " · " + date(LocalDate.parse(start))) }
                Text(t("Rest days do not break streaks or count as missed goals."), style = MaterialTheme.typography.bodySmall)
            }
            CardBox {
                Text(t("Measure your progress"), style = MaterialTheme.typography.titleMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(!limit, { limit = false }, { Text(t("Reach")) }); FilterChip(limit, { limit = true }, { Text(t("Do not exceed")) }) }
                if(limit) Text(t("Choose a limit, including zero. Quantities above the limit count as a penalty. Confirm zero to record a day with no occurrences."), style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(unit, { unit = it }, label = { Text(t("Unit, e.g. glasses, pages, minutes")) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(target, { target = it }, label = { Text(t("Daily target")) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(amount, { amount = it }, label = { Text(t("Amount per tap")) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth(), singleLine = true)
                Row(verticalAlignment = Alignment.CenterVertically) { Text(t("Allow negative values"), modifier = Modifier.weight(1f)); Switch(negative, { negative = it }) }
                Text(t("With negative values enabled, minus can take your balance below zero. History preserves the sign of each quantity."), style = MaterialTheme.typography.bodySmall)
            }
            if(!limit) CardBox {
                Text(t("Find your moment"), style = MaterialTheme.typography.titleMedium)
                Row(verticalAlignment = Alignment.CenterVertically) { Text(t("Preferred time"), Modifier.weight(1f)); IconButton({ hour = (hour + 23) % 24 }) { Icon(Icons.Default.Remove, t("Remove a step")) }; Text("%02d:00".format(hour)); IconButton({ hour = (hour + 1) % 24 }) { Icon(Icons.Default.Add, t("Log a step")) } }
                Row(verticalAlignment = Alignment.CenterVertically) { Text(t("Session duration (minutes)"), Modifier.weight(1f)); IconButton({ duration = (duration - 5).coerceAtLeast(5) }) { Icon(Icons.Default.Remove, t("Remove a step")) }; Text(duration.toString()); IconButton({ duration = (duration + 5).coerceAtMost(240) }) { Icon(Icons.Default.Add, t("Log a step")) } }
                Text(t("The assistant uses these preferences to suggest a free slot. No event is created automatically."), style = MaterialTheme.typography.bodySmall)
            }
            if(original != null) Text(t("Changes to targets and weekdays also apply to past statistics. Recorded quantities stay unchanged."), style = MaterialTheme.typography.bodySmall)
        }
    }
}

fun validEmoji(value: String): Boolean {
    if(value.isBlank() || value.toByteArray().size > 64) return false
    val boundaries = android.icu.text.BreakIterator.getCharacterInstance().apply { setText(value) }
    boundaries.first(); boundaries.next()
    return boundaries.next() == android.icu.text.BreakIterator.DONE && value.codePoints().anyMatch { it in 0x1F000..0x1FAFF || it in 0x2300..0x27FF || it == 0x20E3 || it == 0x00A9 || it == 0x00AE }
}

@Composable fun HabitDetails(h: Habit, state: ScreenState, model: MakeetModel, edit: () -> Unit, close: () -> Unit) {
    var days by rememberSaveable { mutableIntStateOf(28) }; var deleting by remember { mutableStateOf(false) }
    var cleanup by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }
    val context = LocalContext.current; val scope = rememberCoroutineScope()
    val stats = remember(h, state.activities, days) { HabitEngine.statistics(h, state.activities, days) }
    LazyColumn(modifier = Modifier.testTag("habit-details"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { CardBox { HabitMark(h); Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { OutlinedButton(edit) { Text(t("Edit habit")) }; OutlinedButton({ model.archive(h) }) { Text(t(if(h.archived) "Restore" else "Archive")) } }; if(h.archived) Text(t("Archived habits keep their full history.")) } }
        item { PeriodPicker(days) { days = it } }
        item { CardBox { Stats(stats); QuantityChart(stats, h.color) } }
        item { CardBox { Text(t("Hour"), style = MaterialTheme.typography.titleMedium); Row(Modifier.fillMaxWidth().height(80.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) { val max = stats.hours.maxOrNull()?.coerceAtLeast(1) ?: 1; stats.hours.forEach { count -> Box(Modifier.weight(1f).height((count.toDouble() / max * 72).coerceAtLeast(2.0).dp).background(HabitColors[h.color])) } }; Text("00:00                  12:00                  23:00", style = MaterialTheme.typography.labelSmall) } }
        item { Text(t("Logs"), style = MaterialTheme.typography.titleMedium) }
        items(state.activities.filter { it.habitId == h.id }.sortedByDescending { it.timestamp }.take(200), key = { it.id }) { a ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Text(number(a.amount) + " " + h.unit, fontWeight = FontWeight.SemiBold); Text(a.timestamp.atZone(ZoneId.of(h.zone)).format(java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.SHORT)), style = MaterialTheme.typography.bodySmall) }
                val total = HabitEngine.progress(h, state.activities, h.date(a.timestamp)).amount
                TextButton({ model.undo(a.id) }, enabled = h.negative || HabitEngine.total(listOf(total, -a.amount)) >= 0) { Text(t("Undo")) }
            }
        }
        item { TextButton({ deleting = true }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(t("Delete permanently")) } }
    }
    if(deleting) AlertDialog(onDismissRequest = { if(!busy) deleting = false }, title = { Text(h.name) }, text = { Column {
        Text(t("This permanently deletes the habit and all its entries. This cannot be undone."))
        if(DeviceCalendarService(context).allowed()) { Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(cleanup, { cleanup = it }, enabled = !busy); Text(t("Also remove future Makeet blocks")) }; Text(t("Removes only future events linked to this habit in editable calendars. Other events stay in place."), style = MaterialTheme.typography.bodySmall) }
    } }, confirmButton = { TextButton({ scope.launch { busy = true; if(model.remove(h.id, cleanup)) { deleting = false; close() }; busy = false } }, enabled = !busy) { Text(t("Delete habit and progress"), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ deleting = false }, enabled = !busy) { Text(t("Cancel")) } })
}

@Composable fun CalendarScreen(state: ScreenState, model: MakeetModel) {
    val configuration = LocalConfiguration.current
    var monthString by rememberSaveable { mutableStateOf(YearMonth.now().toString()) }
    val month = YearMonth.parse(monthString)
    var selected by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var correction by remember { mutableStateOf<Pair<Habit, Progress>?>(null) }
    val day = LocalDate.parse(selected)
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { CardBox {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { IconButton({ monthString = month.minusMonths(1).toString() }) { Icon(Icons.Default.ChevronLeft, t("Previous month")) }; Text(month.format(java.time.format.DateTimeFormatter.ofPattern("LLLL yyyy", configuration.locales[0])), Modifier.weight(1f), fontWeight = FontWeight.SemiBold); IconButton({ monthString = month.plusMonths(1).toString() }) { Icon(Icons.Default.ChevronRight, t("Next month")) } }
            val locale = configuration.locales[0]
            Row { DayOfWeek.entries.forEach { Text(it.getDisplayName(TextStyle.NARROW, locale), Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) } }
            val offset = month.atDay(1).dayOfWeek.value - 1
            repeat((offset + month.lengthOfMonth() + 6) / 7) { row -> Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(7) { col -> val n = row * 7 + col - offset + 1
                    if(n !in 1..month.lengthOfMonth()) Spacer(Modifier.weight(1f).height(54.dp)) else {
                        val d = month.atDay(n)
                        val habits = state.habits.filter { !it.archived && it.scheduled(d) }
                        val progress = habits.map { HabitEngine.progress(it, state.activities, d) }
                        val done = progress.count { it.complete }; val malus = progress.any { it.malus > 0 }
                        val future = d > LocalDate.now()
                        val fraction = if(habits.isEmpty()) 0f else (progress.sumOf { it.fraction } / habits.size).toFloat()
                        val bg = if(future || habits.isEmpty()) MaterialTheme.colorScheme.surfaceVariant else if(malus) HabitColors[3].copy(alpha = .25f) else MaterialTheme.colorScheme.primary.copy(alpha = .1f + .55f * fraction)
                        Surface(Modifier.weight(1f).height(54.dp).clickable { selected = d.toString() }, shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp), color = bg, border = if(d == day) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) { Text(n.toString()); if(!future && habits.isNotEmpty()) Text("$done/${habits.size}", style = MaterialTheme.typography.labelSmall) }
                        }
                    }
                }
            } }
            Text(t("More color, more progress. Tap a day to see habits and events."), style = MaterialTheme.typography.bodySmall)
        } }
        item { Text(date(day), style = MaterialTheme.typography.titleLarge) }
        items(state.habits.filter { h -> day >= h.date(h.createdAt) && (!h.archived || state.activities.any { it.habitId == h.id && h.date(it.timestamp) == day }) }, key = { it.id }) { h ->
            val p = HabitEngine.progress(h, state.activities, day)
            CardBox { Row(verticalAlignment = Alignment.CenterVertically) { HabitMark(h); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(h.name, fontWeight = FontWeight.SemiBold); Text(number(p.amount) + " " + h.unit); if(day <= h.date(Instant.now())) ProgressLabel(h, p) }; if(day <= h.date(Instant.now())) TextButton({ correction = h to p }) { Text(t("Edit progress")) } } }
        }
        item { CalendarDayEvents(day, state.user?.id ?: "local") }
    }
    correction?.let { (h, p) -> CorrectionSheet(h, day, p, { correction = null }) { value -> model.correct(h.id, day, p, value); correction = null } }
}

@Composable fun CorrectionSheet(h: Habit, day: LocalDate, original: Progress, close: () -> Unit, save: (Double) -> Unit) {
    var amount by remember { mutableDoubleStateOf(original.amount) }
    AlertDialog(onDismissRequest = close, title = { Text(h.name + " · " + date(day)) }, text = { Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { FilledTonalIconButton({ amount = HabitEngine.adjusted(h, amount, -h.step) }, enabled = h.negative || amount > 0) { Icon(Icons.Default.Remove, t("Remove a step")) }; Text(number(amount) + " " + h.unit, Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center); FilledTonalIconButton({ amount = HabitEngine.adjusted(h, amount, h.step) }) { Icon(Icons.Default.Add, t("Log a step")) } }
        TextButton({ amount = 0.0 }) { Text(t("Set to zero")) }
        Text(t("Adjust quantities and save. New entries on past days are marked as manual corrections at noon in the habit’s time zone."))
    } }, confirmButton = { TextButton({ save(amount) }) { Text(t("Save")) } }, dismissButton = { TextButton(close) { Text(t("Cancel")) } })
}
