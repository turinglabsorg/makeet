package org.turinglabs.makeet

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import java.text.NumberFormat
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

val HabitColors = listOf(Color(0xFF4C8061), Color(0xFF658CAC), Color(0xFFC69343), Color(0xFFB87358))
@Composable fun t(key: String): String = stringResource(Strings.resources.getValue(key))
fun localized(context: Context): Context {
    val tags = if(android.os.Build.VERSION.SDK_INT >= 33) context.getSystemService(android.app.LocaleManager::class.java).applicationLocales.toLanguageTags()
        else context.getSharedPreferences("makeet", Context.MODE_PRIVATE).getString("language", "").orEmpty()
    if(tags.isBlank()) return context
    return context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(android.os.LocaleList.forLanguageTags(tags)) })
}
fun l(context: Context, key: String): String = localized(context).getString(Strings.resources.getValue(key))
fun number(value: Double): String = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 3 }.format(value)
fun date(day: LocalDate): String = day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))

@Composable fun MakeetApp(model: MakeetModel) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) darkColorScheme(primary = Color(0xFFA2C4A5), onPrimary = Color(0xFF173525), secondary = Color(0xFFA2C4A5),
        secondaryContainer = Color(0xFF314A39), onSecondaryContainer = Color(0xFFE9EEE5), background = Color(0xFF14231C),
        onBackground = Color(0xFFE9EEE5), surface = Color(0xFF203329), onSurface = Color(0xFFE9EEE5), surfaceVariant = Color(0xFF314035),
        surfaceContainer = Color(0xFF203329), surfaceContainerLow = Color(0xFF1B2B22), surfaceContainerHigh = Color(0xFF2B3E30))
        else lightColorScheme(primary = Color(0xFF376B50), onPrimary = Color.White, secondary = Color(0xFF376B50),
            secondaryContainer = Color(0xFFE8EDE2), onSecondaryContainer = Color(0xFF233B32), background = Color(0xFFF7F5EF),
            onBackground = Color(0xFF233B32), surface = Color.White, onSurface = Color(0xFF233B32), onSurfaceVariant = Color(0xFF68746A),
            surfaceVariant = Color(0xFFE8EDE2), surfaceContainer = Color(0xFFF0F2E8), surfaceContainerLow = Color(0xFFF7F5EF), surfaceContainerHigh = Color(0xFFE4E9DF))
    MaterialTheme(colorScheme = colors) {
        val state by model.screen.collectAsStateWithLifecycle()
        val context = LocalContext.current
        val preferences = remember { context.getSharedPreferences("makeet", Context.MODE_PRIVATE) }
        var onboarding by rememberSaveable { mutableStateOf(!preferences.getBoolean("onboarding.android.v1", false)) }
        Surface(Modifier.fillMaxSize(), color = colors.background) {
            if (onboarding) Onboarding(model) { preferences.edit().putBoolean("onboarding.android.v1", true).apply(); onboarding = false }
            else MainScreens(model, state)
        }
        if (state.error) AlertDialog(onDismissRequest = model::dismissError,
            title = { Text(t("Couldn’t complete the action")) }, text = { Text(t(state.errorKey)) },
            confirmButton = { TextButton(onClick = model::dismissError) { Text(t("OK")) } })
    }
}

@Composable fun LanguagePicker() {
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = true }) { Icon(Icons.Default.Language, null); Spacer(Modifier.width(6.dp)); Text(t("Language")) }
    if (open) AlertDialog(onDismissRequest = { open = false }, title = { Text(t("App language")) },
        text = { Column { listOf("" to t("Device language"), "it" to "Italiano", "en" to "English", "fr" to "Français", "de" to "Deutsch", "es" to "Español").forEach { (tag, name) ->
            TextButton(onClick = { open = false; context.getSharedPreferences("makeet", Context.MODE_PRIVATE).edit().putString("language", tag).apply(); AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(tag)); MakeetWidget.refresh(context) }, modifier = Modifier.fillMaxWidth()) { Text(name) }
        } } }, confirmButton = {})
}

