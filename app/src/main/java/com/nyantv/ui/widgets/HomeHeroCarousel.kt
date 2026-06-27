package com.nyantv.ui.widgets

import androidx.compose.animation.core.animateFloatAsState
import coil.compose.AsyncImagePainter
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.nyantv.BuildConfig
import com.nyantv.data.Media
import com.nyantv.data.ServiceType
import com.nyantv.ui.utils.focusBorder
import com.nyantv.viewmodel.AppViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

@Composable
fun HomeHeroCarousel(
    items: List<Media>,
    onItemClick: (Media) -> Unit,
    vm: AppViewModel,
    modifier: Modifier = Modifier
) {
    if (items.isEmpty()) return

    val pagerState = rememberPagerState(pageCount = { items.size })
    val logos     by vm.carouselLogos.collectAsStateWithLifecycle()
    val backdrops by vm.carouselBackdrops.collectAsStateWithLifecycle()
    var isFocused by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(items) {
        if (items.any { it.serviceType == ServiceType.MAL }) {
            vm.prefetchAnilistBanners(items)
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(220.dp)
            .clip(RoundedCornerShape(16.dp))
            .onFocusChanged { isFocused = it.isFocused || it.hasFocus }
            .focusBorder(RoundedCornerShape(16.dp), inset = true, color = MaterialTheme.colorScheme.primary, isFocused = isFocused)
    ) {
        HorizontalPager(
            state    = pagerState,
            key      = { items[it].id },
            modifier = Modifier.fillMaxSize()
        ) { page ->
            val media = items[page]
            val logoUrl = logos[media.id]
            val coverUrl = if (media.serviceType == ServiceType.MAL) {
                vm.getAnilistBanner(media) ?: media.cover ?: media.poster
            } else {
                media.cover ?: media.poster
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication        = null,
                        onClick           = { onItemClick(media) }
                    )
            ) {
                AsyncImage(
                    model = backdrops[media.id] ?: coverUrl,
                    contentDescription = media.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                listOf(
                                    Color.Black.copy(alpha = 0.2f),
                                    Color.Black.copy(alpha = 0.35f),
                                    Color.Black.copy(alpha = 0.85f)
                                )
                            )
                        )
                )

                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    TitleOrLogo(media = media, logoUrl = logoUrl)
                    CarouselStats(media = media)
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 10.dp, top = 8.dp, bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            repeat(items.size) { index ->
                val selected = index == pagerState.currentPage
                Box(
                    modifier = Modifier
                        .width(4.dp)
                        .height(if (selected) 20.dp else 8.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(
                            if (selected) MaterialTheme.colorScheme.primary
                            else Color.White.copy(alpha = 0.45f)
                        )
                )
            }
        }
    }
}

@Composable
private fun TitleOrLogo(media: Media, logoUrl: String?) {
    var logoLoaded by remember(media.id, logoUrl) { mutableStateOf(false) }
    val logoAlpha by animateFloatAsState(targetValue = if (logoLoaded) 1f else 0f, label = "logoAlpha")

    Box(modifier = Modifier.heightIn(min = 32.dp, max = 55.dp)) {
        Text(
            text = media.title,
            style = MaterialTheme.typography.titleLarge,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.CenterStart)
                .graphicsLayer { alpha = 1f - logoAlpha }
        )

        if (!logoUrl.isNullOrBlank()) {
            AsyncImage(
                model = logoUrl,
                contentDescription = media.title,
                contentScale = ContentScale.Fit,
                alignment = Alignment.CenterStart,
                onState = { state ->
                    logoLoaded = state is AsyncImagePainter.State.Success
                },
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .heightIn(max = 55.dp)
                    .widthIn(max = 280.dp)
                    .wrapContentWidth(Alignment.Start)
                    .graphicsLayer { alpha = logoAlpha }
            )
        }
    }
}

