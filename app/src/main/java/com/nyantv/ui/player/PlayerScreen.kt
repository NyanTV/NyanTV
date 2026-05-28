package com.nyantv.ui.player

import android.graphics.Color as AndroidColor
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import com.nyantv.EpisodeSkipTimes
import com.nyantv.SkipInterval
import com.nyantv.ui.theme.FocusIndication
import com.nyantv.ui.utils.SectionCard
import com.nyantv.viewmodel.AppViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG              = "NyanTV:PlayerScreen"
private const val CONTROLS_HIDE_MS = 4_000L

private data class DisplaySegment(
    val label:    String,
    val startSec: Int,
    val endSec:   Int,
    val color:    Color,
)

private val segmentColorOpening = Color(0xFFFFB300)   // Amber
private val segmentColorEnding  = Color(0xFF7C4DFF)   // Deep purple
private val segmentColorRecap   = Color(0xFF29B6F6)   // Sky blue

private fun EpisodeSkipTimes.toDisplaySegments(): List<DisplaySegment> = buildList {
    fun add(seg: SkipInterval?, label: String, color: Color) {
        if (seg != null) add(DisplaySegment(label, seg.startSec, seg.endSec, color))
    }
    add(op,      "Opening", segmentColorOpening)
    add(mixedOp, "Opening", segmentColorOpening)
    add(ed,      "Ending",  segmentColorEnding)
    add(mixedEd, "Ending",  segmentColorEnding)
    add(recap,   "Recap",   segmentColorRecap)
}

// ── Entry point ────────────────────────────────────────────────────────────────

