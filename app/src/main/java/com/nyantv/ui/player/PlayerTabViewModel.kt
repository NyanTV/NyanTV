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

// ── UI State ──────────────────────────────────────────────────────────────────

sealed interface EpisodeState {
    data object Idle : EpisodeState
    data object Loading : EpisodeState
    data class Success(val episodes: List<SEpisode>) : EpisodeState
    data class Error(val message: String) : EpisodeState
}

sealed interface SearchState {
    data object Idle : SearchState
    data object Loading : SearchState
    data class Results(val items: List<SAnime>) : SearchState
    data class Error(val message: String) : SearchState
}

sealed interface StreamState {
    data object Idle : StreamState
    data object Loading : StreamState
    data class Ready(val videos: List<Video>) : StreamState
    data class Error(val message: String) : StreamState
}

data class PlayerTabUiState(
    val sources: List<SearchableSource> = emptyList(),
    val selectedSource: SearchableSource? = null,
    val searchQuery: String = "",
    val isEditingQuery: Boolean = false,
    val searchState: SearchState = SearchState.Idle,
    val selectedAnime: SAnime? = null,
    val episodeState: EpisodeState = EpisodeState.Idle,
    val selectedEpisode: SEpisode? = null,
    val streamState: StreamState = StreamState.Idle,
    val skipTimes: EpisodeSkipTimes? = null,
    val episodeMeta: Map<String, AniZipEpisodeMeta> = emptyMap(),
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

class PlayerTabViewModel(
    app: Application,
    val mediaId: String,
    private val mediaTitle: String,
    val serviceKey: String,
    private val serviceType: ServiceType,
    private val malId: String?,
) : AndroidViewModel(app) {

    private val cache             = PlayerCache(app)
    private val aniyomi           = AniyomiExtensions(app)
    private val watchHistoryStore = WatchHistoryStore(app)

    private val _watchProgress = MutableStateFlow<EpisodeProgress?>(null)
    val watchProgress: StateFlow<EpisodeProgress?> = _watchProgress.asStateFlow()

    /** AniList-ID wenn AniList-Service aktiv, sonst null */
    val anilistId:    String? get() = if (serviceType == ServiceType.ANILIST) mediaId else null
    /** Immer die MAL-ID, unabhängig vom aktiven Service */
    val currentMalId: String? get() = _malId

    fun refreshWatchProgress() {
        _watchProgress.value = if (serviceKey == "simkl") {
            watchHistoryStore.loadSimkl(mediaId)
        } else {
            watchHistoryStore.loadAnilistMal(anilistId = anilistId, malId = _malId)
        }
    }

    private val _state = MutableStateFlow(PlayerTabUiState())
    val state: StateFlow<PlayerTabUiState> = _state.asStateFlow()
    private var _malId: String? = malId

    private var imdbId: String? = null

    private val _fillerEpisodes = MutableStateFlow<Set<Int>>(emptySet())
    val fillerEpisodes: StateFlow<Set<Int>> = _fillerEpisodes

    private var searchJob: Job? = null
    private var episodeMetaJob: Job? = null
    private var episodeMetaKey: String? = null

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
                            val resolved = resolveSource(savedSourceId, _state.value.sources.firstOrNull())
                                ?: return@collect

                            val currentId = _state.value.selectedSource?.id
                            if (resolved.id == currentId) return@collect

                            _state.update { it.copy(selectedSource = resolved) }

                            val cached = cache.loadSelectedResult(resolved.id, mediaId)
                            if (cached != null) {
                                val anime = SAnime.create().apply {
                                    url           = cached.url
                                    title         = cached.title
                                    thumbnail_url = cached.thumbnail
                                }
                                _state.update { it.copy(selectedAnime = anime) }
                                loadEpisodes(resolved, anime)
                            } else {
                                _state.update { it.copy(selectedAnime = null, episodeState = EpisodeState.Idle) }
                                val q = _state.value.searchQuery
                                if (q.isNotBlank()) autoSearch(resolved, q)
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
                }
            }
        }
        if (serviceKey != "simkl" && malId != null) {
            viewModelScope.launch {
                _fillerEpisodes.value = JikanService.getFillerEpisodes(malId)
            }
        }
        if (malId != null) {
            loadEpisodeMetadata()//malId)
        }
    }

    // ── Source building ───────────────────────────────────────────────────────

    private fun buildSources(): List<SearchableSource> {
        return aniyomi.installedExtensions.value
            .flatMap { ext ->
                ext.sources.filterIsInstance<AnimeHttpSource>().map { httpSource ->
                    AniyomiSearchableSource(
                        httpSource = httpSource,
                        iconUrl    = ext.iconUrl,
                    )
                }
            }
    }

    fun updateMediaTitle(title: String) {
        if (title.isBlank()) return
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

    fun setImdbId(id: String) {
        imdbId = id
    }

    private fun loadEpisodeMetadata() {
        val anilistId = anilistId
        val malId = _malId
        val key = when (serviceType) {
            ServiceType.ANILIST -> anilistId?.let { "anilist:$it" }
            ServiceType.MAL -> malId?.let { "mal:$it" }
            ServiceType.SIMKL -> null
        } ?: return

        if (episodeMetaKey == key && _state.value.episodeMeta.isNotEmpty()) return
        episodeMetaKey = key
        episodeMetaJob?.cancel()
        _state.update { it.copy(episodeMeta = emptyMap()) }
        episodeMetaJob = viewModelScope.launch {
            val result = when (serviceType) {
                ServiceType.ANILIST -> AniZipService.getEpisodesByAnilistId(anilistId!!)
                ServiceType.MAL -> AniZipService.getEpisodesByMalId(malId!!)
                ServiceType.SIMKL -> emptyMap()
            }
            _state.update { it.copy(episodeMeta = result) }
        }
    }

    fun loadSkipTimes(episodeNumber: Float) {
        viewModelScope.launch {
            _state.update { it.copy(skipTimes = null) }
            val result: EpisodeSkipTimes? = when {
                serviceKey == "simkl" -> {
                    val iid = imdbId ?: return@launch
                    IntroDbService.getSkipTimes(iid, season = "1", episode = episodeNumber.toInt().toString())
                }
                _malId != null -> AniskipService.getSkipTimes(
                    malId         = _malId!!,
                    episodeNumber = episodeNumber.toInt().toString(),
                )
                else -> null
            }
            _state.update { it.copy(skipTimes = result) }
        }
    }


    fun loadSkipTimesSimkl(imdbId: String, season: String, episode: String) {
        viewModelScope.launch {
            _state.update { it.copy(skipTimes = null) }
            val result = IntroDbService.getSkipTimes(imdbId, season, episode)
            _state.update { it.copy(skipTimes = result) }
        }
    }



    // ── Source selection ──────────────────────────────────────────────────────

    fun selectSource(source: SearchableSource) {
        if (source.id == _state.value.selectedSource?.id) return
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
            }
            autoSearch(source, _state.value.searchQuery)
        }
    }

    private suspend fun resolveSource(
        savedId:  Long?,
        fallback: SearchableSource?,
    ): SearchableSource? {
        if (savedId == null) return fallback

        repeat(5) { attempt ->
            val found = buildSources().firstOrNull { it.id == savedId }
            if (found != null) return found
            kotlinx.coroutines.delay(100L)
        }

        return fallback
    }

    // ── Search ────────────────────────────────────────────────────────────────

    fun setSearchQuery(query: String) {
        _state.update { it.copy(searchQuery = query) }
    }

    fun setEditingQuery(editing: Boolean) {
        _state.update { it.copy(isEditingQuery = editing) }
    }

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
        _state.update { it.copy(searchState = SearchState.Loading) }
        searchJob = viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { source.search(query) } }
                .onSuccess { page ->
                    _state.update { it.copy(searchState = SearchState.Results(page.animes)) }
                    if (_state.value.selectedAnime == null && page.animes.isNotEmpty()) {
                        selectAnimeResult(page.animes.first(), autoSelected = true)
                    }
                }
                .onFailure { e ->
                    _state.update { it.copy(searchState = SearchState.Error(e.message ?: "Search failed")) }
                }
        }
    }

    // ── Result selection ──────────────────────────────────────────────────────

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

    // ── Episodes ──────────────────────────────────────────────────────────────

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

    // ── Streams ───────────────────────────────────────────────────────────────

    fun selectEpisode(episode: SEpisode) {
        val source = _state.value.selectedSource ?: return
        _state.update { it.copy(selectedEpisode = episode, streamState = StreamState.Loading) }

        loadSkipTimes(episode.episode_number)
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { source.getVideoList(episode) } }
                .onSuccess { videos ->
                    android.util.Log.d("PlayerTab", "videos count=${videos.size}")
                    videos.forEach { v ->
                        android.util.Log.d("PlayerTab", "  quality=${v.quality} url=${v.videoUrl} headers=${v.headers}")
                    }
                    _state.update { it.copy(streamState = StreamState.Ready(videos)) }
                }
                .onFailure { e ->
                    android.util.Log.e("PlayerTab", "getVideoList failed", e)
                    _state.update { it.copy(streamState = StreamState.Error(e.message ?: "Stream-Fehler")) }
                }
        }
    }

    fun clearStreams() = _state.update {
        it.copy(streamState = StreamState.Idle, selectedEpisode = null)
    }

    // ── Factory ───────────────────────────────────────────────────────────────

    class Factory(
        private val app: Application,
        private val mediaId: String,
        private val mediaTitle: String,
        private val serviceKey: String,
        private val serviceType: ServiceType,
        private val malId: String? = null,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            PlayerTabViewModel(app, mediaId, mediaTitle, serviceKey, serviceType, malId) as T
    }
}
