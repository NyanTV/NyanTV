package com.nyantv.data

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import com.nyantv.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import androidx.core.content.edit
import androidx.core.net.toUri
import kotlinx.coroutines.launch

private const val SIMKL_API  = "https://api.simkl.com"
private const val SIMKL_PREFS = "simkl_prefs"
private const val POSTER_BASE = "https://wsrv.nl/?url=https://simkl.in/posters/"

class SimklService(context: Context) : MediaService {

    override val serviceType = ServiceType.SIMKL

    private val http  = OkHttpClient()
    private val json  = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val prefs = context.getSharedPreferences(SIMKL_PREFS, Context.MODE_PRIVATE)

    private var token: String? = prefs.getString("access_token", null)

    private val _isLoggedIn      = MutableStateFlow(token != null)
    private val _profile         = MutableStateFlow<Profile?>(null)
    private val _animeList       = MutableStateFlow<List<TrackedMedia>>(emptyList())
    private val _currentMedia    = MutableStateFlow<TrackedMedia?>(null)
    private val _trending        = MutableStateFlow<List<Media>>(emptyList())
    private val _trendingMovies = MutableStateFlow<List<Media>>(emptyList())
    private val _trendingShows  = MutableStateFlow<List<Media>>(emptyList())
    private val _popular         = MutableStateFlow<List<Media>>(emptyList())
    private val _upcoming        = MutableStateFlow<List<Media>>(emptyList())
    private val _recentlyUpdated = MutableStateFlow<List<Media>>(emptyList())

    // Home page – continue watching / planned, movies + shows merged together
    private val _continueWatching = MutableStateFlow<List<TrackedMedia>>(emptyList())
    private val _planned          = MutableStateFlow<List<TrackedMedia>>(emptyList())

    // Discover page – per-country, movies + shows merged together
    private val _korean   = MutableStateFlow<List<Media>>(emptyList())
    private val _japanese = MutableStateFlow<List<Media>>(emptyList())
    private val _us       = MutableStateFlow<List<Media>>(emptyList())
    private val _uk       = MutableStateFlow<List<Media>>(emptyList())
    private val _canada   = MutableStateFlow<List<Media>>(emptyList())

    override val isLoggedIn:      StateFlow<Boolean>            = _isLoggedIn.asStateFlow()
    override val profile:         StateFlow<Profile?>           = _profile.asStateFlow()
    override val animeList:       StateFlow<List<TrackedMedia>> = _animeList.asStateFlow()
    override val currentMedia:    StateFlow<TrackedMedia?>      = _currentMedia.asStateFlow()
    override val trending:        StateFlow<List<Media>>        = _trending.asStateFlow()
    val trendingMovies:           StateFlow<List<Media>>        = _trendingMovies.asStateFlow()
    val trendingShows:            StateFlow<List<Media>>        = _trendingShows.asStateFlow()
    override val popular:         StateFlow<List<Media>>        = _popular.asStateFlow()
    override val upcoming:        StateFlow<List<Media>>        = _upcoming.asStateFlow()
    override val recentlyUpdated: StateFlow<List<Media>>        = _recentlyUpdated.asStateFlow()

    val continueWatching: StateFlow<List<TrackedMedia>> = _continueWatching.asStateFlow()
    val planned:          StateFlow<List<TrackedMedia>> = _planned.asStateFlow()

    val korean:   StateFlow<List<Media>> = _korean.asStateFlow()
    val japanese: StateFlow<List<Media>> = _japanese.asStateFlow()
    val us:       StateFlow<List<Media>> = _us.asStateFlow()
    val uk:       StateFlow<List<Media>> = _uk.asStateFlow()
    val canada:   StateFlow<List<Media>> = _canada.asStateFlow()

    // ── Auth ───────────────────────────────────────────────────────────────────

    override suspend fun login(context: Context) {
        val clientId = BuildConfig.SIMKL_CLIENT_ID
        val redirect = BuildConfig.REDIRECT_URI
        val url = "https://simkl.com/oauth/authorize?response_type=code&client_id=$clientId&redirect_uri=$redirect"
        CustomTabsIntent.Builder().build().launchUrl(context, url.toUri())
    }