/**
 * Reads [PlayerArgs] exactly once on first composition.
 * Callers must populate [PlayerArgs] before calling navController.navigate("player").
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    vm:     PlayerViewModel = viewModel(),
    appVm: AppViewModel,
    onBack: () -> Unit
) {
    val state      by vm.state.collectAsStateWithLifecycle()
    val subPrefs   by vm.subtitlePrefs.collectAsStateWithLifecycle()
    val currentCue by vm.currentCue.collectAsStateWithLifecycle()

    var controlsVisible           by remember { mutableStateOf(true) }
    var showSubSettings           by remember { mutableStateOf(false) }
    var showStreamPicker          by remember { mutableStateOf(false) }
    var showSubPicker             by remember { mutableStateOf(false) }
    var showTrackingConsentDialog by remember { mutableStateOf(false) }

    val anyPanelOpen = showSubSettings || showStreamPicker || showSubPicker ||
            state.pendingEpisodeVideos.isNotEmpty() ||
            state.fillerWarning != null

    val mainFocusRequester    = remember { FocusRequester() }
    val playBtnFocusRequester = remember { FocusRequester() }

    val scope  = rememberCoroutineScope()
    var hideJob         by remember { mutableStateOf<Job?>(null) }
    var pausedBySettings by remember { mutableStateOf(false) }

    // ── Focus-Requester für beide Buttons ─────────────────────────────────────────
    val skipBtnFocusRequester    = remember { FocusRequester() }
    val bigSkipBtnFocusRequester = remember { FocusRequester() }
    var skipBtnOverrideVisible   by remember { mutableStateOf(false) }

    fun pauseForSettings() {
        if (state.isPlaying) { vm.togglePlayPause(); pausedBySettings = true }
    }

    fun resumeFromSettings() {
        if (pausedBySettings) { vm.togglePlayPause(); pausedBySettings = false }
    }

    fun closePanel() {
        showSubSettings  = false
        showStreamPicker = false
        showSubPicker    = false
        resumeFromSettings()
        scope.launch {
            delay(50)
            runCatching {
                if (controlsVisible) playBtnFocusRequester.requestFocus()
                else mainFocusRequester.requestFocus()
            }
        }
    }

    fun showControls() {
        vm.refreshPosition()
        controlsVisible = true
        hideJob?.cancel()
        if (anyPanelOpen) return
        hideJob = scope.launch {
            delay(CONTROLS_HIDE_MS)
            if (!anyPanelOpen) {
                controlsVisible = false
                runCatching { mainFocusRequester.requestFocus() }
            }
        }
    }

    // ── BackHandler stack ──────────────────────────────────────────────────────
    BackHandler(enabled = showSubSettings)  { closePanel() }
    BackHandler(enabled = showSubPicker)    { closePanel() }
    BackHandler(enabled = showStreamPicker) { closePanel() }
    BackHandler(enabled = controlsVisible && !anyPanelOpen) {
        controlsVisible = false
        hideJob?.cancel()
        scope.launch { runCatching { mainFocusRequester.requestFocus() } }
    }

    // ── Load tracks once ───────────────────────────────────────────────────────
    LaunchedEffect(Unit) {
        vm.loadTracks(PlayerArgs.consume())
        mainFocusRequester.requestFocus()
        showControls()
        when (appVm.trackingMode.value) {
            AppViewModel.TrackingMode.ALWAYS_AUTO -> vm.setSessionTracking(true)
            AppViewModel.TrackingMode.NEVER_AUTO  -> vm.setSessionTracking(false)
            AppViewModel.TrackingMode.ALWAYS_ASK  -> showTrackingConsentDialog = true
        }
    }

    LaunchedEffect("watchedEvent") {
        vm.watchedEvent.collect { event ->
            appVm.markEpisodeWatched(event.mediaId, event.episode.episode_number.toInt())
        }
    }

    LaunchedEffect(controlsVisible) {
        if (controlsVisible && !anyPanelOpen) {
            delay(60)
            runCatching { playBtnFocusRequester.requestFocus() }
        }
    }

    LaunchedEffect(state.isPlaying) {
        if (state.isPlaying && pausedBySettings) {
            pausedBySettings = false
            showControls()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(mainFocusRequester)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false

                if (event.key == Key.Back || event.key == Key.Escape) {
                    return@onPreviewKeyEvent when {
                        anyPanelOpen    -> { closePanel(); true }
                        controlsVisible -> {
                            controlsVisible = false; hideJob?.cancel()
                            scope.launch { runCatching { mainFocusRequester.requestFocus() } }
                            true
                        }
                        else -> { vm.stop(); onBack(); true }
                    }
                }

                if (anyPanelOpen)    return@onPreviewKeyEvent false
                if (controlsVisible) { showControls(); return@onPreviewKeyEvent false }

                // Controls hidden — direct commands

                if (skipBtnOverrideVisible &&
                    (event.key == Key.DirectionCenter || event.key == Key.Enter)
                ) return@onPreviewKeyEvent false
                when (event.key) {
                    Key.DirectionCenter, Key.Enter -> { vm.togglePlayPause(); true }
                    Key.DirectionLeft  -> { vm.seekBackward(); true }
                    Key.DirectionRight -> { vm.seekForward();  true }
                    Key.DirectionUp, Key.DirectionDown -> { showControls(); false }
                    Key.Back -> false
                    else     -> { showControls(); false }
                }
            }
    ) {
        VideoSurface(vm = vm)

        if (subPrefs.enabled && currentCue != null) {
            SubtitleOverlay(
                text     = currentCue!!,
                prefs    = subPrefs,
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)
            )
        }

        if (state.playbackState == Player.STATE_BUFFERING) {
            CircularProgressIndicator(
                modifier    = Modifier.align(Alignment.Center),
                color       = MaterialTheme.colorScheme.primary,
                strokeWidth = 3.dp
            )
        }

        AnimatedVisibility(
            visible  = controlsVisible,
            enter    = fadeIn(tween(200)),
            exit     = fadeOut(tween(400)),
            modifier = Modifier.fillMaxSize()
        ) {
            PlayerControls(
                state                 = state,
                vm                    = vm,
                playBtnFocusRequester = playBtnFocusRequester,
                onBack                = { vm.stop(); onBack() },
                onOpenStreamPicker    = { pauseForSettings(); showStreamPicker = true },
                onOpenSubPicker       = { pauseForSettings(); showSubPicker    = true },
                onSubSettings         = { pauseForSettings(); showSubSettings  = true },
                pauseForSettings      = ::pauseForSettings
            )
        }

        // ── Stream picker ──────────────────────────────────────────────────────
        AnimatedVisibility(
            visible  = showStreamPicker,
            enter    = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit     = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            TrackPickerPanel(
                title        = "Stream",
                tracks       = state.streams.map { it.name },
                selectedIndex = state.selectedStreamIndex,
                showNone     = false,
                onSelect     = { idx -> vm.selectStream(idx ?: 0); closePanel() },
                onDismiss    = { closePanel() }
            )
        }

        // ── Subtitle track picker ──────────────────────────────────────────────
        AnimatedVisibility(
            visible  = showSubPicker,
            enter    = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit     = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            TrackPickerPanel(
                title         = "Subtitles",
                tracks        = state.subtitleTracks.map { it.name },
                selectedIndex = state.selectedSubtitleIndex,
                showNone      = true,
                onSelect      = { idx -> vm.selectSubtitleTrack(idx); closePanel() },
                onDismiss     = { closePanel() }
            )
        }

        // ── Subtitle settings panel ────────────────────────────────────────────
        AnimatedVisibility(
            visible  = showSubSettings,
            enter    = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit     = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            SubtitleSettingsPanel(
                prefs     = subPrefs,
                onUpdate  = { vm.updateSubtitlePrefs { _ -> it } },
                onDismiss = { closePanel() }
            )
        }

        // ── Filler warning dialog ──────────────────────────────────────────────────
        state.fillerWarning?.let { warning ->
            AlertDialog(
                onDismissRequest = { vm.dismissFillerWarning() },
                title = { Text("Filler Episode") },
                text  = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("${warning.targetEpisodeName} is a filler episode. Do you want to watch it?")
                        warning.nextNonFillerName?.let {
                            Text(
                                "Next non-filler: $it",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        }
                    }
                },
                confirmButton = {
                    TextButton(onClick = { vm.confirmFillerEpisode() }) {
                        Text("Watch Filler")
                    }
                },
                dismissButton = {
                    Row {
                        warning.nextNonFillerName?.let {
                            TextButton(onClick = { vm.skipToNextNonFiller() }) {
                                Text("Skip to ${warning.nextNonFillerName}")
                            }
                        }
                        TextButton(onClick = { vm.dismissFillerWarning() }) {
                            Text("Cancel")
                        }
                    }
                }
            )
        }

        AnimatedVisibility(
            visible  = state.pendingEpisodeVideos.isNotEmpty(),
            enter    = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit     = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            TrackPickerPanel(
                title         = "Choose quality for ${state.pendingEpisodeName}",
                tracks        = state.pendingEpisodeVideos.map { it.quality.ifBlank { "Stream" } },
                selectedIndex = null,
                showNone      = false,
                onSelect      = { idx -> idx?.let { vm.confirmPendingEpisodeStream(it) } },
                onDismiss     = { vm.dismissPendingEpisode() }
            )
        }

        LaunchedEffect(state.activeSkip) {
            if (state.activeSkip != null) {
                skipBtnOverrideVisible = true
                delay(50)
                runCatching { skipBtnFocusRequester.requestFocus() }
                delay(10_000L)
                skipBtnOverrideVisible = false
            } else {
                skipBtnOverrideVisible = false
                delay(50)
                runCatching { bigSkipBtnFocusRequester.requestFocus() }
            }
        }

        val activeSkip       = state.activeSkip
        val skipButtonVisible = activeSkip != null && (controlsVisible || skipBtnOverrideVisible) && !anyPanelOpen

// ── Skip Opening / Ending ──────────────────────────────────────────────────────
        AnimatedVisibility(
            visible  = skipButtonVisible,
            enter    = fadeIn() + slideInVertically(initialOffsetY = { it / 2 }),
            exit     = fadeOut(),
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 24.dp, bottom = 80.dp)
        ) {
            activeSkip?.let { skip ->
                OutlinedButton(
                    onClick  = { vm.seekTo(skip.endSec * 1000L) },
                    modifier = Modifier.focusRequester(skipBtnFocusRequester),
                    border   = BorderStroke(1.dp, Color.White.copy(alpha = 0.7f)),
                    colors   = ButtonDefaults.outlinedButtonColors(
                        containerColor = Color.Black.copy(alpha = 0.6f),
                        contentColor   = Color.White,
                    ),
                ) {
                    Text(skip.label, style = MaterialTheme.typography.labelMedium)
                }
            }
        }

// ── Big Skip  ──────────────────────────
        AnimatedVisibility(
            visible  = !skipButtonVisible && controlsVisible && !anyPanelOpen,
            enter    = fadeIn() + slideInVertically(initialOffsetY = { it / 2 }),
            exit     = fadeOut(),
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 24.dp, bottom = 80.dp)
        ) {
            val bigSkipSec = subPrefs.bigSkipSec
            OutlinedButton(
                onClick  = { vm.seekTo(state.positionMs + bigSkipSec * 1000L) },
                modifier = Modifier.focusRequester(bigSkipBtnFocusRequester),
                border   = BorderStroke(1.dp, Color.White.copy(alpha = 0.5f)),
                colors   = ButtonDefaults.outlinedButtonColors(
                    containerColor = Color.Black.copy(alpha = 0.45f),
                    contentColor   = Color.White,
                ),
            ) {
                Text("+${bigSkipSec}s", style = MaterialTheme.typography.labelMedium)
            }
        }


        if (showTrackingConsentDialog) {
            AlertDialog(
                onDismissRequest = {
                    vm.setSessionTracking(false)
                    showTrackingConsentDialog = false
                },
                title = { Text("Track progress?") },
                text  = { Text("Automatically update your watch progress for this session?") },
                confirmButton = {
                    TextButton(onClick = {
                        vm.setSessionTracking(true)
                        showTrackingConsentDialog = false
                    }) { Text("Yes") }
                },
                dismissButton = {
                    TextButton(onClick = {
                        vm.setSessionTracking(false)
                        showTrackingConsentDialog = false
                    }) { Text("No") }
                }
            )
        }

        state.error?.let { msg ->
            Snackbar(
                modifier       = Modifier.align(Alignment.BottomCenter).padding(16.dp),
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor   = MaterialTheme.colorScheme.onErrorContainer
            ) { Text(msg) }
        }
    }
}

// ── Surface ────────────────────────────────────────────────────────────────────

@OptIn(UnstableApi::class)
@Composable
private fun VideoSurface(vm: PlayerViewModel) {
    AndroidView(
        factory = { ctx ->
            SurfaceView(ctx).apply {
                setBackgroundColor(AndroidColor.TRANSPARENT)
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(h: SurfaceHolder)  { vm.setSurface(h.surface) }
                    override fun surfaceChanged(h: SurfaceHolder, fmt: Int, w: Int, ht: Int) {}
                    override fun surfaceDestroyed(h: SurfaceHolder) { vm.clearSurface() }
                })
            }
        },
        modifier = Modifier.fillMaxSize()
    )
}

// ── Controls overlay ───────────────────────────────────────────────────────────

@OptIn(UnstableApi::class)
@Composable
private fun PlayerControls(
    state:                 PlayerUiState,
    vm:                    PlayerViewModel,
    playBtnFocusRequester: FocusRequester,
    onBack:                () -> Unit,
    onOpenStreamPicker:    () -> Unit,
    onOpenSubPicker:       () -> Unit,
    onSubSettings:         () -> Unit,
    pauseForSettings:      () -> Unit
) {
    val gradientTop = Color.Black.copy(alpha = 0.7f)
    val gradientBot = Color.Black.copy(alpha = 0.85f)
    val hasStreams   = state.streams.size > 1
    val hasSubs     = state.subtitleTracks.isNotEmpty()

    Box(modifier = Modifier.fillMaxSize()) {

        // ── Top bar ────────────────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(gradientTop)
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TvIconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
            Text(
                state.title,
                color    = Color.White,
                style    = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )

            // Stream picker button — only if more than one stream available
            if (hasStreams) {
                val currentStreamName = state.streams.getOrNull(state.selectedStreamIndex)?.name ?: ""
                TvTextButton(
                    label   = currentStreamName,
                    onClick = onOpenStreamPicker
                )
                Spacer(Modifier.width(4.dp))
            }

            // Subtitle track picker button — only if tracks are available
            if (hasSubs) {
                TvIconButton(onClick = onOpenSubPicker) {
                    Icon(Icons.Filled.ClosedCaption, contentDescription = "Subtitle Track", tint = Color.White)
                }
            }

            // Subtitle appearance settings
            TvIconButton(onClick = onSubSettings) {
                Icon(Icons.Filled.Subtitles, contentDescription = "Subtitle Settings", tint = Color.White)
            }
        }

        // ── Bottom bar ─────────────────────────────────────────────────────────
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .background(gradientBot)
                .padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ProgressBar(state = state)

            Row(
                modifier          = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text  = "${formatMs(state.positionMs)} / ${formatMs(state.durationMs)}",
                    color = Color.White,
                    style = MaterialTheme.typography.labelMedium
                )
                Spacer(Modifier.weight(1f))

                TvIconButton(
                    onClick  = { vm.navigateEpisode(-1) },
                    enabled  = state.hasPrevEpisode && !state.episodeNavigating,
                ) {
                    Icon(Icons.Filled.SkipPrevious, contentDescription = "Previous episode", tint = Color.White, modifier = Modifier.size(28.dp))
                }

                TvIconButton(onClick = { vm.seekBackward() }) {
                    Icon(Icons.Filled.Replay10, contentDescription = "−10 s", tint = Color.White, modifier = Modifier.size(28.dp))
                }

                if (state.episodeNavigating) {
                    CircularProgressIndicator(
                        modifier    = Modifier.size(52.dp).padding(10.dp),
                        color       = Color.White,
                        strokeWidth = 3.dp
                    )
                } else {
                    TvIconButton(
                        onClick  = { vm.togglePlayPause() },
                        modifier = Modifier.size(52.dp).focusRequester(playBtnFocusRequester)
                    ) {
                        Icon(
                            imageVector        = if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (state.isPlaying) "Pause" else "Play",
                            tint               = Color.White,
                            modifier           = Modifier.size(36.dp)
                        )
                    }
                }

                TvIconButton(onClick = { vm.seekForward() }) {
                    Icon(Icons.Filled.Forward10, contentDescription = "+10 s", tint = Color.White, modifier = Modifier.size(28.dp))
                }

                TvIconButton(
                    onClick  = { vm.navigateEpisode(+1) },
                    enabled  = state.hasNextEpisode && !state.episodeNavigating,
                ) {
                    Icon(Icons.Filled.SkipNext, contentDescription = "Next episode", tint = Color.White, modifier = Modifier.size(28.dp))
                }

                Spacer(Modifier.weight(1f))
                SpeedSelector(
                    onSpeedSelected = { vm.setSpeed(it) },
                    onOpened        = { pauseForSettings() }
                )
            }
        }
    }
}

// ── Track picker panel ─────────────────────────────────────────────────────────

/**
 * Generic D-Pad-navigable bottom panel for selecting one item from a list.
 *
 * Used for both stream selection and subtitle track selection.
 * Pass [showNone] = true to add a "None / Off" option at the top.
 * [onSelect] receives null when "None" is chosen.
 */
