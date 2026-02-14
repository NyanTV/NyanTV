// android/app/src/main/kotlin/com/mukatos/nyantv/TvWatchNextHelper.kt
package com.mukatos.nyantv

import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import com.bumptech.glide.Glide
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

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
                
                val imageUrl = coverUrl ?: posterUrl ?: return@launch
                val processedImageUri = withContext(Dispatchers.IO) {
                    createProgressImage(imageUrl, progress, mediaId)
                }
                
                val existingId = findWatchNextProgram(mediaId)
                val programBuilder = WatchNextProgram.Builder()
                    .setType(TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE)
                    .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                    .setTitle(title)
                    .setEpisodeTitle(episodeTitle)
                    .setEpisodeNumber(episodeNumber.toIntOrNull() ?: 0)
                    .setPosterArtUri(Uri.parse(processedImageUri))
                    .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
                    .setLastPlaybackPositionMillis(currentPosition.toInt())
                    .setDurationMillis(duration.toInt())
                    .setIntentUri(Uri.parse("nyantv://watch/$mediaId/$episodeNumber"))
                    .setInternalProviderId(mediaId)
                
                if (existingId != null) {
                    context.contentResolver.update(
                        TvContractCompat.buildWatchNextProgramUri(existingId),
                        programBuilder.build().toContentValues(),
                        null,
                        null
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
    
    private suspend fun createProgressImage(imageUrl: String, progress: Int, mediaId: String): String {
        return withContext(Dispatchers.IO) {
            try {
                val originalBitmap = Glide.with(context)
                    .asBitmap()
                    .load(imageUrl)
                    .submit()
                    .get()
                
                val result = Bitmap.createBitmap(
                    originalBitmap.width,
                    originalBitmap.height,
                    Bitmap.Config.ARGB_8888
                )
                
                val canvas = Canvas(result)
                canvas.drawBitmap(originalBitmap, 0f, 0f, null)
                
                val barHeight = (originalBitmap.height * 0.02f).coerceAtLeast(4f)
                val barY = originalBitmap.height - barHeight
                
                val bgPaint = Paint().apply {
                    color = 0x80000000.toInt()
                    isAntiAlias = true
                }
                canvas.drawRect(0f, barY, originalBitmap.width.toFloat(), originalBitmap.height.toFloat(), bgPaint)
                
                val progressWidth = (originalBitmap.width * (progress / 100f))
                val progressPaint = Paint().apply {
                    color = 0xFFE50914.toInt()
                    isAntiAlias = true
                }
                
                val radius = barHeight / 2f
                val rect = RectF(0f, barY, progressWidth, originalBitmap.height.toFloat())
                canvas.drawRoundRect(rect, radius, radius, progressPaint)
                
                val cacheDir = File(context.cacheDir, "watch_next")
                cacheDir.mkdirs()
                val outputFile = File(cacheDir, "progress_${mediaId}_${System.currentTimeMillis()}.jpg")
                
                FileOutputStream(outputFile).use { out ->
                    result.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }
                
                originalBitmap.recycle()
                result.recycle()
                
                cleanOldImages(cacheDir)
                
                outputFile.absolutePath
            } catch (e: Exception) {
                android.util.Log.e("TvWatchNext", "Image processing failed", e)
                imageUrl
            }
        }
    }
    
    private fun cleanOldImages(cacheDir: File) {
        try {
            val files = cacheDir.listFiles() ?: return
            val cutoff = System.currentTimeMillis() - (24 * 60 * 60 * 1000)
            files.filter { it.lastModified() < cutoff }.forEach { it.delete() }
        } catch (e: Exception) {
            android.util.Log.e("TvWatchNext", "Cache cleanup failed", e)
        }
    }
    
    private fun findWatchNextProgram(mediaId: String): Long? {
        val cursor: Cursor? = context.contentResolver.query(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            arrayOf(TvContractCompat.WatchNextPrograms._ID),
            null,
            null,
            null
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
                        null,
                        null
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("TvWatchNext", "Remove failed", e)
            }
        }
    }
}