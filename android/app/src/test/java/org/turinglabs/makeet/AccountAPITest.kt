package org.turinglabs.makeet

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.util.UUID

class AccountAPITest {
    private class MemoryStorage(var value: JSONObject?) : SessionStorage {
        override fun load() = value
        override fun save(value: JSONObject?) { this.value = value }
    }
    private val id = UUID.randomUUID().toString()
    private fun tokens(expiry: Long = Instant.now().epochSecond - 1) = JSONObject()
        .put("user", JSONObject().put("id", id).put("email", "qa@example.invalid"))
        .put("access_token", "fixture-access").put("refresh_token", "fixture-refresh")
        .put("expires_in", 900).put("expires_at_android", expiry)
    @Test fun concurrentCallsRotateRefreshOnceAndUseSavedToken() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            val next = tokens().put("access_token", "fixture-next").put("refresh_token", "fixture-next-refresh")
            server.enqueue(MockResponse().setBody(next.toString()))
            repeat(2) { server.enqueue(MockResponse().setBody("{\"name\":\"QA\",\"revision\":0}")) }
            val storage = MemoryStorage(tokens())
            val api = AccountAPI(storage, server.url("/").toString().trimEnd('/'))
            listOf(async { api.authenticated("GET", "/v1/me/profile", id) }, async { api.authenticated("GET", "/v1/me/profile", id) }).awaitAll()
            assertEquals("/v1/auth/refresh", server.takeRequest().path)
            repeat(2) { assertEquals("Bearer fixture-next", server.takeRequest().getHeader("Authorization")) }
            assertEquals(3, server.requestCount)
            assertEquals("fixture-next-refresh", storage.value!!.getString("refresh_token"))
        } finally { server.shutdown() }
    }
    @Test fun redirectsNeverForwardSessionToOtherDestination() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/unexpected"))
            val api = AccountAPI(MemoryStorage(tokens(Instant.now().epochSecond + 900)), server.url("/").toString().trimEnd('/'))
            assertTrue(runCatching { api.authenticated("GET", "/v1/me", id) }.exceptionOrNull() is APIFailure)
            assertEquals(1, server.requestCount)
        } finally { server.shutdown() }
    }
    @Test fun expectedAccountIsCheckedBeforeRequest() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            val api = AccountAPI(MemoryStorage(tokens()), server.url("/").toString().trimEnd('/'))
            assertTrue(runCatching { api.authenticated("GET", "/v1/me", UUID.randomUUID().toString()) }.isFailure)
            assertEquals(0, server.requestCount)
        } finally { server.shutdown() }
    }
    @Test fun rejectedRefreshClearsPersistedSession() = runBlocking {
        val server = MockWebServer(); server.start()
        try {
            server.enqueue(MockResponse().setResponseCode(401).setBody("{\"error\":\"invalid_session\"}"))
            val storage = MemoryStorage(tokens())
            val api = AccountAPI(storage, server.url("/").toString().trimEnd('/'))
            assertTrue(runCatching { api.authenticated("GET", "/v1/me", id) }.isFailure)
            assertNull(api.user()); assertNull(storage.value)
        } finally { server.shutdown() }
    }
}
