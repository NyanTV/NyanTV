package com.nyantv.player

import android.content.Context
import android.util.Log
import android.view.Surface
import dev.jdtech.mpv.MPVLib

class MpvPlayerWrapper(private val context: Context) {

    companion object {
        private const val TAG = "NyanTV:MpvWrapper"
        private const val POSITION_UPDATE_THROTTLE_MS = 500L
    }

    interface Listener {
        fun onStateChanged(state: Int)
        fun onPositionChanged(posMs: Long, durMs: Long)
        fun onBufferedChanged(bufferedMs: Long)
        fun onVideoSizeChanged(width: Int, height: Int)
        fun onError(message: String)
        fun onPlayWhenReadyChanged(playWhenReady: Boolean)
    }

    var listener: Listener? = null
    private var durationMs: Long = 0L
    private var lib: MPVLib? = null

    @Volatile private var lastPositionEmitMs: Long = 0L
    @Volatile private var isLoading = false
    @Volatile private var hasShownFirstFrame = false

    private val observer = object : MPVLib.EventObserver {

        override fun eventProperty(property: String) {}

        override fun eventProperty(property: String, value: Long) {
            when (property) {
                "time-pos" -> {
                    val now = System.currentTimeMillis()
                    if (now - lastPositionEmitMs >= POSITION_UPDATE_THROTTLE_MS) {
                        lastPositionEmitMs = now
                        listener?.onPositionChanged(value * 1000L, durationMs)
                    }
                }
                "duration" -> durationMs = value * 1000L
                "demuxer-cache-time" -> {
                    val pos = lib?.getPropertyDouble("time-pos") ?: 0.0
                    listener?.onBufferedChanged(
                        ((pos * 1000).toLong() + value * 1000L)
                            .coerceAtMost((pos * 1000).toLong() + 120_000L)
                            .coerceAtMost(durationMs)
                    )
                }
            }
        }

        override fun eventProperty(property: String, value: Double) {
            when (property) {
                "time-pos" -> {
                    val now = System.currentTimeMillis()
                    if (now - lastPositionEmitMs >= POSITION_UPDATE_THROTTLE_MS) {
                        lastPositionEmitMs = now
                        listener?.onPositionChanged((value * 1000).toLong(), durationMs)
                    }
                }
                "duration" -> durationMs = (value * 1000).toLong()
                "demuxer-cache-time" -> {
                    val pos = lib?.getPropertyDouble("time-pos") ?: 0.0
                    listener?.onBufferedChanged(
                        ((pos + value) * 1000).toLong()
                            .coerceAtMost((pos * 1000).toLong() + 120_000L)
                            .coerceAtMost(durationMs)
                    )
                }
            }
        }

        override fun eventProperty(property: String, value: Boolean) {
            when (property) {
                "pause"            -> listener?.onPlayWhenReadyChanged(!value)
                "paused-for-cache" -> listener?.onStateChanged(if (value) 2 else 3)
            }
        }
        override fun eventProperty(property: String, value: String) {}

        override fun event(eventId: Int) {
            when (eventId) {
                MPVLib.MpvEvent.MPV_EVENT_START_FILE -> {
                    isLoading = true
                    hasShownFirstFrame = false
                    listener?.onStateChanged(2)
                }
                MPVLib.MpvEvent.MPV_EVENT_PLAYBACK_RESTART -> {
                    isLoading = false
                    listener?.onStateChanged(3)
                }
                MPVLib.MpvEvent.MPV_EVENT_END_FILE -> listener?.onStateChanged(4)
                MPVLib.MpvEvent.MPV_EVENT_VIDEO_RECONFIG -> {
                    val w = lib?.getPropertyInt("width")  ?: 0
                    val h = lib?.getPropertyInt("height") ?: 0
                    if (w > 0 && h > 0) {
                        hasShownFirstFrame = true
                        listener?.onVideoSizeChanged(w, h)
                    } else if (!isLoading && hasShownFirstFrame) {
                        Log.w(TAG, "Unexpected empty video size outside of load, VO likely lost")
                        attemptSurfaceRecovery()
                    }
                    // w/h=0 while isLoading is the normal startup transient
                }
            }
        }
    }

