package com.nyantv.data

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
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
import java.util.concurrent.TimeUnit
import androidx.core.net.toUri
import androidx.core.content.edit
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

private const val GQL_URL = "https://graphql.anilist.co"
private const val PREFS    = "anilist_prefs"
private const val TOKEN_KEY= "token"

class AnilistService(context: Context) : MediaService {

    override val serviceType = ServiceType.ANILIST

    private val http = OkHttpClient.Builder()
        .retryOnConnectionFailure(false)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private var token: String? = prefs.getString(TOKEN_KEY, null)

    // ── State flows ────────────────────────────────────────────────────────────
    private val _isLoggedIn       = MutableStateFlow(token != null)
    private val _profile          = MutableStateFlow<Profile?>(null)
    private val _animeList        = MutableStateFlow<List<TrackedMedia>>(emptyList())
    private val _currentMedia     = MutableStateFlow<TrackedMedia?>(null)
    private val _trending         = MutableStateFlow<List<Media>>(emptyList())
    private val _popular          = MutableStateFlow<List<Media>>(emptyList())
    private val _upcoming         = MutableStateFlow<List<Media>>(emptyList())
    private val _recentlyUpdated  = MutableStateFlow<List<Media>>(emptyList())

    private val detailsCache = object : LinkedHashMap<String, Media>(30, 0.75f, true) {
        override fun removeEldestEntry(eldest: Map.Entry<String, Media>) = size > 30
    }

    override val isLoggedIn:      StateFlow<Boolean>         = _isLoggedIn.asStateFlow()
    override val profile:         StateFlow<Profile?>        = _profile.asStateFlow()
    override val animeList:       StateFlow<List<TrackedMedia>> = _animeList.asStateFlow()
    override val currentMedia:    StateFlow<TrackedMedia?>   = _currentMedia.asStateFlow()
    override val trending:        StateFlow<List<Media>>     = _trending.asStateFlow()
    override val popular:         StateFlow<List<Media>>     = _popular.asStateFlow()
    override val upcoming:        StateFlow<List<Media>>     = _upcoming.asStateFlow()
    override val recentlyUpdated: StateFlow<List<Media>>     = _recentlyUpdated.asStateFlow()

    // ── Auth ───────────────────────────────────────────────────────────────────

    override suspend fun login(context: Context) {
        val clientId = BuildConfig.ANILIST_CLIENT_ID
        val redirect = BuildConfig.REDIRECT_URI
        val url = "https://anilist.co/api/v2/oauth/authorize" +
                  "?client_id=$clientId&redirect_uri=$redirect&response_type=code"
        CustomTabsIntent.Builder().build()
            .launchUrl(context, url.toUri())
        // Token arrives via deep-link; call handleAuthCallback(code) from Activity
    }

