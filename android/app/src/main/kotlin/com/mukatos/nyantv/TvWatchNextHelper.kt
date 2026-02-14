package com.mukatos.nyantv

import android.content.Context
import android.database.Cursor
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class TvWatchNextHelper(private val context: Context) {
    private val scope = CoroutineScope(Dispatchers.Main)

    fun updateWatchNext(data: Map<String, Any>) {
        scope.launch {
            try {
                val mediaId = data["mediaId"] as String
                val title = data["title"] as String
                val episodeTitle = data["episodeTitle"] as String
                val coverUrl = data["coverUrl"] as? String
                val posterUrl = data["posterUrl"] as? String
                val progress = (data["progress"] as Number).toInt()
                val episodeNumber = data["episodeNumber"] as String
                val currentPosition = (data["currentPosition"] as Number).toLong()
                val duration = (data["duration"] as Number).toLong()

                val imageUrl = coverUrl?.takeIf { it.isNotBlank() }
                    ?: posterUrl?.takeIf { it.isNotBlank() }
                    ?: return@launch

                removeOtherEntries(mediaId)

                val existingId = findWatchNextProgram(mediaId)
                val programBuilder = WatchNextProgram.Builder()
                    .setType(TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE)
                    .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                    .setTitle(title)
                    .setEpisodeTitle(episodeTitle)
                    .setEpisodeNumber(episodeNumber.toIntOrNull() ?: 0)
                    .setPosterArtUri(Uri.parse(imageUrl))
                    .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
                    .setLastPlaybackPositionMillis(currentPosition.toInt())
                    .setDurationMillis(duration.toInt())
                    .setIntentUri(Uri.parse("nyantv://watch/$mediaId/$episodeNumber"))
                    .setInternalProviderId(mediaId)

                if (existingId != null) {
                    context.contentResolver.update(
                        TvContractCompat.buildWatchNextProgramUri(existingId),
                        programBuilder.build().toContentValues(),
                        null, null
                    )
                } else {
                    context.contentResolver.insert(
                        TvContractCompat.WatchNextPrograms.CONTENT_URI,
                        programBuilder.build().toContentValues()
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("TvWatchNext", "Update failed", e)
            }
        }
    }

    private fun removeOtherEntries(currentMediaId: String) {
        try {
            val cursor: Cursor? = context.contentResolver.query(
                TvContractCompat.WatchNextPrograms.CONTENT_URI,
                arrayOf(TvContractCompat.WatchNextPrograms._ID),
                null, null, null
            )
            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getLong(0)
                    val programUri = TvContractCompat.buildWatchNextProgramUri(id)
                    val program = getWatchNextProgram(programUri)
                    if (program?.internalProviderId != null &&
                        program.internalProviderId != currentMediaId
                    ) {
                        context.contentResolver.delete(programUri, null, null)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("TvWatchNext", "removeOtherEntries failed", e)
        }
    }

    private fun findWatchNextProgram(mediaId: String): Long? {
        val cursor: Cursor? = context.contentResolver.query(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            arrayOf(TvContractCompat.WatchNextPrograms._ID),
            null, null, null
        )
        cursor?.use {
            while (it.moveToNext()) {
                val id = it.getLong(0)
                val programUri = TvContractCompat.buildWatchNextProgramUri(id)
                val program = getWatchNextProgram(programUri)
                if (program?.internalProviderId == mediaId) {
                    return id
                }
            }
        }
        return null
    }

    private fun getWatchNextProgram(uri: Uri): WatchNextProgram? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        return cursor?.use {
            if (it.moveToFirst()) WatchNextProgram.fromCursor(it) else null
        }
    }

    fun removeFromWatchNext(mediaId: String) {
        scope.launch {
            try {
                val programId = findWatchNextProgram(mediaId)
                if (programId != null) {
                    context.contentResolver.delete(
                        TvContractCompat.buildWatchNextProgramUri(programId),
                        null, null
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("TvWatchNext", "Remove failed", e)
            }
        }
    }
}