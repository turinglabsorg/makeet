package org.turinglabs.makeet

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.time.*
import java.util.UUID

data class Record(val kind: String, val id: String, val revision: Long, val deleted: Boolean,
                  val data: JSONObject, val dirty: Boolean = false, val sequence: Long = 0) {
    fun wire() = JSONObject().put("kind", kind).put("id", id).put("revision", revision).put("deleted", deleted).put("data", data)
    companion object { fun read(d: JSONObject) = Record(d.getString("kind"), d.getString("id").lowercase(),
        d.getLong("revision"), d.getBoolean("deleted"), d.optJSONObject("data") ?: JSONObject()) }
}

class HabitStore(context: Context, val scope: String) : SQLiteOpenHelper(context, "makeet-${safe(scope)}.db", null, 3), java.io.Closeable {
    companion object {
        private fun safe(scope: String): String { require(scope == "local" || UUID.fromString(scope).toString() == scope); return scope }
    }
    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true); db.enableWriteAheadLogging() }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE records(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,data TEXT NOT NULL,dirty INTEGER NOT NULL,sequence INTEGER NOT NULL,parent_id TEXT,PRIMARY KEY(kind,id))")
        db.execSQL("CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
        db.execSQL("CREATE TABLE conflicts(kind TEXT NOT NULL,id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(kind,id))")
        db.execSQL("CREATE INDEX records_dirty ON records(dirty,kind,sequence)")
        db.execSQL("CREATE INDEX records_activity_parent ON records(parent_id) WHERE kind='activity' AND deleted=0")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if(oldVersion < 3) {
            db.execSQL("DROP INDEX IF EXISTS records_activity_parent")
            db.execSQL("ALTER TABLE records ADD COLUMN parent_id TEXT")
            db.rawQuery("SELECT id,data FROM records WHERE kind='activity' AND deleted=0", null).use { cursor ->
                while(cursor.moveToNext()) {
                    val parent = JSONObject(cursor.getString(1)).getString("habit_id")
                    db.execSQL("UPDATE records SET parent_id=? WHERE kind='activity' AND id=?", arrayOf(parent, cursor.getString(0)))
                }
            }
            db.execSQL("CREATE INDEX records_activity_parent ON records(parent_id) WHERE kind='activity' AND deleted=0")
        }
    }
    private fun query(where: String = "", args: Array<String>? = null, order: String = ""): List<Record> = readableDatabase.rawQuery("SELECT * FROM records $where $order", args).use { c ->
        buildList { while (c.moveToNext()) add(Record(c.getString(0), c.getString(1), c.getLong(2), c.getInt(3) != 0,
            JSONObject(c.getString(4)), c.getInt(5) != 0, c.getLong(6))) }
    }
    @Synchronized fun records() = query()
    @Synchronized fun hasPendingChanges() = readableDatabase.rawQuery("SELECT 1 FROM records WHERE dirty=1 LIMIT 1", null).use { it.moveToFirst() }
    private fun find(kind: String, id: String) = query("WHERE kind=? AND id=?", arrayOf(kind, id)).firstOrNull()
    private fun children(id: String) = query("WHERE kind='activity' AND deleted=0 AND parent_id=?", arrayOf(id))
    @Synchronized fun habits() = query("WHERE kind='habit' AND deleted=0").map { Habit.read(it.id, it.data) }.sortedBy { it.createdAt }
    @Synchronized fun activities() = query("WHERE kind='activity' AND deleted=0").map { Activity.read(it.id, it.data) }
    private fun write(record: Record) {
        writableDatabase.insertWithOnConflict("records", null, ContentValues().apply {
            put("kind", record.kind); put("id", record.id); put("revision", record.revision); put("deleted", if (record.deleted) 1 else 0)
            put("data", record.data.toString()); put("dirty", if (record.dirty) 1 else 0); put("sequence", record.sequence)
            put("parent_id", if(record.kind == "activity" && !record.deleted) record.data.getString("habit_id") else null)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    private fun mutate(kind: String, id: String, data: JSONObject, deleted: Boolean = false) {
        val old = find(kind, id)
        check(old?.deleted != true || deleted)
        val sequence = (meta("sequence")?.toLong() ?: 0) + 1
        setMeta("sequence", sequence.toString())
        write(Record(kind, id, old?.revision ?: 0, deleted, data, true, sequence))
    }
    @Synchronized fun <T> transaction(action: () -> T): T {
        writableDatabase.beginTransaction()
        try { val result = action(); writableDatabase.setTransactionSuccessful(); return result }
        finally { writableDatabase.endTransaction() }
    }
    @Synchronized fun save(habit: Habit) = transaction { require(habit.valid()); mutate("habit", habit.id, habit.data()) }
    @Synchronized fun importActivity(activity: Activity) = transaction {
        require(habits().any { it.id == activity.habitId } && activity.amount.isFinite())
        mutate("activity", activity.id, activity.data())
    }
    @Synchronized fun demoIDs(): Set<String> = JSONArray(meta("demo_ids") ?: "[]").let { data -> (0 until data.length()).map { data.getString(it) }.toSet() }
    @Synchronized fun clearDemo() = transaction { demoIDs().forEach { remove(it) }; setMeta("demo_ids", null) }
    @Synchronized fun importFromLocal(local: HabitStore) = transaction {
        check(scope != "local" && local.scope == "local")
        val demo = local.demoIDs()
        val real = local.habits().filter { it.id !in demo }
        val existing = habits().map { it.id }.toSet()
        real.filter { it.id !in existing }.forEach { save(it) }
        val parents = real.map { it.id }.toSet()
        val existingActivities = activities().map { it.id }.toSet()
        local.activities().filter { it.habitId in parents && it.id !in existingActivities }.forEach { importActivity(it) }
    }
    @Synchronized fun log(habitId: String, delta: Double, day: LocalDate? = null, now: Instant = Instant.now()) = transaction {
        val habit = habits().first { it.id == habitId }
        val chosen = day ?: habit.date(now)
        require(chosen <= habit.date(now) && chosen >= habit.date(habit.createdAt) && delta.isFinite())
        val previous = HabitEngine.progress(habit, activities(), chosen)
        val next = HabitEngine.adjusted(habit, previous.amount, delta)
        val at = if (chosen == habit.date(now)) now else chosen.atTime(12, 0).atZone(ZoneId.of(habit.zone)).toInstant()
        if(delta < 0 && !habit.negative) {
            var remaining = minOf(-delta, previous.amount.coerceAtLeast(0.0))
            val entries = children(habitId).map { Activity.read(it.id, it.data) }.filter { habit.date(it.timestamp) == chosen && it.amount > 0 }.sortedByDescending { it.timestamp }
            for(entry in entries) {
                if(remaining <= 0) break
                val removed = minOf(remaining, entry.amount)
                val corrected = entry.amount - removed
                remaining -= removed
                if(corrected <= maxOf(Math.ulp(entry.amount), Math.ulp(removed)) * 8) mutate("activity", entry.id, JSONObject(), true)
                else mutate("activity", entry.id, entry.copy(amount = corrected).data())
            }
            if(habit.goal == Goal.LIMIT && previous.amount > 0 && next == 0.0) {
                val zero = Activity(habitId = habitId, amount = 0.0, timestamp = at)
                mutate("activity", zero.id, zero.data())
            }
        } else if (next != previous.amount || delta == 0.0 && habit.goal == Goal.LIMIT && !previous.logged) {
            val a = Activity(habitId = habitId, amount = HabitEngine.total(listOf(next, -previous.amount)), timestamp = at)
            mutate("activity", a.id, a.data())
        }
    }
    @Synchronized fun correct(habitId: String, day: LocalDate, expected: Progress, amount: Double, now: Instant = Instant.now()) = transaction {
        val habit = habits().first { it.id == habitId }
        require(amount.isFinite() && (habit.negative || amount >= 0))
        check(HabitEngine.progress(habit, activities(), day) == expected) { "stale_day" }
        log(habitId, HabitEngine.total(listOf(amount, -expected.amount)), day, now)
    }
    @Synchronized fun remove(habitId: String) = transaction {
        val habit = find("habit", habitId) ?: return@transaction
        (listOf(habit) + children(habitId)).forEach { mutate(it.kind, it.id, JSONObject(), true) }
    }
    @Synchronized fun undo(activityId: String) = transaction {
        val activity = activities().first { it.id == activityId }
        val habit = habits().first { it.id == activity.habitId }
        val day = habit.date(activity.timestamp)
        require(habit.negative || HabitEngine.total(listOf(HabitEngine.progress(habit, activities(), day).amount, -activity.amount)) >= 0)
        mutate("activity", activityId, JSONObject(), true)
    }
    @Synchronized fun meta(key: String): String? = readableDatabase.rawQuery("SELECT value FROM metadata WHERE key=?", arrayOf(key)).use { if (it.moveToFirst()) it.getString(0) else null }
    @Synchronized fun setMeta(key: String, value: String?) {
        if (value == null) writableDatabase.delete("metadata", "key=?", arrayOf(key))
        else writableDatabase.insertWithOnConflict("metadata", null, ContentValues().apply { put("key", key); put("value", value) }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    @Synchronized fun pending(): JSONObject = transaction {
        meta("pending")?.let { return@transaction JSONObject(it) }
        check(conflicts().isEmpty()) { "revision_conflict" }
        val changes = query("WHERE dirty=1", order = "ORDER BY kind DESC,sequence LIMIT 100")
        val body = JSONObject().put("cursor", meta("cursor")?.toLong() ?: 0).put("mutation_id", if (changes.isEmpty()) "" else UUID.randomUUID().toString())
            .put("changes", JSONArray(changes.map { it.wire() }))
        setMeta("pending", body.toString())
        setMeta("pending_sequences", JSONObject().apply { changes.forEach { put(it.kind + it.id, it.sequence) } }.toString())
        body
    }
    @Synchronized fun apply(response: JSONObject) = transaction {
        val sent = JSONObject(meta("pending_sequences") ?: "{}")
        val applied = response.getJSONArray("applied")
        for (i in 0 until applied.length()) {
            val incoming = Record.read(applied.getJSONObject(i))
            val old = find(incoming.kind, incoming.id)
            if (old != null && old.sequence != sent.optLong(old.kind + old.id, -1) && !incoming.deleted)
                write(old.copy(revision = maxOf(old.revision, incoming.revision)))
            else write(incoming)
        }
        val changes = response.getJSONArray("changes")
        for (i in 0 until changes.length()) receive(Record.read(changes.getJSONObject(i)))
        setMeta("cursor", response.getLong("cursor").toString())
        setMeta("pending", null); setMeta("pending_sequences", null)
    }
    private fun receive(incoming: Record) {
        val old = find(incoming.kind, incoming.id)
        if (!incoming.deleted && old != null && incoming.revision <= old.revision) return
        if (incoming.deleted) {
            write(incoming)
            if (incoming.kind == "habit") children(incoming.id)
                .forEach { write(it.copy(deleted = true, dirty = false, data = JSONObject())) }
        } else if (old?.dirty == true) conflict(incoming) else write(incoming)
    }
    private fun conflict(record: Record) { writableDatabase.insertWithOnConflict("conflicts", null, ContentValues().apply {
        put("kind", record.kind); put("id", record.id); put("data", record.wire().toString())
    }, SQLiteDatabase.CONFLICT_REPLACE) }
    @Synchronized fun recordConflicts(items: JSONArray) = transaction {
        for (i in 0 until items.length()) {
            val r = Record.read(items.getJSONObject(i))
            if (r.deleted) receive(r) else conflict(r)
        }
        setMeta("pending", null); setMeta("pending_sequences", null)
    }
    @Synchronized fun conflicts(): List<Record> = readableDatabase.rawQuery("SELECT data FROM conflicts", null).use { c ->
        buildList { while (c.moveToNext()) add(Record.read(JSONObject(c.getString(0)))) }
    }
    @Synchronized fun resolve(remote: Record, useLocal: Boolean) = transaction {
        val old = find(remote.kind, remote.id)
        if (useLocal && !remote.deleted && old != null) write(old.copy(revision = remote.revision, dirty = true)) else write(remote)
        writableDatabase.delete("conflicts", "kind=? AND id=?", arrayOf(remote.kind, remote.id))
    }
    @Synchronized fun export() = JSONObject().put("format", "makeet-android-1").put("exported_at", Instant.now().toString())
        .put("demo_habit_ids", JSONArray(demoIDs().toList()))
        .put("records", JSONArray(records().filter { !it.deleted }.map { it.wire() }))
}