    suspend fun handleAuthCallback(code: String) = withContext(Dispatchers.IO) {
        android.util.Log.d("SimklService", "handleAuthCallback called, code=${code.take(10)}...")
        val body = buildJsonObject {
            put("code",          code)
            put("client_id",     BuildConfig.SIMKL_CLIENT_ID)
            put("client_secret", BuildConfig.SIMKL_CLIENT_SECRET)
            put("redirect_uri",  BuildConfig.REDIRECT_URI)
            put("grant_type",    "authorization_code")
        }
        android.util.Log.d("SimklService", "posting to $SIMKL_API/oauth/token")
        val resp = postJson("$SIMKL_API/oauth/token", body) ?: return@withContext
        android.util.Log.d("SimklService", "response: $resp")
        token = resp["access_token"]!!.jsonPrimitive.content
        prefs.edit { putString("access_token", token) }
        _isLoggedIn.value = true
        fetchUserProfile()
        refreshUserLists()
    }

    override suspend fun logout() {
        token = null
        prefs.edit { remove("access_token") }
        _isLoggedIn.value = false
        _profile.value   = null
        _animeList.value = emptyList()
    }

    override suspend fun autoLogin() {
        if (token == null) return
        withContext(Dispatchers.IO) {
            runCatching {
                coroutineScope {
                    launch { fetchUserProfile() }
                    launch { refreshUserLists() }
                }
            }.onFailure {
                android.util.Log.e("SimklService", "autoLogin failed", it)
            }
        }
    }

    // ── Profile ────────────────────────────────────────────────────────────────

    private suspend fun fetchUserProfile() = withContext(Dispatchers.IO) {
        val data = postJsonAuthed("$SIMKL_API/users/settings", buildJsonObject {}) ?: return@withContext
        val account = data["account"]?.jsonObject
        val user    = data["user"]?.jsonObject
        _profile.value = Profile(
            id     = account?.get("id")?.jsonPrimitive?.contentOrNull,
            name   = user?.get("name")?.jsonPrimitive?.contentOrNull,
            avatar = user?.get("avatar")?.jsonPrimitive?.contentOrNull
        )
    }

    // ── Homepage ───────────────────────────────────────────────────────────────

    override suspend fun fetchHomePage() = withContext(Dispatchers.IO) {
        coroutineScope {
            val movies = async { fetchTrending("movies") }
            val shows  = async { fetchTrending("tv") }
            _trendingMovies.value = movies.await().take(15)
            _trendingShows.value  = shows.await().take(15)
            val combined = (_trendingMovies.value + _trendingShows.value)
                .sortedByDescending { it.popularity }
            _trending.value = combined.take(15)
            _popular.value  = combined.drop(15).take(15)
        }
    }

    private suspend fun fetchTrending(type: String): List<Media> = withContext(Dispatchers.IO) {
        runCatching {
            val simklType = if (type == "movies") "movies" else "tv"
            val req = Request.Builder()
                .url("https://data.simkl.in/discover/trending/$simklType/today_100.json?client_id=${BuildConfig.SIMKL_CLIENT_ID}")
                .build()
            val resp = http.newCall(req).execute()
            if (!resp.isSuccessful) {
                android.util.Log.e("SimklService", "fetchTrending $type HTTP ${resp.code}")
                return@withContext emptyList()
            }
            val body = resp.body.string()
            android.util.Log.d("SimklService", "fetchTrending $type sample: ${body.take(500)}")
            json.parseToJsonElement(body).jsonArray
                .mapNotNull { it.jsonObject.toSimklMedia(isMovie = type == "movies") }
        }.getOrElse {
            android.util.Log.e("SimklService", "fetchTrending $type failed", it)
            emptyList()
        }
    }

    // ── Discover page – per-country, movies + shows merged into one list ───────

    suspend fun fetchDiscoverPage() = withContext(Dispatchers.IO) {
        coroutineScope {
            val korean   = async { fetchCountryContent("kr") }
            val japanese = async { fetchCountryContent("jp") }
            val us       = async { fetchCountryContent("us") }
            val uk       = async { fetchCountryContent("gb") }
            val canada   = async { fetchCountryContent("ca") }
            _korean.value   = korean.await()
            _japanese.value = japanese.await()
            _us.value       = us.await()
            _uk.value       = uk.await()
            _canada.value   = canada.await()
        }
    }