    private fun attemptSurfaceRecovery() {
        val surface = attachedSurface ?: return
        lib?.detachSurface()
        lib?.attachSurface(surface)
        lib?.setOptionString("force-window", "yes")
        lib?.setOptionString("vo", "gpu")
    }

    fun initialize() {
        lib = MPVLib.create(context) ?: return Unit.also { Log.e(TAG, "MPVLib.create() returned null") }
        lib!!.apply {
            setOptionString("network-timeout",        "15")
            setOptionString("cache",                  "yes")
            setOptionString("cache-secs",             "120")
            setOptionString("demuxer-max-bytes",      "100MiB")
            setOptionString("demuxer-max-back-bytes", "20MiB")
            setOptionString("demuxer-readahead-secs", "120")
            setOptionString("hwdec",                  "auto-safe")
            setOptionString("vo",                     "gpu")
            setOptionString("ao",                     "audiotrack")
            setOptionString("keep-open",              "yes")
            init()

            addObserver(observer)
            observeProperty("time-pos",                   MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
            observeProperty("duration",                   MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
            observeProperty("demuxer-cache-time",         MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
            observeProperty("pause",                      MPVLib.MpvFormat.MPV_FORMAT_FLAG)
            observeProperty("paused-for-cache",           MPVLib.MpvFormat.MPV_FORMAT_FLAG)
        }
    }

    private var attachedSurface: Surface? = null

    fun attachSurface(surface: Surface) {
        lib?.detachSurface()
        lib?.attachSurface(surface)
        lib?.setOptionString("force-window", "yes")
        lib?.setOptionString("vo", "gpu")
        attachedSurface = surface
    }

    fun detachSurface() {
        lib?.detachSurface()
        attachedSurface = null
    }

    fun load(uri: String, headers: Map<String, String> = emptyMap(), startPositionMs: Long = 0L) {
        val l = lib ?: return

        val forceHighest = context
            .getSharedPreferences("nyantv_player_prefs", Context.MODE_PRIVATE)
            .getString("quality_mode", "abr") == "highest"
        l.setOptionString("hls-bitrate", if (forceHighest) "max" else "no")

        if (headers.isNotEmpty())
            l.setOptionString("http-header-fields",
                headers.entries.joinToString("\r\n") { "${it.key}: ${it.value}" })
        if (startPositionMs > 0L)
            l.setOptionString("start", (startPositionMs / 1000.0).toString())

        l.command(arrayOf("loadfile", uri))
    }

    fun play()  { lib?.setPropertyBoolean("pause", false) }
    fun pause() { lib?.setPropertyBoolean("pause", true) }
    fun stop()  { lib?.command(arrayOf("stop")) }

    fun seekTo(positionMs: Long) {
        lib?.command(arrayOf("seek", (positionMs / 1000.0).toString(), "absolute"))
        listener?.onPositionChanged(positionMs, durationMs)
    }

    fun seekForward()  { lib?.command(arrayOf("seek",  "10", "relative+keyframes")) }
    fun seekBackward() { lib?.command(arrayOf("seek", "-10", "relative+keyframes")) }
    fun setPlaybackSpeed(s: Float){ lib?.setPropertyDouble("speed", s.toDouble()) }

    fun getCurrentPosition(): Long = ((lib?.getPropertyDouble("time-pos") ?: 0.0) * 1000).toLong()
    fun getDuration():        Long = durationMs
    fun getBufferedPosition(): Long {
        val pos   = lib?.getPropertyDouble("time-pos")           ?: 0.0
        val cache = lib?.getPropertyDouble("demuxer-cache-time") ?: 0.0
        return ((pos + cache) * 1000).toLong()
            .coerceAtMost((pos * 1000).toLong() + 120_000L)
            .coerceAtMost(durationMs)
    }
    fun isPlaying(): Boolean = !(lib?.getPropertyBoolean("pause") ?: true)

    fun release() {
        lib?.removeObserver(observer)
        lib?.destroy()
        lib = null
    }
}