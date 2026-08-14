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

    /** Must match the intent filter in the manifest and the Supabase redirect list. */
    const val REDIRECT_URI = "splitfree://auth-callback"
}

class SupabaseException(message: String) : Exception(message)

data class Session(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMillis: Long,
    val userId: String,
    val email: String?,
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
    val email: String? get() = current?.email

    // MARK: - Auth

    /**
     * Starts an email sign-in.
     *
     * One request produces both a link and a six-digit code; which of them the
     * email shows is decided by the project's email template. The stock template
     * shows only the link, so the link is the path that works without
     * configuring anything, and `redirect_to` is what brings that link back
     * into the app instead of to a web page.
     */
    suspend fun sendEmailCode(email: String) {
        // `redirect_to` is a query parameter. GoTrue ignores it in the body, and
        // ignores it silently: the email still arrives, the link still works,
        // and it opens the project's website instead of the app.
        val redirect = URLEncoder.encode(SupabaseConfig.REDIRECT_URI, "UTF-8")
        request(
            path = "/auth/v1/otp?redirect_to=$redirect",
            method = "POST",
            body = JSONObject().put("email", email).put("create_user", true),
            authorized = false,
        )
    }

    suspend fun verifyEmailCode(email: String, code: String): Session {
        val body = JSONObject().put("email", email).put("token", code).put("type", "email")
        return storeSession(JSONObject(request("/auth/v1/verify", "POST", body, authorized = false)))
    }

    /**
     * Which sign-in providers the project actually has switched on.
     *
     * Asked rather than assumed, because a button for a provider nobody
     * configured is a button that fails when tapped. Email is always available.
     */
    suspend fun enabledProviders(): Set<String> = runCatching {
        val external = JSONObject(request("/auth/v1/settings", "GET", authorized = false))
            .optJSONObject("external") ?: return emptySet()
        external.keys().asSequence().filter { external.optBoolean(it) }.toSet()
    }.getOrDefault(emptySet())

    /** The URL to open in a browser for a provider with no native flow. */
    fun oauthUrl(provider: String): String {
        val redirect = URLEncoder.encode(SupabaseConfig.REDIRECT_URI, "UTF-8")
        return "${SupabaseConfig.url}/auth/v1/authorize?provider=$provider&redirect_to=$redirect"
    }

    /** Completes a browser OAuth round trip. Supabase returns tokens in the fragment. */
    fun completeOAuth(callback: String): Session {
        val fragment = callback.substringAfter('#', "")
        if (fragment.isBlank()) throw SupabaseException("Sign-in was cancelled.")

        val values = fragment.split("&").mapNotNull { pair ->
            val parts = pair.split("=", limit = 2)
            if (parts.size == 2) parts[0] to java.net.URLDecoder.decode(parts[1], "UTF-8") else null
        }.toMap()

        val access = values["access_token"]
        val refresh = values["refresh_token"]
        if (access == null || refresh == null) {
            throw SupabaseException(values["error_description"] ?: "Sign-in failed.")
        }
        val expiresIn = values["expires_in"]?.toLongOrNull() ?: 3600
        val session = Session(
            accessToken = access,
            refreshToken = refresh,
            expiresAtMillis = System.currentTimeMillis() + expiresIn * 1000,
            userId = userIdFromJwt(access).orEmpty(),
            email = null,
        )
        writeSession(session)
        return session
    }

    /**
     * Fills in the account's email after a link or browser sign-in. Those flows
     * hand back tokens in a URL fragment and nothing else, so the account row
     * would otherwise read "Signed in" and leave someone with two addresses
     * unable to tell which one they used.
     */
    suspend fun refreshUserDetails() {
        val session = current ?: return
        runCatching {
            val json = JSONObject(request("/auth/v1/user", "GET", authorized = true))
            val email = json.optString("email").takeIf { it.isNotBlank() } ?: return
            writeSession(session.copy(email = email))
        }
    }

    fun signOut() {
        current = null
        prefs.edit().clear().apply()
    }

    private fun storeSession(payload: JSONObject): Session {
        val access = payload.optString("access_token")
        val refresh = payload.optString("refresh_token")
        if (access.isBlank() || refresh.isBlank()) throw SupabaseException("The server sent an unusable sign-in.")

        val user = payload.optJSONObject("user")
        val session = Session(
            accessToken = access,
            refreshToken = refresh,
            expiresAtMillis = System.currentTimeMillis() + payload.optLong("expires_in", 3600) * 1000,
            userId = user?.optString("id").takeUnless { it.isNullOrBlank() } ?: userIdFromJwt(access).orEmpty(),
            email = user?.optString("email").takeUnless { it.isNullOrBlank() },
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
            .putString("email", session.email)
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
            email = prefs.getString("email", null),
        )
    }

    /**
     * Reads `sub` out of the JWT payload, for the case where the token endpoint
     * does not echo the user back. Nothing security-sensitive rests on it; the
     * server decides who you are for itself.
     */
    private fun userIdFromJwt(token: String): String? = runCatching {
        val payload = token.split(".").getOrNull(1) ?: return null
        val decoded = android.util.Base64.decode(
            payload,
            android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP,
        )
        JSONObject(String(decoded, Charsets.UTF_8)).optString("sub").takeIf { it.isNotBlank() }
    }.getOrNull()

    private suspend fun validSession(): Session {
        val existing = current ?: throw SupabaseException(SIGNED_OUT)
        if (!existing.isExpired) return existing

        // Serialised, so ten parallel requests do not each spend the refresh
        // token and invalidate the other nine.
        return refreshLock.withLock {
            val latest = current ?: throw SupabaseException(SIGNED_OUT)
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
                // A refresh token that no longer works means the session is over.
                signOut()
                throw SupabaseException(SIGNED_OUT)
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
