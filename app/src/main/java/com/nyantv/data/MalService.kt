package com.nyantv.data

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import java.security.SecureRandom
import android.util.Base64
import com.nyantv.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import androidx.core.net.toUri
import androidx.core.content.edit

private const val MAL_API  = "https://api.myanimelist.net/v2"
private const val MAL_AUTH = "https://myanimelist.net/v1/oauth2"
private const val MAL_PREFS = "mal_prefs"

class MalService(context: Context) : MediaService {

    override val serviceType = ServiceType.MAL

    private val http  = OkHttpClient()
    private val json  = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val prefs = context.getSharedPreferences(MAL_PREFS, Context.MODE_PRIVATE)

    private var accessToken:  String? = prefs.getString("access_token",  null)
    private var refreshToken: String? = prefs.getString("refresh_token", null)

    private val _isLoggedIn      = MutableStateFlow(accessToken != null)
    private val _profile         = MutableStateFlow<Profile?>(null)
    private val _animeList       = MutableStateFlow<List<TrackedMedia>>(emptyList())
    private val _currentMedia    = MutableStateFlow<TrackedMedia?>(null)
    private val _trending        = MutableStateFlow<List<Media>>(emptyList())
    private val _popular         = MutableStateFlow<List<Media>>(emptyList())
    private val _upcoming        = MutableStateFlow<List<Media>>(emptyList())
    private val _recentlyUpdated = MutableStateFlow<List<Media>>(emptyList())

    override val isLoggedIn:      StateFlow<Boolean>            = _isLoggedIn.asStateFlow()
    override val profile:         StateFlow<Profile?>           = _profile.asStateFlow()
    override val animeList:       StateFlow<List<TrackedMedia>> = _animeList.asStateFlow()
    override val currentMedia:    StateFlow<TrackedMedia?>      = _currentMedia.asStateFlow()
    override val trending:        StateFlow<List<Media>>        = _trending.asStateFlow()
    override val popular:         StateFlow<List<Media>>        = _popular.asStateFlow()
    override val upcoming:        StateFlow<List<Media>>        = _upcoming.asStateFlow()
    override val recentlyUpdated: StateFlow<List<Media>>        = _recentlyUpdated.asStateFlow()

    // ── Auth ───────────────────────────────────────────────────────────────────

    override suspend fun login(context: Context) {
        val clientId = BuildConfig.MAL_CLIENT_ID

        val bytes = ByteArray(96).also { SecureRandom().nextBytes(it) }
        val verifier = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

        prefs.edit { putString("code_verifier", verifier) }

        val url = "$MAL_AUTH/authorize" +
                "?response_type=code" +
                "&client_id=$clientId" +
                "&code_challenge=$verifier" +
                "&code_challenge_method=plain"

        CustomTabsIntent.Builder().build().launchUrl(context, url.toUri())
    }

    suspend fun handleAuthCallback(code: String) = withContext(Dispatchers.IO) {
        val verifier = prefs.getString("code_verifier", null)
        android.util.Log.d("MalService", "handleAuthCallback: code=$code, verifier=${verifier?.take(10)}...")
        if (verifier == null) {
            android.util.Log.e("MalService", "code_verifier is null!")
            return@withContext
        }

        val body = "grant_type=authorization_code" +
                "&client_id=${BuildConfig.MAL_CLIENT_ID}" +
                "&client_secret=${BuildConfig.MAL_CLIENT_SECRET}" +
                "&code=$code" +
                "&code_verifier=$verifier"

        val tokens = postForm("$MAL_AUTH/token", body) ?: return@withContext

        prefs.edit { remove("code_verifier") }

        saveTokens(
            tokens["access_token"]!!.jsonPrimitive.content,
            tokens["refresh_token"]?.jsonPrimitive?.contentOrNull
        )
        fetchUserProfile()
        refreshUserLists()
    }

    private suspend fun refreshAccessToken() = withContext(Dispatchers.IO) {
        val rt = refreshToken ?: return@withContext
        val body = "grant_type=refresh_token" +
                "&client_id=${BuildConfig.MAL_CLIENT_ID}" +
                "&client_secret=${BuildConfig.MAL_CLIENT_SECRET}" +
                "&refresh_token=$rt"
        val tokens = postForm("$MAL_AUTH/token", body) ?: return@withContext
        saveTokens(
            tokens["access_token"]!!.jsonPrimitive.content,
            tokens["refresh_token"]?.jsonPrimitive?.contentOrNull ?: rt
        )
    }

