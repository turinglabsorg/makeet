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
import java.time.Instant
import java.util.UUID

class ProfileFixtureState : ViewModel() {
    val id = UUID.randomUUID().toString()
    @Volatile var profile = JSONObject().put("name", "QA Profile").put("revision", 0)
    @Volatile var conflict = false
}

class ProfileTestActivity : AppCompatActivity() {
    private val fixtureState: ProfileFixtureState by viewModels()
    val fixtureId get() = fixtureState.id
    var profile: JSONObject
        get() = fixtureState.profile
        set(value) { fixtureState.profile = value }
    var conflict: Boolean
        get() = fixtureState.conflict
        set(value) { fixtureState.conflict = value }
    lateinit var model: MakeetModel
        private set
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val target = applicationContext
        check(BuildConfig.DEBUG)
        check(android.os.Build.FINGERPRINT.contains("generic") || android.os.Build.MODEL.contains("sdk_gphone"))
        check(!File(target.noBackupFilesDir, "makeet-session").exists())
        target.getSharedPreferences("makeet", MODE_PRIVATE).edit().putBoolean("onboarding.android.v1", true).commit()
        val fixture = fixtureState
        val tokens = JSONObject().put("user", JSONObject().put("id", fixtureId).put("email", "qa@example.invalid"))
            .put("access_token", "fixture-access").put("refresh_token", "fixture-refresh").put("expires_at_android", Instant.now().epochSecond + 900).put("expires_in", 900)
        val storage = object : SessionStorage { override fun load() = tokens; override fun save(value: JSONObject?) = Unit }
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.host == "makeet.invalid")
            var code = 200
            val body = when(request.url.encodedPath) {
                "/v1/config" -> "{\"apple_android_enabled\":false}"
                "/v1/sync" -> "{\"cursor\":0,\"has_more\":false,\"changes\":[],\"applied\":[]}"
                "/v1/me/profile" -> {
                    if(request.method == "PUT") {
                        val buffer = okio.Buffer(); request.body!!.writeTo(buffer)
                        val draft = JSONObject(buffer.readUtf8())
                        if(fixture.conflict) { code = 409; fixture.profile = JSONObject().put("name", "Remote QA").put("revision", 2); "{\"error\":\"revision_conflict\"}" }
                        else { draft.put("revision", draft.getLong("revision") + 1); fixture.profile = draft; fixture.profile.toString() }
                    } else fixture.profile.toString()
                }
                else -> error("Unexpected fixture route")
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("fixture").body(body.toResponseBody("application/json".toMediaType())).build()
        }.build()
        val api = AccountAPI(storage, "https://makeet.invalid", client)
        model = ViewModelProvider(this, object : ViewModelProvider.Factory { override fun <T: ViewModel> create(modelClass: Class<T>): T {
            @Suppress("UNCHECKED_CAST") return MakeetModel(target.applicationContext as android.app.Application, api) as T
        } })[MakeetModel::class.java]
        setContent { MakeetApp(model) }
    }
    override fun onDestroy() {
        super.onDestroy()
        if(isFinishing) {
            val target = applicationContext
            target.deleteDatabase("makeet-$fixtureId.db")
            target.getSharedPreferences("makeet", MODE_PRIVATE).edit().putString("scope", "local").commit()
        }
    }
}