@Composable
private fun TrackPickerPanel(
    title:         String,
    tracks:        List<String>,
    selectedIndex: Int?,
    showNone:      Boolean,
    onSelect:      (Int?) -> Unit,
    onDismiss:     () -> Unit
) {
    val closeFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { closeFocus.requestFocus() } }

    Surface(
        modifier       = Modifier.fillMaxWidth().focusGroup(),
        color          = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
        tonalElevation = 8.dp
    ) {
        Column(
            modifier            = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Header
            Row(
                modifier          = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    title,
                    modifier   = Modifier.weight(1f),
                    style      = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium,
                    color      = MaterialTheme.colorScheme.onSurface
                )
                TvIconButton(onClick = onDismiss, modifier = Modifier.focusRequester(closeFocus)) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = MaterialTheme.colorScheme.onSurface)
                }
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))

            // "None" / Off row
            if (showNone) {
                TrackPickerRow(
                    name       = "Off",
                    isSelected = selectedIndex == null,
                    onSelect   = { onSelect(null) }
                )
            }

            // Track rows
            tracks.forEachIndexed { idx, name ->
                TrackPickerRow(
                    name       = name,
                    isSelected = selectedIndex == idx,
                    onSelect   = { onSelect(idx) }
                )
            }
        }
    }
}

