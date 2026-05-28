package com.nyantv.ui.widgets

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.nyantv.data.Media
import com.nyantv.data.ServiceType
import com.nyantv.data.TrackedMedia
import com.nyantv.ui.SectionRow
import com.nyantv.viewmodel.AppViewModel

@Composable
fun HomeSections(vm: AppViewModel, navController: NavController, onDetailClick: (String) -> Unit) {
    val service         by vm.serviceType.collectAsStateWithLifecycle()
    val animeList       by vm.animeList.collectAsStateWithLifecycle()
    val trending        by vm.trending.collectAsStateWithLifecycle()
    val popular         by vm.popular.collectAsStateWithLifecycle()
    val trendingMovies  by vm.trendingMovies.collectAsStateWithLifecycle()
    val trendingShows   by vm.trendingShows.collectAsStateWithLifecycle()

    val anilistContinue by vm.anilistShowContinue.collectAsStateWithLifecycle()
    val anilistPlanned  by vm.anilistShowPlanned.collectAsStateWithLifecycle()
    val malContinue     by vm.malShowContinue.collectAsStateWithLifecycle()
    val malPlanned      by vm.malShowPlanned.collectAsStateWithLifecycle()
    val simklContMovies by vm.simklShowContMovies.collectAsStateWithLifecycle()
    val simklPlanMovies by vm.simklShowPlanMovies.collectAsStateWithLifecycle()
    val simklContSeries by vm.simklShowContSeries.collectAsStateWithLifecycle()
    val simklPlanSeries by vm.simklShowPlanSeries.collectAsStateWithLifecycle()

    val trackedMap = animeList.associateBy { it.id }

    fun TrackedMedia.toMedia() = Media(
        id           = id,
        title        = title,
        poster       = poster,
        episodes     = totalEpisodes,
        averageScore = averageScore?.takeIf { it > 0f },
        serviceType  = service,
        idMal        = if (service == ServiceType.MAL) id else null,
    )
    fun List<TrackedMedia>.toMedia() = map { it.toMedia() }
    fun navigate(id: String) = onDetailClick(id)

    when (service) {
        ServiceType.ANILIST -> {
            val watching = animeList.filter { it.watchingStatus == "CURRENT" }
            val planned  = animeList.filter { it.watchingStatus == "PLANNING" }
            if (anilistContinue && watching.isNotEmpty()) {
                SectionRow(title = "Continue Watching", items = watching.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (anilistPlanned && planned.isNotEmpty()) {
                SectionRow(title = "Planned Anime", items = planned.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            SectionRow(title = "Trending Now",  items = trending, onItemClick = { navigate(it.id) })
            SectionRow(title = "Popular Anime", items = popular,  onItemClick = { navigate(it.id) })
        }

        ServiceType.MAL -> {
            val watching = animeList.filter { it.watchingStatus == "CURRENT" }
            val planned  = animeList.filter { it.watchingStatus == "PLANNING" }
            if (malContinue && watching.isNotEmpty()) {
                SectionRow(title = "Continue Watching", items = watching.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (malPlanned && planned.isNotEmpty()) {
                SectionRow(title = "Planned Anime", items = planned.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            SectionRow(title = "Trending Now",  items = trending, onItemClick = { navigate(it.id) })
            SectionRow(title = "Popular Anime", items = popular,  onItemClick = { navigate(it.id) })
        }

        ServiceType.SIMKL -> {
            val contMovies = animeList.filter { it.watchingStatus == "CURRENT"  && it.isMovie == true }
            val planMovies = animeList.filter { it.watchingStatus == "PLANNING" && it.isMovie == true }
            val contSeries = animeList.filter { it.watchingStatus == "CURRENT"  && it.isMovie != true }
            val planSeries = animeList.filter { it.watchingStatus == "PLANNING" && it.isMovie != true }

            if (simklContMovies && contMovies.isNotEmpty()) {
                SectionRow(title = "Continue Watching (Movies)", items = contMovies.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (simklPlanMovies && planMovies.isNotEmpty()) {
                SectionRow(title = "Planned Movies", items = planMovies.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (simklContSeries && contSeries.isNotEmpty()) {
                SectionRow(title = "Continue Watching (Series)", items = contSeries.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (simklPlanSeries && planSeries.isNotEmpty()) {
                SectionRow(title = "Planned Series", items = planSeries.toMedia(), onItemClick = { navigate(it.id) }, trackedMap = trackedMap)
            }
            if (trendingMovies.isNotEmpty()) {
                SectionRow(title = "Trending Movies", items = trendingMovies, onItemClick = { navigate(it.id) })
            }
            if (trendingShows.isNotEmpty()) {
                SectionRow(title = "Trending Shows", items = trendingShows, onItemClick = { navigate(it.id) })
            }
        }
    }
}