    private suspend fun fetchCountryContent(country: String): List<Media> = coroutineScope {
        val movies = async { fetchCountryGenre("movies", country) }
        val shows  = async { fetchCountryGenre("tv", country) }
        (movies.await() + shows.await()).sortedByDescending { it.popularity ?: 0 }
    }

    private suspend fun fetchCountryGenre(type: String, country: String): List<Media> = withContext(Dispatchers.IO) {
        runCatching {
            val url = if (type == "movies")
                "$SIMKL_API/movies/genres/all/all-types/$country/all-years/rank?extended=overview&client_id=${BuildConfig.SIMKL_CLIENT_ID}&limit=20"
            else
                "$SIMKL_API/tv/genres/all/all-types/$country/all-networks/all-years/rank?extended=overview&client_id=${BuildConfig.SIMKL_CLIENT_ID}&limit=20"
            getRawArray(url)?.mapNotNull { it.jsonObject.toSimklMedia(isMovie = type == "movies") } ?: emptyList()
        }.getOrElse {
            android.util.Log.e("SimklService", "fetchCountryGenre $type/$country failed", it)
            emptyList()
        }
    }

    // ── Details ────────────────────────────────────────────────────────────────

    override suspend fun fetchDetails(id: String): Media = withContext(Dispatchers.IO) {
        val simklId = id.substringBefore("*")
        val isMovie = id.substringAfter("*") == "MOVIE"
        val type    = if (isMovie) "movies" else "tv"
        runCatching {
            val data = getRaw("$SIMKL_API/$type/$simklId?extended=full&client_id=${BuildConfig.SIMKL_CLIENT_ID}")
                ?: return@withContext Media(id = id, title = "?")
            data.toSimklMediaFull(isMovie = isMovie) ?: Media(id = id, title = "?")
        }.getOrElse { Media(id = id, title = "?") }
    }

    // ── Search ─────────────────────────────────────────────────────────────────

    override suspend fun search(query: String): List<Media> = withContext(Dispatchers.IO) {
        coroutineScope {
            val movies = async {
                getRawArray("$SIMKL_API/search/movie?q=$query&extended=full&client_id=${BuildConfig.SIMKL_CLIENT_ID}")
                    ?.mapNotNull { it.jsonObject.toSimklMedia(isMovie = true) } ?: emptyList()
            }
            val series = async {
                getRawArray("$SIMKL_API/search/tv?q=$query&extended=full&client_id=${BuildConfig.SIMKL_CLIENT_ID}")
                    ?.mapNotNull { it.jsonObject.toSimklMedia(isMovie = false) } ?: emptyList()
            }
            movies.await() + series.await()
        }
    }

    // ── User lists – movies + shows merged into animeList ─────────────────────

    override suspend fun refreshUserLists() = withContext(Dispatchers.IO) {
        coroutineScope {
            val movies = async { fetchUserMovies() }
            val shows  = async { fetchUserShows() }
            val all = movies.await() + shows.await()
            _animeList.value = all
            _continueWatching.value = all.filter { it.watchingStatus == "CURRENT" }
            _planned.value          = all.filter { it.watchingStatus == "PLANNING" }
        }
    }

    private suspend fun fetchUserMovies(): List<TrackedMedia> = withContext(Dispatchers.IO) {
        coroutineScope {
            val listReq   = async { getAuthed("$SIMKL_API/sync/all-items/movies") }
            val ratingsReq = async {
                getRawArray("$SIMKL_API/ratings/ratings/movies?user_watchlist=all&fields=simkl,ext&client_id=${BuildConfig.SIMKL_CLIENT_ID}", authHeaders())
            }
            val data    = listReq.await() ?: return@coroutineScope emptyList()
            val ratings = ratingsReq.await()

            val ratingMap = mutableMapOf<String, JsonObject>()
            ratings?.forEach { r ->
                val id = r.jsonObject["id"]?.jsonPrimitive?.intOrNull?.toString()
                    ?: return@forEach
                ratingMap[id] = r.jsonObject
            }

            data["movies"]?.jsonArray?.mapNotNull { entry ->
                val movie   = entry.jsonObject["movie"]?.jsonObject ?: return@mapNotNull null
                val ids     = movie["ids"]?.jsonObject ?: return@mapNotNull null
                val simklId = ids["simkl"]?.jsonPrimitive?.intOrNull?.toString()
                    ?: return@mapNotNull null
                if (simklId.isBlank()) return@mapNotNull null

                val r = ratingMap[simklId]
                val simklRating = r?.get("simkl")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
                val imdbRating  = r?.get("imdb")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
                val score = (simklRating ?: imdbRating)?.let { (it * 10).toInt() }

                TrackedMedia(
                    id             = "${simklId}*MOVIE",
                    title          = movie["title"]?.jsonPrimitive?.contentOrNull ?: "?",
                    poster         = movie["poster"]?.jsonPrimitive?.contentOrNull
                        ?.let { "${POSTER_BASE}${it}_m.jpg" },
                    watchingStatus = simklStatusToAL(entry.jsonObject["status"]?.jsonPrimitive?.contentOrNull),
                    episodeCount   = if (simklStatusToAL(entry.jsonObject["status"]?.jsonPrimitive?.contentOrNull) == "COMPLETED") 1 else 0,
                    totalEpisodes  = 1,
                    averageScore   = score,
                    isMovie        = true
                )
            } ?: emptyList()
        }
    }