@Composable fun Onboarding(model: MakeetModel, finish: () -> Unit) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    var choice by rememberSaveable { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val context = LocalContext.current; val scope = rememberCoroutineScope()
    val state by model.screen.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("Makeet", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); LanguagePicker() }
        Row(Modifier.padding(vertical = 24.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { repeat(3) { Box(Modifier.weight(1f).height(4.dp).background(if (it <= step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant, CircleShape)) } }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(t(when(step) { 0 -> "Make room in your day"; 1 -> "Where should your progress live?"; else -> "Let’s start with something simple." }), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.SemiBold)
            Text(t(when(step) { 0 -> "Make room for the habits that matter to you. Makeet helps you record how much you do and find the right time."; 1 -> "An account keeps your progress with you, even on a new device. Or you can start just here."; else -> "Choose a habit, your target amount, and your ideal time. We’ll shape the rest together." }), style = MaterialTheme.typography.bodyLarge)
            if (step == 0) {
                CardBox { Text(t("A glimpse of your day"), style = MaterialTheme.typography.labelLarge); Text("💧  " + t("Drink water"), style = MaterialTheme.typography.titleLarge); Text("3 / 6  " + t("glasses")); LinearProgressIndicator(progress = { 0.5f }, modifier = Modifier.fillMaxWidth()); Text(t("Illustrative preview"), style = MaterialTheme.typography.labelSmall) }
                Text(t("Glasses, pages, minutes: add quantities and correct them when needed."))
                Text(t("Calendar and notifications are optional. Enable them later, with your permission."))
            }
            if (step == 1) {
                listOf("account" to "With an account", "local" to "Only on this device").forEach { (value, label) ->
                    OutlinedCard(onClick = { choice = value }, border = BorderStroke(if(choice == value) 2.dp else 1.dp, if(choice == value) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant), modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) { RadioButton(choice == value, { choice = value }); Column { Text(t(label), fontWeight = FontWeight.SemiBold); Text(t(if(value == "local") "No sign-up. Your progress stays here. You can sign in whenever you like." else "Your private archive, synced for free.")) } }
                    }
                }
                if(choice == "account") {
                    ProviderButtons(model) { step = 2 }
                    Text(t("Already have habits on this device? You decide whether to import them after signing in."), style = MaterialTheme.typography.bodySmall)
                    PolicyLinks()
                }
            }
            if (step == 2) {
                Text(t("All features are free, including account sync."))
                Text(t("You can adjust past days from the habit’s start date onward."))
                Text(t("Connect your calendar when you want. Every new event needs your confirmation."))
            }
        }
        if(step != 1 || choice != "account") Button(onClick = { if(step == 2) finish() else step = if(step == 0 && state.user != null) 2 else step + 1 },
            enabled = step != 1 || choice != null, modifier = Modifier.fillMaxWidth().padding(top = 16.dp).heightIn(min = 56.dp)) { Text(t(if(step == 2) "Let’s begin" else if(step == 1) "Continue on this device" else "Continue")) }
        if(step > 0) TextButton(onClick = { step-- }, modifier = Modifier.fillMaxWidth()) { Text(t("Back")) }
    }
}

@Composable fun GoogleButton(loading: Boolean, click: () -> Unit) {
    OutlinedButton(onClick = click, enabled = !loading, modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp), shape = RoundedCornerShape(15.dp)) {
        Image(painterResource(R.drawable.google_logo), null, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(12.dp)); Text(t("Continue with Google"))
        if(loading) { Spacer(Modifier.width(12.dp)); CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) }
    }
}

@Composable fun ProviderButtons(model: MakeetModel, signedIn: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by model.screen.collectAsStateWithLifecycle()
    var busy by remember { mutableStateOf(false) }
    var task by remember { mutableStateOf<Job?>(null) }
    var passwordAccess by remember { mutableStateOf(false) }
    fun begin() {
        task = scope.launch {
            busy = true
            try { if(model.signIn(context)) signedIn() }
            finally { busy = false }
        }
    }
    GoogleButton(busy) { begin() }
    if(state.passwordEnabled) OutlinedButton({ passwordAccess = true }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp)) { Text(t("Sign in with password")) }
    if(passwordAccess) PasswordAccess(model, null, { passwordAccess = false }) { passwordAccess = false; signedIn() }
    if(busy) TextButton(onClick = { task?.cancel() }) { Text(t("Cancel")) }
}

