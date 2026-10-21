package org.turinglabs.makeet

import androidx.exifinterface.media.ExifInterface

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.time.*

data class ScreenState(val habits: List<Habit> = emptyList(), val activities: List<Activity> = emptyList(),
                       val user: User? = null, val profile: JSONObject = JSONObject(), val syncing: Boolean = false,
                       val error: Boolean = false, val synced: Boolean = false, val conflicts: List<Record> = emptyList(),
                       val passwordEnabled: Boolean = false,
                       val demo: Boolean = false,
                       val demoIds: Set<String> = emptySet(),
                       val errorKey: String = "Your progress is retained. Check your connection or reopen this screen and try again.")

class MakeetModel(app: Application, injectedAPI: AccountAPI?) : AndroidViewModel(app) {
    constructor(app: Application) : this(app, null)
    private val context get() = getApplication<Application>()
    private val encryptedStorage = EncryptedSession(app).also { storage ->
        val p = app.getSharedPreferences("makeet", Context.MODE_PRIVATE)
        p.getString("pending_deleted_account", null)?.let { id ->
            runCatching {
                storage.save(null)
                val name = "makeet-${java.util.UUID.fromString(id)}.db"
                check(app.deleteDatabase(name) || !app.getDatabasePath(name).exists())
                app.deleteSharedPreferences("makeet.calendar.$id")
                p.edit().remove("pending_deleted_account").commit()
            }
        }
    }
    private val sessionStorage = object : SessionStorage {
        override fun load(): JSONObject? = if(app.getSharedPreferences("makeet", Context.MODE_PRIVATE).contains("pending_deleted_account")) null else encryptedStorage.load()
        override fun save(value: JSONObject?) = encryptedStorage.save(value)
    }
    private val api = injectedAPI ?: AccountAPI(sessionStorage)
    private var store = HabitStore(app, api.user()?.id ?: "local")
    private val operation = Mutex()
    private val authentication = Mutex()
    @Volatile private var closed = false
    private val state = MutableStateFlow(ScreenState())
    val screen = state.asStateFlow()
    init {
        updateScope(); reload(api.sessionLoadFailed)
        viewModelScope.launch { runCatching { api.passwordEnabled() }.onSuccess { state.value = state.value.copy(passwordEnabled = it) } }
        if (api.user() != null) synchronize()
    }
    private fun updateScope() {
        context.getSharedPreferences("makeet", Context.MODE_PRIVATE).edit().putString("scope", store.scope).commit()
        MakeetWidget.refresh(context)
        ReminderReceiver.schedule(context)
    }
    private fun reload(error: Boolean = false) {
        if(closed) return
        state.value = state.value.copy(habits = store.habits(), activities = store.activities(), user = api.user(),
            profile = JSONObject(store.meta("profile") ?: "{}"), error = error, conflicts = store.conflicts(), synced = state.value.synced && !store.hasPendingChanges())
        val demoIds = store.demoIDs()
        state.value = state.value.copy(demo = demoIds.isNotEmpty(), demoIds = demoIds)
        MakeetWidget.refresh(context)
    }
    fun refresh() { reload(api.sessionLoadFailed); if (api.user() != null) synchronize() }
    fun dismissError() { state.value = state.value.copy(error = false, errorKey = "Your progress is retained. Check your connection or reopen this screen and try again.") }
    private fun mutate(action: (HabitStore) -> Unit) { viewModelScope.launch {
        operation.withLock { withContext(Dispatchers.IO) { runCatching { action(store) }.onFailure { e ->
            state.value = state.value.copy(error = true, errorKey = when(e.message) {
                "stale_habit" -> "This habit changed. Close and reopen the editor before saving."
                "stale_day" -> "Your progress has changed. Reopen the day to use the latest values."
                else -> "Your progress is retained. Check your connection or reopen this screen and try again."
            })
        } }; reload(state.value.error) }
        if (api.user() != null) syncNow()
    } }
    fun save(habit: Habit, original: Habit? = null) = mutate { db ->
        if(original != null) check(db.habits().firstOrNull { it.id == original.id } == original) { "stale_habit" }
        require(db.activities().filter { it.habitId == habit.id }.all { habit.date(it.timestamp) >= habit.date(habit.createdAt) })
        db.save(habit)
    }
    fun log(id: String, delta: Double) = mutate { it.log(id, delta) }
    fun correct(id: String, day: LocalDate, original: Progress, value: Double) = mutate { it.correct(id, day, original, value) }
    fun archive(habit: Habit) = save(habit.copy(archived = !habit.archived))
    fun exploreDemo() = mutate { DemoData.seed(it, context) }
    fun clearDemo() = mutate { check(it.scope == "local"); it.clearDemo() }
    suspend fun remove(id: String, cleanupCalendar: Boolean): Boolean = operation.withLock {
        try {
            withContext(Dispatchers.IO) {
                check(store.habits().any { it.id == id })
                if(cleanupCalendar) DeviceCalendarService(context).removeFuture(id)
                store.remove(id)
            }
            reload()
            if(api.user() != null) synchronize()
            true
        } catch(e: CancellationException) { throw e }
        catch(_: Exception) { reload(error = true); false }
    }
    fun undo(id: String) = mutate { it.undo(id) }
    fun resolve(remote: Record, local: Boolean) = mutate { it.resolve(remote, local) }
    fun synchronize() { viewModelScope.launch { syncNow() } }
    suspend fun createCalendarEvents(proposals: List<Proposal>, selection: CalendarSelection, expectedScope: String): Int = operation.withLock {
        withContext(Dispatchers.IO) {
            check(store.scope == expectedScope && selectedCalendars(context, expectedScope) == selection)
            store.transaction {
                val habits = store.habits(); val activities = store.activities()
                require(proposals.none { it.habit.id in store.demoIDs() })
                require(proposals.all { p -> habits.any { it == p.habit && !it.archived && it.goal == Goal.MINIMUM && it.scheduled(it.date(p.start)) } && !HabitEngine.progress(p.habit, activities, p.habit.date(p.start)).complete })
                DeviceCalendarService(context).create(proposals, selection.ids, selection.destination ?: error("missing_calendar"), habits)
            }
        }
    }
    private suspend fun syncNow() = operation.withLock {
        val user = api.user() ?: return@withLock
        val active = store
        state.value = state.value.copy(syncing = true, error = false, synced = false)
        var drained = false
        try {
            withContext(Dispatchers.IO) {
                var more = true; var pages = 0
                while (more && pages++ < 100) {
                    check(api.user()?.id == user.id && store === active)
                    val request = active.pending()
                    val response = api.authenticated("POST", "/v1/sync", user.id, request)
                    check(api.user()?.id == user.id && store === active)
                    active.apply(response)
                    more = response.getBoolean("has_more") || active.hasPendingChanges()
                    if (active.conflicts().isNotEmpty()) break
                }
                drained = !more
                val profile = api.authenticated("GET", "/v1/me/profile", user.id)
                check(store === active); active.setMeta("profile", profile.toString())
            }
            state.value = state.value.copy(synced = drained && active.conflicts().isEmpty() && !active.hasPendingChanges())
            reload()
        } catch (e: Exception) {
            if (e is APIFailure && e.status == 409 && e.payload.has("conflicts")) active.recordConflicts(e.payload.getJSONArray("conflicts"))
            if (api.user() == null) switchToLocal()
            reload(error = true)
        } finally { state.value = state.value.copy(syncing = false) }
    }
    suspend fun signIn(activity: Context): Boolean {
        if(!authentication.tryLock()) return false
        return try {
            val challenge = api.challenge()
            check(BuildConfig.GOOGLE_SERVER_CLIENT_ID.isNotBlank())
            val option = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_SERVER_CLIENT_ID).setNonce(challenge.getString("nonce")).build()
            val result = CredentialManager.create(activity).getCredential(activity, GetCredentialRequest.Builder().addCredentialOption(option).build())
            val token = GoogleIdTokenCredential.createFrom(result.credential.data)
            operation.withLock {
                val user = api.exchange(challenge, token.idToken)
                store.close(); store = HabitStore(context, user.id)
                updateScope(); reload()
            }
            syncNow()
            true
        } catch (_: GetCredentialCancellationException) { false }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { state.value = state.value.copy(error = true); false }
        finally { authentication.unlock() }
    }
    suspend fun passwordLogin(identifier: String, password: String) {
        check(authentication.tryLock())
        try {
            operation.withLock {
                check(api.user() == null)
                val user = api.passwordLogin(identifier, password)
                val next = try { HabitStore(context, user.id) }
                    catch(e: Exception) { runCatching { api.logout() }; throw e }
                store.close(); store = next; updateScope(); reload()
            }
            syncNow()
        } finally { authentication.unlock() }
    }
    suspend fun requestPassword(username: String, email: String, password: String, userID: String?): String {
        check(api.user()?.id == userID)
        return api.requestPassword(username, email, password, context.resources.configuration.locales[0].language, userID)
    }
    suspend fun recoverPassword(identifier: String) = api.recoverPassword(identifier, context.resources.configuration.locales[0].language)
    suspend fun confirmPassword(id: String, code: String, password: String, userID: String?) {
        check(api.user()?.id == userID)
        api.confirmPassword(id, code, password, userID)
    }
    suspend fun passwordStatus(userID: String) = api.passwordStatus(userID)
    private fun switchToLocal() {
        store.close(); store = HabitStore(context, "local"); state.value = ScreenState(passwordEnabled = state.value.passwordEnabled); updateScope()
    }
    fun logout() { viewModelScope.launch { operation.withLock { api.logout(); switchToLocal(); reload() } } }
    suspend fun deleteAccount(): Boolean = operation.withLock {
        val user = api.user() ?: return@withLock false
        try {
            api.authenticated("DELETE", "/v1/me", user.id, JSONObject().put("confirmation", "DELETE"))
        } catch (_: Exception) { reload(error = true); return@withLock false }
        val p = context.getSharedPreferences("makeet", Context.MODE_PRIVATE)
        p.edit().putString("pending_deleted_account", user.id).commit()
        val sessionCleared = runCatching { api.clearAfterDeletion() }.isSuccess
        store.close(); store = HabitStore(context, "local"); state.value = ScreenState(passwordEnabled = state.value.passwordEnabled); updateScope(); reload()
        val name = "makeet-${user.id}.db"
        val archiveCleared = context.deleteDatabase(name) || !context.getDatabasePath(name).exists()
        context.deleteSharedPreferences("makeet.calendar.${user.id}")
        if(sessionCleared && archiveCleared) p.edit().remove("pending_deleted_account").commit()
        else {
            p.edit().putString("pending_deleted_account", user.id).commit()
            state.value = state.value.copy(error = true, errorKey = "Your account was deleted from the service. Restart the app to finish clearing this device’s archive.")
        }
        true
    }
    suspend fun saveProfile(name: String, image: String?, revision: Long): Boolean = operation.withLock {
        val user = api.user() ?: return@withLock false
        try {
            val value = JSONObject().put("name", name).put("image", image ?: JSONObject.NULL).put("revision", revision)
            val result = api.authenticated("PUT", "/v1/me/profile", user.id, value)
            store.setMeta("profile", result.toString()); reload(); true
        } catch (e: Exception) {
            if(e is APIFailure && e.status == 409) {
                runCatching { api.authenticated("GET", "/v1/me/profile", user.id) }.onSuccess { store.setMeta("profile", it.toString()) }
                state.value = state.value.copy(errorKey = "Your profile changed on another device. Reopen the editor to load the latest version.")
            }
            reload(error = true); false
        }
    }
    fun localHasData() = HabitStore(context, "local").use { it.habits().isNotEmpty() }
    fun importLocal() = mutate { destination ->
        check(destination.scope != "local")
        HabitStore(context, "local").use { local ->
            destination.importFromLocal(local)
        }
    }
    suspend fun export(expectedScope: String): String = operation.withLock {
        check(store.scope == expectedScope)
        withContext(Dispatchers.IO) {
            val data = store.export()
            api.user()?.let { user -> runCatching { api.authenticated("GET", "/v1/me/export", user.id) }.getOrNull()?.let { data.put("server", it) } }
            data.toString(2)
        }
    }
    suspend fun normalizePhoto(uri: android.net.Uri): String = withContext(Dispatchers.IO) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1; while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 640) sample *= 2
        val decoded = context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: error("invalid_image")
        val orientation = runCatching { context.contentResolver.openInputStream(uri)!!.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) } }.getOrDefault(1)
        val transform = android.graphics.Matrix().apply {
            when(orientation) {
                2 -> setScale(-1f, 1f)
                3 -> setRotate(180f)
                4 -> setScale(1f, -1f)
                5 -> { setRotate(90f); postScale(-1f, 1f) }
                6 -> setRotate(90f)
                7 -> { setRotate(-90f); postScale(-1f, 1f) }
                8 -> setRotate(-90f)
            }
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
        val side = minOf(upright.width, upright.height)
        val cropped = Bitmap.createBitmap(upright, (upright.width - side) / 2, (upright.height - side) / 2, side, side)
        val normalized = Bitmap.createScaledBitmap(cropped, 320, 320, true)
        val stream = ByteArrayOutputStream(); normalized.compress(Bitmap.CompressFormat.JPEG, 85, stream)
        require(stream.size() <= 128 * 1024)
        Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
    override fun onCleared() {
        closed = true
        super.onCleared()
        store.close()
    }
}