    /** Call from MainActivity when deep-link nyantv://callback?code=... arrives */
    suspend fun handleAuthCallback(code: String) = withContext(Dispatchers.IO) {
        val clientId     = BuildConfig.ANILIST_CLIENT_ID
        val clientSecret = BuildConfig.ANILIST_CLIENT_SECRET
        val redirect     = BuildConfig.REDIRECT_URI
        val body = "grant_type=authorization_code" +
                   "&client_id=$clientId" +
                   "&client_secret=$clientSecret" +
                   "&redirect_uri=$redirect" +
                   "&code=$code"
        val req = Request.Builder()
            .url("https://anilist.co/api/v2/oauth/token")
            .post(body.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()
        val resp = http.newCall(req).execute()
        if (resp.isSuccessful) {
            val data = json.parseToJsonElement(resp.body.string()).jsonObject
            token = data["access_token"]!!.jsonPrimitive.content
            prefs.edit { putString(TOKEN_KEY, token) }
            _isLoggedIn.value = true
            fetchUserProfile()
            refreshUserLists()
        }
    }

    override suspend fun logout() {
        token = null
        prefs.edit { remove(TOKEN_KEY) }
        _isLoggedIn.value = false
        _profile.value = null
        _animeList.value = emptyList()
    }

    override suspend fun autoLogin() {
        if (token != null) {
            _isLoggedIn.value = true
            withContext(Dispatchers.IO) {
                runCatching {
                    coroutineScope {
                        launch { fetchUserProfile() }
                        launch { refreshUserLists() }
                    }
                }.onFailure {
                    android.util.Log.e("AnilistService", "autoLogin failed", it)
                }
            }
        }
    }

    // ── Profile ────────────────────────────────────────────────────────────────

    private suspend fun fetchUserProfile() = withContext(Dispatchers.IO) {
        val viewer = gql("""{ Viewer {
        id name
        avatar { large }
        bannerImage
        statistics { anime { count episodesWatched meanScore } }
    } }""")["data"]?.jsonObject?.get("Viewer")

        if (viewer == null || viewer is JsonNull) return@withContext

        val data = viewer.jsonObject
        _profile.value = Profile(
            id              = data["id"]?.jsonPrimitive?.contentOrNull,
            name            = data["name"]?.jsonPrimitive?.contentOrNull,
            avatar          = data["avatar"]?.jsonObject?.get("large")?.jsonPrimitive?.contentOrNull,
            banner          = data["bannerImage"]?.jsonPrimitive?.contentOrNull,
            animeCount      = data["statistics"]?.jsonObject?.get("anime")?.jsonObject?.get("count")?.jsonPrimitive?.intOrNull,
            episodesWatched = data["statistics"]?.jsonObject?.get("anime")?.jsonObject?.get("episodesWatched")?.jsonPrimitive?.intOrNull,
            meanScore       = data["statistics"]?.jsonObject?.get("anime")?.jsonObject?.get("meanScore")?.jsonPrimitive?.floatOrNull
        )
    }

    // ── Homepage data ──────────────────────────────────────────────────────────

    override suspend fun fetchHomePage() = withContext(Dispatchers.IO) {
        val data = gql(HOME_QUERY)["data"]?.jsonObject ?: return@withContext
        _trending.value        = data["trending"]?.jsonObject?.get("media")
            ?.jsonArray?.map { it.jsonObject.toMedia() }?.distinctBy { it.id } ?: emptyList()
        _popular.value         = data["popular"]?.jsonObject?.get("media")
            ?.jsonArray?.map { it.jsonObject.toMedia() }?.distinctBy { it.id } ?: emptyList()
        _upcoming.value        = data["upcoming"]?.jsonObject?.get("media")
            ?.jsonArray?.map { it.jsonObject.toMedia() }?.distinctBy { it.id } ?: emptyList()
        _recentlyUpdated.value = data["recent"]?.jsonObject?.get("media")
            ?.jsonArray?.map { it.jsonObject.toMedia()}?.distinctBy { it.id } ?: emptyList()
    }

    // ── Details ────────────────────────────────────────────────────────────────

    override suspend fun fetchDetails(id: String): Media = withContext(Dispatchers.IO) {
        detailsCache[id]?.let { return@withContext it }

        try {
            val data = gql(DETAILS_QUERY, mapOf("id" to (id.toIntOrNull() ?: 0)))
            val media = data["data"]?.jsonObject?.get("Media")?.jsonObject?.toMedia()
                ?: Media(id = id, title = "?")
            if (media.title != "?") detailsCache[id] = media
            media
        } catch (e: Exception) {
            android.util.Log.e("NyanTV", "fetchDetails FAILED for id=$id", e)
            Media(id = id, title = "?")
        }
    }

    // ── Search ─────────────────────────────────────────────────────────────────

    override suspend fun search(query: String): List<Media> = withContext(Dispatchers.IO) {
        val data = gql(SEARCH_QUERY, mapOf("search" to query))
        data["data"]?.jsonObject?.get("Page")?.jsonObject?.get("media")?.jsonArray
            ?.map { it.jsonObject.toMedia() } ?: emptyList()
    }

    // ── User lists ─────────────────────────────────────────────────────────────

    override suspend fun refreshUserLists() = withContext(Dispatchers.IO) {
        val profileId = _profile.value?.id?.toIntOrNull() ?: run {
            fetchUserProfile()
            _profile.value?.id?.toIntOrNull() ?: return@withContext
        }
        val data = gql(USER_LIST_QUERY, mapOf("userId" to profileId))
        val lists = data["data"]?.jsonObject
            ?.get("MediaListCollection")?.jsonObject
            ?.get("lists")?.jsonArray ?: return@withContext
        _animeList.value = lists
            .flatMap { it.jsonObject["entries"]?.jsonArray ?: emptyList() }
            .map { it.jsonObject.toTrackedMedia() }
            .distinctBy { it.id }
    }

    override fun setCurrentMedia(id: String) {
        _currentMedia.value = _animeList.value.firstOrNull { it.id == id }
    }

    override suspend fun updateEntry(id: String, status: String?, progress: Int?, score: Float?) =
        withContext(Dispatchers.IO) {
            val vars = buildJsonObject {
                put("id", id.toInt())
                status?.let   { put("status",   it) }
                progress?.let { put("progress", it) }
                score?.let    { put("score",    it) }
            }
            gql(UPDATE_MUTATION, emptyMap(), vars)
            refreshUserLists()
            setCurrentMedia(id)
        }

    override suspend fun deleteEntry(id: String) = withContext(Dispatchers.IO) {
        gql(DELETE_MUTATION, mapOf("id" to (id.toIntOrNull() ?: 0)))
        refreshUserLists()
        setCurrentMedia(id)
    }

    // ── GraphQL helper ─────────────────────────────────────────────────────────

    private suspend fun gql(
        query: String,
        variables: Map<String, Any> = emptyMap(),
        variablesJson: JsonObject? = null
    ): JsonObject = withContext(Dispatchers.IO) {
        val vars = variablesJson ?: buildJsonObject {
            variables.forEach { (k, v) ->
                when (v) {
                    is String -> put(k, v)
                    is Int    -> put(k, v)
                    is Float  -> put(k, v)
                    is Boolean-> put(k, v)
                }
            }
        }
        val bodyJson = buildJsonObject {
            put("query", query.trimIndent())
            put("variables", vars)
        }
        val req = Request.Builder()
            .url(GQL_URL)
            .post(bodyJson.toString().toRequestBody("application/json".toMediaType()))
            .apply { token?.let { header("Authorization", "Bearer $it") } }
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .build()
        val resp = http.newCall(req).execute()
        json.parseToJsonElement(resp.body.string()).jsonObject
    }

    // Cover-provider

    private val anilistBannerCache = mutableMapOf<String, String?>()

    suspend fun prefetchAnilistBanners(items: List<Media>) = withContext(Dispatchers.IO) {
        val malIds = items
            .filter { it.serviceType == ServiceType.MAL }
            .mapNotNull { it.idMal ?: it.id }
            .filter { !anilistBannerCache.containsKey(it) }
            .distinct()
        if (malIds.isEmpty()) return@withContext

        val query = """
        query {
          ${malIds.mapIndexed { i, id ->
            "m$i: Media(idMal: $id, type: ANIME) { idMal bannerImage }"
        }.joinToString("\n")}
        }
    """.trimIndent()

        val body = """{"query":${json.encodeToString(query)}}"""
        val request = Request.Builder()
            .url("https://graphql.anilist.co")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        runCatching {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext
                val data = json.parseToJsonElement(response.body.string())
                    .jsonObject["data"]?.jsonObject ?: return@withContext
                data.values.forEach { entry ->
                    val obj = entry as? JsonObject ?: return@forEach
                    val malId = obj["idMal"]?.jsonPrimitive?.contentOrNull ?: return@forEach
                    val banner = obj["bannerImage"]?.jsonPrimitive?.contentOrNull
                    anilistBannerCache[malId] = banner
                }
            }
        }.onFailure { android.util.Log.e("CarouselLogo", "AniList banner prefetch failed", it) }
    }

