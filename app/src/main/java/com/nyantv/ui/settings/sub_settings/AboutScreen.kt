package com.nyantv.ui.settings.sub_settings

import android.content.Intent
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.nyantv.ui.utils.SubScreenHeader
import androidx.core.net.toUri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.URL

// ── Bot exclusion ─────────────────────────────────────────────────────────────

private val EXCLUDED_IDS = setOf(
    "198982749", // github-actions[bot]
    "41898282",  // github-actions (actions-user)
    "65916846",  // actions-user
    "49699333",  // dependabot[bot]
    "13309880",  // code-factor
    "86238378",  // hoemotion (repo dev, shown separately)
)

private val EXCLUDED_LOGINS = setOf("actions-user", "code-factor", "github-actions", "dependabot", "openai")

private fun isBot(login: String, id: String, type: String): Boolean {
    val l = login.lowercase()
    return l in EXCLUDED_LOGINS || id in EXCLUDED_IDS || type == "Bot" || l.endsWith("[bot]") || l.endsWith("-bot")
}

// ── Curated contributors (override display fields, pick up live counts) ───────

private data class Contributor(val login: String, val id: String, val name: String, val avatar: String, val url: String, val role: String, val commits: Int = 0, val pinned: Boolean = false)

private val CURATED = mapOf(
    "itsmechinmoy" to Contributor("itsmechinmoy", "167056923", "itsmechinmoy", "https://avatars.githubusercontent.com/u/167056923", "https://github.com/itsmechinmoy", "Contributor & Early-Supporter", pinned = true),
)

// ── GitHub fetch ──────────────────────────────────────────────────────────────

private suspend fun fetchContributors(): List<Contributor> = withContext(Dispatchers.IO) {
    val byLogin = mutableMapOf<String, Contributor>()
    var page = 1
    while (true) {
        val json = runCatching {
            URL("https://api.github.com/repos/NyanTV/NyanTV/contributors?per_page=100&page=$page")
                .openConnection().apply { setRequestProperty("Accept", "application/vnd.github.v3+json"); connectTimeout = 10_000; readTimeout = 10_000 }
                .getInputStream().bufferedReader().readText()
        }.getOrNull() ?: break
        val arr = runCatching { JSONArray(json) }.getOrNull() ?: break
        if (arr.length() == 0) break
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val login = o.optString("login").trim().ifEmpty { continue }
            val id = o.optInt("id").toString()
            if (isBot(login, id, o.optString("type"))) continue
            byLogin[login.lowercase()] = Contributor(login, id, login, o.optString("avatar_url"), o.optString("html_url"), "Contributor", commits = o.optInt("contributions"))
        }
        page++
    }

    val result = (byLogin.keys + CURATED.keys).map { key ->
        val c = CURATED[key]; val a = byLogin[key]
        Contributor(
            login   = c?.login ?: a?.login ?: key,
            id      = c?.id ?: a?.id ?: "",
            name    = c?.name ?: a?.name ?: key,
            avatar  = c?.avatar ?: a?.avatar ?: "https://avatars.githubusercontent.com/$key",
            url     = c?.url ?: a?.url ?: "https://github.com/$key",
            role    = c?.role ?: "Contributor",
            commits = a?.commits ?: 0,
            pinned  = c?.pinned ?: false,
        )
    }
    result.sortedWith(compareByDescending<Contributor> { it.pinned }.thenByDescending { it.commits })
}

// ── Screen ────────────────────────────────────────────────────────────────────