@Composable
private fun CarouselStats(media: Media) {
    val items = buildList {
        media.episodes?.takeIf { it > 0 }?.let { add("$it EP") }
        media.status?.let { add(normalizeLabel(it)) }
        media.format?.let { add(normalizeLabel(it)) }
        seasonLabel(media)?.let { add(it) }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        items.take(4).forEach { label ->
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
                shape = RoundedCornerShape(6.dp)
            ) {
                Text(
                    text = label,
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
        }
        media.averageScore?.takeIf { it > 0 }?.let { score ->
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.75f),
                shape = RoundedCornerShape(6.dp)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = "%.1f".format(score / 10f),
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall
                    )
                    Icon(
                        imageVector = Icons.Filled.Star,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(10.dp)
                    )
                }
            }
        }
    }
}

private fun normalizeLabel(value: String): String {
    val normalized = value.replace('_', ' ').trim()
    return when (normalized.uppercase()) {
        "TV" -> "TV"
        else -> normalized.lowercase().replaceFirstChar { it.uppercase() }
    }
}

private fun seasonLabel(media: Media): String? {
    val season = media.season?.let(::normalizeLabel)
    val year = media.seasonYear
    return when {
        season != null && year != null -> "$season $year"
        season != null -> season
        year != null -> year.toString()
        else -> null
    }
}

internal object CarouselLogoResolver {
    private val http = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val cache = mutableMapOf<String, String?>()
    private val tmdbRegex = Regex("https://image\\.tmdb\\.org/t/p/original[^\"'\\\\ ]+")

    suspend fun resolve(media: Media): String? = withContext(Dispatchers.IO) {
        val cacheKey = "${media.serviceType}:${media.id}:${media.idMal}:${media.tmdbId}"
        if (cache.containsKey(cacheKey)) return@withContext cache[cacheKey]

        val logo = when (media.serviceType) {
            ServiceType.ANILIST -> fromAniZip("anilist_id", media.id)
                ?: fromAniZip("anilistId", media.id)
            ServiceType.MAL -> {
                val malId = media.idMal ?: media.id
                coroutineScope {
                    val a = async { fromAniZip("mal_id", malId) }
                    val b = async { fromAniZip("malId", malId) }
                    a.await() ?: b.await()
                }
            }
            ServiceType.SIMKL -> fromTmdb(media.tmdbId, media.format == "MOVIE")
        }

        cache[cacheKey] = logo
        logo
    }

    private fun fromAniZip(key: String, id: String): String? {
        if (id.isBlank()) return null
        val endpoints = listOf(
            "https://api.ani.zip/mappings?$key=$id",
            "https://api.ani.zip/anime/$id"
        )
        endpoints.forEach { url ->
            getJson(url)?.let { jsonElement ->
                extractLogoUrl(jsonElement)?.let { return "https://wsrv.nl/?url=$it" }
            }
        }
        return null
    }

    private fun fromTmdb(tmdbId: String?, isMovie: Boolean): String? {
        if (tmdbId.isNullOrBlank()) {
            android.util.Log.w("CarouselLogo", "fromTmdb: tmdbId is null/blank")
            return null
        }
        val apiKey = BuildConfig.TMDB_API_KEY.takeIf { it.isNotBlank() } ?: run {
            android.util.Log.e("CarouselLogo", "fromTmdb: TMDB_API_KEY is missing")
            return null
        }
        val type = if (isMovie) "movie" else "tv"
        val url = "https://api.themoviedb.org/3/$type/$tmdbId/images?api_key=$apiKey&include_image_language=en,null"

        val result = getJson(url)?.let { extractTmdbLogoPath(it) }
            ?.let { "https://wsrv.nl/?url=https://image.tmdb.org/t/p/original$it" }

        android.util.Log.d("CarouselLogo", "fromTmdb: tmdbId=$tmdbId type=$type → $result")
        return result
    }

    private fun extractTmdbLogoPath(element: JsonElement): String? {
        val logos = (element as? JsonObject)?.get("logos") as? JsonArray ?: return null
        val items = logos.filterIsInstance<JsonObject>()

        return (items.firstOrNull { it.isEnglishLogo() && it.isPng() }
            ?: items.firstOrNull { it.isEnglishLogo() }
            ?: items.firstOrNull())
            ?.get("file_path")
            ?.let { it as? JsonPrimitive }
            ?.contentOrNull
    }

