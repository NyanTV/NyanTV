package com.nyantv.player

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.nyantv.AniZipEpisodeMeta
import com.nyantv.AniZipService
import com.nyantv.AniskipService
import com.nyantv.EpisodeSkipTimes
import com.nyantv.IntroDbService
import com.nyantv.JikanService
import com.nyantv.data.ServiceType
import com.nyantv.extensions.AniyomiExtensions
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PlayerTabUiState(
    val sources:        List<SearchableSource>          = emptyList(),
    val selectedSource: SearchableSource?               = null,
    val searchQuery:    String                          = "",
    val isEditingQuery: Boolean                         = false,
    val searchState:    SearchState                     = SearchState.Idle,
    val selectedAnime:  SAnime?                         = null,
    val episodeState:   EpisodeState                    = EpisodeState.Idle,
    val selectedEpisode: SEpisode?                      = null,
    val streamState:    StreamState                     = StreamState.Idle,
    val skipTimes:      EpisodeSkipTimes?               = null,
    val episodeMeta:    Map<String, AniZipEpisodeMeta>  = emptyMap(),
)

class PlayerTabViewModel(
    app: Application,
    val mediaId:      String,
    mediaTitle:   String,
    val serviceKey:   String,
    private val serviceType:  ServiceType,
    private val malId:        String?,
) : AndroidViewModel(app) {

    private val cache             = PlayerCache(app)
    private val aniyomi           = AniyomiExtensions(app)
    private val watchHistoryStore = WatchHistoryStore(app)

    // ── Watch progress ─────────────────────────────────────────────────────────

    private val _resumeProgress = MutableStateFlow<EpisodeProgress?>(null)
    val resumeProgress: StateFlow<EpisodeProgress?> = _resumeProgress.asStateFlow()

    private val _episodeProgressMap = MutableStateFlow<Map<Int, EpisodeProgress>>(emptyMap())
    val episodeProgressMap: StateFlow<Map<Int, EpisodeProgress>> = _episodeProgressMap.asStateFlow()

    private val _watchedEpisodes = MutableStateFlow<Set<Int>>(emptySet())
    val watchedEpisodes: StateFlow<Set<Int>> = _watchedEpisodes.asStateFlow()

    val anilistId:    String? get() = if (serviceType == ServiceType.ANILIST) mediaId else null
    val currentMalId: String? get() = _malId

    val mediaBannerUrl: String get() = _mediaBannerUrl
    val mediaPosterUrl: String get() = _mediaPosterUrl
    private var _mediaBannerUrl: String = ""
    private var _mediaPosterUrl: String = ""

    var mediaTitle: String = mediaTitle
        private set

    fun setMediaImages(banner: String?, poster: String?) {
        _mediaBannerUrl = banner ?: ""
        _mediaPosterUrl = poster ?: ""
    }

    fun refreshWatchProgress() {
        _episodeProgressMap.value = emptyMap()

        _resumeProgress.value = if (serviceKey == "simkl") {
            watchHistoryStore.loadSimkl(mediaId)
        } else {
            watchHistoryStore.loadAnilistMal(anilistId = anilistId, malId = _malId)
        }
        _watchedEpisodes.value = if (serviceKey == "simkl") {
            watchHistoryStore.getWatchedSimkl(mediaId)
        } else {
            watchHistoryStore.getWatchedAnilistMal(anilistId = anilistId, malId = _malId)
        }
    }

    fun episodeProgressFor(episodeNumber: Float): EpisodeProgress? {
        val cached = _episodeProgressMap.value[episodeNumber.toInt()]
        if (cached != null) return cached
        val loaded = if (serviceKey == "simkl") {
            watchHistoryStore.loadEpisodeProgressSimkl(mediaId, episodeNumber)
        } else {
            watchHistoryStore.loadEpisodeProgressAnilistMal(anilistId, _malId, episodeNumber)
        }
        if (loaded != null) {
            _episodeProgressMap.update { it + (episodeNumber.toInt() to loaded) }
        }
        return loaded
    }

    private val _state = MutableStateFlow(PlayerTabUiState())
    val state: StateFlow<PlayerTabUiState> = _state.asStateFlow()
    private var _malId: String? = malId
    private var imdbId: String? = null

    private val _fillerEpisodes = MutableStateFlow<Set<Int>>(emptySet())
    val fillerEpisodes: StateFlow<Set<Int>> = _fillerEpisodes

    private var searchJob:      Job? = null
    private var episodeMetaJob: Job? = null
    private var episodeMetaKey: String? = null
    private var pendingTargetSourceId: Long? = null

    init {
        refreshWatchProgress()
        loadEpisodeMetadata()

        viewModelScope.launch(Dispatchers.IO) {
            runCatching { aniyomi.extensionManager.refresh() }
        }

        var initialised = false

        viewModelScope.launch {
            aniyomi.installedExtensions.collect { _ ->
                val newSources      = buildSources()
                val currentSourceId = _state.value.selectedSource?.id

                if (!initialised && newSources.isNotEmpty()) {
                    initialised = true

                    val savedQuery = cache.loadQueryOverride(mediaId)
                    val fallback   = newSources.firstOrNull()

                    _state.update {
                        it.copy(
                            sources        = newSources,
                            searchQuery    = savedQuery ?: mediaTitle,
                            selectedSource = fallback,
                        )
                    }

                    viewModelScope.launch {
                        cache.observeSelectedSourceId(serviceKey).collect { savedSourceId ->
                            pendingTargetSourceId = savedSourceId
                            val currentSources = buildSources()
                            val resolved = currentSources.firstOrNull { it.id == savedSourceId }
                                ?: _state.value.sources.firstOrNull()
                                ?: return@collect

                            applySource(resolved)

                            if (savedSourceId != null && resolved.id != savedSourceId) {
                                pendingTargetSourceId = savedSourceId
                            } else {
                                pendingTargetSourceId = null
                            }
                        }
                    }

                } else if (initialised) {
                    _state.update { s ->
                        s.copy(
                            sources        = newSources,
                            selectedSource = newSources.firstOrNull { it.id == currentSourceId }
                                ?: s.selectedSource,
                        )
                    }

                    val targetId = pendingTargetSourceId
                    if (targetId != null) {
                        val late = newSources.firstOrNull { it.id == targetId }
                        if (late != null && _state.value.selectedSource?.id != targetId) {
                            pendingTargetSourceId = null
                            applySource(late)
                        }
                    }
                }
            }
        }

        if (serviceKey != "simkl" && malId != null) {
            viewModelScope.launch {
                _fillerEpisodes.value = JikanService.getFillerEpisodes(malId)
            }
        }
        if (malId != null) {
            loadEpisodeMetadata()
        }
    }

    private fun applySource(source: SearchableSource) {
        _state.update { it.copy(selectedSource = source) }
        viewModelScope.launch {
            val cached = cache.loadSelectedResult(source.id, mediaId)
            if (cached != null) {
                val anime = SAnime.create().apply {
                    url           = cached.url
                    title         = cached.title
                    thumbnail_url = cached.thumbnail
                }
                _state.update { it.copy(selectedAnime = anime) }
                loadEpisodes(source, anime)
            } else {
                _state.update { it.copy(selectedAnime = null, episodeState = EpisodeState.Idle) }
                val q = _state.value.searchQuery
                if (q.isNotBlank()) autoSearch(source, q)
            }
        }
    }

    private fun buildSources(): List<SearchableSource> {
        return aniyomi.installedExtensions.value
            .flatMap { ext ->
                ext.sources.filterIsInstance<AnimeHttpSource>().map { httpSource ->
                    AniyomiSearchableSource(httpSource = httpSource, iconUrl = ext.iconUrl)
                }
            }
    }

    fun updateMediaTitle(title: String) {
        if (title.isBlank()) return
        if (mediaTitle.isBlank()) mediaTitle = title
        val s = _state.value
        if (s.searchQuery.isNotBlank()) return
        _state.update { it.copy(searchQuery = title) }
        if (s.selectedAnime == null && s.searchState is SearchState.Idle) {
            val source = s.selectedSource ?: return
            autoSearch(source, title)
        }
    }

    fun updateMalId(id: String) {
        if (_malId != null) return
        _malId = id
        viewModelScope.launch {
            _fillerEpisodes.value = JikanService.getFillerEpisodes(id)
            state.value.selectedEpisode?.let { loadSkipTimes(it.episode_number) }
        }
        loadEpisodeMetadata()
    }

    fun setImdbId(id: String) { imdbId = id }

    private fun loadEpisodeMetadata() {
        val anilistId = anilistId
        val malId     = _malId
        val key = when (serviceType) {
            ServiceType.ANILIST -> anilistId?.let { "anilist:$it" }
            ServiceType.MAL     -> malId?.let     { "mal:$it" }
            ServiceType.SIMKL   -> null
        } ?: return

        if (episodeMetaKey == key && _state.value.episodeMeta.isNotEmpty()) return
        episodeMetaKey = key
        episodeMetaJob?.cancel()
        _state.update { it.copy(episodeMeta = emptyMap()) }
        episodeMetaJob = viewModelScope.launch {
            val result = when (serviceType) {
                ServiceType.ANILIST -> AniZipService.getEpisodesByAnilistId(anilistId!!)
                ServiceType.MAL     -> AniZipService.getEpisodesByMalId(malId!!)
                ServiceType.SIMKL   -> emptyMap()
            }
            _state.update { it.copy(episodeMeta = result) }
        }
    }

    fun loadSkipTimes(episodeNumber: Float) {
        viewModelScope.launch {
            _state.update { it.copy(skipTimes = null) }
            _state.update { it.copy(skipTimes = fetchSkipTimesFor(episodeNumber)) }
        }
    }

    fun loadSkipTimesSimkl(imdbId: String, season: String, episode: String) {
        viewModelScope.launch {
            _state.update { it.copy(skipTimes = null) }
            val result = IntroDbService.getSkipTimes(imdbId, season, episode)
            _state.update { it.copy(skipTimes = result) }
        }
    }
    suspend fun fetchSkipTimesFor(episodeNumber: Float): EpisodeSkipTimes? = when {
        serviceKey == "simkl" -> {
            val iid = imdbId ?: return null
            IntroDbService.getSkipTimes(iid, season = "1", episode = episodeNumber.toInt().toString())
        }
        _malId != null -> AniskipService.getSkipTimes(
            malId         = _malId!!,
            episodeNumber = episodeNumber.toInt().toString(),
        )
        else -> null
    }

    /** Overload accepting an [SEpisode] directly, for convenience at call sites. */
    suspend fun fetchSkipTimesFor(episode: SEpisode): EpisodeSkipTimes? =
        fetchSkipTimesFor(episode.episode_number)

    fun selectSource(source: SearchableSource) {
        if (source.id == _state.value.selectedSource?.id) return
        pendingTargetSourceId = null
        _state.update {
            it.copy(
                selectedSource = source,
                selectedAnime  = null,
                episodeState   = EpisodeState.Idle,
                searchState    = SearchState.Idle,
            )
        }
        viewModelScope.launch {
            cache.saveSelectedSource(serviceKey, source.id)
            val cached = cache.loadSelectedResult(source.id, mediaId)
            if (cached != null) {
                val anime = SAnime.create().apply {
                    url           = cached.url
                    title         = cached.title
                    thumbnail_url = cached.thumbnail
                }
                _state.update { it.copy(selectedAnime = anime) }
                loadEpisodes(source, anime)
            } else {
                autoSearch(source, _state.value.searchQuery)
            }
        }
    }

    fun setSearchQuery(query: String)    { _state.update { it.copy(searchQuery = query) } }
    fun setEditingQuery(editing: Boolean){ _state.update { it.copy(isEditingQuery = editing) } }

    fun submitSearch() {
        val source = _state.value.selectedSource ?: return
        val query  = _state.value.searchQuery.trim()
        if (query.isEmpty()) return
        _state.update { it.copy(isEditingQuery = false) }
        viewModelScope.launch {
            cache.saveQueryOverride(mediaId, query)
            cache.clearResult(source.id, mediaId)
            _state.update { it.copy(selectedAnime = null, episodeState = EpisodeState.Idle) }
            doSearch(source, query)
        }
    }

    private fun autoSearch(source: SearchableSource, query: String) {
        viewModelScope.launch { doSearch(source, query) }
    }

    fun ensureSearched() {
        if (_state.value.searchState !is SearchState.Idle) return
        val source = _state.value.selectedSource ?: return
        val q = _state.value.searchQuery.trim()
        if (q.isNotBlank()) autoSearch(source, q)
    }

    private suspend fun doSearch(source: SearchableSource, query: String) {
        searchJob?.cancel()
        val job = viewModelScope.launch {
            _state.update { it.copy(searchState = SearchState.Loading) }
            runCatching { withContext(Dispatchers.IO) { source.search(query) } }
                .onSuccess { page ->
                    if (page.animes.isEmpty()) {
                        _state.update { it.copy(searchState = SearchState.Error("No results found")) }
                        return@onSuccess
                    }
                    _state.update { it.copy(searchState = SearchState.Results(page.animes)) }
                    if (_state.value.selectedAnime == null) {
                        selectAnimeResult(page.animes.first(), autoSelected = true)
                    }
                }
                .onFailure { e ->
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    _state.update { it.copy(searchState = SearchState.Error(e.message ?: "Search failed")) }
                }
        }
        searchJob = job
        job.join()
    }

    fun selectAnimeResult(anime: SAnime, autoSelected: Boolean = false) {
        val source = _state.value.selectedSource ?: return
        _state.update { it.copy(selectedAnime = anime) }
        viewModelScope.launch {
            if (!autoSelected) cache.saveSelectedResult(source.id, mediaId, anime)
            loadEpisodes(source, anime)
        }
    }

    fun confirmAnimeResult(anime: SAnime) {
        val source = _state.value.selectedSource ?: return
        _state.update { it.copy(selectedAnime = anime) }
        viewModelScope.launch {
            cache.saveSelectedResult(source.id, mediaId, anime)
            loadEpisodes(source, anime)
        }
    }

    private fun loadEpisodes(source: SearchableSource, anime: SAnime, retryCount: Int = 0) {
        viewModelScope.launch {
            _state.update { it.copy(episodeState = EpisodeState.Loading) }
            runCatching { withContext(Dispatchers.IO) { source.getEpisodes(anime) } }
                .onSuccess { episodes ->
                    _state.update {
                        it.copy(episodeState = EpisodeState.Success(episodes.sortedBy { ep -> ep.episode_number }))
                    }
                }
                .onFailure { e ->
                    if (retryCount < 2) {
                        kotlinx.coroutines.delay(500L * (retryCount + 1))
                        loadEpisodes(source, anime, retryCount + 1)
                    } else {
                        _state.update { it.copy(episodeState = EpisodeState.Error(e.message ?: "Failed to load episodes")) }
                    }
                }
        }
    }

    fun retryEpisodes() {
        val source = _state.value.selectedSource ?: return
        val anime  = _state.value.selectedAnime  ?: return
        loadEpisodes(source, anime)
    }

    suspend fun getVideosForEpisode(episode: SEpisode): List<Video> {
        val source = _state.value.selectedSource
            ?: throw IllegalStateException("No source selected")
        return withContext(Dispatchers.IO) { source.getVideoList(episode) }
    }

    fun selectEpisode(episode: SEpisode) {
        val source = _state.value.selectedSource ?: return
        _state.update { it.copy(selectedEpisode = episode, streamState = StreamState.Loading) }
        loadSkipTimes(episode.episode_number)
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { source.getVideoList(episode) } }
                .onSuccess { videos ->
                    _state.update { it.copy(streamState = StreamState.Ready(videos)) }
                }
                .onFailure { e ->
                    _state.update { it.copy(streamState = StreamState.Error(e.message ?: "Stream-Fehler")) }
                }
        }
    }

    fun clearStreams() = _state.update { it.copy(streamState = StreamState.Idle) }

    class Factory(
        private val app:         Application,
        private val mediaId:     String,
        private val mediaTitle:  String,
        private val serviceKey:  String,
        private val serviceType: ServiceType,
        private val malId:       String? = null,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            PlayerTabViewModel(app, mediaId, mediaTitle, serviceKey, serviceType, malId) as T
    }
}