@Composable
private fun TrackPickerRow(
    name:      String,
    isSelected: Boolean,
    onSelect:  () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isFocused        by interactionSource.collectIsFocusedAsState()
    val primary           = MaterialTheme.colorScheme.primary

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = when {
                    isFocused  -> primary.copy(alpha = 0.18f)
                    isSelected -> primary.copy(alpha = 0.08f)
                    else       -> Color.Transparent
                },
                shape = RoundedCornerShape(8.dp)
            )
            .focusable(interactionSource = interactionSource)
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionCenter, Key.Enter -> { onSelect(); true }
                    else -> false
                }
            }
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment     = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Radio indicator
        Box(
            modifier = Modifier
                .size(18.dp)
                .border(
                    width = 2.dp,
                    color = if (isSelected || isFocused) primary else MaterialTheme.colorScheme.outline,
                    shape = RoundedCornerShape(50)
                ),
            contentAlignment = Alignment.Center
        ) {
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .size(9.dp)
                        .background(primary, RoundedCornerShape(50))
                )
            }
        }

        Text(
            name,
            style      = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color      = if (isSelected || isFocused) primary else MaterialTheme.colorScheme.onSurface
        )
    }
}

// ── TV control helpers ─────────────────────────────────────────────────────────

@Composable
private fun TvIconButton(
    onClick:  () -> Unit,
    modifier: Modifier = Modifier,
    enabled:  Boolean  = true,
    content:  @Composable () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    IconButton(
        onClick  = onClick,
        enabled  = enabled,
        modifier = modifier
            .onFocusChanged { focused = it.isFocused }
            .background(
                color = if (focused) Color.White.copy(alpha = 0.22f) else Color.Transparent,
                shape = RoundedCornerShape(8.dp)
            )
    ) {
        val alpha = if (enabled) 1f else 0.38f
        Box(modifier = Modifier.graphicsLayer { this.alpha = alpha }) { content() }
    }
}

