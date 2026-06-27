package com.nyantv.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nyantv.data.*
import com.nyantv.ui.theme.AppTheme
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.nyantv.ui.utils.NetworkState
import kotlinx.coroutines.delay
import androidx.core.content.edit
import com.nyantv.ui.theme.ActiveTheme
import com.nyantv.ui.theme.CustomTheme
import com.nyantv.ui.widgets.CarouselLogoResolver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

class AppViewModel(app: Application) : AndroidViewModel(app) {

    // ── Service management ─────────────────────────────────────────────────────
    private val prefs = app.getSharedPreferences("nyantv_prefs", Context.MODE_PRIVATE)

    private val _serviceType = MutableStateFlow(
        ServiceType.valueOf(
            prefs.getString("service_type", ServiceType.ANILIST.name) ?: ServiceType.ANILIST.name
        )
    )
    val serviceType: StateFlow<ServiceType> = _serviceType.asStateFlow()

    private var _service: MediaService = buildService(_serviceType.value, app)
    private val serviceJobs = mutableListOf<kotlinx.coroutines.Job>()

    private var sideService: MediaService? = buildSideService(_serviceType.value, app)
    private var syncManager: SyncManager?  = buildSyncManager()


// ── Theme ──────────────────────────────────────────────────────────────────

    private val _activeTheme = MutableStateFlow(
        prefs.getString("active_theme_builtin", null)
            ?.let { runCatching { ActiveTheme.BuiltIn(AppTheme.valueOf(it)) }.getOrNull() }
            ?: run {
                val customName = prefs.getString("active_theme_custom", null)
                val customJson = prefs.getString("custom_themes", null)
                if (customName != null && customJson != null) {
                    runCatching {
                        val arr = org.json.JSONArray(customJson)
                        val match = (0 until arr.length())
                            .map { CustomTheme.fromJson(arr.getString(it)) }
                            .firstOrNull { it.name == customName }
                        match?.let { ActiveTheme.Custom(it) }
                    }.getOrNull()
                } else null
            }
            ?: ActiveTheme.BuiltIn(AppTheme.SAKURA)
    )
    val activeTheme: StateFlow<ActiveTheme> = _activeTheme.asStateFlow()

    private val _customThemes = MutableStateFlow(
        prefs.getString("custom_themes", null)
            ?.let { json ->
                runCatching {
                    val arr = org.json.JSONArray(json)
                    List(arr.length()) { i -> CustomTheme.fromJson(arr.getString(i)) }
                }.getOrElse { emptyList() }
            } ?: emptyList()
    )
    val customThemes: StateFlow<List<CustomTheme>> = _customThemes.asStateFlow()

    fun setTheme(t: AppTheme) {
        _activeTheme.value = ActiveTheme.BuiltIn(t)
        prefs.edit {
            putString("active_theme_builtin", t.name)
            remove("active_theme_custom")
        }
    }

    fun setCustomTheme(t: CustomTheme) {
        _activeTheme.value = ActiveTheme.Custom(t)
        prefs.edit {
            putString("active_theme_custom", t.name)
            remove("active_theme_builtin")
        }
    }

    fun importThemeJson(json: String): Result<CustomTheme> = runCatching {
        val theme = CustomTheme.fromJson(json)
        val updated = (_customThemes.value + theme).distinctBy { it.name }
        _customThemes.value = updated
        prefs.edit { putString("custom_themes", org.json.JSONArray(updated.map { it.toJson() }).toString()) }
        theme
    }

    fun deleteCustomTheme(t: CustomTheme) {
        val updated = _customThemes.value - t
        _customThemes.value = updated
        prefs.edit { putString("custom_themes", org.json.JSONArray(updated.map { it.toJson() }).toString()) }
        if (_activeTheme.value == ActiveTheme.Custom(t)) setTheme(AppTheme.SAKURA)
    }