@Composable
fun AboutScreen(navController: NavController) {
    val context = LocalContext.current
    val version = remember {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }

    var contributors by remember { mutableStateOf<List<Contributor>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        contributors = runCatching { fetchContributors() }.getOrDefault(emptyList())
        loading = false
    }

    fun openUrl(url: String) {
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()))
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        SubScreenHeader(title = "About", navController = navController)

        // ── App card ───────────────────────────────────────────────────────────
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape    = MaterialTheme.shapes.large,
            colors   = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(
                modifier            = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AsyncImage(
                    model              = "file:///android_asset/images/logo_transparent.png",
                    contentDescription = "NyanTV Logo",
                    contentScale       = ContentScale.Fit,
                    modifier           = Modifier
                        .size(100.dp)
                        .border(2.dp, MaterialTheme.colorScheme.primary, CircleShape)
                        .padding(4.dp)
                        .clip(CircleShape)
                )
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("NyanTV", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                    Text("v$version", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }

                Spacer(Modifier.height(4.dp))

                // Developer row
                OutlinedCard(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
                    Row(
                        modifier              = Modifier.fillMaxWidth().padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment     = Alignment.CenterVertically
                    ) {
                        AsyncImage(
                            model              = "https://avatars.githubusercontent.com/u/86238378?s=400",
                            contentDescription = null,
                            modifier           = Modifier.size(40.dp).clip(CircleShape)
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Developer", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                            Text("hoemotion", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                        }
                        IconButton(onClick = { openUrl("https://github.com/hoemotion") }) {
                            Icon(Icons.Filled.Code, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }

        // ── Social ─────────────────────────────────────────────────────────────
        AboutSection(title = "Social", subtitle = "Join us for feedback or feature requests") {
            AboutTile(icon = Icons.AutoMirrored.Filled.Send,    title = "Telegram", onClick = { openUrl("https://t.me/NyanSupport") })
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
            AboutTile(icon = Icons.Filled.Forum,   title = "Discord",  onClick = { openUrl("https://discord.gg/y2vaFPXs4F") })
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
            AboutTile(icon = Icons.AutoMirrored.Filled.Chat,    title = "Stoat",    onClick = { openUrl("https://stoat.chat/invite/fKzse8yy") })
        }

        // ── Contributors ─────────────────────────────────────────────────────────
        AboutSection(title = "Contributors", subtitle = "Thanks to everyone who helped build NyanTV") {
            if (loading) {
                Box(Modifier.fillMaxWidth().padding(vertical = 20.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                }
            } else {
                contributors.forEachIndexed { index, c ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        AsyncImage(model = c.avatar, contentDescription = null, modifier = Modifier.size(36.dp).clip(CircleShape))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(c.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                            Text(
                                buildString {
                                    append(c.role)
                                    val stats = listOfNotNull(
                                        if (c.commits > 0) "${c.commits} commit${if (c.commits == 1) "" else "s"}" else null,
                                    )
                                    if (stats.isNotEmpty()) append(" · ${stats.joinToString(" · ")}")
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                            )
                        }
                        IconButton(onClick = { openUrl(c.url) }) {
                            Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
        }

        // ── Development ────────────────────────────────────────────────────────
        AboutSection(title = "Development", subtitle = "Explore the project and contribute") {
            AboutTile(icon = Icons.Filled.Code,        title = "GitHub",          subtitle = "View source code", onClick = { openUrl("https://github.com/NyanTV/NyanTV") })
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
            AboutTile(icon = Icons.Filled.Coffee,      title = "Ko-fi",           subtitle = "Support the developer", onClick = { openUrl("https://ko-fi.com/hoemotion") })
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
            AboutTile(icon = Icons.Filled.BugReport,   title = "Features/Issues", subtitle = "Report bugs or suggest features", onClick = { openUrl("https://github.com/NyanTV/NyanTV/issues") })
        }
    }
}

@Composable
private fun AboutSection(
    title: String,
    subtitle: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape    = MaterialTheme.shapes.large,
        colors   = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column {
            Column(modifier = Modifier.padding(start = 16.dp, top = 14.dp, bottom = 8.dp)) {
                Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))
            content()
        }
    }
}

@Composable
private fun AboutTile(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment     = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)) }
        }
        IconButton(onClick = onClick) {
            Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(18.dp))
        }
    }
}
