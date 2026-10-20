package org.turinglabs.makeet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.time.Instant

class MakeetWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { ids.forEach { render(context, manager, it) } }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if(intent.action != "org.turinglabs.makeet.LOG") return
        val active = scope(context)
        if(intent.getStringExtra("scope") != active) { refresh(context); return }
        runCatching { HabitStore(context, active).use { store ->
            val id = intent.getStringExtra("habit") ?: return@use
            val h = store.habits().firstOrNull { it.id == id && !it.archived && it.scheduled(it.date(Instant.now())) } ?: return@use
            store.log(id, when(intent.getIntExtra("direction", 0)) { -1 -> -h.step; 1 -> h.step; else -> if(h.goal == Goal.LIMIT) 0.0 else return@use })
        } }
        refresh(context)
    }
    companion object {
        private fun scope(context: Context) = context.getSharedPreferences("makeet", Context.MODE_PRIVATE).getString("scope", "local") ?: "local"
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, MakeetWidget::class.java)).forEach { render(context, manager, it) }
        }
        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val active = scope(context)
            val views = RemoteViews(context.packageName, R.layout.habit_widget)
            val open = PendingIntent.getActivity(context, widgetId, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_title, open)
            views.setTextViewText(R.id.widget_title, "Makeet")
            runCatching { HabitStore(context, active).use { store ->
                val activities = store.activities()
                if(store.demoIDs().isNotEmpty()) views.setTextViewText(R.id.widget_title, "Makeet · " + l(context, "Demo data"))
                val habits = store.habits().filter { !it.archived && it.scheduled(it.date(Instant.now())) }.take(2)
                views.setViewVisibility(R.id.widget_empty, if(habits.isEmpty()) View.VISIBLE else View.GONE)
                views.setTextViewText(R.id.widget_empty, l(context, "Open Makeet to access your data."))
                views.setOnClickPendingIntent(R.id.widget_empty, open)
                listOf(R.id.widget_row1, R.id.widget_row2).forEachIndexed { index, row ->
                    val h = habits.getOrNull(index)
                    views.setViewVisibility(row, if(h == null) View.GONE else View.VISIBLE)
                    if(h != null) {
                        val p = HabitEngine.progress(h, activities, h.date(Instant.now()))
                        val nameId = if(index == 0) R.id.widget_name1 else R.id.widget_name2
                        val quantityId = if(index == 0) R.id.widget_quantity1 else R.id.widget_quantity2
                        val minusId = if(index == 0) R.id.widget_minus1 else R.id.widget_minus2
                        val plusId = if(index == 0) R.id.widget_plus1 else R.id.widget_plus2
                        views.setTextViewText(nameId, if(h.symbol.startsWith("emoji:")) h.symbol.removePrefix("emoji:") + " " + h.name else h.name)
                        var quantity = number(p.amount) + " / " + number(h.target) + " " + h.unit
                        if(h.goal == Goal.LIMIT) quantity += " · " + l(context, if(!p.logged) "Not confirmed" else if(p.complete) "Within limit" else "Penalty")
                        if(p.malus > 0) quantity += " " + number(p.malus)
                        views.setTextViewText(quantityId, quantity)
                        views.setContentDescription(quantityId, quantity)
                        views.setTextColor(quantityId, if(p.malus > 0 || p.amount < 0) 0xFFB87358.toInt() else 0xFF376B50.toInt())
                        views.setBoolean(minusId, "setEnabled", h.negative || p.amount > 0)
                        views.setOnClickPendingIntent(nameId, open)
                        for((view, direction) in listOf(minusId to -1, plusId to 1)) {
                            val action = Intent(context, MakeetWidget::class.java).setAction("org.turinglabs.makeet.LOG")
                                .setData(Uri.parse("makeet-widget://$widgetId/$active/${h.id}/$direction"))
                                .putExtra("scope", active).putExtra("habit", h.id).putExtra("direction", direction)
                            views.setOnClickPendingIntent(view, PendingIntent.getBroadcast(context, 0, action, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                            views.setContentDescription(view, l(context, if(direction < 0) "Remove a step" else "Log a step"))
                        }
                        if(h.goal == Goal.LIMIT && !p.logged) {
                            val zero = Intent(context, MakeetWidget::class.java).setAction("org.turinglabs.makeet.LOG")
                                .setData(Uri.parse("makeet-widget://$widgetId/$active/${h.id}/zero"))
                                .putExtra("scope", active).putExtra("habit", h.id).putExtra("direction", 0)
                            views.setOnClickPendingIntent(quantityId, PendingIntent.getBroadcast(context, 0, zero, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                            views.setContentDescription(quantityId, l(context, "Confirm zero"))
                        } else views.setOnClickPendingIntent(quantityId, open)
                    }
                }
            } }.onFailure { views.setViewVisibility(R.id.widget_row1, View.GONE); views.setViewVisibility(R.id.widget_row2, View.GONE); views.setViewVisibility(R.id.widget_empty, View.VISIBLE); views.setTextViewText(R.id.widget_empty, l(context, "Open Makeet to access your data.")) }
            manager.updateAppWidget(widgetId, views)
        }
    }
}
