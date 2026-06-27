package com.nyantv.ui

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.remember
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.focusGroup
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.LocalFocusManager
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.util.UnstableApi
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import kotlinx.coroutines.delay
import coil.compose.AsyncImage
import com.nyantv.data.ServiceType
import com.nyantv.ui.anime.AnimeScreen
import com.nyantv.ui.home.HomeScreen
import com.nyantv.ui.library.LibraryScreen
import com.nyantv.ui.player.PlayerArgs
import com.nyantv.ui.player.PlayerScreen
import com.nyantv.ui.player.PlayerViewModel
import com.nyantv.ui.screens.DetailScreen
import com.nyantv.ui.screens.SearchScreen
import com.nyantv.ui.settings.SettingsScreen
import com.nyantv.ui.settings.sub_settings.AboutScreen
import com.nyantv.ui.settings.sub_settings.AccountsScreen
import com.nyantv.ui.settings.sub_settings.ExperimentalScreen
import com.nyantv.ui.settings.sub_settings.ExtensionsScreen
import com.nyantv.ui.settings.sub_settings.LogsScreen
import com.nyantv.ui.settings.sub_settings.PlayerSettingsScreen
import com.nyantv.ui.settings.sub_settings.ThemeScreen
import com.nyantv.ui.theme.FocusIndication
import com.nyantv.viewmodel.AppViewModel
import kotlinx.coroutines.launch

// ─── Routes ────────────────────────────────────────────────────────────────────

sealed class Screen(val route: String, val label: String, val icon: ImageVector) {
    object Home     : Screen("home",     "Home",    Icons.Filled.Home)
    object Anime    : Screen("anime",    "Anime",   Icons.Filled.Movie)
    object Library  : Screen("library",  "Library", Icons.Filled.VideoLibrary)
    object Settings : Screen("settings", "Settings",Icons.Filled.Settings)
}

fun Screen.displayLabel(serviceType: ServiceType) = when {
    this is Screen.Anime && serviceType == ServiceType.SIMKL -> "Cinema"
    else -> label
}

private val navItems = listOf(Screen.Home, Screen.Anime, Screen.Library, Screen.Settings)


// ─── Root composable ───────────────────────────────────────────────────────────

@androidx.annotation.OptIn(UnstableApi::class)
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun MainNavigation(
    vm:                AppViewModel = viewModel(),
    deepLink:          Triple<String, String, String>? = null,
    onDeepLinkConsumed: () -> Unit = {},
) {
    val navController = rememberNavController()
    val backEntry     by navController.currentBackStackEntryAsState()
    val currentRoute   = backEntry?.destination?.route
    val serviceType   by vm.serviceType.collectAsStateWithLifecycle()

    val detailHistory   = remember { mutableStateListOf<String>() }
    val sidebarFocusReq = remember { FocusRequester() }
    val focusManager    = LocalFocusManager.current
    val scope           = rememberCoroutineScope()

    var showPlayer by remember { mutableStateOf(false) }
    var playerSessionKey by remember { mutableIntStateOf(0) }

    val returnFocusReq = remember { FocusRequester() }

    val detailOpen = detailHistory.isNotEmpty()

    var playerReturnCount by remember { mutableIntStateOf(0) }

    var pendingPlayerTab by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(deepLink) {
        val (linkServiceKey, mediaId, _) = deepLink ?: return@LaunchedEffect

        val currentServiceKey = when (vm.serviceType.value) {
            ServiceType.ANILIST, ServiceType.MAL -> "anilist_mal"
            ServiceType.SIMKL                    -> "simkl"
        }

        if (linkServiceKey != currentServiceKey) {
            onDeepLinkConsumed()
            return@LaunchedEffect
        }

        detailHistory.clear()
        detailHistory.add(mediaId)
        pendingPlayerTab = mediaId
        onDeepLinkConsumed()
    }

    fun openDetail(id: String) {
        focusManager.clearFocus(force = true)
        detailHistory.add(id)
    }

    Box(modifier = Modifier.fillMaxSize()) {

        Row(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .then(
                    if (detailOpen && !showPlayer)
                        Modifier.focusProperties { onEnter = { cancelFocusChange() } }
                    else Modifier
                )
        ) {
            if (!detailOpen && !showPlayer) {
                Sidebar(
                    items           = navItems,
                    currentRoute    = currentRoute,
                    serviceType     = serviceType,
                    vm              = vm,
                    sidebarFocusReq = sidebarFocusReq,
                    onNavigate      = { screen ->
                        if (currentRoute == "search") navController.popBackStack()
                        navController.navigate(screen.route) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState    = true
                        }
                    }
                )
            }

            NavHost(
                navController    = navController,
                startDestination = Screen.Home.route,
                modifier         = Modifier
                    .weight(1f)
                    .then(
                        if (detailOpen && !showPlayer)
                            Modifier.focusProperties { onEnter = { cancelFocusChange() } }
                        else Modifier
                    ),
                enterTransition    = { fadeIn(tween(450)) },
                exitTransition     = { fadeOut(tween(450)) },
                popEnterTransition = { fadeIn(tween(450)) },
                popExitTransition  = { fadeOut(tween(450)) }
            ) {
                composable(Screen.Home.route)       { HomeScreen(vm, navController) { openDetail(it) } }
                composable(Screen.Anime.route)      { AnimeScreen(vm, navController) { openDetail(it) } }
                composable(Screen.Library.route)    { LibraryScreen(vm, navController) { openDetail(it) } }
                composable("search")                { SearchScreen(vm, navController, sidebarFocusReq) { openDetail(it) } }
                composable(Screen.Settings.route)   { SettingsScreen(vm, navController) }
                composable("settings/accounts")     { AccountsScreen(vm, navController) }
                composable("settings/theme")        { ThemeScreen(vm, navController) }
                composable("settings/logs")         { LogsScreen(navController) }
                composable("settings/about")        { AboutScreen(navController) }
                composable("settings/experimental") { ExperimentalScreen(navController, onOpenPlayer = { showPlayer = true }) }
                composable("settings/player")       { PlayerSettingsScreen(navController) }
                composable("settings/extensions")   { ExtensionsScreen(navController) }
            }
        }

        // ── DetailScreen Overlay ───────────────────────────────────────────
        if (detailHistory.isNotEmpty()) {
            detailHistory.lastOrNull()?.let { id ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .focusGroup()
                        .then(
                            if (!showPlayer)
                                Modifier.focusProperties { onExit = { cancelFocusChange() } }
                            else Modifier
                        )
                ) {
                    DetailScreen(
                        id                 = id,
                        vm                 = vm,
                        returnFocusReq     = returnFocusReq,
                        playerReturnCount  = playerReturnCount,
                        autoOpenPlayerTab  = pendingPlayerTab == id,
                        onAutoTabConsumed  = { pendingPlayerTab = null },
                        onBack             = { detailHistory.removeLastOrNull() },
                        onNavigateToDetail = { newId ->
                            detailHistory.remove(newId)
                            detailHistory.add(newId)
                        },
                        onNavigateToPlayer = { showPlayer = true }
                    )
                }
            }
        }

        // ── PlayerScreen Overlay ───────────────────────────────────────────
        if (showPlayer) {
            key(playerSessionKey) {
                PlayerScreen(
                    appVm  = vm,
                    onBack = {
                        showPlayer = false
                        playerSessionKey++
                        playerReturnCount++
                        scope.launch {
                            delay(100)
                            runCatching { returnFocusReq.requestFocus() }
                        }
                    }
                )
            }
        }
    }
}


