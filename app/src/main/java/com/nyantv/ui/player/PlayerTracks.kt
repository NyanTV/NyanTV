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

/**
 * A single subtitle track grouped by language name.
 *
 * Multiple [urls] exist when the same language is offered by different CDN
 * origins. The ViewModel picks the best URL at
 * load time by matching the origin domain of the currently active stream,
 * so switching CDN automatically picks a subtitle URL that won't be Cloudflare-blocked.
 */
data class SubtitleTrack(
    val name: String,
    val urls: List<SubtitleUrl>,
) {
    /** One concrete subtitle URL together with the CDN domain it came from. */
    data class SubtitleUrl(
        val url: String,
        val streamDomain: String,
    )

    /**
     * Picks the best URL for [currentStreamUrl].
     * Preference order:
     *  1. Same domain as the current stream
     *  2. First available URL as fallback
     */
    fun bestUrlFor(currentStreamUrl: String): String? {
        val domain = extractDomain(currentStreamUrl)
        return urls.firstOrNull { it.streamDomain == domain }?.url
            ?: urls.firstOrNull()?.url
    }
}

/** Extracts the registrable host from a URL string. */
fun extractDomain(url: String): String = runCatching {
    val host = java.net.URI(url).host ?: return@runCatching ""
    val parts = host.split(".")
    if (parts.size >= 2) parts.takeLast(2).joinToString(".") else host
}.getOrDefault("")

fun extractUrlPath(url: String): String = runCatching {
    val path = java.net.URI(url).rawPath ?: java.net.URI(url).path
    if (path.isNullOrBlank()) url else path
}.getOrDefault(url)

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
    var seriesTitle:        String              = ""
    var mediaId:            String              = ""
    var resumePositionMs:   Long                = 0L
    var serviceKey:         String              = "anilist_mal"
    var anilistId:          String?             = null
    var malId:              String?             = null

    var episodes: List<SEpisode> = emptyList()
    var currentEpisodeIndex: Int = -1
    var onLoadEpisodeVideos: (suspend (SEpisode) -> List<Video>)? = null
    var onLoadSkipTimes:     (suspend (SEpisode) -> EpisodeSkipTimes?)? = null
    var fillerEpisodes: Set<Int> = emptySet()
    var skipTimes:           EpisodeSkipTimes?   = null
    var episodeMeta: Map<String, AniZipEpisodeMeta> = emptyMap()
    var mediaCoverUrl:  String = ""
    var mediaBannerUrl: String = ""
    var mediaPosterUrl: String = ""

    fun consume(): Snapshot {
        val snapshot = Snapshot(
            streams = streams,
            subtitleTracks = subtitleTracks,
            initialStreamIndex = initialStreamIndex,
            title = title,
            seriesTitle = seriesTitle,
            mediaId = mediaId,
            resumePositionMs = resumePositionMs,
            serviceKey = serviceKey,
            anilistId = anilistId,
            malId = malId,
            episodes = episodes,
            currentEpisodeIndex = currentEpisodeIndex,
            onLoadEpisodeVideos = onLoadEpisodeVideos,
            onLoadSkipTimes = onLoadSkipTimes,
            fillerEpisodes = fillerEpisodes,
            skipTimes = skipTimes,
            episodeMeta = episodeMeta,
            mediaCoverUrl = mediaCoverUrl,
            mediaBannerUrl = mediaBannerUrl,
            mediaPosterUrl = mediaPosterUrl,
        )
        clear()
        return snapshot
    }

    private fun clear() {
        streams             = emptyList()
        subtitleTracks      = emptyList()
        initialStreamIndex  = 0
        title               = ""
        seriesTitle         = ""
        mediaId             = ""
        resumePositionMs    = 0L
        serviceKey          = "anilist_mal"
        anilistId           = null
        malId               = null
        episodes            = emptyList()
        currentEpisodeIndex = -1
        onLoadEpisodeVideos = null
        onLoadSkipTimes     = null
        fillerEpisodes      = emptySet()
        skipTimes           = null
        episodeMeta         = emptyMap()
        mediaCoverUrl       = ""
        mediaBannerUrl      = ""
        mediaPosterUrl      = ""
    }

    data class Snapshot(
        val streams:             List<StreamTrack>,
        val subtitleTracks:      List<SubtitleTrack>,
        val initialStreamIndex:  Int,
        val title:               String,
        val seriesTitle:               String,
        val mediaId:             String                               = "",
        val resumePositionMs:    Long                                 = 0L,
        val serviceKey:          String                               = "anilist_mal",
        val anilistId:           String?                              = null,
        val malId:               String?                              = null,
        val episodes:            List<SEpisode>                       = emptyList(),
        val currentEpisodeIndex: Int                                  = -1,
        val onLoadEpisodeVideos: (suspend (SEpisode) -> List<Video>)? = null,
        val onLoadSkipTimes:     (suspend (SEpisode) -> EpisodeSkipTimes?)? = null,
        val fillerEpisodes:      Set<Int>                             = emptySet(),
        val skipTimes:           EpisodeSkipTimes?                    = null,
        val episodeMeta:         Map<String, AniZipEpisodeMeta>       = emptyMap(),
        val mediaCoverUrl:  String = "",
        val mediaBannerUrl: String = "",
        val mediaPosterUrl: String = "",
    )
}