    private suspend fun fetchUserShows(): List<TrackedMedia> = withContext(Dispatchers.IO) {
        coroutineScope {
            val listReq    = async { getAuthed("$SIMKL_API/sync/all-items/shows") }
            val ratingsReq = async {
                getRawArray("$SIMKL_API/ratings/ratings/tv?user_watchlist=all&fields=simkl,ext&client_id=${BuildConfig.SIMKL_CLIENT_ID}", authHeaders())
            }
            val data    = listReq.await() ?: return@coroutineScope emptyList()
            val ratings = ratingsReq.await()

            val ratingMap = mutableMapOf<String, JsonObject>()
            ratings?.forEach { r ->
                val id = r.jsonObject["id"]?.jsonPrimitive?.intOrNull?.toString()
                    ?: return@forEach
                ratingMap[id] = r.jsonObject
            }

            data["shows"]?.jsonArray?.mapNotNull { entry ->
                val show    = entry.jsonObject["show"]?.jsonObject ?: return@mapNotNull null
                val ids     = show["ids"]?.jsonObject ?: return@mapNotNull null
                val simklId = ids["simkl"]?.jsonPrimitive?.intOrNull?.toString()
                    ?: return@mapNotNull null
                if (simklId.isBlank()) return@mapNotNull null

                val r = ratingMap[simklId]
                val simklRating = r?.get("simkl")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
                val imdbRating  = r?.get("imdb")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
                val score = (simklRating ?: imdbRating)?.let { (it * 10).toInt() }

                TrackedMedia(
                    id             = "${simklId}*SERIES",
                    title          = show["title"]?.jsonPrimitive?.contentOrNull ?: "?",
                    poster         = show["poster"]?.jsonPrimitive?.contentOrNull
                        ?.let { "${POSTER_BASE}${it}_m.jpg" },
                    watchingStatus = simklStatusToAL(entry.jsonObject["status"]?.jsonPrimitive?.contentOrNull),
                    episodeCount   = entry.jsonObject["watched_episodes_count"]?.jsonPrimitive?.intOrNull,
                    totalEpisodes  = entry.jsonObject["total_episodes_count"]?.jsonPrimitive?.intOrNull,
                    averageScore   = score,
                    isMovie        = false
                )
            } ?: emptyList()
        }
    }

    override fun setCurrentMedia(id: String) {
        _currentMedia.value = _animeList.value.firstOrNull { it.id == id }
    }

