package com.nyantv.ui.anime

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.nyantv.data.ServiceType
import com.nyantv.ui.*
import com.nyantv.ui.utils.NetworkStatusContent
import com.nyantv.ui.utils.focusBorder
import com.nyantv.ui.widgets.HomeHeroCarousel
import com.nyantv.viewmodel.AppViewModel

// ─── Anime browse screen ───────────────────────────────────────────────────────

@Composable
fun AnimeScreen(vm: AppViewModel, navController: NavController, onDetailClick: (String) -> Unit) {
    val trending        by vm.trending.collectAsStateWithLifecycle()
    val popular         by vm.popular.collectAsStateWithLifecycle()
    val upcoming        by vm.upcoming.collectAsStateWithLifecycle()
    val recentlyUpdated by vm.recentlyUpdated.collectAsStateWithLifecycle()
    val networkState    by vm.networkState.collectAsStateWithLifecycle()
    val serviceType     by vm.serviceType.collectAsStateWithLifecycle()

    val korean          by vm.korean.collectAsStateWithLifecycle()
    val japanese        by vm.japanese.collectAsStateWithLifecycle()
    val us              by vm.us.collectAsStateWithLifecycle()
    val uk              by vm.uk.collectAsStateWithLifecycle()
    val canada          by vm.canada.collectAsStateWithLifecycle()

    NetworkStatusContent(
        state       = networkState,
        serviceName = serviceType.name.lowercase().replaceFirstChar { it.uppercase() },
        onRetry     = { vm.retryLoad() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Spacer(Modifier.height(16.dp))

            // ── Search button (navigates to dedicated search screen) ───────────
            SearchButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp).focusBorder(MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.primary, inset = true),
                onClick  = { navController.navigate("search") },
                serviceType = serviceType
            )

            // ── Browse sections ───────────────────────────────────────────────
            if (trending.isNotEmpty()) {
                HomeHeroCarousel(
                    items    = trending,
                    onItemClick = { onDetailClick(it.id) },
                    vm = vm,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            }

            if (serviceType == ServiceType.SIMKL) {
                SectionRow(title = "Trending Today", items = trending, onItemClick = { onDetailClick(it.id) })
                SectionRow(title = "Popular Hits", items = popular, onItemClick = { onDetailClick(it.id) })
                if (korean.isNotEmpty()) SectionRow(title = "Korean Discoveries", items = korean, onItemClick = { onDetailClick(it.id) })
                if (japanese.isNotEmpty()) SectionRow(title = "Japanese Discoveries", items = japanese, onItemClick = { onDetailClick(it.id) })
                if (us.isNotEmpty()) SectionRow(title = "US Discoveries", items = us, onItemClick = { onDetailClick(it.id) })
                if (uk.isNotEmpty()) SectionRow(title = "UK Discoveries", items = uk, onItemClick = { onDetailClick(it.id) })
                if (canada.isNotEmpty()) SectionRow(title = "Canada Discoveries", items = canada, onItemClick = { onDetailClick(it.id) })
            } else {
                SectionRow(title = "Recently Updated", items = recentlyUpdated, onItemClick = { onDetailClick(it.id) })
                SectionRow(title = "Trending",          items = trending,        onItemClick = { onDetailClick(it.id) })
                SectionRow(title = "Popular",           items = popular,         onItemClick = { onDetailClick(it.id) })
                SectionRow(title = "Upcoming",          items = upcoming,        onItemClick = { onDetailClick(it.id) })
            }
        }
    }
}

// ─── Clickable search bar surface ─────────────────────────────────────────────

@Composable
private fun SearchButton(modifier: Modifier = Modifier, onClick: () -> Unit, serviceType: ServiceType) {
    Surface(
        onClick   = onClick,
        modifier  = modifier,
        shape     = MaterialTheme.shapes.large,
        color     = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
        border    = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)),
        tonalElevation = 0.dp
    ) {
        Row(
            modifier            = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment   = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            )
            Text(
                text  ="Search ${if (serviceType == ServiceType.SIMKL) "movies and shows" else "anime"}…",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }
    }
}