    private fun saveTokens(access: String, refresh: String?) {
        accessToken  = access
        refreshToken = refresh
        prefs.edit {
            putString("access_token", access)
                .apply { refresh?.let { putString("refresh_token", it) } }
        }
        _isLoggedIn.value = true
    }

    override suspend fun logout() {
        accessToken  = null
        refreshToken = null
        prefs.edit { remove("access_token").remove("refresh_token") }
        _isLoggedIn.value = false
        _profile.value    = null
        _animeList.value  = emptyList()
    }

    override suspend fun autoLogin() {
        if (accessToken == null) return
        withContext(Dispatchers.IO) {
            runCatching {
                // validate token with a cheap call
                val resp = get("$MAL_API/users/@me")
                if (resp == null) refreshAccessToken()
                fetchUserProfile()
                refreshUserLists()
            }.onFailure {
                android.util.Log.e("MalService", "autoLogin failed", it)
            }
        }
    }

    // ── Profile ────────────────────────────────────────────────────────────────

    private suspend fun fetchUserProfile() = withContext(Dispatchers.IO) {
        val data = get("$MAL_API/users/@me?fields=name,picture,anime_statistics") ?: return@withContext
        _profile.value = Profile(
            id     = data["id"]?.jsonPrimitive?.contentOrNull,
            name   = data["name"]?.jsonPrimitive?.contentOrNull,
            avatar = data["picture"]?.jsonPrimitive?.contentOrNull,
            animeCount      = data["anime_statistics"]?.jsonObject?.get("num_items")?.jsonPrimitive?.intOrNull,
            episodesWatched = data["anime_statistics"]?.jsonObject?.get("num_episodes")?.jsonPrimitive?.intOrNull,
            meanScore       = data["anime_statistics"]?.jsonObject?.get("mean_score")?.jsonPrimitive?.floatOrNull
        )
    }

    // ── Homepage ───────────────────────────────────────────────────────────────

    override suspend fun fetchHomePage() = withContext(Dispatchers.IO) {
        val fields = "fields=mean,status,media_type,num_episodes,main_picture"
        _trending.value = fetchList("$MAL_API/anime/ranking?ranking_type=airing&limit=15&$fields")
        _popular.value  = fetchList("$MAL_API/anime/ranking?ranking_type=bypopularity&limit=15&$fields")
        _upcoming.value = fetchList("$MAL_API/anime/ranking?ranking_type=upcoming&limit=15&$fields")
    }

    private suspend fun fetchList(url: String): List<Media> = withContext(Dispatchers.IO) {
        val data = get(url) ?: return@withContext emptyList()
        data["data"]?.jsonArray?.map { it.jsonObject["node"]!!.jsonObject.toMalMedia() } ?: emptyList()
    }

    // ── Details ────────────────────────────────────────────────────────────────

    override suspend fun fetchDetails(id: String): Media = withContext(Dispatchers.IO) {
        val fields = "fields=mean,status,media_type,synopsis,genres,num_episodes,start_date,rank,popularity,main_picture,recommendations"
        runCatching {
            val data = get("$MAL_API/anime/$id?$fields") ?: return@withContext Media(id = id, title = "?")
            val recommendations = data["recommendations"]?.jsonArray?.mapNotNull { rec ->
                val node = rec.jsonObject["node"]?.jsonObject ?: return@mapNotNull null
                node.toMalMedia()
            } ?: emptyList()
            data.toMalMedia().copy(recommendations = recommendations)
        }.getOrElse { Media(id = id, title = "?") }
    }

    // ── Search ─────────────────────────────────────────────────────────────────

    override suspend fun search(query: String): List<Media> = withContext(Dispatchers.IO) {
        val fields = "fields=mean,status,num_episodes,main_picture"
        val data = get("$MAL_API/anime?q=$query&limit=30&$fields") ?: return@withContext emptyList()
        data["data"]?.jsonArray?.map { it.jsonObject["node"]!!.jsonObject.toMalMedia() } ?: emptyList()
    }

    // ── User list ──────────────────────────────────────────────────────────────

    override suspend fun refreshUserLists() = withContext(Dispatchers.IO) {
        val fields = "fields=num_episodes,mean,list_status"
        val data = get("$MAL_API/users/@me/animelist?$fields&limit=1000&sort=list_updated_at") ?: return@withContext
        _animeList.value = data["data"]?.jsonArray?.map { entry ->
            val node   = entry.jsonObject["node"]!!.jsonObject
            val status = entry.jsonObject["list_status"]!!.jsonObject
            TrackedMedia(
                id             = node["id"]?.jsonPrimitive?.contentOrNull ?: "",
                title          = node["title"]?.jsonPrimitive?.contentOrNull ?: "?",
                poster         = node["main_picture"]?.jsonObject?.get("large")?.jsonPrimitive?.contentOrNull,
                watchingStatus = malStatusToAL(status["status"]?.jsonPrimitive?.contentOrNull),
                episodeCount   = status["num_episodes_watched"]?.jsonPrimitive?.intOrNull,
                totalEpisodes  = node["num_episodes"]?.jsonPrimitive?.intOrNull,
                score          = status["score"]?.jsonPrimitive?.floatOrNull,
                averageScore   = node["mean"]?.jsonPrimitive?.floatOrNull?.times(10)?.toInt(),
                isMovie        = null
            )
        } ?: emptyList()
    }