@Composable
private fun TvTextButton(label: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    TextButton(
        onClick  = onClick,
        modifier = Modifier
            .onFocusChanged { focused = it.isFocused }
            .background(
                color = if (focused) Color.White.copy(alpha = 0.22f) else Color.Transparent,
                shape = RoundedCornerShape(8.dp)
            )
    ) {
        Text(label, color = Color.White, style = MaterialTheme.typography.labelMedium, maxLines = 1)
    }
}

// ── Progress bar ───────────────────────────────────────────────────────────────

@Composable
private fun ProgressBar(state: PlayerUiState) {
    val primary   = MaterialTheme.colorScheme.primary
    val buffColor = primary.copy(alpha = 0.35f)
    val bgColor   = Color.White.copy(alpha = 0.2f)
    val dur       = state.durationMs.takeIf { it > 0 } ?: return

    val progress  = (state.positionMs.toFloat() / dur).coerceIn(0f, 1f)
    val buffered  = (state.bufferedMs.toFloat() / dur).coerceIn(0f, 1f)
    val segments  = remember(state.skipTimes) {
        state.skipTimes?.toDisplaySegments() ?: emptyList()
    }

    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {

        Box(modifier = Modifier.fillMaxWidth().height(18.dp)) {
            val active = state.activeSkip
            if (active != null) {
                val midFrac = ((active.startSec + active.endSec) * 500f / dur)
                    .coerceIn(0f, 100f)
                val seg = segments.firstOrNull { it.startSec == active.startSec }
                val labelColor = seg?.color ?: primary

                Box(
                    modifier = Modifier
                        .fillMaxWidth(midFrac / 100f)
                        .wrapContentWidth(Alignment.End)
                ) {
                    Surface(
                        color    = labelColor.copy(alpha = 0.92f),
                        shape    = RoundedCornerShape(4.dp),
                        modifier = Modifier.padding(end = 4.dp)
                    ) {
                        Text(
                            text     = active.label,
                            color    = Color.Black.copy(alpha = 0.82f),
                            style    = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }
            }
        }

        Box(modifier = Modifier.fillMaxWidth().height(6.dp)) {
            val totalMs = dur.toFloat()

            Box(Modifier.fillMaxSize().background(bgColor, RoundedCornerShape(3.dp)))

            Box(Modifier.fillMaxWidth(buffered).fillMaxHeight().background(buffColor, RoundedCornerShape(3.dp)))

            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(primary, RoundedCornerShape(3.dp)))

            segments.forEach { seg ->
                val startFrac = (seg.startSec * 1000f / totalMs).coerceIn(0f, 1f)
                val widthFrac = ((seg.endSec - seg.startSec) * 1000f / totalMs).coerceIn(0f, 1f - startFrac)
                Row(Modifier.fillMaxHeight()) {
                    Spacer(Modifier.fillMaxWidth(startFrac))
                    Box(
                        Modifier
                            .fillMaxHeight()
                            .fillMaxWidth(widthFrac)
                            .background(seg.color.copy(alpha = 0.78f))
                    )
                }
            }

            // Playhead
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress)
                    .wrapContentWidth(Alignment.End)
                    .size(6.dp)
                    .background(Color.White, RoundedCornerShape(50))
            )
        }
    }
}

