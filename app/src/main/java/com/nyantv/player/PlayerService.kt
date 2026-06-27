package com.nyantv.player

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.common.C

@UnstableApi
class PlayerService : Service() {

    // ── WakeLock ───────────────────────────────────────────────────────────
    private var wakeLock: PowerManager.WakeLock? = null

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE,
            "NyanTV:PlaybackWakeLock"
        ).apply { setReferenceCounted(false) }
        wakeLock?.acquire(6 * 60 * 60 * 1000L)
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
    }

    companion object { private const val TAG = "NyanTV:PlayerService" }

    // ── Threads & handlers ─────────────────────────────────────────────────────
    private lateinit var playerThread: HandlerThread
    private lateinit var playerHandler: Handler

    // ── ExoPlayer ──────────────────────────────────────────────────────────────
    private lateinit var player: ExoPlayer
    private lateinit var trackSelector: DefaultTrackSelector

    // ── MPV ────────────────────────────────────────────────────────────────────
    private var mpv: MpvPlayerWrapper? = null
    private var usingMpv = false
    private var currentSurface: Surface? = null

    // ── Callbacks ──────────────────────────────────────────────────────────────
    private val callbacks = RemoteCallbackList<IPlayerCallback>()
    private var positionTick: Runnable? = null

    // ── Helpers ────────────────────────────────────────────────────────────────
    @Volatile private var lastKnownPositionMs: Long = 0L
    @Volatile private var lastKnownDurationMs: Long = 0L
    @Volatile private var lastKnownBufferedMs: Long = 0L
    @Volatile private var lastKnownIsPlaying: Boolean = false
    @Volatile private var lastKnownPlaybackState: Int = Player.STATE_IDLE

    private fun ensureMpv() {
        if (mpv != null) return
        mpv = MpvPlayerWrapper(this).also { m ->
            m.initialize()
            m.listener = object : MpvPlayerWrapper.Listener {
                override fun onStateChanged(state: Int)                  = broadcast { it.onStateChanged(state) }
                override fun onPositionChanged(posMs: Long, durMs: Long) {
                    lastKnownPositionMs = posMs
                    lastKnownDurationMs = durMs
                    broadcast { it.onPositionChanged(posMs, durMs) }
                }
                override fun onBufferedChanged(bufferedMs: Long) {
                    lastKnownBufferedMs = bufferedMs
                    broadcast { it.onBufferedChanged(bufferedMs) }
                }
                override fun onVideoSizeChanged(w: Int, h: Int)          = broadcast { it.onVideoSizeChanged(w, h) }
                override fun onError(message: String)                    = broadcast { it.onError(message) }
                override fun onPlayWhenReadyChanged(play: Boolean) {
                    lastKnownIsPlaying = play
                    broadcast { it.onPlayWhenReadyChanged(play) }
                }
            }
        }
    }

    private fun useMpv(): Boolean =
        getSharedPreferences("nyantv_player_prefs", Context.MODE_PRIVATE)
            .getString("player_engine", "exoplayer") == "libmpv"

    // ── AIDL stub ──────────────────────────────────────────────────────────────
    private val stub = object : IPlayerService.Stub() {

        override fun load(uri: String, startPositionMs: Long) {
            post {
                val toMpv = useMpv()
                prepareEngine(toMpv)

                if (toMpv) {
                    ensureMpv()
                    currentSurface?.let { mpv?.attachSurface(it) }
                    mpv?.load(uri = uri, startPositionMs = startPositionMs)
                } else {
                    val mediaItem = MediaItem.Builder()
                        .setUri(uri)
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(startPositionMs)
                                .build()
                        )
                        .build()
                    player.setMediaItem(mediaItem)
                    player.prepare()
                    player.playWhenReady = true
                }
            }
        }

        override fun loadWithHeaders(uri: String, headersJson: String, startPositionMs: Long) {
            post {
                val headers = runCatching {
                    org.json.JSONObject(headersJson).let { j ->
                        j.keys().asSequence().associateWith { j.getString(it) }
                    }
                }.getOrDefault(emptyMap())

                val toMpv = useMpv()
                prepareEngine(toMpv)

                if (toMpv) {
                    usingMpv = true
                    ensureMpv()
                    currentSurface?.let { mpv?.attachSurface(it) }
                    mpv?.load(uri = uri, headers = headers, startPositionMs = startPositionMs)
                } else {
                    usingMpv = false
                    val dataSourceFactory = androidx.media3.datasource.DefaultHttpDataSource.Factory()
                        .setUserAgent(headers["User-Agent"] ?: "Mozilla/5.0")
                        .setDefaultRequestProperties(headers)
                        .setConnectTimeoutMs(15_000)
                        .setReadTimeoutMs(15_000)
                        .setAllowCrossProtocolRedirects(true)

                    val errorPolicy = object : DefaultLoadErrorHandlingPolicy() {
                        override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long =
                            if (loadErrorInfo.errorCount <= 5) 1_000L else C.TIME_UNSET
                        override fun getMinimumLoadableRetryCount(dataType: Int) = 5
                    }

                    val mediaSourceFactory = androidx.media3.exoplayer.source.DefaultMediaSourceFactory(dataSourceFactory)
                        .setLoadErrorHandlingPolicy(errorPolicy)

                    val mediaItem = MediaItem.Builder()
                        .setUri(uri)
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(startPositionMs)
                                .build()
                        )
                        .build()

                    val forceHighest = getSharedPreferences("nyantv_player_prefs", Context.MODE_PRIVATE)
                        .getString("quality_mode", "abr") == "highest"
                    trackSelector.setParameters(
                        trackSelector.buildUponParameters()
                            .setForceHighestSupportedBitrate(forceHighest)
                    )
                    player.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem))
                    player.prepare()
                    player.playWhenReady = true
                }
            }
        }

        override fun play() = post {
            acquireWakeLock()
            if (usingMpv) mpv?.play() else player.play()
        }

        override fun pause() = post {
            releaseWakeLock()
            if (usingMpv) mpv?.pause() else player.pause()
        }

        override fun stop() = post {
            releaseWakeLock()
            if (usingMpv) mpv?.stop()
            else { player.stop(); player.clearMediaItems() }
        }

        override fun seekTo(positionMs: Long)       = post { if (usingMpv) mpv?.seekTo(positionMs)      else player.seekTo(positionMs) }
        override fun seekForward()                  = post { if (usingMpv) mpv?.seekForward()            else player.seekForward() }
        override fun seekBackward()                 = post { if (usingMpv) mpv?.seekBackward()           else player.seekBack() }
        override fun setPlaybackSpeed(speed: Float) = post { if (usingMpv) mpv?.setPlaybackSpeed(speed) else player.setPlaybackSpeed(speed) }

        override fun setSurface(surface: Surface?) {
            Log.d(TAG, "setSurface: $surface")
            currentSurface = surface
            post {
                if (usingMpv) surface?.let { mpv?.attachSurface(it) } ?: mpv?.detachSurface()
                else player.setVideoSurface(surface)
            }
        }

        override fun clearSurface() = post {
            currentSurface = null
            if (usingMpv) {
                mpv?.detachSurface()
                mpv?.stop()
                mpv?.release()
                mpv = null
                usingMpv = false
            } else {
                player.clearVideoSurface()
            }
        }

        override fun registerCallback(cb: IPlayerCallback?) {
            cb?.let {
                callbacks.register(it)
                Log.d(TAG, "registerCallback — total=${callbacks.registeredCallbackCount}")
            }
        }

        override fun unregisterCallback(cb: IPlayerCallback?) {
            cb?.let { callbacks.unregister(it) }
        }

        private fun <T> runOnPlayerThread(block: () -> T): T {
            if (Looper.myLooper() == playerThread.looper) return block()
            val task = java.util.concurrent.FutureTask(block)
            playerHandler.post(task)
            return runCatching {
                task.get(500, java.util.concurrent.TimeUnit.MILLISECONDS)
            }.getOrThrow()
        }

        override fun getPosition()         = lastKnownPositionMs
        override fun getDuration()         = lastKnownDurationMs
        override fun getBufferedPosition() = lastKnownBufferedMs
        override fun getState()            = if (usingMpv) 3 else lastKnownPlaybackState
        override fun getPlayWhenReady()    = lastKnownIsPlaying
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")

        playerThread = HandlerThread("ExoPlayerThread", Process.THREAD_PRIORITY_AUDIO)
            .also { it.start() }
        playerHandler = Handler(playerThread.looper)

        trackSelector = DefaultTrackSelector(this)
        player = ExoPlayer.Builder(this)
            .setLooper(playerThread.looper)
            .setTrackSelector(trackSelector)
            .setLoadControl(AdaptiveBufferingHelper.buildLoadControl(this))
            .build()
            .also { it.addListener(playerListener) }

        Log.d(TAG, "ExoPlayer ready on thread: ${playerThread.name}")

        schedulePositionTicks()
    }

    override fun onBind(intent: Intent): IBinder {
        Log.d(TAG, "onBind")
        return stub
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")

        positionTick?.let { playerHandler.removeCallbacks(it) }

        mpv?.release()
        mpv = null
        releaseWakeLock()

        playerHandler.post {
            player.removeListener(playerListener)
            player.release()
            playerThread.quitSafely()
        }

        callbacks.kill()
        super.onDestroy()
    }

    // ── ExoPlayer listener ─────────────────────────────────────────────────────

    private val playerListener = object : Player.Listener {

        override fun onPlaybackStateChanged(state: Int) {
            if (usingMpv) return
            lastKnownPlaybackState = state
            Log.d(TAG, "onPlaybackStateChanged: $state")
            broadcast { it.onStateChanged(state) }
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (usingMpv) return
            lastKnownIsPlaying = playWhenReady
            Log.d(TAG, "onPlayWhenReadyChanged: $playWhenReady")
            broadcast { it.onPlayWhenReadyChanged(playWhenReady) }
        }

        override fun onPlayerError(error: PlaybackException) {
            if (usingMpv) return
            Log.e(TAG, "onPlayerError: ${error.errorCode} — ${error.localizedMessage}", error)
            broadcast { it.onError(error.localizedMessage ?: "Playback error") }
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (usingMpv) return
            Log.d(TAG, "onVideoSizeChanged: ${videoSize.width}x${videoSize.height}")
            broadcast { it.onVideoSizeChanged(videoSize.width, videoSize.height) }
        }

        override fun onPositionDiscontinuity(
            oldPos: Player.PositionInfo,
            newPos: Player.PositionInfo,
            reason: Int
        ) {
            if (usingMpv) return
            if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                val pos = player.currentPosition
                val dur = player.duration
                val buf = player.bufferedPosition
                lastKnownPositionMs = pos
                lastKnownDurationMs = dur
                lastKnownBufferedMs = buf
                Log.d(TAG, "seek discontinuity → pos=$pos")
                broadcast { cb ->
                    cb.onPositionChanged(pos, dur)
                    cb.onBufferedChanged(buf)
                }
            }
        }
    }

    // ── Position ticks ─────────────────────────────────────────────────────────

    private fun schedulePositionTicks() {
        positionTick = object : Runnable {
            override fun run() {
                if (!usingMpv) {
                    val state = player.playbackState
                    if (state == Player.STATE_READY || state == Player.STATE_BUFFERING) {
                        val pos = player.currentPosition
                        val dur = player.duration
                        val buf = player.bufferedPosition
                        lastKnownPositionMs = pos
                        lastKnownDurationMs = dur
                        lastKnownBufferedMs = buf
                        broadcast {
                            it.onPositionChanged(pos, dur)
                            it.onBufferedChanged(buf)
                        }
                    }
                }
                playerHandler.postDelayed(this, 500L)
            }
        }
        playerHandler.postDelayed(positionTick!!, 500L)
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun broadcast(action: (IPlayerCallback) -> Unit) {
        val n = callbacks.beginBroadcast()
        repeat(n) { i -> runCatching { action(callbacks.getBroadcastItem(i)) } }
        callbacks.finishBroadcast()
    }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == playerThread.looper) block()
        else playerHandler.post(block)
    }

    private fun prepareEngine(targetUsesMpv: Boolean) {
        if (usingMpv == targetUsesMpv) return
        if (usingMpv) {
            mpv?.stop()
            mpv?.detachSurface()
            mpv?.release()
            mpv = null
        } else {
            player.stop()
            player.clearMediaItems()
        }
        usingMpv = targetUsesMpv
    }
}