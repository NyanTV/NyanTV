package com.nyantv.ui.screens

import android.content.Context
import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.input.key.*
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.*
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.nyantv.AniZipEpisodeMeta
import com.nyantv.player.*
import com.nyantv.ui.player.PlayerArgs
import com.nyantv.ui.player.StreamTrack
import com.nyantv.ui.player.SubtitleTrack
import com.nyantv.ui.player.extractDomain
import com.nyantv.ui.player.extractUrlPath
import com.nyantv.ui.utils.displayName
import com.nyantv.ui.utils.focusBorder
import com.nyantv.ui.utils.resolveEpisodeMeta
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import kotlinx.coroutines.delay

@Composable
fun PlayerTabScreen(
    vm:                  PlayerTabViewModel,
    watchedEpisodeCount: Int                = 0,
    playerReturnCount:   Int     = 0,
    onEpisodeSelected:   () -> Unit,
    onOverlayDismiss:    () -> Unit         = {},
    modifier:            Modifier           = Modifier,
) {
    val context = LocalContext.current
    val state            by vm.state.collectAsStateWithLifecycle()
    val fillerEpisodes   by vm.fillerEpisodes.collectAsStateWithLifecycle()
    val resumeProgress   by vm.resumeProgress.collectAsStateWithLifecycle()
    val watchedEpisodes  by vm.watchedEpisodes.collectAsStateWithLifecycle()
    var showResultPicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.refreshWatchProgress() }

    val changeFocusReq = remember { FocusRequester() }
    val resumeCardFocusReq = remember { FocusRequester() }
    val listState      = rememberLazyListState()
    val episodeSuccess = state.episodeState as? EpisodeState.Success
    val pageSize       = 12

    val initialPage = remember(episodeSuccess?.episodes?.size, state.selectedEpisode) {
        val eps = episodeSuccess?.episodes ?: return@remember 0
        val idx = eps.indexOfFirst { it == state.selectedEpisode }
        if (idx >= 0) idx / pageSize else 0
    }

    var page by rememberSaveable(episodeSuccess?.episodes?.size) { mutableStateOf(initialPage) }

    LaunchedEffect(initialPage) {
        if (page != initialPage) page = initialPage
    }

    LaunchedEffect(page, state.selectedEpisode) {
        val eps = (state.episodeState as? EpisodeState.Success)?.episodes ?: return@LaunchedEffect
        val globalIdx = eps.indexOfFirst { it == state.selectedEpisode }.takeIf { it >= 0 } ?: return@LaunchedEffect
        if (globalIdx / pageSize != page) return@LaunchedEffect
        val rowInPage = (globalIdx % pageSize) / 2
        delay(80)
        listState.animateScrollToItem(rowInPage.coerceAtLeast(0))
    }

    LaunchedEffect(playerReturnCount) {
        if (playerReturnCount > 0) {
            vm.refreshWatchProgress()
            delay(150)
            runCatching { resumeCardFocusReq.requestFocus() }
        }
    }
    LaunchedEffect(Unit) { vm.refreshWatchProgress() }

    Box(modifier = modifier.fillMaxSize()) {
        var prevShowResultPicker by remember { mutableStateOf(false) }
        LaunchedEffect(showResultPicker) {
            if (!showResultPicker && prevShowResultPicker) {
                delay(50)
                onOverlayDismiss()
            }
            prevShowResultPicker = showResultPicker
        }

        LazyColumn(
            state               = listState,
            modifier            = Modifier.fillMaxSize(),
            contentPadding      = PaddingValues(
                start  = 16.dp,
                end    = 16.dp,
                top    = 16.dp,
                bottom = 80.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Source Dropdown ──────────────────────────────────────────
            item {
                SourceDropdown(
                    sources        = state.sources,
                    selectedSource = state.selectedSource,
                    onSelect       = { vm.selectSource(it) },
                )
            }

            // ── Found result row ─────────────────────────────────────────
            item {
                when {
                    state.selectedAnime != null -> {
                        Column {
                            Text(
                                "Found result",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            )
                            Text(
                                state.selectedAnime!!.title,
                                style      = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                maxLines   = 1,
                                overflow   = TextOverflow.Ellipsis,
                                color      = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                    state.searchState is SearchState.Loading -> {
                        Row(
                            verticalAlignment     = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            Text(
                                "Searching…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            )
                        }
                    }
                    else -> {
                        Row(
                            modifier              = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment     = Alignment.CenterVertically,
                        ) {
                            Text(
                                (state.searchState as? SearchState.Error)?.message ?: "No result found",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                            OutlinedButton(
                                onClick  = { showResultPicker = true },
                                modifier = Modifier.focusRequester(changeFocusReq),
                            ) { Text("Search") }
                        }
                    }
                }
            }

            // ── Stream loading indicator ─────────────────────────────────
            if (state.streamState is StreamState.Loading) {
                item {
                    Row(
                        verticalAlignment     = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text("Loading streams…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                }
            }

            if (state.streamState is StreamState.Error) {
                item {
                    Text(
                        (state.streamState as StreamState.Error).message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            // ── Episode list ─────────────────────────────────────────────
            when (val es = state.episodeState) {
                is EpisodeState.Loading -> item {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                }
                is EpisodeState.Error -> item {
                    Column {
                        Text(es.message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { vm.retryEpisodes() }) { Text("Retry") }
                    }
                }
                is EpisodeState.Success -> {
                    val totalPages = (es.episodes.size + pageSize - 1) / pageSize
                    val slice      = es.episodes.drop(page * pageSize).take(pageSize)

                    // ── Change button ────────────────────────────────────
                    item {
                        OutlinedButton(
                            onClick  = { showResultPicker = true },
                            modifier = Modifier.focusRequester(changeFocusReq),
                        ) { Text("Change") }
                    }

                    resumeProgress?.let { resume ->
                        val resumeEp = es.episodes.firstOrNull {
                            it.episode_number.toInt() == resume.episodeNumber.toInt()
                        }
                        if (resumeEp != null && resume.durationMs > 0L) {
                            item {
                                ResumeCard(
                                    episode     = resumeEp,
                                    progress    = resume,
                                    episodeMeta = state.episodeMeta,
                                    onClick     = { vm.selectEpisode(resumeEp) },
                                    modifier    = Modifier.focusRequester(resumeCardFocusReq),
                                )
                            }
                        }
                    }

                    // ── Page chips ───────────────────────────────────────
                    if (totalPages > 1) {
                        item {
                            Row(
                                modifier              = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                repeat(totalPages) { index ->
                                    val from       = index * pageSize + 1
                                    val to         = minOf((index + 1) * pageSize, es.episodes.size)
                                    val isSelected = page == index

                                    val chipShape = RoundedCornerShape(6.dp)

                                    Box(
                                        modifier = Modifier
                                            .focusBorder(shape = chipShape, color = MaterialTheme.colorScheme.primary, inset = true)
                                            .clip(chipShape)
                                            .background(
                                                if (isSelected) MaterialTheme.colorScheme.secondaryContainer
                                                else MaterialTheme.colorScheme.surfaceContainer
                                            )
                                            .clickable(
                                                interactionSource = remember { MutableInteractionSource() },
                                                indication        = null,
                                            ) { page = index }
                                            .padding(horizontal = 12.dp, vertical = 6.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            "$from–$to",
                                            style = MaterialTheme.typography.labelMedium,
                                            color = if (isSelected)
                                                MaterialTheme.colorScheme.onSecondaryContainer
                                            else
                                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // ── Episodes ─────────────────────────────────────────
                    items(
                        items = slice.chunked(2),
                        key = { pair -> pair.first().let { "${it.episode_number}_${it.url}" } },
                    ) { pair ->
                        Row(
                            modifier              = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            pair.forEach { episode ->
                                val epNum            = episode.episode_number.toInt()
                                val isWatched        = epNum in watchedEpisodes
                                val progressFraction = vm.episodeProgressFor(episode.episode_number)
                                    ?.let { (it.positionMs.toFloat() / it.durationMs.toFloat()).coerceIn(0f, 1f) }
                                    ?.takeIf { it > 0f && !isWatched }
                                val meta = state.episodeMeta.resolveEpisodeMeta(episode.episode_number)
                                EpisodeRow(
                                    episode          = episode,
                                    meta             = meta,
                                    isLoading        = state.selectedEpisode == episode && state.streamState is StreamState.Loading,
                                    isFiller         = epNum in fillerEpisodes,
                                    isWatched        = isWatched,
                                    progressFraction = progressFraction,
                                    onClick          = { vm.selectEpisode(episode) },
                                    modifier         = Modifier.weight(1f),
                                )
                            }
                            if (pair.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
                else -> {}
            }
        }

        // ── Stream dialog ─────────────────────────────────────────────────
        if (state.streamState is StreamState.Ready) {
            val videos = (state.streamState as StreamState.Ready).videos
            AlertDialog(
                onDismissRequest = { vm.clearStreams() },
                title = { Text(state.selectedEpisode?.name ?: "Choose stream") },
                text = {
                    Column {
                        videos.forEachIndexed { index, video ->
                            TextButton(
                                onClick = {
                                    val allEpisodes = (state.episodeState as? EpisodeState.Success)?.episodes ?: emptyList()
                                    PlayerArgs.streams = videos.map { v ->
                                        StreamTrack(
                                            name    = v.quality.ifBlank { "Stream" },
                                            url     = v.videoUrl.takeIf { it.isNotBlank() && it != "null" } ?: v.videoPageUrl,
                                            headers = v.headers?.toMultimap()
                                                ?.mapValues { it.value.firstOrNull() ?: "" }
                                                ?: emptyMap(),
                                        )
                                    }
                                    PlayerArgs.skipTimes          = state.skipTimes
                                    val prefs = context.getSharedPreferences("nyantv_player_prefs", Context.MODE_PRIVATE)
                                    val useAdvanced = prefs.getBoolean("subtitle_advanced_grouping", false)

                                    PlayerArgs.subtitleTracks = if (!useAdvanced) {
                                        videos
                                            .flatMap { v ->
                                                val streamDomain = extractDomain(
                                                    v.videoUrl.takeIf { it.isNotBlank() && it != "null" } ?: v.videoPageUrl
                                                )
                                                v.subtitleTracks.map { track ->
                                                    Triple(track.lang, track.url, streamDomain)
                                                }
                                            }
                                            .groupBy { (lang, _, _) -> lang }
                                            .map { (lang, entries) ->
                                                SubtitleTrack(
                                                    name = lang,
                                                    urls = entries
                                                        .map { (_, url, domain) -> SubtitleTrack.SubtitleUrl(url = url, streamDomain = domain) }
                                                        .distinctBy { it.url }
                                                )
                                            }
                                    } else {
                                        videos
                                            .flatMap { v ->
                                                val streamDomain = extractDomain(
                                                    v.videoUrl.takeIf { it.isNotBlank() && it != "null" } ?: v.videoPageUrl
                                                )
                                                v.subtitleTracks.map { track ->
                                                    Triple(track.lang, track.url, streamDomain)
                                                }
                                            }
                                            .groupBy { (lang, url, _) ->
                                                "$lang|${extractUrlPath(url)}"
                                            }
                                            .map { (key, entries) ->
                                                val (lang, path) = key.split("|", limit = 2)
                                                val slug = path.substringAfterLast('/')
                                                    .substringBefore('?')
                                                    .substringBeforeLast('.')
                                                val displayName = if (slug.isNotBlank() && slug != lang) "$lang ($slug)" else lang
                                                SubtitleTrack(
                                                    name = displayName,
                                                    urls = entries
                                                        .map { (_, url, domain) -> SubtitleTrack.SubtitleUrl(url = url, streamDomain = domain) }
                                                        .distinctBy { it.url }
                                                )
                                            }
                                    }

                                    PlayerArgs.initialStreamIndex  = index
                                    PlayerArgs.episodes            = allEpisodes
                                    PlayerArgs.currentEpisodeIndex = allEpisodes.indexOfFirst { it == state.selectedEpisode }
                                    PlayerArgs.onLoadEpisodeVideos = { episode -> vm.getVideosForEpisode(episode) }
                                    PlayerArgs.onLoadSkipTimes     = { episode -> vm.fetchSkipTimesFor(episode) }
                                    PlayerArgs.fillerEpisodes      = fillerEpisodes
                                    PlayerArgs.mediaId             = vm.mediaId
                                    PlayerArgs.serviceKey          = vm.serviceKey
                                    PlayerArgs.anilistId           = vm.anilistId
                                    PlayerArgs.malId               = vm.currentMalId
                                    PlayerArgs.resumePositionMs    = vm.episodeProgressFor(
                                        state.selectedEpisode?.episode_number ?: 0f
                                    )
                                        ?.takeIf { it.positionMs > 0L && it.positionMs < it.durationMs - 10_000L }
                                        ?.positionMs
                                        ?: 0L
                                    PlayerArgs.episodeMeta         = state.episodeMeta
                                    PlayerArgs.title               = state.selectedEpisode?.displayName(state.episodeMeta) ?: ""
                                    PlayerArgs.seriesTitle         = vm.mediaTitle
                                    PlayerArgs.mediaCoverUrl  = state.episodeMeta
                                        .resolveEpisodeMeta(state.selectedEpisode?.episode_number ?: 0f)
                                        ?.image?.takeIf { it.isNotBlank() } ?: ""
                                    PlayerArgs.mediaBannerUrl = vm.mediaBannerUrl
                                    PlayerArgs.mediaPosterUrl = vm.mediaPosterUrl
                                    vm.clearStreams()
                                    onEpisodeSelected()
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text(video.quality.ifBlank { "Stream ${index + 1}" }) }
                        }
                    }
                },
                confirmButton = {},
            )
        }

        if (showResultPicker) {
            LaunchedEffect(Unit) { vm.ensureSearched() }
            ResultPickerOverlay(
                state     = state,
                onSearch  = { vm.setSearchQuery(it); vm.submitSearch() },
                onSelect  = { anime -> vm.confirmAnimeResult(anime); showResultPicker = false },
                onDismiss = { showResultPicker = false },
            )
        }
    }
}

// ── Source Dropdown ───────────────────────────────────────────────────────────

@Composable
private fun SourceDropdown(
    sources:        List<SearchableSource>,
    selectedSource: SearchableSource?,
    onSelect:       (SearchableSource) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier              = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment     = Alignment.CenterVertically,
            ) {
                Text(
                    selectedSource?.let { "${it.name} (${it.lang.uppercase()})" } ?: "No source",
                    style    = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Icon(Icons.Default.ArrowDropDown, contentDescription = null)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            sources.forEach { source ->
                DropdownMenuItem(
                    text        = { Text("${source.name} (${source.lang.uppercase()})") },
                    onClick     = { onSelect(source); expanded = false },
                    leadingIcon = source.iconUrl?.let { url ->
                        {
                            AsyncImage(
                                model              = url,
                                contentDescription = null,
                                modifier           = Modifier.size(20.dp).clip(RoundedCornerShape(4.dp)),
                            )
                        }
                    },
                )
            }
        }
    }
}

// ── Episode Row ───────────────────────────────────────────────────────────────

@Composable
private fun EpisodeRow(
    episode:          SEpisode,
    meta:             AniZipEpisodeMeta?,
    isLoading:        Boolean,
    isFiller:         Boolean,
    isWatched:        Boolean,
    progressFraction: Float?,
    onClick:          () -> Unit,
    modifier:         Modifier = Modifier,
) {
    val title = episode.name.takeIf { it.contains(":") }
        ?: meta?.title?.takeIf { it.isNotBlank() }
            ?.let { "Episode ${episode.episode_number.toInt()}: $it" }
        ?: episode.name.ifBlank { "Episode ${episode.episode_number.toInt()}" }
    val description = meta?.summary?.takeIf { it.isNotBlank() }
        ?: meta?.overview?.takeIf { it.isNotBlank() }
    val infoParts = buildList {
        meta?.rating?.takeIf { it.isNotBlank() }?.let { add("★ $it") }
        meta?.airDate?.takeIf { it.isNotBlank() }?.let { add(it) }
    }
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
        var isFocused by remember { mutableStateOf(false) }
        Surface(
            onClick  = onClick,
            modifier = modifier
                .fillMaxWidth()
                .alpha(if (isWatched) 0.45f else 1f)
                .onFocusChanged { isFocused = it.isFocused || it.hasFocus }
                .focusBorder(MaterialTheme.shapes.small, inset = true, color = MaterialTheme.colorScheme.primary, isFocused = isFocused),
            shape    = MaterialTheme.shapes.small,
            color    = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Box {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(
                        modifier = Modifier.weight(1f),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        meta?.image?.takeIf { it.isNotBlank() }?.let { image ->
                            AsyncImage(
                                model = image,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(96.dp, 56.dp)
                                    .clip(RoundedCornerShape(6.dp)),
                            )
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                title,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            description?.let {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                                )
                            }
                            if (infoParts.isNotEmpty()) {
                                Text(
                                    infoParts.joinToString(" · "),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.9f),
                                )
                            }
                            if (isFiller) {
                                Text(
                                    "Filler Episode",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
                                )
                            }
                        }
                    }
                    if (isLoading)
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    else
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                }
                if (progressFraction != null && progressFraction > 0f) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(3.dp)
                            .align(Alignment.BottomStart)
                            .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(progressFraction)
                            .height(3.dp)
                            .align(Alignment.BottomStart)
                            .background(MaterialTheme.colorScheme.primary)
                    )
                }
            }
        }
    }
}

// ── Result Picker Overlay ─────────────────────────────────────────────────────

@Composable
private fun ResultPickerOverlay(
    state:     PlayerTabUiState,
    onSearch:  (String) -> Unit,
    onSelect:  (SAnime) -> Unit,
    onDismiss: () -> Unit,
) {
    var query              by remember { mutableStateOf(TextFieldValue(state.searchQuery)) }
    val backButtonFocusReq = remember { FocusRequester() }
    val searchFocusReq     = remember { FocusRequester() }
    BackHandler { onDismiss() }
    val focusManager       = LocalFocusManager.current
    val gridState          = rememberLazyGridState()

    LaunchedEffect(Unit) { runCatching { searchFocusReq.requestFocus() } }

    Surface(
        modifier = Modifier
            .fillMaxSize()
            .focusGroup(),
            //.focusProperties { onExit = { cancelFocusChange() } },
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val searchButtonFocusReq = remember { FocusRequester() }

                OutlinedTextField(
                    value         = query,
                    onValueChange = { query = it },
                    modifier      = Modifier
                        .weight(1f)
                        .focusRequester(searchFocusReq)
                        .onPreviewKeyEvent { event ->
                            if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                            when (event.key) {
                                Key.DirectionUp    -> { backButtonFocusReq.requestFocus(); true }
                                Key.DirectionDown  -> { focusManager.moveFocus(FocusDirection.Down); true }
                                Key.DirectionLeft  -> true
                                Key.DirectionRight -> { searchButtonFocusReq.requestFocus(); true }
                                else -> false
                            }
                        },
                    placeholder  = { Text("Search…") },
                    singleLine   = true,
                )

                Spacer(Modifier.width(8.dp))

                CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
                    FilledIconButton(
                        onClick = { onSearch(query.text) },
                        modifier = Modifier
                            .focusRequester(searchButtonFocusReq)
                            .onPreviewKeyEvent { event ->
                                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                                when (event.key) {
                                    Key.DirectionUp -> {
                                        searchFocusReq.requestFocus(); true
                                    }

                                    Key.DirectionDown -> {
                                        focusManager.moveFocus(FocusDirection.Down); true
                                    }

                                    Key.DirectionLeft -> {
                                        searchFocusReq.requestFocus(); true
                                    }

                                    Key.DirectionCenter,
                                    Key.Enter -> {
                                        onSearch(query.text); true
                                    }

                                    else -> false
                                }
                            }
                            .focusBorder(CircleShape),
                    ) {
                        Icon(Icons.Default.Search, contentDescription = "Search")
                    }
                }
            }

            when (val ss = state.searchState) {
                is SearchState.Loading -> Box(
                    modifier         = Modifier.fillMaxWidth(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(modifier = Modifier.padding(24.dp))
                }
                is SearchState.Error -> Text(
                    ss.message,
                    color    = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
                )
                is SearchState.Results -> LazyVerticalGrid(
                    state                 = gridState,
                    columns               = GridCells.Adaptive(120.dp),
                    modifier              = Modifier
                        .fillMaxSize()
                        .onPreviewKeyEvent { event ->
                            if (event.type == KeyEventType.KeyDown &&
                                event.key == Key.DirectionUp &&
                                !gridState.canScrollBackward
                            ) {
                                searchFocusReq.requestFocus()
                                true
                            } else false
                        },
                    contentPadding        = PaddingValues(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement   = Arrangement.spacedBy(8.dp),
                ) {
                    items(ss.items) { anime ->
                        ResultCard(anime = anime, onClick = { focusManager.clearFocus(); onSelect(anime) })
                    }
                }
                else -> {}
            }
        }
    }
}

// ── Result Card ───────────────────────────────────────────────────────────────

@Composable
private fun ResultCard(anime: SAnime, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape   = MaterialTheme.shapes.medium,
        color   = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column {
            AsyncImage(
                model              = anime.thumbnail_url,
                contentDescription = null,
                contentScale       = ContentScale.Crop,
                modifier           = Modifier
                    .fillMaxWidth()
                    .height(160.dp)
                    .clip(MaterialTheme.shapes.medium),
            )
            Text(
                anime.title,
                style    = MaterialTheme.typography.labelSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(6.dp),
            )
        }
    }
}

@Composable
private fun ResumeCard(
    episode:     SEpisode,
    progress:    EpisodeProgress,
    episodeMeta: Map<String, AniZipEpisodeMeta>,
    onClick:     () -> Unit,
    modifier:    Modifier = Modifier,
) {
    val fraction = (progress.positionMs.toFloat() / progress.durationMs).coerceIn(0f, 1f)
    val meta     = episodeMeta.resolveEpisodeMeta(episode.episode_number)
    val title    = episode.name.takeIf { it.contains(":") }
        ?: meta?.title?.takeIf { it.isNotBlank() }
            ?.let { "Episode ${episode.episode_number.toInt()}: $it" }
        ?: episode.name.ifBlank { "Episode ${episode.episode_number.toInt()}" }

    val remainingMs = progress.durationMs - progress.positionMs
    val remainingMin = (remainingMs / 60_000).toInt()

    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .focusBorder(MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f), gap = 0.5.dp),
        shape   = MaterialTheme.shapes.medium,
        color   = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f),
        border  = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
        ),
    ) {
        Box {
            Row(
                modifier              = Modifier.padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment     = Alignment.CenterVertically,
            ) {
                meta?.image?.takeIf { it.isNotBlank() }?.let { image ->
                    AsyncImage(
                        model              = image,
                        contentDescription = null,
                        contentScale       = ContentScale.Crop,
                        modifier           = Modifier
                            .size(120.dp, 68.dp)
                            .clip(RoundedCornerShape(6.dp)),
                    )
                }
                Column(
                    modifier            = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Continue watching",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        title,
                        style    = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (remainingMin > 0) {
                        Text(
                            "${remainingMin}min left",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                    }
                }
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = null,
                    tint     = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp),
                )
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .align(Alignment.BottomStart)
                    .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(4.dp)
                    .align(Alignment.BottomStart)
                    .background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}