// ── Speed selector ─────────────────────────────────────────────────────────────

@Composable
private fun SpeedSelector(onSpeedSelected: (Float) -> Unit, onOpened: () -> Unit = {}) {
    var expanded by remember { mutableStateOf(false) }
    var current  by remember { mutableStateOf(1.0f) }
    var focused  by remember { mutableStateOf(false) }
    Box {
        TextButton(
            onClick  = { onOpened(); expanded = true },
            modifier = Modifier
                .onFocusChanged { focused = it.isFocused }
                .background(
                    color = if (focused) Color.White.copy(alpha = 0.22f) else Color.Transparent,
                    shape = RoundedCornerShape(8.dp)
                )
        ) {
            Text("${current}×", color = Color.White, style = MaterialTheme.typography.labelMedium)
        }
        DropdownMenu(
            expanded         = expanded,
            onDismissRequest = { expanded = false },
            modifier         = Modifier.background(MaterialTheme.colorScheme.surface)
        ) {
            listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f).forEach { speed ->
                DropdownMenuItem(
                    text    = { Text("${speed}×") },
                    onClick = { current = speed; onSpeedSelected(speed); expanded = false }
                )
            }
        }
    }
}

// ── Subtitle overlay ───────────────────────────────────────────────────────────

@Composable
fun SubtitleOverlay(text: String, prefs: SubtitlePrefs, modifier: Modifier = Modifier) {
    val textColor = runCatching {
        val hex  = prefs.colorHex.trimStart('#')
        val argb = hex.toLong(16)
        Color(
            alpha = ((argb shr 24) and 0xFF).toInt() / 255f,
            red   = ((argb shr 16) and 0xFF).toInt() / 255f,
            green = ((argb shr 8)  and 0xFF).toInt() / 255f,
            blue  = ( argb         and 0xFF).toInt() / 255f
        )
    }.getOrDefault(Color.White)

    Box(
        modifier = modifier
            .padding(horizontal = 32.dp)
            .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(4.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp)
    ) {
        Text(
            text       = text,
            color      = textColor,
            fontSize   = prefs.fontSize.sp,
            fontWeight = if (prefs.bold) FontWeight.Bold else FontWeight.Normal,
            textAlign  = TextAlign.Center
        )
    }
}