@Composable fun PolicyLinks() {
    val context = LocalContext.current
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("Privacy notice" to "privacy", "Terms of use" to "terms").forEach { (label, path) -> TextButton(onClick = { openSite(context, path) }) { Text(t(label)) } }
    }
}
fun openSite(context: Context, path: String) {
    val language = context.resources.configuration.locales[0].language.let { if(it in listOf("it", "en", "fr", "de", "es")) it else "en" }
    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://makeet.app/$language/$path")))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MainScreens(model: MakeetModel, state: ScreenState) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var edit by remember { mutableStateOf<Habit?>(null) }; var create by rememberSaveable { mutableStateOf(false) }
    var detail by rememberSaveable { mutableStateOf<String?>(null) }
    var clearDemo by remember { mutableStateOf(false) }
    val titles = listOf("Today", "Calendar", "Trends", "Your plan")
    val icons = listOf(Icons.Default.GridView, Icons.Default.CalendarMonth, Icons.Default.BarChart, Icons.Default.AutoAwesome)
    val accountLabel = t("Account")
    Scaffold(containerColor = MaterialTheme.colorScheme.background,
        topBar = { TopAppBar(title = { Text(t(titles[tab]), fontWeight = FontWeight.SemiBold) },
            navigationIcon = { IconButton(onClick = { create = true }) { Icon(Icons.Default.Add, t("New habit")) } },
            actions = { IconButton(onClick = { settings = true }, modifier = Modifier.semantics { contentDescription = accountLabel }) { Avatar(state.profile, 34) } },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)) },
        bottomBar = { NavigationBar { titles.forEachIndexed { i, title -> NavigationBarItem(selected = tab == i, onClick = { tab = i }, icon = { Icon(icons[i], null) }, label = { Text(t(title)) }) } } }) { padding ->
      Column(Modifier.padding(padding).fillMaxSize()) {
        if(state.demo) Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(t("Demo data"), Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton({ clearDemo = true }) { Text(t("Delete demo data")) }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when(tab) {
                0 -> Today(state, model, { create = true }, { detail = it })
                1 -> CalendarScreen(state, model)
                2 -> Trends(state) { detail = it }
                3 -> Planner(state, model, { settings = true })
            }
        }
      }
    }
    if(clearDemo) AlertDialog(onDismissRequest = { clearDemo = false }, title = { Text(t("Delete all demo data?")) }, text = { Text(t("Your own habits are preserved. Only the labeled examples and their entries will be removed.")) }, confirmButton = { TextButton({ model.clearDemo(); clearDemo = false }) { Text(t("Delete demo data")) } }, dismissButton = { TextButton({ clearDemo = false }) { Text(t("Cancel")) } })
    if(settings) FullScreen(t("Connections"), { settings = false }) { AccountScreen(model, state) }
    if(create || edit != null) HabitEditor(edit, { create = false; edit = null }) { model.save(it, edit); create = false; edit = null }
    detail?.let { id -> state.habits.firstOrNull { it.id == id }?.let { h ->
        FullScreen(h.name, { detail = null }) { HabitDetails(h, state, model, { edit = h }, { detail = null }) }
    } ?: run { detail = null } }
}

@Composable fun Avatar(profile: org.json.JSONObject, size: Int) {
    val image = remember(profile.optString("image")) { runCatching { Base64.decode(profile.optString("image"), Base64.DEFAULT).let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }.getOrNull() }
    Surface(Modifier.size(size.dp), shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) {
        if(image != null) Image(image, t("Profile photo"), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        else Box(contentAlignment = Alignment.Center) { val name = profile.optString("name"); if(name.isNotBlank()) Text(name.split(" ").take(2).mapNotNull { it.firstOrNull() }.joinToString(""), fontWeight = FontWeight.SemiBold) else Icon(Icons.Default.Person, t("Account")) }
    }
}

@Composable fun CardBox(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content) }
}

@Composable fun HabitMark(habit: Habit) {
    if(habit.symbol.startsWith("emoji:")) Text(habit.symbol.removePrefix("emoji:"), fontSize = 26.sp)
    else Icon(when(habit.symbol) { "drop.fill" -> Icons.Default.WaterDrop; "book.fill" -> Icons.Default.MenuBook; "figure.walk" -> Icons.Default.DirectionsWalk; "cup.and.saucer.fill" -> Icons.Default.Coffee; "moon.fill" -> Icons.Default.Bedtime; "heart.fill" -> Icons.Default.Favorite; else -> Icons.Default.Eco }, null, tint = HabitColors[habit.color], modifier = Modifier.size(28.dp))
}