    fun getAnilistBanner(media: Media): String? {
        if (media.serviceType != ServiceType.MAL) return null
        return anilistBannerCache[media.idMal ?: media.id]
    }

    suspend fun resolveAnilistBanner(media: Media): String? {
        if (media.serviceType != ServiceType.MAL) return null
        val malId = media.idMal ?: media.id
        if (anilistBannerCache.containsKey(malId)) return anilistBannerCache[malId]
        prefetchAnilistBanners(listOf(media))
        return anilistBannerCache[malId]
    }

    // ── Queries ────────────────────────────────────────────────────────────────

    private companion object {
        val HOME_QUERY = """
        query {
          trending: Page(page:1, perPage:15) { media(type:ANIME, sort:TRENDING_DESC) { ...F } }
          popular:  Page(page:1, perPage:15) { media(type:ANIME, sort:POPULARITY_DESC) { ...F } }
          upcoming: Page(page:1, perPage:15) { media(type:ANIME, status:NOT_YET_RELEASED, sort:POPULARITY_DESC) { ...F } }
          recent:   Page(page:1, perPage:15) { media(type:ANIME, sort:UPDATED_AT_DESC, status:RELEASING, isAdult:false, countryOfOrigin:"JP") { ...F } }
        }
        fragment F on Media {
          id idMal title { romaji english } coverImage { large } bannerImage averageScore episodes status format season seasonYear
        }
        """.trimIndent()

        val DETAILS_QUERY = $$"""
        query($id: Int) { Media(id: $id) {
          id idMal title { romaji english native } description
          coverImage { large color } bannerImage averageScore episodes status genres format season seasonYear popularity
          nextAiringEpisode { airingAt episode }
          relations { edges { node { id title { romaji english } coverImage { large } type status averageScore } relationType } }
          recommendations { edges { node { mediaRecommendation { id title { romaji english } coverImage { large } type averageScore } } } }
          characters { edges { node { name { full } image { large } } voiceActors(language:JAPANESE) { name { full } image { large } } } }
          studios { nodes { name } }
        } }
        """.trimIndent()

        val SEARCH_QUERY = $$"""
        query($search: String) { Page(page:1) { media(type:ANIME, search:$search) {
          id title { romaji english } coverImage { large color } averageScore episodes status
        } } }
        """.trimIndent()

        val USER_LIST_QUERY = $$"""
        query($userId: Int) { MediaListCollection(userId: $userId, type:ANIME, sort:UPDATED_TIME_DESC) {
          lists { entries { status progress score
            media { id title { romaji english } coverImage { large } episodes popularity averageScore }
          } }
        } }
        """.trimIndent()

        val UPDATE_MUTATION = $$"""
        mutation($id:Int, $status:MediaListStatus, $progress:Int, $score:Float) {
          SaveMediaListEntry(mediaId:$id, status:$status, progress:$progress, score:$score) { id }
        }
        """.trimIndent()

        val DELETE_MUTATION = $$"""
        mutation($id:Int) { DeleteMediaListEntry(id:$id) { deleted } }
        """.trimIndent()
    }
}