    override fun setCurrentMedia(id: String) {
        _currentMedia.value = _animeList.value.firstOrNull { it.id == id }
    }

    override suspend fun updateEntry(id: String, status: String?, progress: Int?, score: Float?) =
        withContext(Dispatchers.IO) {
            val body = buildString {
                status?.let   { append("status=${alStatusToMal(it)}&") }
                progress?.let { append("num_watched_episodes=$it&") }
                score?.let    { append("score=${it.toInt()}&") }
            }.trimEnd('&')
            putForm("$MAL_API/anime/$id/my_list_status", body)
            refreshUserLists()
            setCurrentMedia(id)
        }

    override suspend fun deleteEntry(id: String) = withContext(Dispatchers.IO) {
        delete("$MAL_API/anime/$id/my_list_status")
        refreshUserLists()
        setCurrentMedia(id)
    }

    // ── HTTP helpers ───────────────────────────────────────────────────────────

    private suspend fun get(url: String): JsonObject? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .apply {
                if (accessToken != null) {
                    header("Authorization", "Bearer $accessToken")
                } else {
                    header("X-MAL-CLIENT-ID", BuildConfig.MAL_CLIENT_ID)
                }
            }
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) {
            android.util.Log.e("MalService", "GET $url failed: ${resp.code}")
            return@withContext null
        }
        runCatching { json.parseToJsonElement(resp.body.string()).jsonObject }.getOrNull()
    }

    private suspend fun postForm(url: String, body: String): JsonObject? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .post(body.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) {
            val errorBody = resp.body.string()
            android.util.Log.e("MalService", "postForm $url failed: ${resp.code} – $errorBody")
            return@withContext null
        }
        json.parseToJsonElement(resp.body.string()).jsonObject
    }

    private suspend fun putForm(url: String, body: String) = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .put(body.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .header("Authorization", "Bearer $accessToken")
            .build()
        http.newCall(req).execute()
    }

    private suspend fun delete(url: String) = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .delete()
            .header("Authorization", "Bearer $accessToken")
            .build()
        http.newCall(req).execute()
    }

    // ── Status mapping ─────────────────────────────────────────────────────────

    private fun malStatusToAL(s: String?) = when (s) {
        "watching"      -> "CURRENT"
        "completed"     -> "COMPLETED"
        "on_hold"       -> "PAUSED"
        "dropped"       -> "DROPPED"
        "plan_to_watch" -> "PLANNING"
        else            -> "UNKNOWN"
    }

    private fun alStatusToMal(s: String) = when (s) {
        "CURRENT"   -> "watching"
        "COMPLETED" -> "completed"
        "PAUSED"    -> "on_hold"
        "DROPPED"   -> "dropped"
        "PLANNING"  -> "plan_to_watch"
        else        -> "watching"
    }
}

// ── MAL JSON → Media ───────────────────────────────────────────────────────────

private fun JsonObject.toMalMedia(): Media {
    val pic = this["main_picture"]?.jsonObject
    val malId = this["id"]?.jsonPrimitive?.contentOrNull.orEmpty()
    return Media(
        id           = malId,
        title        = this["title"]?.jsonPrimitive?.contentOrNull ?: "?",
        poster       = pic?.get("large")?.jsonPrimitive?.contentOrNull,
        description  = this["synopsis"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.contentOrNull,
        averageScore = this["mean"]?.jsonPrimitive?.floatOrNull?.times(10)?.toInt(),
        episodes     = this["num_episodes"]?.jsonPrimitive?.intOrNull,
        status       = this["status"]?.jsonPrimitive?.contentOrNull.normalizeStatus(),
        genres       = this["genres"]?.takeIf { it !is JsonNull }?.jsonArray
            ?.mapNotNull { it.jsonObject["name"]?.jsonPrimitive?.contentOrNull }
            ?: emptyList(),
        serviceType  = ServiceType.MAL,
        idMal        = malId.takeIf { it.isNotBlank() }
    )
}