    override suspend fun updateEntry(id: String, status: String?, progress: Int?, score: Float?) =
        withContext(Dispatchers.IO) {
            val isMovie = id.substringAfter("*") == "MOVIE"
            val simklId = id.substringBefore("*")
            val newStatus = alStatusToSimkl(status ?: "CURRENT")
            val existingEntry = _animeList.value.firstOrNull { it.id == id }
            val alreadyExists = existingEntry != null
            val currentProgress = existingEntry?.episodeCount ?: 0
            val isDecreasing = progress != null && progress < currentProgress
            val statusChanged = alreadyExists && existingEntry.watchingStatus != (status ?: existingEntry.watchingStatus)

            if (isMovie) {
                val body = buildJsonObject {
                    put("movies", buildJsonArray {
                        add(buildJsonObject {
                            if (!alreadyExists) put("to", newStatus)
                            put("ids", buildJsonObject { put("simkl", simklId) })
                        })
                    })
                }
                val url = if (alreadyExists) "$SIMKL_API/sync/history" else "$SIMKL_API/sync/add-to-list"
                postJsonAuthed(url, body)
            } else {
                if (!alreadyExists || statusChanged) {
                    val statusBody = buildJsonObject {
                        put("shows", buildJsonArray {
                            add(buildJsonObject {
                                put("to", newStatus)
                                put("ids", buildJsonObject { put("simkl", simklId) })
                            })
                        })
                    }
                    postJsonAuthed("$SIMKL_API/sync/add-to-list", statusBody)
                }

                if (isDecreasing) {
                    val removeBody = buildJsonObject {
                        put("shows", buildJsonArray {
                            add(buildJsonObject {
                                put("ids", buildJsonObject { put("simkl", simklId) })
                                put("seasons", buildJsonArray {
                                    add(buildJsonObject {
                                        put("number", 1)
                                        put("episodes", buildJsonArray {
                                            for (i in 1..currentProgress) {
                                                add(buildJsonObject { put("number", i) })
                                            }
                                        })
                                    })
                                })
                            })
                        })
                    }
                    postJsonAuthed("$SIMKL_API/sync/history/remove", removeBody)
                }

                if (progress != null && progress > 0) {
                    val addBody = buildJsonObject {
                        put("shows", buildJsonArray {
                            add(buildJsonObject {
                                put("ids", buildJsonObject { put("simkl", simklId) })
                                put("episodes", buildJsonArray {
                                    for (i in 1..progress) {
                                        add(buildJsonObject { put("number", i) })
                                    }
                                })
                            })
                        })
                    }
                    postJsonAuthed("$SIMKL_API/sync/history", addBody)
                }
            }

            refreshUserLists()
            setCurrentMedia(id)
        }

    override suspend fun deleteEntry(id: String) = withContext(Dispatchers.IO) {
        val isMovie = id.substringAfter("*") == "MOVIE"
        val simklId = id.substringBefore("*")
        val body = if (isMovie) buildJsonObject {
            put("movies", buildJsonArray {
                add(buildJsonObject { put("ids", buildJsonObject { put("simkl", simklId) }) })
            })
        } else buildJsonObject {
            put("shows", buildJsonArray {
                add(buildJsonObject { put("ids", buildJsonObject { put("simkl", simklId) }) })
            })
        }
        postJsonAuthed("$SIMKL_API/sync/history/remove", body)
        refreshUserLists()
        setCurrentMedia(id)
    }

    // ── HTTP helpers ───────────────────────────────────────────────────────────

    private fun authHeaders() = mapOf(
        "Authorization"  to "Bearer $token",
        "simkl-api-key"  to BuildConfig.SIMKL_CLIENT_ID,
        "Content-Type"   to "application/json"
    )

    private suspend fun get(url: String): JsonObject? = withContext(Dispatchers.IO) {
        val req  = Request.Builder().url(url).build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return@withContext null
        runCatching { json.parseToJsonElement(resp.body.string()).jsonObject }.getOrNull()
    }

    private suspend fun getRaw(url: String): JsonObject? = get(url)

