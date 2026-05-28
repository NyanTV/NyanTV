package com.nyantv.ui.player

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import android.view.Surface
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.util.UnstableApi
import com.nyantv.AniZipEpisodeMeta
import com.nyantv.EpisodeSkipTimes
import com.nyantv.SkipInterval
import com.nyantv.player.EpisodeProgress
import com.nyantv.player.IPlayerCallback
import com.nyantv.player.IPlayerService
import com.nyantv.player.PlayerService
import com.nyantv.player.WatchHistoryStore
import com.nyantv.ui.utils.displayName
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

// ── UI state ───────────────────────────────────────────────────────────────────

data class PlayerUiState(
    val connected:             Boolean             = false,
    val positionMs:            Long                = 0L,
    val durationMs:            Long                = 0L,
    val bufferedMs:            Long                = 0L,
    val playbackState:         Int                 = 1,
    val isPlaying:             Boolean             = false,
    val error:                 String?             = null,
    val videoWidth:            Int                 = 0,
    val videoHeight:           Int                 = 0,
    val title:                 String              = "",
    // ── Multi-track ────────────────────────────────────────────────────────
    val streams:               List<StreamTrack>   = emptyList(),
    val selectedStreamIndex:   Int                 = 0,
    val subtitleTracks:        List<SubtitleTrack> = emptyList(),
    val hasNextEpisode:     Boolean    = false,
    val hasPrevEpisode:     Boolean    = false,
    val episodeNavigating:  Boolean    = false,
    val pendingEpisodeName: String = "",
    val pendingEpisodeVideos: List<Video> = emptyList(),
    val fillerWarning: FillerWarning? = null,
    /** null = subtitles disabled / no track selected */
    val selectedSubtitleIndex: Int?                = null,
    val skipTimes: EpisodeSkipTimes? = null,
    val activeSkip: ActiveSkip? = null,
)

data class FillerWarning(
    val targetEpisodeName:    String,
    val delta:                Int,
    val nextNonFillerIndex:   Int?,
    val nextNonFillerName:    String?,
)

data class SubtitlePrefs(
    val enabled:       Boolean = true,
    val fontSize:      Float   = 18f,
    val bold:          Boolean = false,
    val colorHex:      String  = "#FFFFFFFF",
    val translateTo:   String? = null,
    val lingvaBaseUrl: String  = "https://lingva.ml",
    val bigSkipSec:    Int     = 75,
)

data class ActiveSkip(val label: String, val startSec: Int, val endSec: Int)

data class WatchedEvent(val episode: SEpisode, val mediaId: String)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@UnstableApi
class PlayerViewModel(app: Application) : AndroidViewModel(app) {

    companion object {
        private const val TAG          = "NyanTV:PlayerVM"
        private const val PREF_QUALITY = "preferred_quality_name"
    }