    // ── Passthrough flows ──────────────────────────────────────────────────────
    private val _isLoggedIn      = MutableStateFlow(false)
    private val _profile         = MutableStateFlow<Profile?>(null)
    private val _animeList       = MutableStateFlow<List<TrackedMedia>>(emptyList())
    private val _currentMedia    = MutableStateFlow<TrackedMedia?>(null)
    private val _trending        = MutableStateFlow<List<Media>>(emptyList())
    private val _popular         = MutableStateFlow<List<Media>>(emptyList())
    private val _upcoming        = MutableStateFlow<List<Media>>(emptyList())
    private val _recentlyUpdated = MutableStateFlow<List<Media>>(emptyList())
    private val _searchResults   = MutableStateFlow<List<Media>>(emptyList())
    private val _networkState    = MutableStateFlow(NetworkState.LOADING)

    private val _trendingMovies = MutableStateFlow<List<Media>>(emptyList())
    private val _trendingShows  = MutableStateFlow<List<Media>>(emptyList())

    // Simkl Discover – per-country lists
    private val _korean   = MutableStateFlow<List<Media>>(emptyList())
    private val _japanese = MutableStateFlow<List<Media>>(emptyList())
    private val _us       = MutableStateFlow<List<Media>>(emptyList())
    private val _uk       = MutableStateFlow<List<Media>>(emptyList())
    private val _canada   = MutableStateFlow<List<Media>>(emptyList())

    private val _carouselLogos     = MutableStateFlow<Map<String, String?>>(emptyMap())
    private val _carouselBackdrops = MutableStateFlow<Map<String, String?>>(emptyMap())
    val carouselLogos:     StateFlow<Map<String, String?>> = _carouselLogos.asStateFlow()
    val carouselBackdrops: StateFlow<Map<String, String?>> = _carouselBackdrops.asStateFlow()

    val isLoggedIn:      StateFlow<Boolean>            = _isLoggedIn.asStateFlow()
    val profile:         StateFlow<Profile?>           = _profile.asStateFlow()
    val animeList:       StateFlow<List<TrackedMedia>> = _animeList.asStateFlow()
    val currentMedia:    StateFlow<TrackedMedia?>      = _currentMedia.asStateFlow()
    val trending:        StateFlow<List<Media>>        = _trending.asStateFlow()
    val popular:         StateFlow<List<Media>>        = _popular.asStateFlow()
    val upcoming:        StateFlow<List<Media>>        = _upcoming.asStateFlow()
    val recentlyUpdated: StateFlow<List<Media>>        = _recentlyUpdated.asStateFlow()
    val searchResults:   StateFlow<List<Media>>        = _searchResults.asStateFlow()
    val networkState:    StateFlow<NetworkState>       = _networkState.asStateFlow()
    val trendingMovies:  StateFlow<List<Media>>        = _trendingMovies.asStateFlow()
    val trendingShows:   StateFlow<List<Media>>        = _trendingShows.asStateFlow()
    val korean:          StateFlow<List<Media>>        = _korean.asStateFlow()
    val japanese:        StateFlow<List<Media>>        = _japanese.asStateFlow()
    val us:              StateFlow<List<Media>>        = _us.asStateFlow()
    val uk:              StateFlow<List<Media>>        = _uk.asStateFlow()
    val canada:          StateFlow<List<Media>>        = _canada.asStateFlow()

    init {
        viewModelScope.launch {
            awaitAll(
                async { _service.autoLogin() },
                async { sideService?.autoLogin() }
            )
            bindService()
            loadHome()
        }
    }


    // ── Service switching ──────────────────────────────────────────────────────

    fun switchService(type: ServiceType) {
        if (type == _serviceType.value) return
        _serviceType.value = type
        prefs.edit { putString("service_type", type.name) }

        serviceJobs.forEach { it.cancel() }
        serviceJobs.clear()

        val cached = loadProfileCache(type)

        _isLoggedIn.value        = cached != null
        _profile.value           = cached
        _animeList.value         = emptyList()
        _trending.value          = emptyList()
        _carouselLogos.value     = emptyMap()
        _carouselBackdrops.value = emptyMap()
        _popular.value           = emptyList()
        _upcoming.value          = emptyList()
        _recentlyUpdated.value   = emptyList()
        _trendingMovies.value    = emptyList()
        _trendingShows.value     = emptyList()
        _korean.value            = emptyList()
        _japanese.value          = emptyList()
        _us.value                = emptyList()
        _uk.value                = emptyList()
        _canada.value            = emptyList()

        _service     = buildService(type, getApplication())
        sideService  = buildSideService(type, getApplication())
        syncManager  = buildSyncManager()
        bindService()

        viewModelScope.launch {
            _service.autoLogin()
            sideService?.autoLogin()
            loadHome()
            System.gc()
        }
    }