    private suspend fun getRawArray(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): List<JsonElement>? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return@withContext null
        runCatching { json.parseToJsonElement(resp.body.string()).jsonArray.toList() }.getOrNull()
    }

    private suspend fun getAuthed(url: String): JsonObject? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .apply { authHeaders().forEach { (k, v) -> header(k, v) } }
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) return@withContext null
        runCatching { json.parseToJsonElement(resp.body.string()).jsonObject }.getOrNull()
    }

    private suspend fun postJson(url: String, body: JsonObject): JsonObject? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) {
            android.util.Log.e("SimklService", "postJson $url failed: ${resp.code} – ${resp.body.string()}")
            return@withContext null
        }
        runCatching { json.parseToJsonElement(resp.body.string()).jsonObject }.getOrNull()
    }

    private suspend fun postJsonAuthed(url: String, body: JsonObject): JsonObject? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .apply { authHeaders().forEach { (k, v) -> header(k, v) } }
            .build()
        val resp = http.newCall(req).execute()
        if (!resp.isSuccessful) {
            android.util.Log.e("SimklService", "postJsonAuthed $url failed: ${resp.code} – ${resp.body.string()}")
            return@withContext null
        }
        runCatching { json.parseToJsonElement(resp.body.string()).jsonObject }.getOrNull()
    }

    // ── Status mapping ─────────────────────────────────────────────────────────

    private fun simklStatusToAL(s: String?) = when (s) {
        "watching"    -> "CURRENT"
        "completed"   -> "COMPLETED"
        "hold"        -> "PAUSED"
        "dropped"     -> "DROPPED"
        "plantowatch" -> "PLANNING"
        else          -> "UNKNOWN"
    }

    private fun alStatusToSimkl(s: String) = when (s) {
        "CURRENT"   -> "watching"
        "COMPLETED" -> "completed"
        "PAUSED"    -> "hold"
        "DROPPED"   -> "dropped"
        "PLANNING"  -> "plantowatch"
        else        -> "watching"
    }
}

// ── Simkl JSON → Media ────────────────────────────────────────────────────────

private fun JsonObject.toSimklMedia(isMovie: Boolean): Media? {
    val ids     = this["ids"]?.jsonObject
    val simklId = ids?.get("simkl_id")?.jsonPrimitive?.contentOrNull
        ?: ids?.get("simkl")?.jsonPrimitive?.contentOrNull
    if (simklId.isNullOrBlank()) return null
    val tmdbId = ids?.get("tmdb_id")?.jsonPrimitive?.contentOrNull
        ?: ids?.get("tmdb")?.jsonPrimitive?.contentOrNull

    val poster = this["poster"]?.jsonPrimitive?.contentOrNull
        ?.let { "${POSTER_BASE}${it}_m.jpg" }

    val ratingsObj   = this["ratings"]?.jsonObject
    val simklRating  = ratingsObj?.get("simkl")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
    val imdbRating   = ratingsObj?.get("imdb")?.jsonObject?.get("rating")?.jsonPrimitive?.floatOrNull
    val rating       = simklRating ?: imdbRating
    val averageScore = rating?.let { (it * 10).toInt() }

    val popularity = ratingsObj?.get("simkl")?.jsonObject?.get("votes")?.jsonPrimitive?.intOrNull

    return Media(
        id           = if (isMovie) "${simklId}*MOVIE" else "${simklId}*SERIES",
        title        = this["title"]?.jsonPrimitive?.contentOrNull ?: "?",
        poster       = poster,
        cover        = this["fanart"]?.jsonPrimitive?.contentOrNull
            ?.let { "https://wsrv.nl/?url=https://simkl.in/fanart/${it}_w.jpg" },
        description  = this["overview"]?.jsonPrimitive?.contentOrNull,
        status       = this["status"]?.jsonPrimitive?.contentOrNull.normalizeStatus(),
        averageScore = averageScore,
        format       = if (isMovie) "MOVIE" else "TV",
        seasonYear   = this["year"]?.jsonPrimitive?.intOrNull,
        popularity   = popularity,
        tmdbId       = tmdbId,
        serviceType  = ServiceType.SIMKL
    )
}

private fun JsonObject.toSimklMediaFull(isMovie: Boolean): Media? {
    val base = toSimklMedia(isMovie) ?: return null

    val recommendations = this["users_recommendations"]?.jsonArray?.mapNotNull { rec ->
        runCatching {
            val obj     = rec.jsonObject
            val ids     = obj["ids"]?.jsonObject
            val recId   = ids?.get("simkl")?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val poster  = obj["poster"]?.jsonPrimitive?.contentOrNull
                ?.let { "https://simkl.in/posters/${it}_m.jpg" }
            Media(
                id          = if (isMovie) "${recId}*MOVIE" else "${recId}*SERIES",
                title       = obj["title"]?.jsonPrimitive?.contentOrNull ?: "?",
                poster      = poster,
                serviceType = ServiceType.SIMKL
            )
        }.getOrNull()
    } ?: emptyList()

    return base.copy(
        recommendations = recommendations,
        episodes        = this["total_episodes"]?.jsonPrimitive?.intOrNull,
        genres          = this["genres"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList(),
        description     = this["overview"]?.jsonPrimitive?.contentOrNull
    )
}
