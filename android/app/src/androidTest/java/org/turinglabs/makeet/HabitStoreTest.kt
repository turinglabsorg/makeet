package org.turinglabs.makeet

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.time.*
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class HabitStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun isolated(block: (HabitStore, String) -> Unit) {
        val id = UUID.randomUUID().toString()
        val store = HabitStore(context, id)
        try { block(store, id) } finally { store.close(); context.deleteDatabase("makeet-$id.db") }
    }
    @Test fun signedProgressZeroCorrectionAndReopening() = isolated { store, id ->
        val h = Habit(name = "QA Balance", unit = "times", negative = true, createdAt = Instant.now().minusSeconds(86400 * 2))
        store.save(h); store.log(h.id, -1.0); store.log(h.id, -1.0)
        val day = h.date(Instant.now())
        val previous = HabitEngine.progress(h, store.activities(), day)
        assertEquals(-2.0, previous.amount, 0.0)
        store.correct(h.id, day, previous, 0.0)
        HabitStore(context, id).use { reopened -> assertEquals(0.0, HabitEngine.progress(h, reopened.activities(), day).amount, 0.0) }
        val yesterday = day.minusDays(1)
        store.correct(h.id, yesterday, HabitEngine.progress(h, store.activities(), yesterday), -3.0)
        assertEquals(-3.0, HabitEngine.progress(h, store.activities(), yesterday).amount, 0.0)
        assertEquals(0.0, HabitEngine.progress(h, store.activities(), day).amount, 0.0)
    }
    @Test fun zeroLimitIsDurableAndClampsLegacyMinus() = isolated { store, id ->
        val h = Habit(name = "QA Limit", unit = "times", target = 0.0, goal = Goal.LIMIT)
        store.save(h); store.log(h.id, -1.0)
        assertTrue(store.activities().isEmpty())
        store.log(h.id, 0.0)
        HabitStore(context, id).use { reopened -> assertTrue(HabitEngine.progress(h, reopened.activities(), h.date(Instant.now())).complete) }
        store.log(h.id, 2.0); store.log(h.id, -1.0)
        assertEquals(1.0, HabitEngine.progress(h, store.activities(), h.date(Instant.now())).malus, 0.0)
    }
    @Test fun staleCorrectionCannotOverwriteNewEntry() = isolated { store, _ ->
        val h = Habit(name = "QA Stale", unit = "times"); store.save(h)
        val day = h.date(Instant.now()); val snapshot = HabitEngine.progress(h, store.activities(), day)
        store.log(h.id, 1.0)
        assertTrue(runCatching { store.correct(h.id, day, snapshot, 0.0) }.isFailure)
        assertEquals(1.0, HabitEngine.progress(h, store.activities(), day).amount, 0.0)
    }
    @Test fun immutablePendingBatchSurvivesReopeningAndConcurrentEdit() = isolated { store, id ->
        val h = Habit(name = "QA Sync", unit = "times"); store.save(h)
        val request = store.pending().toString()
        store.save(h.copy(name = "Edited during upload"))
        HabitStore(context, id).use { reopened -> assertEquals(request, reopened.pending().toString()) }
        val incoming = Record("habit", h.id, 1, false, h.data()).wire()
        store.apply(JSONObject().put("cursor", 1).put("has_more", false).put("applied", JSONArray().put(incoming)).put("changes", JSONArray().put(incoming)))
        assertEquals("Edited during upload", store.habits().single().name)
        assertTrue(store.records().single().dirty)
        assertEquals(1, store.records().single().revision)
    }
    @Test fun remoteDeletionCannotResurrectPendingHabitOrActivity() = isolated { store, _ ->
        val h = Habit(name = "QA Delete", unit = "times"); store.save(h); store.log(h.id, 1.0)
        val pending = store.pending()
        val deletion = Record("habit", h.id, 1, true, JSONObject()).wire()
        store.recordConflicts(JSONArray().put(deletion))
        assertTrue(store.habits().isEmpty()); assertTrue(store.activities().isEmpty())
        assertFalse(store.records().any { it.dirty && !it.deleted })
    }
    @Test fun archivesArePartitionedAndExportHasNoCredentials() = isolated { store, _ ->
        val h = Habit(name = "Private QA", unit = "times"); store.save(h)
        isolated { other, _ -> assertTrue(other.habits().isEmpty()) }
        val json = store.export().toString()
        assertTrue(json.contains("Private QA")); assertFalse(json.contains("refresh_token")); assertFalse(json.contains("access_token"))
        store.remove(h.id)
        assertTrue(store.habits().isEmpty()); assertFalse(store.export().toString().contains("Private QA"))
    }
    @Test fun legacyArchiveUpgradePreservesProgressAndUsesParentIndex() {
        for(version in listOf(1, 2)) {
            val id = UUID.randomUUID().toString(); val name = "makeet-$id.db"
            val h = Habit(name = "QA migration", unit = "times")
            val a = Activity(habitId = h.id, amount = 1.0)
            try {
                context.openOrCreateDatabase(name, 0, null).use { db ->
                    db.execSQL("CREATE TABLE records(kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted INTEGER NOT NULL,data TEXT NOT NULL,dirty INTEGER NOT NULL,sequence INTEGER NOT NULL,PRIMARY KEY(kind,id))")
                    db.execSQL("CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
                    db.execSQL("CREATE TABLE conflicts(kind TEXT NOT NULL,id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(kind,id))")
                    db.execSQL("CREATE INDEX records_dirty ON records(dirty,kind,sequence)")
                    if(version == 2) db.execSQL("CREATE INDEX records_activity_parent ON records(kind) WHERE kind='activity' AND deleted=0")
                    db.execSQL("INSERT INTO records VALUES('habit',?,0,0,?,1,1)", arrayOf(h.id, h.data().toString()))
                    db.execSQL("INSERT INTO records VALUES('activity',?,0,0,?,1,2)", arrayOf(a.id, a.data().toString()))
                    db.version = version
                }
                HabitStore(context, id).use { upgraded ->
                    assertEquals(listOf(h), upgraded.habits()); assertEquals(listOf(a), upgraded.activities())
                    assertEquals(3, upgraded.readableDatabase.version)
                    upgraded.readableDatabase.rawQuery("EXPLAIN QUERY PLAN SELECT * FROM records WHERE kind='activity' AND deleted=0 AND parent_id=?", arrayOf(h.id)).use { cursor ->
                        assertTrue(cursor.moveToFirst()); assertTrue(cursor.getString(3).contains("records_activity_parent"))
                    }
                    upgraded.remove(h.id)
                    assertTrue(upgraded.activities().isEmpty())
                }
            } finally {
                context.deleteDatabase(name)
            }
        }
    }
    @Test fun clampedReductionPreservesSurvivingRegistrationTimestamps() = isolated { store, _ ->
        val now = Instant.now()
        val h = Habit(name = "QA timestamps", unit = "times", createdAt = now.minusSeconds(86400))
        store.save(h)
        val day = h.date(now)
        val older = Activity(habitId = h.id, amount = 1.0, timestamp = day.atTime(1, 0).atZone(ZoneId.of(h.zone)).toInstant())
        val newer = older.copy(id = UUID.randomUUID().toString(), timestamp = older.timestamp.plusSeconds(60))
        store.importActivity(older); store.importActivity(newer)
        store.log(h.id, -1.0, now = now)
        assertEquals(listOf(older), store.activities())
        assertTrue(store.records().any { it.id == newer.id && it.deleted })
    }
}