    private fun bindService() {
        serviceJobs += viewModelScope.launch { _service.isLoggedIn.collect      { _isLoggedIn.value = it } }
        serviceJobs += viewModelScope.launch {
            _service.profile
                .filterNotNull()
                .collect { profile ->
                    _profile.value = profile
                    saveProfileCache(_serviceType.value, profile)
                }
        }
        serviceJobs += viewModelScope.launch { _service.animeList.collect       { _animeList.value = it } }
        serviceJobs += viewModelScope.launch { _service.currentMedia.collect    { _currentMedia.value = it } }
        serviceJobs += viewModelScope.launch {
            _service.trending.collect { items ->
                _trending.value = items
                launch { preloadCarouselAssets(items) }
            }
        }
        serviceJobs += viewModelScope.launch { _service.popular.collect         { _popular.value = it } }
        serviceJobs += viewModelScope.launch { _service.upcoming.collect        { _upcoming.value = it } }
        serviceJobs += viewModelScope.launch { _service.recentlyUpdated.collect { _recentlyUpdated.value = it } }

        val simkl = _service as? SimklService
        if (simkl != null) {
            serviceJobs += viewModelScope.launch { simkl.trendingMovies.collect { _trendingMovies.value = it } }
            serviceJobs += viewModelScope.launch { simkl.trendingShows.collect  { _trendingShows.value = it } }
            serviceJobs += viewModelScope.launch { simkl.korean.collect         { _korean.value         = it } }
            serviceJobs += viewModelScope.launch { simkl.japanese.collect       { _japanese.value       = it } }
            serviceJobs += viewModelScope.launch { simkl.us.collect             { _us.value             = it } }
            serviceJobs += viewModelScope.launch { simkl.uk.collect             { _uk.value             = it } }
            serviceJobs += viewModelScope.launch { simkl.canada.collect         { _canada.value         = it } }
        } else {
            _trendingMovies.value = emptyList()
            _trendingShows.value  = emptyList()
            _korean.value         = emptyList()
            _japanese.value       = emptyList()
            _us.value             = emptyList()
            _uk.value             = emptyList()
            _canada.value         = emptyList()
        }
    }

    // ── Tracking Automation ────────────────────────────────────────────────────
    enum class TrackingMode { ALWAYS_ASK, ALWAYS_AUTO, NEVER_AUTO }

    private val _trackingMode = MutableStateFlow(
        TrackingMode.valueOf(prefs.getString("tracking_mode", TrackingMode.ALWAYS_ASK.name) ?: TrackingMode.ALWAYS_ASK.name)
    )
    val trackingMode: StateFlow<TrackingMode> = _trackingMode.asStateFlow()

    fun setTrackingMode(mode: TrackingMode) {
        _trackingMode.value = mode
        prefs.edit { putString("tracking_mode", mode.name) }
    }

    // ── Sync Tracking ──────────────────────────────────────────────────────────
    private val _syncMalWithAnilist = MutableStateFlow(prefs.getBoolean("sync_mal_anilist", false))
    val syncMalWithAnilist: StateFlow<Boolean> = _syncMalWithAnilist.asStateFlow()

    fun setSyncMalWithAnilist(v: Boolean) {
        _syncMalWithAnilist.value = v
        prefs.edit { putBoolean("sync_mal_anilist", v) }
    }

    // ── Homescreen Lists ───────────────────────────────────────────────────────
    private val _anilistShowContinue = MutableStateFlow(prefs.getBoolean("anilist_show_continue", true))
    private val _anilistShowPlanned  = MutableStateFlow(prefs.getBoolean("anilist_show_planned",  false))
    private val _malShowContinue     = MutableStateFlow(prefs.getBoolean("mal_show_continue",     true))
    private val _malShowPlanned      = MutableStateFlow(prefs.getBoolean("mal_show_planned",      false))
    private val _simklShowContinue   = MutableStateFlow(prefs.getBoolean("simkl_show_continue",   true))
    private val _simklShowPlanned    = MutableStateFlow(prefs.getBoolean("simkl_show_planned",    false))