@Composable
private fun SubtitleSettingsPanel(
    prefs:     SubtitlePrefs,
    onUpdate:  (SubtitlePrefs) -> Unit,
    onDismiss: () -> Unit
) {
    val closeBtnFocus = remember { FocusRequester() }
    val trapRequester =
        remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { closeBtnFocus.requestFocus() } }

    Surface(
        modifier       = Modifier.fillMaxWidth().focusRequester(trapRequester).focusProperties { onExit = { cancelFocusChange() } }.focusGroup(),
        color          = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f),
        tonalElevation = 8.dp
    ) {
        Column(
            modifier            = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header
            Row(
                modifier          = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Subtitles",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface
                )
                TvIconButton(
                    onClick  = onDismiss,
                    modifier = Modifier.focusRequester(closeBtnFocus)
                ) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = MaterialTheme.colorScheme.onSurface)
                }
            }

            // ── Appearance ─────────────────────────────────────────────────
            SectionCard(title = "Appearance") {
                // Show subtitles toggle
                SettingsToggleRow(
                    label    = "Show subtitles",
                    subtitle = "Display subtitles during playback",
                    checked  = prefs.enabled,
                    onToggle = { onUpdate(prefs.copy(enabled = it)) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
                // Font size slider
                SettingsSliderRow(
                    label    = "Font size",
                    subtitle = "Adjust subtitle text size",
                    value    = prefs.fontSize,
                    range    = 12f..32f,
                    step     = 1f,
                    display  = "${prefs.fontSize.toInt()} sp",
                    onChange = { onUpdate(prefs.copy(fontSize = it)) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
                // Bold toggle
                SettingsToggleRow(
                    label    = "Bold text",
                    subtitle = "Make subtitle text bold",
                    checked  = prefs.bold,
                    onToggle = { onUpdate(prefs.copy(bold = it)) }
                )
            }

            // ── Translation ────────────────────────────────────────────────
            SectionCard(title = "Translation") {
                SettingsDropdownRow(
                    label    = "Auto-translate to",
                    subtitle = "Automatically translate subtitles",
                    selected = prefs.translateTo ?: "Off",
                    options  = listOf(null, "en", "de", "fr", "es", "ja", "ko", "zh"),
                    display  = { it ?: "Off" },
                    onSelect = { onUpdate(prefs.copy(translateTo = it)) }
                )
            }
        }
    }
}

// ── Themed Settings Rows ───────────────────────────────────────────────────────

@Composable
private fun SettingsToggleRow(
    label:    String,
    subtitle: String,
    checked:  Boolean,
    onToggle: (Boolean) -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isFocused        by interactionSource.collectIsFocusedAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (isFocused) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                else Color.Transparent
            )
            .focusable(interactionSource = interactionSource)
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionCenter, Key.Enter,
                    Key.DirectionLeft, Key.DirectionRight -> { onToggle(!checked); true }
                    else -> false
                }
            }
            .padding(16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment     = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label,    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,  color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
            Switch(
                checked         = checked,
                onCheckedChange = onToggle,
                modifier        = Modifier
                    .focusProperties { canFocus = false }
                    .border(
                        width = if (isFocused) 2.dp else 0.dp,
                        color = if (isFocused) MaterialTheme.colorScheme.primary else Color.Transparent,
                        shape = RoundedCornerShape(50)
                    )
            )
        }
    }
}