    private val prefs = app.getSharedPreferences("nyantv_player_prefs", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    private var surfaceReady   = false
    private var pendingUri:    String?  = null
    private var pendingSurface: Surface? = null

    private val _subtitlePrefs = MutableStateFlow(loadSubtitlePrefs())
    val subtitlePrefs: StateFlow<SubtitlePrefs> = _subtitlePrefs.asStateFlow()


    // ── Watch history ──────────────────────────────────────────────────────────
    private val watchHistoryStore   = WatchHistoryStore(app)
    private var serviceKey          = "anilist_mal"
    private var anilistId:  String? = null
    private var malId:      String? = null
    private var pendingResumeMs     = 0L
    private var hasResumed          = false
    private var lastSavedPositionMs = -1L

    // ── Auto-tracking ──────────────────────────────────────────────────────────
    private var mediaId                  = ""
    private var sessionTrackingEnabled   = false
    private var hasTrackedCurrentEpisode = false

    private val _watchedEvent = MutableSharedFlow<WatchedEvent>(extraBufferCapacity = 1)
    val watchedEvent: SharedFlow<WatchedEvent> = _watchedEvent.asSharedFlow()

    fun setSessionTracking(enabled: Boolean) {
        sessionTrackingEnabled = enabled
    }

    private val _currentCue = MutableStateFlow<String?>(null)
    val currentCue: StateFlow<String?> = _currentCue.asStateFlow()

    private val subtitleEngine   = SubtitleEngine()
    private var lingvaTranslator: LingvaTranslator? = null

    // ── Service binding ────────────────────────────────────────────────────────

    private var service: IPlayerService? = null

    private val aidlCallback = object : IPlayerCallback.Stub() {
        override fun onStateChanged(state: Int) {
            _state.update { it.copy(playbackState = state) }
            if (state == androidx.media3.common.Player.STATE_READY && !hasResumed && pendingResumeMs > 0L) {
                hasResumed = true
                val ms = pendingResumeMs
                pendingResumeMs = 0L
                service?.seekTo(ms)
            }
        }

        override fun onPositionChanged(positionMs: Long, durationMs: Long) {
            val currentSec    = (positionMs / 1000L).toInt()
            val newActiveSkip = computeActiveSkip(currentSec)

            _state.update {
                it.copy(
                    positionMs = positionMs,
                    durationMs = durationMs,
                    activeSkip = newActiveSkip
                )
            }
            _currentCue.value = subtitleEngine.currentCue(positionMs)
            checkAndTrackIfNeeded(positionMs, durationMs)

            if (durationMs > 0L && positionMs - lastSavedPositionMs >= 5_000L) {
                lastSavedPositionMs = positionMs
                episodes.getOrNull(currentEpisodeIndex)?.let { ep ->
                    if (mediaId.isNotEmpty()) {
                        val p = EpisodeProgress(ep.episode_number, positionMs, durationMs)
                        if (serviceKey == "simkl") watchHistoryStore.saveSimkl(mediaId, p)
                        else                       watchHistoryStore.saveAnilistMal(anilistId, malId, p)
                    }
                }
            }
        }
        override fun onBufferedChanged(bufferedMs: Long) = _state.update { it.copy(bufferedMs = bufferedMs) }
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean) = _state.update { it.copy(isPlaying = playWhenReady) }
        override fun onVideoSizeChanged(width: Int, height: Int)    = _state.update { it.copy(videoWidth = width, videoHeight = height) }
        override fun onError(message: String) { Log.e(TAG, "onError: $message"); _state.update { it.copy(error = message) } }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            Log.d(TAG, "onServiceConnected")
            service = IPlayerService.Stub.asInterface(binder).also { it.registerCallback(aidlCallback) }
            _state.update { it.copy(connected = true) }
            maybeStartPending()
        }
        override fun onServiceDisconnected(name: ComponentName) {
            Log.w(TAG, "onServiceDisconnected")
            service = null
            _state.update { it.copy(connected = false) }
        }
    }

    init {
        app.bindService(Intent(app, PlayerService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
    }

    // ── Track loading (new entry point) ────────────────────────────────────────

    /**
     * Called once per navigation event with the full track list from [PlayerArgs].
     *
     * Stream selection logic:
     *  1. Look for a previously saved quality name in SharedPreferences.
     *  2. If found in the new list → use it (quality persistence across sessions).
     *  3. Otherwise → fall back to [PlayerArgs.Snapshot.initialStreamIndex].
     */

    private var episodes: List<SEpisode> = emptyList()
    private var episodeMeta: Map<String, AniZipEpisodeMeta> = emptyMap()
    private var currentEpisodeIndex: Int = -1
    private var onLoadEpisodeVideos: (suspend (SEpisode) -> List<Video>)? = null
    fun loadTracks(snapshot: PlayerArgs.Snapshot) {
        val streams   = snapshot.streams
        val subtitles = snapshot.subtitleTracks

        val savedQuality = prefs.getString(PREF_QUALITY, null)
        val bestIdx = savedQuality
            ?.let { name -> streams.indexOfFirst { it.name == name }.takeIf { it >= 0 } }
            ?: snapshot.initialStreamIndex.coerceIn(0, (streams.size - 1).coerceAtLeast(0))

        val initialSubIdx = if (subtitles.isNotEmpty()) 0 else null

        _state.update {
            it.copy(
                title                 = snapshot.title,
                streams               = streams,
                selectedStreamIndex   = bestIdx,
                subtitleTracks        = subtitles,
                selectedSubtitleIndex = initialSubIdx,
                skipTimes = snapshot.skipTimes,
            )
        }

        if (streams.isNotEmpty()) {
            val track = streams[bestIdx]
            loadUri(track.url, track.headers)
        }
        initialSubIdx?.let { loadSubtitleByIndex(it) }

        episodes                 = snapshot.episodes
        currentEpisodeIndex      = snapshot.currentEpisodeIndex
        onLoadEpisodeVideos      = snapshot.onLoadEpisodeVideos
        fillerEpisodes           = snapshot.fillerEpisodes
        mediaId                  = snapshot.mediaId
        serviceKey               = snapshot.serviceKey
        anilistId                = snapshot.anilistId
        malId                    = snapshot.malId
        sessionTrackingEnabled   = false
        hasTrackedCurrentEpisode = false
        pendingResumeMs          = snapshot.resumePositionMs
        hasResumed               = false
        lastSavedPositionMs      = -1L
        episodeMeta              = snapshot.episodeMeta

        _state.update {
            it.copy(
                hasNextEpisode = currentEpisodeIndex in 0 until episodes.size - 1,
                hasPrevEpisode = currentEpisodeIndex > 0,
            )
        }
    }

    private fun checkAndTrackIfNeeded(positionMs: Long, durationMs: Long) {
        if (!sessionTrackingEnabled)  return
        if (hasTrackedCurrentEpisode) return
        if (durationMs <= 0L)         return
        val threshold = prefs.getInt("watched_threshold", 80) / 100f
        if (positionMs.toFloat() / durationMs < threshold) return

        hasTrackedCurrentEpisode = true
        if (mediaId.isNotEmpty()) {
            if (serviceKey == "simkl") watchHistoryStore.clearSimkl(mediaId)
            else                       watchHistoryStore.clearAnilistMal(anilistId, malId)
        }
        val episode = episodes.getOrNull(currentEpisodeIndex) ?: return
        viewModelScope.launch { _watchedEvent.emit(WatchedEvent(episode, mediaId)) }
    }

    private fun computeActiveSkip(positionSec: Int): ActiveSkip? {
        val times = _state.value.skipTimes ?: return null

        fun check(seg: SkipInterval?, label: String): ActiveSkip? {
            if (seg == null) return null
            if (positionSec >= seg.startSec && positionSec < seg.endSec)
                return ActiveSkip(label, seg.startSec, seg.endSec)
            return null
        }

        return check(times.op,      "Skip Opening")
            ?: check(times.mixedOp, "Skip Opening")
            ?: check(times.ed,      "Skip Ending")
            ?: check(times.mixedEd, "Skip Ending")
            ?: check(times.recap,   "Skip Recap")
    }

    fun navigateEpisode(delta: Int) {
        val targetIndex  = currentEpisodeIndex + delta
        val episode      = episodes.getOrNull(targetIndex) ?: return

        if (delta > 0 && episode.episode_number.toInt() in fillerEpisodes) {
            val nextNonFillerIndex = episodes.indexOfFirst { ep ->
                episodes.indexOf(ep) > targetIndex &&
                        ep.episode_number.toInt() !in fillerEpisodes
            }.takeIf { it >= 0 }
            _pendingDelta = delta
            _state.update {
                it.copy(
                    fillerWarning = FillerWarning(
                        targetEpisodeName  = episode.displayName(episodeMeta),
                        delta              = delta,
                        nextNonFillerIndex = nextNonFillerIndex,
                        nextNonFillerName  = nextNonFillerIndex?.let { idx ->
                            episodes.getOrNull(idx)?.displayName(episodeMeta)
                        },
                    )
                )
            }
            return
        }

        doNavigateEpisode(delta)
    }

    fun confirmFillerEpisode() {
        val delta = _state.value.fillerWarning?.delta ?: return
        _state.update { it.copy(fillerWarning = null) }
        doNavigateEpisode(delta)
    }

    fun skipToNextNonFiller() {
        val warning = _state.value.fillerWarning ?: return
        val targetIdx = warning.nextNonFillerIndex ?: return
        _state.update { it.copy(fillerWarning = null) }
        val delta = targetIdx - currentEpisodeIndex
        doNavigateEpisode(delta)
    }

    fun dismissFillerWarning() {
        _state.update { it.copy(fillerWarning = null) }
    }

    private fun doNavigateEpisode(delta: Int) {
        val targetIndex = currentEpisodeIndex + delta
        val episode     = episodes.getOrNull(targetIndex) ?: return
        val loader      = onLoadEpisodeVideos ?: return
        _pendingDelta = delta

        viewModelScope.launch {
            _state.update { it.copy(episodeNavigating = true) }
            runCatching { loader(episode) }
                .onSuccess { videos ->
                    val currentQuality = _state.value.streams
                        .getOrNull(_state.value.selectedStreamIndex)?.name
                    val matchIndex = videos.indexOfFirst { v ->
                        v.quality.ifBlank { "Stream" } == currentQuality
                    }
                    if (matchIndex != -1) {
                        loadEpisodeVideos(videos, matchIndex, episode, targetIndex)
                    } else {
                        _state.update {
                            it.copy(
                                episodeNavigating    = false,
                                pendingEpisodeVideos = videos,
                                pendingEpisodeName   = episode.displayName(episodeMeta),
                            )
                        }
                    }
                }
                .onFailure {
                    _state.update { it.copy(episodeNavigating = false) }
                }
        }
    }

    fun confirmPendingEpisodeStream(index: Int) {
        val videos      = _state.value.pendingEpisodeVideos
        val targetIndex = currentEpisodeIndex + _pendingDelta
        val episode     = episodes.getOrNull(targetIndex) ?: return
        _pendingDelta   = 0
        viewModelScope.launch {
            loadEpisodeVideos(videos, index, episode, targetIndex)
        }
    }

    fun dismissPendingEpisode() {
        _state.update { it.copy(pendingEpisodeVideos = emptyList()) }
    }

    private var _pendingDelta = 0

    private var fillerEpisodes: Set<Int> = emptySet()

    private fun loadEpisodeVideos(
        videos:      List<Video>,
        streamIndex: Int,
        episode:     SEpisode,
        newIndex:    Int,
    ) {
        val streams = videos.map { v ->
            StreamTrack(
                name    = v.quality.ifBlank { "Stream" },
                url     = v.url ?: v.videoUrl,
                headers = v.headers?.toMultimap()
                    ?.mapValues { it.value.firstOrNull() ?: "" }
                    ?: emptyMap(),
            )
        }
        val subs = videos
            .flatMap { it.subtitleTracks }
            .distinctBy { it.url }
            .map { SubtitleTrack(it.lang, it.url) }

        currentEpisodeIndex      = newIndex
        hasTrackedCurrentEpisode = false
        pendingResumeMs          = 0L
        hasResumed               = false
        lastSavedPositionMs      = -1L

        val initialSubIdx = if (subs.isNotEmpty()) 0 else null

        _state.update {
            it.copy(
                streams               = streams,
                subtitleTracks        = subs,
                selectedStreamIndex   = streamIndex,
                selectedSubtitleIndex = initialSubIdx,
                title                 = episode.displayName(episodeMeta),
                episodeNavigating     = false,
                hasNextEpisode        = newIndex in 0 until episodes.size - 1,
                hasPrevEpisode        = newIndex > 0,
                pendingEpisodeVideos  = emptyList(),
            )
        }

        selectStream(streamIndex)
        initialSubIdx?.let { loadSubtitleByIndex(it) } ?: run {
            subtitleEngine.clear()
            _currentCue.value = null
        }
    }

    /** Switch stream at runtime (e.g. from the in-player picker). Saves quality preference. */
    fun selectStream(index: Int) {
        val streams = _state.value.streams
        if (index !in streams.indices) return
        _state.update { it.copy(selectedStreamIndex = index) }
        prefs.edit().putString(PREF_QUALITY, streams[index].name).apply()
        loadUri(streams[index].url, streams[index].headers)
    }

    /** Switch subtitle track, or pass null to disable subtitles. */
    fun selectSubtitleTrack(index: Int?) {
        _state.update { it.copy(selectedSubtitleIndex = index) }
        if (index == null) {
            subtitleEngine.clear()
            _currentCue.value = null
        } else {
            loadSubtitleByIndex(index)
        }
    }

    // ── Readiness gate ─────────────────────────────────────────────────────────

    private fun loadUri(uri: String, headers: Map<String, String> = emptyMap()) {
        Log.d(TAG, "loadUri: $uri")
        pendingUri = uri
        pendingHeaders = headers
        maybeStartPending()
    }
    private var pendingHeaders: Map<String, String> = emptyMap()

    private fun maybeStartPending() {
        val svc = service ?: return
        if (!surfaceReady) return
        pendingSurface?.let { svc.setSurface(it) }
        val uri = pendingUri ?: return
        Log.d(TAG, "maybeStartPending: firing load($uri)")
        if (pendingHeaders.isEmpty()) {
            svc.load(uri)
        } else {
            val headersJson = org.json.JSONObject(pendingHeaders).toString()
            svc.loadWithHeaders(uri, headersJson)
        }
        pendingUri = null
        pendingHeaders = emptyMap()
    }

    // ── Playback commands ──────────────────────────────────────────────────────

    fun play()                     = service?.play()
    fun pause()                    = service?.pause()
    fun stop()                     = service?.stop()
    fun seekTo(ms: Long)           = service?.seekTo(ms)
    fun seekForward()              = service?.seekForward()
    fun seekBackward()             = service?.seekBackward()
    fun setSpeed(speed: Float)     = service?.setPlaybackSpeed(speed)
    fun togglePlayPause()          { if (_state.value.isPlaying) pause() else play() }

    // ── Surface management ─────────────────────────────────────────────────────

    fun setSurface(surface: Surface) {
        pendingSurface = surface
        service?.setSurface(surface)
        surfaceReady = true
        maybeStartPending()
    }

    fun clearSurface() {
        pendingSurface = null
        service?.clearSurface()
        surfaceReady = false
    }

    fun refreshPosition() {
        val s = service ?: return
        runCatching {
            _state.update { it.copy(positionMs = s.position, durationMs = s.duration, bufferedMs = s.bufferedPosition) }
        }
    }

    // ── Subtitle management ────────────────────────────────────────────────────

    private fun loadSubtitleByIndex(index: Int) {
        val url = _state.value.subtitleTracks.getOrNull(index)?.url ?: return
        viewModelScope.launch {
            val p = _subtitlePrefs.value
            lingvaTranslator = p.translateTo?.let { LingvaTranslator(baseUrl = p.lingvaBaseUrl, targetLang = it) }
            runCatching { subtitleEngine.load(url, lingvaTranslator) }
                .onFailure { Log.e(TAG, "subtitle load failed", it) }
        }
    }

    fun updateSubtitlePrefs(update: (SubtitlePrefs) -> SubtitlePrefs) {
        val new = update(_subtitlePrefs.value)
        _subtitlePrefs.value = new
        saveSubtitlePrefs(new)
        lingvaTranslator = new.translateTo?.let { LingvaTranslator(baseUrl = new.lingvaBaseUrl, targetLang = it) }
        // Re-load active track with updated translator
        _state.value.selectedSubtitleIndex?.let { loadSubtitleByIndex(it) }
    }

    // ── Persistence ────────────────────────────────────────────────────────────

    private fun loadSubtitlePrefs() = SubtitlePrefs(
        enabled       = prefs.getBoolean("sub_enabled",   true),
        fontSize      = prefs.getFloat("sub_size",        18f),
        bold          = prefs.getBoolean("sub_bold",      false),
        colorHex      = prefs.getString("sub_color",      "#FFFFFFFF") ?: "#FFFFFFFF",
        translateTo   = prefs.getString("sub_translate",  null),
        lingvaBaseUrl = prefs.getString("sub_lingva_url", "https://lingva.ml") ?: "https://lingva.ml",
        bigSkipSec    = prefs.getInt("big_skip_sec",      75),
    )

    private fun saveSubtitlePrefs(p: SubtitlePrefs) {
        prefs.edit().apply {
            putBoolean("sub_enabled",   p.enabled)
            putFloat("sub_size",        p.fontSize)
            putBoolean("sub_bold",      p.bold)
            putString("sub_color",      p.colorHex)
            putString("sub_translate",  p.translateTo)
            putString("sub_lingva_url", p.lingvaBaseUrl)
            putInt("big_skip_sec",      p.bigSkipSec)
            apply()
        }
    }

    // ── Cleanup ────────────────────────────────────────────────────────────────

    override fun onCleared() {
        runCatching { service?.unregisterCallback(aidlCallback) }
        getApplication<Application>().unbindService(serviceConnection)
        super.onCleared()
    }
}