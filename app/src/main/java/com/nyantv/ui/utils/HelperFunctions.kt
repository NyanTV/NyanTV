package com.nyantv.ui.utils

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.navigation.NavController
import com.nyantv.AniZipEpisodeMeta
import com.nyantv.ui.theme.FocusIndication
import eu.kanade.tachiyomi.animesource.model.SEpisode

@Composable
fun ScoreBadge(averageScore: Int?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = if (averageScore == null || averageScore == 0) {
                "%.1f".format(0f)
            } else {
                "%.1f".format(averageScore / 10f)
            },
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(Modifier.width(2.dp))
        Icon(
            imageVector        = Icons.Filled.Star,
            contentDescription = null,
            tint               = Color(0xFFFFD700),
            modifier           = Modifier.size(12.dp)
        )
    }
}

@Composable
fun Modifier.focusBorder(
    shape: Shape,
    gap: Dp = 1.dp,
    color: Color = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
    inset: Boolean = false
): Modifier {
    var isFocused by remember { mutableStateOf(false) }
    return this
        .onFocusChanged { isFocused = it.isFocused }
        .drawWithContent {
            drawContent()
            if (isFocused) {
                val strokeWidth = 2f * density
                if (inset) {
                    val half = strokeWidth / 2f
                    val insetSize = Size(size.width - half * 2, size.height - half * 2)
                    val outline = shape.createOutline(insetSize, layoutDirection, this)
                    translate(left = half, top = half) {
                        drawOutline(outline = outline, color = color, style = Stroke(width = strokeWidth))
                    }
                } else {
                    val gapPx = gap.toPx()
                    val largerSize = Size(size.width + gapPx * 2, size.height + gapPx * 2)
                    val outline = shape.createOutline(largerSize, layoutDirection, this)
                    translate(left = -gapPx, top = -gapPx) {
                        drawOutline(outline = outline, color = color, style = Stroke(width = strokeWidth))
                    }
                }
            }
        }
}

@Composable
private fun SectionCardDialog(
    title: String,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    val primary        = MaterialTheme.colorScheme.primary
    val backIndication = remember(primary) { FocusIndication(primary, cornerRadiusDp = 8.dp) }
    val backInteraction = remember { MutableInteractionSource() }

    Dialog(
        onDismissRequest = onDismiss,
        properties       = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth(0.5f)
                .wrapContentHeight(),
            shape  = MaterialTheme.shapes.extraLarge,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 6.dp)
        ) {
            Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(
                    modifier              = Modifier.fillMaxWidth(),
                    verticalAlignment     = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(RoundedCornerShape(9.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .clickable(
                                interactionSource = backInteraction,
                                indication        = backIndication
                            ) { onDismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Close",
                            tint     = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                    Text(
                        text       = title,
                        style      = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color      = MaterialTheme.colorScheme.onBackground
                    )
                }

                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape    = MaterialTheme.shapes.large,
                    colors   = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface
                    )
                ) {
                    Column { content() }
                }
            }
        }
    }
}

@Composable
fun SectionCard(
    title: String,
    dialogContent: (@Composable (onDismiss: () -> Unit) -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    var showDialog by remember { mutableStateOf(false) }

    if (showDialog && dialogContent != null) {
        SectionCardDialog(
            title      = title,
            onDismiss  = { showDialog = false },
            content    = { dialogContent { showDialog = false } }
        )
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (dialogContent != null)
                    Modifier.clickable { showDialog = true }
                else
                    Modifier
            ),
        shape  = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column {
            if (dialogContent != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusBorder(MaterialTheme.shapes.large, inset = true)
                        .padding(start = 16.dp, top = 14.dp, bottom = 14.dp, end = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment     = Alignment.CenterVertically
                ) {
                    Text(
                        text       = title,
                        style      = MaterialTheme.typography.labelLarge,
                        color      = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Icon(
                        Icons.AutoMirrored.Filled.OpenInNew,
                        contentDescription = null,
                        tint     = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        modifier = Modifier.size(18.dp)
                    )
                }
            } else {
                Text(
                    text       = title,
                    style      = MaterialTheme.typography.labelLarge,
                    color      = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                    modifier   = Modifier.padding(start = 16.dp, top = 14.dp, bottom = 14.dp, end = 16.dp)
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))
            content()
        }
    }
}

@Composable
fun SubScreenHeader(title: String, navController: NavController) {
    val primary         = MaterialTheme.colorScheme.primary
    val backIndication  = remember(primary) { FocusIndication(primary, cornerRadiusDp = 8.dp) }
    val backInteraction = remember { MutableInteractionSource() }

    Row(
        modifier              = Modifier.fillMaxWidth(),
        verticalAlignment     = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f))
                .clickable(
                    interactionSource = backInteraction,
                    indication        = backIndication
                ) { navController.popBackStack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint     = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(20.dp)
            )
        }
        Text(
            text       = title,
            style      = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color      = MaterialTheme.colorScheme.onBackground
        )
    }
}

fun Map<String, AniZipEpisodeMeta>.resolveEpisodeMeta(episodeNumber: Float): AniZipEpisodeMeta? {
    if (isEmpty()) return null
    val keys = linkedSetOf<String>()
    if (episodeNumber % 1f == 0f) {
        keys.add(episodeNumber.toInt().toString())
        keys.add(episodeNumber.toString())
    } else {
        keys.add("%.1f".format(episodeNumber))
        keys.add(episodeNumber.toString())
    }
    return keys.firstNotNullOfOrNull { this[it] }
}

fun SEpisode.displayName(episodeMeta: Map<String, AniZipEpisodeMeta> = emptyMap()): String {
    val meta = episodeMeta.resolveEpisodeMeta(episode_number)
    val metaTitle = meta?.title?.takeIf { it.isNotBlank() }

    return name.takeIf { it.contains(":") }
        ?: metaTitle?.let { "Episode ${episode_number.toInt()}: $it" }
        ?: name.ifBlank { "Episode ${episode_number.toInt()}" }
}