@Composable fun Today(state: ScreenState, model: MakeetModel, create: () -> Unit, detail: (String) -> Unit) {
    val habits = state.habits.filter { !it.archived && it.scheduled(it.date(Instant.now())) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { Text(date(LocalDate.now()), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if(habits.isEmpty()) item { CardBox { Text(t(if(state.habits.isEmpty()) "There’s room for a first step." else "You can rest today"), style = MaterialTheme.typography.headlineSmall); Text(t(if(state.habits.isEmpty()) "Create a habit in Today to start tracking it." else "No habits are scheduled. View and adjust all your progress in Calendar.")); Button(onClick = create) { Text(t("New habit")) }; if(state.user == null && state.habits.isEmpty()) TextButton(model::exploreDemo) { Text(t("Explore with demo data")) } } }
        items(habits, key = { it.id }) { h ->
            val day = h.date(Instant.now()); val p = HabitEngine.progress(h, state.activities, day)
            CardBox {
                Row(Modifier.fillMaxWidth().clickable { detail(h.id) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { HabitMark(h); Column(Modifier.weight(1f)) { Text(h.name, style = MaterialTheme.typography.titleLarge); ProgressLabel(h, p) }; Icon(Icons.Default.ChevronRight, t("Details")) }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    FilledTonalIconButton(onClick = { model.log(h.id, -h.step) }, enabled = h.negative || p.amount > 0, modifier = Modifier.size(48.dp)) { Icon(Icons.Default.Remove, t("Remove a step")) }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(number(p.amount) + " / " + number(h.target), style = MaterialTheme.typography.headlineMedium); Text(h.unit, style = MaterialTheme.typography.labelMedium) }
                    FilledTonalIconButton(onClick = { model.log(h.id, h.step) }, modifier = Modifier.size(48.dp)) { Icon(Icons.Default.Add, t("Log a step")) }
                }
                LinearProgressIndicator(progress = { p.fraction.toFloat() }, color = if(p.malus > 0) HabitColors[3] else HabitColors[h.color], trackColor = MaterialTheme.colorScheme.surfaceVariant, drawStopIndicator = {}, modifier = Modifier.fillMaxWidth())
                if(h.goal == Goal.LIMIT && !p.logged) OutlinedButton(onClick = { model.log(h.id, 0.0) }, modifier = Modifier.fillMaxWidth()) { Text(t("Confirm zero")) }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { repeat(14) { i -> val d = day.minusDays(13L - i); val old = HabitEngine.progress(h, state.activities, d); Box(Modifier.weight(1f).height(10.dp).background(if(old.malus > 0) HabitColors[3] else if(old.complete) HabitColors[h.color] else MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(3.dp))) } }
            }
        }
    }
}

@Composable fun ProgressLabel(habit: Habit, p: Progress) {
    if(p.malus > 0) Text(t("Penalty") + " · " + number(p.malus), color = HabitColors[3])
    else if(habit.goal == Goal.LIMIT) Text(t(if(p.logged) "Within limit" else "Not confirmed"), color = if(p.logged) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
    else if(p.complete) Text(t("Done"), color = MaterialTheme.colorScheme.primary)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun FullScreen(title: String, close: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Scaffold(containerColor = MaterialTheme.colorScheme.background, topBar = { TopAppBar(title = { Text(title) }, navigationIcon = { IconButton(close) { Icon(Icons.AutoMirrored.Filled.ArrowBack, t("Back")) } }, actions = actions, colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)) }) { padding -> Box(Modifier.padding(padding)) { content() } }
    }
}

@Composable fun Trends(state: ScreenState, detail: (String) -> Unit) {
    var days by rememberSaveable { mutableIntStateOf(28) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PeriodPicker(days) { days = it } }
        if(state.habits.isEmpty()) item { Text(t("Create a habit in Today to start tracking it.")) }
        items(state.habits, key = { it.id }) { h -> val stats = remember(h, state.activities, days) { HabitEngine.statistics(h, state.activities, days) }
            CardBox { Row(Modifier.fillMaxWidth().clickable { detail(h.id) }, horizontalArrangement = Arrangement.spacedBy(12.dp)) { HabitMark(h); Text(h.name, style = MaterialTheme.typography.titleLarge) }; Stats(stats); QuantityChart(stats, h.color) }
        }
    }
}

@Composable fun PeriodPicker(days: Int, change: (Int) -> Unit) { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(7 to "7 days", 28 to "28 days", 84 to "12 weeks").forEach { (value, label) -> FilterChip(days == value, { change(value) }, { Text(t(label)) }) } } }
@Composable fun Stats(stats: Statistics) {
    listOf("Amount" to number(stats.total), "daily average" to number(stats.average), "days on target" to "${stats.completed} / ${stats.expected}", "current streak in days" to stats.currentStreak.toString(), "Best streak" to stats.bestStreak.toString()).forEach { (label, value) -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(t(label), modifier = Modifier.weight(1f)); Text(value, fontWeight = FontWeight.SemiBold) } }
}
@Composable fun QuantityChart(stats: Statistics, color: Int) {
    val description = t("How much, day by day")
    Box(Modifier.fillMaxWidth().height(96.dp).semantics { contentDescription = description }) {
      Box(Modifier.fillMaxWidth().height(1.dp).align(Alignment.Center).background(MaterialTheme.colorScheme.outlineVariant))
      Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        val max = maxOf(1.0, stats.daily.maxOfOrNull { kotlin.math.abs(it.second.amount) } ?: 1.0)
        stats.daily.forEach { (_, p) -> Column(Modifier.weight(1f).fillMaxHeight()) {
            val height = (kotlin.math.abs(p.amount) / max * 44).coerceAtLeast(2.0).dp
            val fill = if(p.malus > 0 || p.amount < 0) HabitColors[3] else HabitColors[color]
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) { if(p.amount >= 0) Box(Modifier.fillMaxWidth().height(height).background(fill, RoundedCornerShape(2.dp))) }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) { if(p.amount < 0) Box(Modifier.fillMaxWidth().height(height).background(fill, RoundedCornerShape(2.dp))) }
        } }
      }
    }
}