    val anilistShowContinue: StateFlow<Boolean> = _anilistShowContinue.asStateFlow()
    val anilistShowPlanned:  StateFlow<Boolean> = _anilistShowPlanned.asStateFlow()
    val malShowContinue:     StateFlow<Boolean> = _malShowContinue.asStateFlow()
    val malShowPlanned:      StateFlow<Boolean> = _malShowPlanned.asStateFlow()
    val simklShowContinue:   StateFlow<Boolean> = _simklShowContinue.asStateFlow()
    val simklShowPlanned:    StateFlow<Boolean> = _simklShowPlanned.asStateFlow()

    fun setAnilistShowContinue(v: Boolean) { _anilistShowContinue.value = v; prefs.edit { putBoolean("anilist_show_continue", v) } }
    fun setAnilistShowPlanned(v: Boolean)  { _anilistShowPlanned.value  = v; prefs.edit { putBoolean("anilist_show_planned",  v) } }
    fun setMalShowContinue(v: Boolean)     { _malShowContinue.value     = v; prefs.edit { putBoolean("mal_show_continue",     v) } }
    fun setMalShowPlanned(v: Boolean)      { _malShowPlanned.value      = v; prefs.edit { putBoolean("mal_show_planned",      v) } }
    fun setSimklShowContinue(v: Boolean)   { _simklShowContinue.value   = v; prefs.edit { putBoolean("simkl_show_continue",   v) } }
    fun setSimklShowPlanned(v: Boolean)    { _simklShowPlanned.value    = v; prefs.edit { putBoolean("simkl_show_planned",    v) } }

    // ── Actions ────────────────────────────────────────────────────────────────

    fun loadHome() = viewModelScope.launch {
        _networkState.value = NetworkState.LOADING

        repeat(3) { attempt ->
            val result = runCatching {
                val simkl = _service as? SimklService
                if (simkl != null) {
                    coroutineScope {
                        val home     = async { simkl.fetchHomePage() }
                        val discover = async { simkl.fetchDiscoverPage() }
                        home.await()
                        discover.await()
                    }
                } else {
                    _service.fetchHomePage()
                }
            }
            if (result.isSuccess) {
                _networkState.value = NetworkState.SUCCESS
                return@launch
            }
            android.util.Log.e("AppViewModel", "loadHome attempt $attempt failed", result.exceptionOrNull())
            if (attempt < 2) delay(2_000L * (attempt + 1))
        }

        _networkState.value = NetworkState.ERROR
    }

    fun retryLoad() = viewModelScope.launch {
        runCatching { _service.autoLogin() }
            .onFailure { android.util.Log.e("AppViewModel", "autoLogin failed on retry", it) }

        runCatching { sideService?.autoLogin() }
            .onFailure { android.util.Log.e("AppViewModel", "sideService autoLogin failed on retry", it) }

        loadHome()
    }

    fun search(query: String) = viewModelScope.launch {
        if (query.isBlank()) { _searchResults.value = emptyList(); return@launch }
        runCatching { _searchResults.value = _service.search(query) }
    }

    suspend fun fetchDetails(id: String): Media =
        runCatching { _service.fetchDetails(id) }.getOrElse { Media(id = id, title = "?") }

    fun login(context: Context) = viewModelScope.launch { _service.login(context) }

    fun logout() = viewModelScope.launch { _service.logout() }

    fun updateEntry(id: String, status: String?, progress: Int?, score: Float?) =
        viewModelScope.launch {
            _service.updateEntry(id, status, progress, score)

            _animeList.update { list ->
                val updated = list.firstOrNull { it.id == id } ?: return@update list
                listOf(updated) + list.filter { it.id != id }
            }

            if (_syncMalWithAnilist.value) {
                val sm = syncManager ?: return@launch
                when (_serviceType.value) {
                    ServiceType.ANILIST -> sm.syncFromAnilist(id, status, progress, score)
                    ServiceType.MAL     -> sm.syncFromMal(id, status, progress, score)
                    ServiceType.SIMKL   -> { }
                }
            }
        }


