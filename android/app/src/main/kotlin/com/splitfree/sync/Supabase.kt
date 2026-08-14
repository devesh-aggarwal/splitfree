package com.splitfree.sync

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.splitfree.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Where the backend lives, and whether there is one at all.
 *
 * Both values come from build config so the open-source repo carries nobody's
 * project keys. When they are blank, [isConfigured] is false and the whole sync
 * feature stays off: the app is exactly the local-only app it was before, which
 * is the point of making accounts optional.
 */
object SupabaseConfig {
    /**
     * The project's base URL. The scheme is optional in the config file and
     * added here when missing, so the same value works in either platform's
     * config format.
     */
    val url: String
        get() {
            val raw = BuildConfig.SUPABASE_URL.trim().trimEnd('/')
            if (raw.isBlank() || raw == "https:" || raw == "http:") return ""
            if (raw.startsWith("http", ignoreCase = true)) return raw
            // Loopback means a stack running on this machine, which serves plain
            // HTTP. On Android the emulator reaches the host at 10.0.2.2.
            val isLoopback = raw.startsWith("127.0.0.1") ||
                raw.startsWith("localhost") ||
                raw.startsWith("10.0.2.2") ||
                raw.startsWith("[::1]")
            return (if (isLoopback) "http://" else "https://") + raw
        }

    val anonKey: String get() = BuildConfig.SUPABASE_ANON_KEY.trim()

    val isConfigured: Boolean get() = url.isNotBlank() && anonKey.isNotBlank()

}

class SupabaseException(message: String) : Exception(message)

data class Session(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMillis: Long,
    val userId: String,
) {
    /** Treated as expired a minute early, so a request never leaves with a token that dies in flight. */
    val isExpired: Boolean get() = System.currentTimeMillis() >= expiresAtMillis - 60_000
}

/**
 * A small, dependency-free Supabase client: GoTrue for auth, PostgREST for data,
 * and RPC for the sync and invite functions.
 *
 * Only the endpoints this app actually uses are implemented. That is a few
 * hundred lines against pulling in an SDK, and it keeps the dependency list
 * short enough to read.
 */
class SupabaseClient(context: Context) {

    private val appContext = context.applicationContext
    private val refreshLock = Mutex()

    /**
     * A refresh token is a long-lived credential, so it goes in encrypted
     * preferences rather than ordinary ones.
     */
    private val prefs: SharedPreferences by lazy {
        runCatching {
            EncryptedSharedPreferences.create(
                appContext,
                "splitfree.session",
                MasterKey.Builder(appContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }.getOrElse {
            // Some devices have a broken keystore. Signing out is better than
            // refusing to launch.
            appContext.getSharedPreferences("splitfree.session", Context.MODE_PRIVATE)
        }
    }

    @Volatile private var current: Session? = null

    init {
        current = readSession()
    }

    val isSignedIn: Boolean get() = current != null
    val userId: String? get() = current?.userId

    // MARK: - Identity

    /**
     * Gets an identity without asking anybody for anything.
     *
     * Sharing needs row level security to have something to key on, and that is
     * all it needs. No email, no password, no screen.
     */
    suspend fun signInAnonymously(): Session {
        current?.let { if (!it.isExpired) return it }
        return storeSession(JSONObject(request("/auth/v1/signup", "POST", JSONObject(), authorized = false)))
    }

    fun signOut() {
        current = null
        prefs.edit().clear().apply()
    }

    private fun storeSession(payload: JSONObject): Session {
        val access = payload.optString("access_token")
        val refresh = payload.optString("refresh_token")
        if (access.isBlank() || refresh.isBlank()) throw SupabaseException("The server sent an unusable session.")
        val session = Session(
            accessToken = access,
            refreshToken = refresh,
            expiresAtMillis = System.currentTimeMillis() + payload.optLong("expires_in", 3600) * 1000,
            userId = payload.optJSONObject("user")?.optString("id").orEmpty(),
        )
        writeSession(session)
        return session
    }

    private fun writeSession(session: Session) {
        current = session
        prefs.edit()
            .putString("access", session.accessToken)
            .putString("refresh", session.refreshToken)
            .putLong("expires", session.expiresAtMillis)
            .putString("user", session.userId)
            .apply()
    }

    private fun readSession(): Session? {
        val access = prefs.getString("access", null) ?: return null
        val refresh = prefs.getString("refresh", null) ?: return null
        return Session(
            accessToken = access,
            refreshToken = refresh,
            expiresAtMillis = prefs.getLong("expires", 0),
            userId = prefs.getString("user", "").orEmpty(),
        )
    }

    private suspend fun validSession(): Session {
        val existing = current ?: return signInAnonymously()
        if (!existing.isExpired) return existing

        return refreshLock.withLock {
            val latest = current ?: return@withLock signInAnonymously()
            if (!latest.isExpired) return@withLock latest
            try {
                storeSession(
                    JSONObject(
                        request(
                            "/auth/v1/token?grant_type=refresh_token",
                            "POST",
                            JSONObject().put("refresh_token", latest.refreshToken),
                            authorized = false,
                        )
                    )
                )
            } catch (error: Exception) {
                // A dead refresh token is not worth surfacing when the identity
                // is disposable. Take a fresh one.
                signOut()
                signInAnonymously()
            }
        }
    }

    // MARK: - Data

    suspend fun rpc(name: String, arguments: JSONObject = JSONObject()): String =
        request("/rest/v1/rpc/$name", "POST", arguments, authorized = true)

    suspend fun upsert(table: String, rows: JSONArray, onConflict: String) {
        if (rows.length() == 0) return
        request(
            path = "/rest/v1/$table?on_conflict=$onConflict",
            method = "POST",
            body = rows,
            authorized = true,
            extraHeaders = mapOf("Prefer" to "resolution=merge-duplicates,return=minimal"),
        )
    }

    // MARK: - Transport

    private suspend fun request(
        path: String,
        method: String,
        body: Any? = null,
        authorized: Boolean,
        extraHeaders: Map<String, String> = emptyMap(),
    ): String {
        if (!SupabaseConfig.isConfigured) throw SupabaseException("This build isn't set up for syncing.")

        // Authorization carries a user's session and nothing else. The older
        // anon key was a JWT and could stand in for one; the newer publishable
        // keys are not JWTs, and a server asked to parse one as a token rejects
        // the request. The apikey header identifies the project either way.
        val token = if (authorized) validSession().accessToken else null

        return withContext(Dispatchers.IO) {
            val connection = (URL(SupabaseConfig.url + path).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 15_000
                readTimeout = 30_000
                setRequestProperty("apikey", SupabaseConfig.anonKey)
                if (token != null) setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "application/json")
                extraHeaders.forEach { (key, value) -> setRequestProperty(key, value) }
                if (body != null) {
                    doOutput = true
                    outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                }
            }

            try {
                val code = connection.responseCode
                val stream = if (code in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
                if (code !in 200..299) throw SupabaseException(errorMessage(text, code))
                text
            } finally {
                connection.disconnect()
            }
        }
    }

    /** Supabase reports failures in a few shapes, depending on which component answered. */
    private fun errorMessage(body: String, code: Int): String {
        val fallback = "The server returned an error ($code)."
        return runCatching {
            val json = JSONObject(body)
            listOf("msg", "message", "error_description", "error", "hint", "details")
                .firstNotNullOfOrNull { json.optString(it).takeIf { value -> value.isNotBlank() } }
                ?: fallback
        }.getOrDefault(fallback)
    }

    companion object {
        const val SIGNED_OUT = "Sign in to sync."
    }
}