@Composable
private fun SettingsSliderRow(
    label:    String,
    subtitle: String,
    value:    Float,
    range:    ClosedFloatingPointRange<Float>,
    step:     Float,
    display:  String,
    onChange: (Float) -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isFocused        by interactionSource.collectIsFocusedAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (isFocused) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                else Color.Transparent
            )
            .focusable(interactionSource = interactionSource)
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionLeft  -> { onChange((value - step).coerceIn(range.start, range.endInclusive)); true }
                    Key.DirectionRight -> { onChange((value + step).coerceIn(range.start, range.endInclusive)); true }
                    else -> false
                }
            }
            .padding(16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment     = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label,    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,  color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        Row(
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                display,
                style      = MaterialTheme.typography.labelSmall,
                color      = if (isFocused) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                fontWeight = FontWeight.SemiBold
            )
            Slider(
                value         = value,
                onValueChange = onChange,
                valueRange    = range,
                modifier      = Modifier
                    .width(140.dp)
                    .focusProperties { canFocus = false },
                colors = SliderDefaults.colors(
                    thumbColor         = if (isFocused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    activeTrackColor   = if (isFocused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    inactiveTrackColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)
                )
            )
        }
    }
}

@Composable
private fun <T> SettingsDropdownRow(
    label:    String,
    subtitle: String,
    selected: String,
    options:  List<T>,
    display:  (T) -> String,
    onSelect: (T) -> Unit
) {
    val primary           = MaterialTheme.colorScheme.primary
    val interactionSource = remember { MutableInteractionSource() }
    val indication        = remember(primary) { FocusIndication(primary, cornerRadiusDp = 8.dp) }
    var expanded         by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment     = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label,    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall,  color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        Box(
            modifier = Modifier
                .indication(interactionSource, indication)
                .focusable(interactionSource = interactionSource)
                .onKeyEvent { event ->
                    if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                    when (event.key) {
                        Key.DirectionCenter, Key.Enter -> { expanded = true; true }
                        else -> false
                    }
                }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Row(
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    selected,
                    style      = MaterialTheme.typography.labelMedium,
                    color      = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
                Icon(Icons.Filled.ArrowDropDown, null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text    = { Text(display(option)) },
                        onClick = { onSelect(option); expanded = false }
                    )
                }
            }
        }
    }
}
/**
 * Eigener Toggle-Indikator für TV: nicht fokussierbar (kein Interference mit
 * dem focusable() der Row), rein visuell.
 */

// ── Hilfsfunktionen ────────────────────────────────────────────────────────────

private fun formatMs(ms: Long): String {
    if (ms <= 0) return "0:00"
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}