// ─── Sidebar ───────────────────────────────────────────────────────────────────

@Composable
private fun Sidebar(
    items:           List<Screen>,
    currentRoute:    String?,
    serviceType:     ServiceType,
    vm:              AppViewModel,
    sidebarFocusReq: FocusRequester,
    onNavigate:      (Screen) -> Unit
) {
    val profile  by vm.profile.collectAsStateWithLifecycle()
    val loggedIn by vm.isLoggedIn.collectAsStateWithLifecycle()

    val focusOwnerRoute = when (currentRoute) {
        "search" -> Screen.Anime.route
        else     -> currentRoute
    }

    Column(
        modifier = Modifier
            .width(80.dp)
            .fillMaxHeight()
            .background(MaterialTheme.colorScheme.surface)
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceContainer),
            contentAlignment = Alignment.Center
        ) {
            if (loggedIn && profile?.avatar != null) {
                AsyncImage(
                    model              = profile!!.avatar,
                    contentDescription = "Profile",
                    modifier           = Modifier.fillMaxSize().clip(CircleShape)
                )
            } else {
                Icon(
                    Icons.Filled.Person, contentDescription = "Profile",
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                )
            }
        }

        Spacer(Modifier.height(16.dp))

        items.forEach { screen ->
            SidebarItem(
                icon           = screen.icon,
                label          = screen.displayLabel(serviceType),
                selected       = currentRoute == screen.route,
                focusRequester = if (screen.route == focusOwnerRoute) sidebarFocusReq else null,
                onClick        = { onNavigate(screen) }
            )
        }
    }
}

// ─── Sidebar item ──────────────────────────────────────────────────────────────

@Composable
private fun SidebarItem(
    icon:           ImageVector,
    label:          String,
    selected:       Boolean,
    focusRequester: FocusRequester? = null,
    onClick:        () -> Unit
) {
    val primary           = MaterialTheme.colorScheme.primary
    val sidebarIndication = remember(primary) { FocusIndication(primary, cornerRadiusDp = 12.dp) }
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed        by interactionSource.collectIsPressedAsState()
    var keepHighlight    by remember { mutableStateOf(false) }

    LaunchedEffect(isPressed) {
        if (isPressed) keepHighlight = true
        else { delay(150); keepHighlight = false }
    }

    val color = if (selected) MaterialTheme.colorScheme.primary
    else          MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)

    val bgColor = when {
        isPressed || keepHighlight || selected -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
        else                                   -> MaterialTheme.colorScheme.surface
    }

    Column(
        modifier = Modifier
            .width(64.dp)
            .clip(MaterialTheme.shapes.medium)
            .background(bgColor)
            .then(focusRequester?.let { Modifier.focusRequester(it) } ?: Modifier)
            .clickable(
                interactionSource = interactionSource,
                indication        = sidebarIndication,
                onClick           = onClick
            )
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(icon, contentDescription = label, tint = color, modifier = Modifier.size(22.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = color)
    }
}