    fun deleteEntry(id: String) = viewModelScope.launch { _service.deleteEntry(id) }

    fun markEpisodeWatched(mediaId: String, episodeNumber: Int) {
        updateEntry(
            id       = mediaId,
            status   = "CURRENT",
            progress = episodeNumber,
            score    = null,
        )
    }

    fun setCurrentMedia(id: String) = _service.setCurrentMedia(id)

    fun handleAuthCallback(code: String) = viewModelScope.launch {
        val target: MediaService? = when {
            _service    is AnilistService -> _service
            _service    is MalService     -> _service
            _service    is SimklService   -> _service
            sideService is AnilistService -> sideService
            sideService is MalService     -> sideService
            else                          -> null
        }
        when (target) {
            is AnilistService -> target.handleAuthCallback(code)
            is MalService     -> target.handleAuthCallback(code)
            is SimklService   -> target.handleAuthCallback(code)
        }
    }

    // Filtered list helpers
    //fun listByStatus(status: String) = animeList.value.filter {
    //    it.watchingStatus?.equals(status, ignoreCase = true) == true
    //}

    private fun buildSideService(active: ServiceType, app: Application): MediaService? =
        when (active) {
            ServiceType.ANILIST -> buildService(ServiceType.MAL,     app)
            ServiceType.MAL     -> buildService(ServiceType.ANILIST, app)
            ServiceType.SIMKL   -> null
        }

    private fun buildSyncManager(): SyncManager? {
        val anilist = when {
            _service    is AnilistService -> _service    as AnilistService
            sideService is AnilistService -> sideService as AnilistService
            else                          -> return null
        }
        val mal = when {
            _service    is MalService -> _service    as MalService
            sideService is MalService -> sideService as MalService
            else                      -> return null
        }
        return SyncManager(anilist, mal)
    }

    private fun saveProfileCache(type: ServiceType, profile: Profile) {
        prefs.edit {
            putString("cache_${type.name}_name",   profile.name)
            putString("cache_${type.name}_avatar", profile.avatar)
        }
    }

    private fun loadProfileCache(type: ServiceType): Profile? {
        val name   = prefs.getString("cache_${type.name}_name",   null) ?: return null
        val avatar = prefs.getString("cache_${type.name}_avatar", null)
        return Profile(name = name, avatar = avatar)
    }

    private suspend fun preloadCarouselAssets(items: List<Media>) {
        coroutineScope {
            items
                .filter { !_carouselLogos.value.containsKey(it.id) }
                .map { media ->
                    async(Dispatchers.IO) {
                        val logo     = async { CarouselLogoResolver.resolve(media) }
                        val backdrop = async { CarouselLogoResolver.resolveBackdrop(media) }
                        media.id to Pair(logo.await(), backdrop.await())
                    }
                }
                .awaitAll()
                .forEach { (id, pair) ->
                    _carouselLogos.update     { it + (id to pair.first) }
                    _carouselBackdrops.update { it + (id to pair.second) }
                }
        }
    }

    suspend fun resolveAnilistBanner(media: Media): String? {
        val anilist = when {
            _service    is AnilistService -> _service    as AnilistService
            sideService is AnilistService -> sideService as AnilistService
            else                          -> return null
        }
        return anilist.resolveAnilistBanner(media)
    }

    suspend fun prefetchAnilistBanners(items: List<Media>) {
        val anilist = when {
            _service    is AnilistService -> _service    as AnilistService
            sideService is AnilistService -> sideService as AnilistService
            else                          -> return
        }
        anilist.prefetchAnilistBanners(items)
    }

    fun getAnilistBanner(media: Media): String? {
        val anilist = when {
            _service    is AnilistService -> _service    as AnilistService
            sideService is AnilistService -> sideService as AnilistService
            else                          -> return null
        }
        return anilist.getAnilistBanner(media)
    }

}
