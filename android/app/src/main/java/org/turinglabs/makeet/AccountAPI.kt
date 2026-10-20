package org.turinglabs.makeet

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class User(val id: String, val email: String)
class APIFailure(val status: Int, val payload: JSONObject) : Exception(payload.optString("error", "request_failed"))

interface SessionStorage { fun load(): JSONObject?; fun save(value: JSONObject?); }

class EncryptedSession(context: Context) : SessionStorage {
    private val file = File(context.noBackupFilesDir, "makeet-session")
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("makeet.session.v1", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("makeet.session.v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized override fun load(): JSONObject? {
        if (!file.exists()) return null
        val bytes = file.readBytes()
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    @Synchronized override fun save(value: JSONObject?) {
        if (value == null) { check(!file.exists() || file.delete()); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val temp = File(file.parentFile, "makeet-session.tmp")
        java.io.FileOutputStream(temp).use { stream ->
            stream.write(cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))); stream.fd.sync()
        }
        check(temp.renameTo(file))
    }
}

class AccountAPI(private val storage: SessionStorage, private val baseURL: String = BuildConfig.API_URL,
                 private val http: OkHttpClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
                     .callTimeout(30, TimeUnit.SECONDS).build()) {
    private val mutex = Mutex()
    var sessionLoadFailed = false
        private set
    @Volatile private var session: JSONObject? = runCatching { storage.load() }.getOrElse { sessionLoadFailed = true; null }
    private var generation = UUID.randomUUID()
    fun user(): User? = session?.getJSONObject("user")?.let { User(UUID.fromString(it.getString("id")).toString(), it.getString("email")) }
    suspend fun appleEnabled() = send("GET", "/v1/config").optBoolean("apple_android_enabled", false)
    suspend fun challenge(provider: String = "google") = send("POST", "/v1/auth/challenges", JSONObject().put("provider", provider))
    suspend fun startApple(challenge: JSONObject, proof: String, language: String) = send("POST", "/v1/auth/apple/start", JSONObject()
        .put("challenge_id", challenge.getString("id")).put("code_challenge", proof).put("language", language))
    suspend fun pollApple(id: String, verifier: String) = send("POST", "/v1/auth/apple/result", JSONObject().put("id", id).put("code_verifier", verifier))
    suspend fun exchange(challenge: JSONObject, token: String, provider: String = "google", code: String = ""): User = mutex.withLock {
        val response = send("POST", "/v1/auth/exchange", JSONObject().put("provider", provider)
            .put("challenge_id", challenge.getString("id")).put("id_token", token).put("authorization_code", code))
        currentCoroutineContext().ensureActive()
        install(response)
        generation = UUID.randomUUID()
        user()!!
    }
    private fun install(response: JSONObject) {
        UUID.fromString(response.getJSONObject("user").getString("id"))
        response.put("expires_at_android", Instant.now().epochSecond + response.getLong("expires_in"))
        storage.save(response); session = response; sessionLoadFailed = false
    }
    suspend fun authenticated(method: String, path: String, expectedUser: String, body: JSONObject? = null): JSONObject = mutex.withLock {
        check(user()?.id == expectedUser) { "signed_out" }
        val epoch = generation
        var current = session ?: error("signed_out")
        suspend fun refresh() {
            val response = send("POST", "/v1/auth/refresh", JSONObject().put("refresh_token", current.getString("refresh_token")))
            check(response.getJSONObject("user").getString("id") == expectedUser && generation == epoch) { "signed_out" }
            install(response); current = response
        }
        try {
            if (current.getLong("expires_at_android") < Instant.now().epochSecond + 30) refresh()
            val result = try { send(method, path, body, current.getString("access_token")) }
            catch (e: APIFailure) { if (e.status != 401) throw e; refresh(); send(method, path, body, current.getString("access_token")) }
            check(generation == epoch && user()?.id == expectedUser) { "signed_out" }
            result
        } catch (e: APIFailure) {
            if (e.status == 401) { storage.save(null); session = null; generation = UUID.randomUUID() }
            throw e
        }
    }
    suspend fun logout() = mutex.withLock {
        val current = session
        if (current != null) runCatching { send("POST", "/v1/auth/logout", token = current.getString("access_token")) }
        storage.save(null); session = null; generation = UUID.randomUUID()
    }
    suspend fun clearAfterDeletion() = mutex.withLock { session = null; generation = UUID.randomUUID(); storage.save(null) }
    private suspend fun send(method: String, path: String, body: JSONObject? = null, token: String? = null): JSONObject = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(baseURL + path).header("Accept", "application/json")
            .header("User-Agent", "MakeetAndroid/1.0").header("Cache-Control", "no-store")
        if (token != null) request.header("Authorization", "Bearer $token")
        if (path == "/v1/sync") request.header("X-Makeet-Sync-Version", "2")
        request.method(method, if (method in listOf("GET", "HEAD")) null else (body ?: JSONObject()).toString().toRequestBody("application/json".toMediaType()))
        http.newCall(request.build()).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            val json = runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
            if (!response.isSuccessful) throw APIFailure(response.code, json)
            if (raw.isNotBlank() && json.length() == 0 && raw.trim() != "{}") error("invalid_response")
            json
        }
    }
}