    private fun JsonObject.isEnglishLogo() =
        (this["iso_639_1"] as? JsonPrimitive)?.contentOrNull == "en"

    private fun JsonObject.isPng() =
        (this["file_path"] as? JsonPrimitive)?.contentOrNull?.endsWith(".png", ignoreCase = true) == true

    private fun isLogoUrl(value: String): Boolean =
        (value.startsWith("http://") || value.startsWith("https://")) &&
                (value.contains(".png", ignoreCase = true) || value.contains(".svg", ignoreCase = true) ||
                        value.contains(".webp", ignoreCase = true))

    private fun extractLogoUrl(element: JsonElement): String? {
        return when (element) {
            is JsonObject -> {
                val logoKeys = listOf("clearlogo", "clearLogo", "logo", "logoImage")
                val direct = logoKeys.firstNotNullOfOrNull { key ->
                    (element[key] as? JsonPrimitive)?.contentOrNull
                        ?.takeIf { isLogoUrl(it) }
                }
                if (direct != null) return direct

                val imagesArray = element["images"] as? JsonArray
                imagesArray?.filterIsInstance<JsonObject>()
                    ?.firstOrNull { img ->
                        (img["coverType"] as? JsonPrimitive)?.contentOrNull
                            ?.equals("Clearlogo", ignoreCase = true) == true
                    }
                    ?.let { (it["url"] as? JsonPrimitive)?.contentOrNull?.takeIf { u -> isLogoUrl(u) } }
            }
            is JsonArray -> element.filterIsInstance<JsonObject>().firstNotNullOfOrNull { extractLogoUrl(it) }
            else -> null
        }
    }

    private fun isImageUrl(value: String): Boolean =
        value.startsWith("http://") || value.startsWith("https://")

    private fun getJson(url: String): JsonElement? =
        runCatching {
            val request = Request.Builder().url(url).build()
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                val body = response.body.string()
                json.parseToJsonElement(body)
            }
        }.getOrNull()

    private fun getString(url: String): String? =
        runCatching {
            val request = Request.Builder().url(url).build()
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                response.body.string()
            }
        }.getOrNull()

    private val backdropCache = mutableMapOf<String, String?>()

    suspend fun resolveBackdrop(media: Media): String? = withContext(Dispatchers.IO) {
        val cacheKey = "backdrop:${media.serviceType}:${media.id}:${media.tmdbId}"
        if (backdropCache.containsKey(cacheKey)) return@withContext backdropCache[cacheKey]

        val result = when (media.serviceType) {
            ServiceType.SIMKL -> fromTmdbBackdrop(media.tmdbId, media.format == "MOVIE")
            else -> null
        }

        backdropCache[cacheKey] = result
        result
    }

    private fun fromTmdbBackdrop(tmdbId: String?, isMovie: Boolean): String? {
        if (tmdbId.isNullOrBlank()) return null
        val apiKey = BuildConfig.TMDB_API_KEY.takeIf { it.isNotBlank() } ?: return null
        val type = if (isMovie) "movie" else "tv"
        val url = "https://api.themoviedb.org/3/$type/$tmdbId/images?api_key=$apiKey&include_image_language=en,null"

        return getJson(url)
            ?.let { extractTmdbBackdropPath(it) }
            ?.let { "https://image.tmdb.org/t/p/w1280$it" }
    }

    private fun extractTmdbBackdropPath(element: JsonElement): String? {
        val backdrops = (element as? JsonObject)?.get("backdrops") as? JsonArray ?: return null
        return backdrops.filterIsInstance<JsonObject>()
            .maxByOrNull {
                (it["vote_count"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: 0
            }
            ?.get("file_path")
            ?.let { it as? JsonPrimitive }
            ?.contentOrNull
    }
}
