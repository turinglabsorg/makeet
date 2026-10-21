package org.turinglabs.makeet

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import java.io.File
import java.util.UUID

class PasswordFixtureState : ViewModel() {
    val id = UUID.randomUUID().toString()
    var credentials = JSONObject()
    var pending = JSONObject()
    var session: JSONObject? = null
}
class PasswordTestActivity : AppCompatActivity() {
    private val fixture: PasswordFixtureState by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(BuildConfig.DEBUG)
        check(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
        check(!File(noBackupFilesDir, "makeet-session").exists())
        getSharedPreferences("makeet", MODE_PRIVATE).edit().putBoolean("onboarding.android.v1", true).commit()
        val state = fixture
        if(intent.getBooleanExtra("password_account_fixture", false) && state.session == null) {
            state.session = JSONObject().put("user", JSONObject().put("id", state.id).put("email", "provider@example.invalid"))
                .put("access_token", "password-ui-access").put("refresh_token", "password-ui-refresh").put("expires_in", 3600)
                .put("expires_at_android", java.time.Instant.now().epochSecond + 3600)
        }
        val storage = object : SessionStorage {
            override fun load() = state.session
            override fun save(value: JSONObject?) { state.session = value }
        }
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); check(request.url.host == "password-fixture.makeet.invalid")
            val buffer = okio.Buffer(); request.body?.writeTo(buffer)
            val body = runCatching { JSONObject(buffer.readUtf8()) }.getOrElse { JSONObject() }
            var code = 200
            val result: JSONObject = synchronized(state) {
                when(request.url.encodedPath) {
                    "/v1/config" -> JSONObject().put("password_enabled", true)
                    "/v1/auth/password/register" -> { state.pending = body; code = 202; JSONObject().put("request_id", "password-ui-request") }
                    "/v1/auth/password/recover" -> { code = 202; JSONObject().put("request_id", "password-ui-recovery") }
                    "/v1/auth/password/confirm", "/v1/me/password/confirm" -> {
                        if(body.optString("code") != "12345678") { code = 400; JSONObject().put("error", "invalid_verification") }
                        else {
                            if(body.optString("request_id") == "password-ui-recovery") state.credentials.put("password", body.getString("password"))
                            else state.credentials = state.pending
                            JSONObject().put("confirmed", true)
                        }
                    }
                    "/v1/me/password" -> if(request.method == "POST") { state.pending = body; code = 202; JSONObject().put("request_id", "password-ui-request") }
                        else JSONObject().put("enabled", state.credentials.length() > 0).put("username", state.credentials.optString("username"))
                    "/v1/auth/password/login" -> {
                        if(state.credentials.length() > 0 && body.optString("identifier") == state.credentials.optString("username") && body.optString("password") == state.credentials.optString("password")) {
                            JSONObject().put("user", JSONObject().put("id", state.id).put("email", state.credentials.getString("email")))
                                .put("access_token", "password-ui-access").put("refresh_token", "password-ui-refresh").put("expires_in", 3600)
                        } else { code = 401; JSONObject().put("error", "invalid_credentials") }
                    }
                    "/v1/sync" -> JSONObject("{\"cursor\":0,\"has_more\":false,\"changes\":[],\"applied\":[]}")
                    "/v1/me/profile" -> JSONObject().put("name", "Password QA").put("revision", 0)
                    "/v1/auth/logout" -> { code = 204; JSONObject() }
                    else -> error("Unexpected password fixture route")
                }
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("fixture").body(result.toString().toResponseBody("application/json".toMediaType())).build()
        }.build()
        val api = AccountAPI(storage, "https://password-fixture.makeet.invalid", client)
        val model = ViewModelProvider(this, object : ViewModelProvider.Factory {
            override fun <T: ViewModel> create(modelClass: Class<T>): T {
                @Suppress("UNCHECKED_CAST") return MakeetModel(application, api) as T
            }
        })[MakeetModel::class.java]
        setContent { MakeetApp(model) }
    }
    override fun onDestroy() {
        super.onDestroy()
        if(isFinishing) { deleteDatabase("makeet-${fixture.id}.db"); getSharedPreferences("makeet", MODE_PRIVATE).edit().putString("scope", "local").commit() }
    }
}
