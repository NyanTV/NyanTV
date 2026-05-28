package com.nyantv.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
    onEpisodeSelected:   () -> Unit,
    onOverlayDismiss:    () -> Unit         = {},
    modifier:            Modifier           = Modifier,
) {
    val state          by vm.state.collectAsStateWithLifecycle()
    val fillerEpisodes by vm.fillerEpisodes.collectAsStateWithLifecycle()
    val watchProgress  by vm.watchProgress.collectAsStateWithLifecycle()
    var showResultPicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.refreshWatchProgress() }
    val changeFocusReq = remember { FocusRequester() }
    val episodeSuccess = state.episodeState as? EpisodeState.Success
    val pageSize = 12
    var page by remember(episodeSuccess?.episodes?.size) { mutableStateOf(0) }

    Box(modifier = modifier.fillMaxSize()) {
        LaunchedEffect(showResultPicker) {
            if (!showResultPicker) {
                delay(50)
                onOverlayDismiss()
            }
        }
        LazyColumn(
            modifier            = Modifier.fillMaxSize(),
            contentPadding      = PaddingValues(16.dp),
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
                    state.searchState is SearchState.Error || state.searchState is SearchState.Idle -> {
                        Row(
                            modifier              = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment     = Alignment.CenterVertically,
                        ) {
                            Text(
                                "No result found",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                            OutlinedButton(
                                onClick  = { showResultPicker = true },
                                modifier = Modifier.focusRequester(changeFocusReq),
                            ) { Text("Search") }
                        }
                    }
                    else -> {}
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
                        Text(
                            es.message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
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
                                    FilterChip(
                                        selected = isSelected,
                                        onClick  = { page = index },
                                        label    = {
                                            Text(
                                                "$from–$to",
                                                color = if (isSelected)
                                                    MaterialTheme.colorScheme.onSecondaryContainer
                                                else
                                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                                            )
                                        },
                                    )
                                }
                            }
                        }
                    }

                    // ── Episodes ─────────────────────────────────────────
                    items(slice) { episode ->
                        val epNum          = episode.episode_number.toInt()
                        val isWatched      = epNum <= watchedEpisodeCount
                        val progressFraction = watchProgress
                            ?.takeIf { it.episodeNumber.toInt() == epNum && !isWatched }
                            ?.let { (it.positionMs.toFloat() / it.durationMs.toFloat()).coerceIn(0f, 1f) }
                        val meta = state.episodeMeta.resolveEpisodeMeta(episode.episode_number)
                        EpisodeRow(
                            episode          = episode,
                            meta             = meta,
                            isLoading        = state.selectedEpisode == episode && state.streamState is StreamState.Loading,
                            isFiller         = epNum in fillerEpisodes,
                            isWatched        = isWatched,
                            progressFraction = progressFraction,
                            onClick          = { vm.selectEpisode(episode) },
                        )
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
                                            url     = v.url ?: v.videoUrl,
                                            headers = v.headers?.toMultimap()
                                                ?.mapValues { it.value.firstOrNull() ?: "" }
                                                ?: emptyMap(),
                                        )
                                    }
                                    PlayerArgs.skipTimes  = state.skipTimes
                                    PlayerArgs.subtitleTracks = videos
                                        .flatMap { v -> v.subtitleTracks }
                                        .distinctBy { it.url }
                                        .map { track -> SubtitleTrack(track.lang, track.url) }
                                    PlayerArgs.initialStreamIndex  = index
                                    PlayerArgs.episodes            = allEpisodes
                                    PlayerArgs.currentEpisodeIndex = allEpisodes.indexOfFirst { it == state.selectedEpisode }
                                    PlayerArgs.onLoadEpisodeVideos = { episode -> vm.getVideosForEpisode(episode) }
                                    PlayerArgs.fillerEpisodes      = fillerEpisodes
                                    PlayerArgs.mediaId             = vm.mediaId
                                    PlayerArgs.serviceKey          = vm.serviceKey
                                    PlayerArgs.anilistId           = vm.anilistId
                                    PlayerArgs.malId               = vm.currentMalId
                                    PlayerArgs.resumePositionMs    = watchProgress
                                        ?.takeIf { it.episodeNumber.toInt() == state.selectedEpisode?.episode_number?.toInt() }
                                        ?.positionMs ?: 0L
                                    PlayerArgs.episodeMeta         = state.episodeMeta
                                    PlayerArgs.title = state.selectedEpisode?.displayName(state.episodeMeta) ?: ""
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

        // ── Result picker overlay ─────────────────────────────────────────
        if (showResultPicker) {
            LaunchedEffect(Unit) {
                vm.ensureSearched()
            }
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
    Surface(
        onClick  = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (isWatched) 0.45f else 1f),
        shape    = MaterialTheme.shapes.small,
        color    = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Box {
            Row(
                modifier              = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    modifier              = Modifier.weight(1f),
                    verticalAlignment     = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    meta?.image?.takeIf { it.isNotBlank() }?.let { image ->
                        AsyncImage(
                            model              = image,
                            contentDescription = null,
                            contentScale       = ContentScale.Crop,
                            modifier           = Modifier.size(96.dp, 56.dp).clip(RoundedCornerShape(6.dp)),
                        )
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            title,
                            style    = MaterialTheme.typography.bodyMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        description?.let {
                            Text(
                                it,
                                style    = MaterialTheme.typography.bodySmall,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                color    = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
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
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                else
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
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
