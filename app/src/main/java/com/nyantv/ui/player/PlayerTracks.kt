package com.nyantv.ui.player

import com.nyantv.AniZipEpisodeMeta
import com.nyantv.EpisodeSkipTimes
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video

/** A single playable stream (e.g. "HD-1 1080p DUB"). */
data class StreamTrack(
    val name: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
)

/** A single external subtitle track (e.g. "English (OpenSubtitles)"). */
data class SubtitleTrack(val name: String, val url: String)

/**
 * Temporary argument holder for the player screen.
 *
 * NavController routes are strings, so passing a list of tracks through a
 * nav argument would require JSON encoding + URL escaping. Instead callers
 * populate this object immediately before calling navController.navigate("player"),
 * and PlayerScreen reads + clears it on first composition.
 */
object PlayerArgs {
    var streams:            List<StreamTrack>   = emptyList()
    var subtitleTracks:     List<SubtitleTrack> = emptyList()
    var initialStreamIndex: Int                 = 0
    var title:              String              = ""
    var mediaId:            String              = ""
    var resumePositionMs:   Long                = 0L
    var serviceKey:         String              = "anilist_mal"
    var anilistId:          String?             = null
    var malId:              String?             = null

    var episodes: List<SEpisode> = emptyList()
    var currentEpisodeIndex: Int = -1
    var onLoadEpisodeVideos: (suspend (SEpisode) -> List<Video>)? = null
    var fillerEpisodes: Set<Int> = emptySet()
    var skipTimes:           EpisodeSkipTimes?   = null
    var episodeMeta: Map<String, AniZipEpisodeMeta> = emptyMap()

    fun consume(): Snapshot {
        val snapshot = Snapshot(
            streams, subtitleTracks, initialStreamIndex, title,
            mediaId, resumePositionMs, serviceKey, anilistId, malId,
            episodes, currentEpisodeIndex, onLoadEpisodeVideos, fillerEpisodes, skipTimes, episodeMeta,
        )
        clear()
        return snapshot
    }

    private fun clear() {
        streams             = emptyList()
        subtitleTracks      = emptyList()
        initialStreamIndex  = 0
        title               = ""
        mediaId             = ""
        resumePositionMs    = 0L
        serviceKey          = "anilist_mal"
        anilistId           = null
        malId               = null
        episodes            = emptyList()
        currentEpisodeIndex = -1
        onLoadEpisodeVideos = null
        fillerEpisodes      = emptySet()
        skipTimes           = null
        episodeMeta         = emptyMap()
    }

    data class Snapshot(
        val streams:             List<StreamTrack>,
        val subtitleTracks:      List<SubtitleTrack>,
        val initialStreamIndex:  Int,
        val title:               String,
        val mediaId:             String                               = "",
        val resumePositionMs:    Long                                 = 0L,
        val serviceKey:          String                               = "anilist_mal",
        val anilistId:           String?                              = null,
        val malId:               String?                              = null,
        val episodes:            List<SEpisode>                       = emptyList(),
        val currentEpisodeIndex: Int                                  = -1,
        val onLoadEpisodeVideos: (suspend (SEpisode) -> List<Video>)? = null,
        val fillerEpisodes:      Set<Int>                             = emptySet(),
        val skipTimes:           EpisodeSkipTimes?                    = null,
        val episodeMeta:         Map<String, AniZipEpisodeMeta>       = emptyMap()
    )
}