package com.nyantv

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import okhttp3.Request

data class AniZipEpisodeMeta(
    val title: String? = null,
    val summary: String? = null,
    val overview: String? = null,
    val image: String? = null,
    val rating: String? = null,
    val airDate: String? = null,
)

object AniZipService {

    private const val TAG = "AniZipService"
    private const val EPISODES_URL = "https://api.ani.zip/v1/episodes"
    private val client = OkHttpClient()
    private val json   = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    suspend fun getEpisodesByAnilistId(anilistId: String): Map<String, AniZipEpisodeMeta> =
        fetchEpisodes("$EPISODES_URL?anilist_id=$anilistId")

    suspend fun getEpisodesByMalId(malId: String): Map<String, AniZipEpisodeMeta> =
        fetchEpisodes("$EPISODES_URL?mal_id=$malId")

    suspend fun getEpisodes(malId: String): Map<String, AniZipEpisodeMeta> = getEpisodesByMalId(malId)

    private data class EpisodePayload(val key: String?, val obj: JsonObject)

    private fun JsonElement.extractEpisodeObjects(): List<EpisodePayload> = when (this) {
        is JsonObject -> extractFromObject(this)
        is kotlinx.serialization.json.JsonArray -> this.mapNotNull { it.asObject()?.let { obj -> EpisodePayload(null, obj) } }
        else -> emptyList()
    }

    private fun extractFromObject(obj: JsonObject): List<EpisodePayload> {
        val direct = obj["episodes"]
        val fromEpisodes = when (direct) {
            is JsonObject -> direct.mapNotNull { (key, value) ->
                value.asObject()?.let { EpisodePayload(key, it) }
            }
            is kotlinx.serialization.json.JsonArray -> direct.mapNotNull { it.asObject()?.let { ep -> EpisodePayload(null, ep) } }
            else -> emptyList()
        }
        if (fromEpisodes.isNotEmpty()) return fromEpisodes

        val data = obj["data"]
        return when (data) {
            is JsonObject -> extractFromObject(data)
            is kotlinx.serialization.json.JsonArray -> data.mapNotNull { it.asObject()?.let { ep -> EpisodePayload(null, ep) } }
            else -> emptyList()
        }
    }

    private suspend fun fetchEpisodes(url: String): Map<String, AniZipEpisodeMeta> {
        val root = fetchJson(url) ?: return emptyMap()
        return parseEpisodes(root)
    }

    private fun parseEpisodes(root: JsonElement): Map<String, AniZipEpisodeMeta> {
        val episodes = root.extractEpisodeObjects()
        if (episodes.isEmpty()) return emptyMap()

        val result = mutableMapOf<String, AniZipEpisodeMeta>()

        for (payload in episodes) {
            val obj = payload.obj
            val episodeRaw = obj.string("episode")
                ?: payload.key
                ?: obj.string("ep")
                ?: obj.string("number")
            val keys = episodeKeys(episodeRaw)
            if (keys.isEmpty()) continue

            val meta = AniZipEpisodeMeta(
                title    = extractTitle(obj["title"] ?: obj["titles"]),
                summary  = obj.string("summary") ?: obj.string("synopsis"),
                overview = obj.string("overview") ?: obj.string("description"),
                image    = obj.string("image") ?: obj.string("thumbnail") ?: obj.string("thumb"),
                rating   = obj.string("rating"),
                airDate  = obj.string("airdate") ?: obj.string("airDate") ?: obj.string("air_date"),
            )

            if (meta.title == null &&
                meta.summary == null &&
                meta.overview == null &&
                meta.image == null &&
                meta.rating == null &&
                meta.airDate == null
            ) {
                continue
            }

            keys.forEach { key -> result[key] = meta }
        }

        return result
    }

    private suspend fun fetchJson(url: String): JsonElement? = withContext(Dispatchers.IO) {
        try {
            val response = client.newCall(Request.Builder().url(url).build()).execute()
            if (response.code != 200) return@withContext null

            val body = response.body?.string().orEmpty()
            if (body.isBlank()) return@withContext null

            json.parseToJsonElement(body)
        } catch (e: Exception) {
            Log.e(TAG, "AniZip request failed", e)
            null
        }
    }

    private fun extractTitle(element: JsonElement?): String? {
        return when (element) {
            is JsonPrimitive -> element.stringOrNull()
            is JsonObject -> listOf(
                "english", "en", "romaji", "native", "ja", "jp", "japanese", "title", "short",
            ).firstNotNullOfOrNull { key -> element[key].stringOrNull() }
            else -> null
        }
    }

    private fun JsonObject.string(key: String): String? = this[key].stringOrNull()

    private fun JsonElement?.asObject(): JsonObject? = this as? JsonObject

    private fun JsonElement?.stringOrNull(): String? {
        if (this == null || this is JsonNull) return null
        val prim = this as? JsonPrimitive ?: return null
        val content = prim.contentOrNull?.trim().orEmpty()
        return content.takeIf { it.isNotBlank() && it != "null" }
    }

    private fun episodeKeys(raw: String?): Set<String> {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isBlank()) return emptySet()
        val keys = mutableSetOf(trimmed)
        val numeric = trimmed.toFloatOrNull() ?: return keys
        if (numeric % 1f == 0f) {
            keys.add(numeric.toInt().toString())
            keys.add(numeric.toString())
        } else {
            keys.add("%.1f".format(numeric))
            keys.add(numeric.toString())
        }
        return keys
    }

}
