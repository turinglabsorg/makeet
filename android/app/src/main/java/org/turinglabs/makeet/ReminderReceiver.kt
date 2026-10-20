package org.turinglabs.makeet

import android.Manifest
import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.time.*

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("makeet", Context.MODE_PRIVATE)
        if(intent.action == "org.turinglabs.makeet.REMIND" && prefs.getBoolean("reminders", false)) {
            val active = prefs.getString("scope", "local") ?: "local"
            if(active == intent.getStringExtra("scope")) runCatching { HabitStore(context, active).use { store ->
                val entries = store.activities()
                val demoIds = store.demoIDs()
                if(store.habits().any { h -> h.id !in demoIds && !h.archived && h.scheduled(h.date(Instant.now())) && HabitEngine.progress(h, entries, h.date(Instant.now())).let { if(h.goal == Goal.LIMIT) !it.logged else !it.complete } }) notify(context)
            } }
        }
        schedule(context)
    }
    companion object {
        fun allowed(context: Context) = android.os.Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        fun notify(context: Context) {
            if(!allowed(context)) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel("makeet-reminders", l(context, "Daily reminder"), NotificationManager.IMPORTANCE_DEFAULT))
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            manager.notify(100, Notification.Builder(context, "makeet-reminders").setSmallIcon(R.drawable.notification_icon)
                .setContentTitle("Makeet").setContentText(l(context, "One small step today.")).setContentIntent(open).setAutoCancel(true).build())
        }
        fun schedule(context: Context) {
            val p = context.getSharedPreferences("makeet", Context.MODE_PRIVATE)
            val active = p.getString("scope", "local") ?: "local"
            val intent = Intent(context, ReminderReceiver::class.java).setAction("org.turinglabs.makeet.REMIND").putExtra("scope", active)
            val pending = PendingIntent.getBroadcast(context, 100, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.cancel(pending)
            if(!p.getBoolean("reminders", false) || !allowed(context)) return
            val now = ZonedDateTime.now()
            var next = now.toLocalDate().atTime(p.getInt("reminder_hour", 18), 0).atZone(now.zone)
            if(next <= now) next = next.plusDays(1)
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.toInstant().toEpochMilli(), pending)
        }
    }
}

@Composable fun NotificationConnections() {
    val context = LocalContext.current
    val p = remember { context.getSharedPreferences("makeet", Context.MODE_PRIVATE) }
    var enabled by remember { mutableStateOf(p.getBoolean("reminders", false)) }
    var hour by remember { mutableIntStateOf(p.getInt("reminder_hour", 18)) }
    var allowed by remember { mutableStateOf(ReminderReceiver.allowed(context)) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> allowed = granted; ReminderReceiver.schedule(context) }
    CardBox {
        Text(t("Notifications"), style = MaterialTheme.typography.titleLarge)
        Text(t("Optional reminders run on this device. They contain no habit names. Delivery time is managed by Android."))
        Row { Text(t("Daily reminder"), Modifier.weight(1f)); Switch(enabled, { enabled = it; p.edit().putBoolean("reminders", it).apply(); if(it && !allowed && android.os.Build.VERSION.SDK_INT >= 33) request.launch(Manifest.permission.POST_NOTIFICATIONS); ReminderReceiver.schedule(context) }) }
        if(enabled) {
            Row { Text(t("Reminder time"), Modifier.weight(1f)); TextButton({ hour = (hour + 1) % 24; p.edit().putInt("reminder_hour", hour).apply(); ReminderReceiver.schedule(context) }) { Text("%02d:00".format(hour)) } }
            if(!allowed) Text(t("Not allowed"))
            OutlinedButton({ if(!allowed && android.os.Build.VERSION.SDK_INT >= 33) request.launch(Manifest.permission.POST_NOTIFICATIONS) else ReminderReceiver.notify(context) }) { Text(t("Send test notification")) }
        }
    }
}
