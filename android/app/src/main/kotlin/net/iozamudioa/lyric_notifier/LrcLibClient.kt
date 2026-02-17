package net.iozamudioa.lyric_notifier

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

interface LyricsProvider {
    fun fetchLyrics(title: String, artist: String, preferSynced: Boolean): Map<String, Any?>
    fun searchLyricsCandidates(query: String): List<Map<String, String>>
}

object LyricsProviderRegistry {
    @Volatile
    var active: LyricsProvider = LrcLibLyricsProvider
}

object LrcLibLyricsProvider : LyricsProvider {
    private const val TAG = "LRCLIB_NATIVE"
    private val apiHttpHelper = ApiHttpHelper()

    override fun fetchLyrics(title: String, artist: String, preferSynced: Boolean): Map<String, Any?> {
        val cleanTitle = title.trim()
        val cleanArtist = artist.trim()
        val debugSteps = mutableListOf<String>()

        return try {
            val getUrl = buildUrl(
                path = "/api/get",
                params = mapOf("track_name" to cleanTitle, "artist_name" to cleanArtist),
            )
            debugSteps += "GET $getUrl"
            val getResult = requestLyricsResult(getUrl, debugSteps, preferSynced)
            debugSteps += "GET status=${getResult.status}"

            getResult.lyrics?.let {
                debugSteps += "GET hit lyricsLength=${it.length}"
                logDebug(debugSteps)
                mapOf("lyrics" to it, "debug" to debugSteps, "metadata" to getResult.metadata)
            } ?: run {
                val searchUrl = buildUrl(
                    path = "/api/search",
                    params = mapOf("track_name" to cleanTitle, "artist_name" to cleanArtist),
                )
                debugSteps += "SEARCH(track/artist) $searchUrl"
                val searchResult = requestLyricsResult(searchUrl, debugSteps, preferSynced)
                debugSteps += "SEARCH(track/artist) status=${searchResult.status}"
                searchResult.lyrics?.let {
                    debugSteps += "SEARCH(track/artist) hit lyricsLength=${it.length}"
                    logDebug(debugSteps)
                    mapOf("lyrics" to it, "debug" to debugSteps, "metadata" to searchResult.metadata)
                } ?: run {
                    val queryUrl = buildUrl(
                        path = "/api/search",
                        params = mapOf("q" to "$cleanTitle $cleanArtist"),
                    )
                    debugSteps += "SEARCH(q) $queryUrl"
                    val queryResult = requestLyricsResult(queryUrl, debugSteps, preferSynced)
                    debugSteps += "SEARCH(q) status=${queryResult.status}"
                    queryResult.lyrics?.let {
                        debugSteps += "SEARCH(q) hit lyricsLength=${it.length}"
                        logDebug(debugSteps)
                        mapOf("lyrics" to it, "debug" to debugSteps, "metadata" to queryResult.metadata)
                    } ?: run {
                        logDebug(debugSteps)
                        mapOf(
                            "lyrics" to "No se encontró letra para esta canción en lrclib.",
                            "debug" to debugSteps,
                            "metadata" to null,
                        )
                    }
                }
            }
        } catch (error: Exception) {
            debugSteps += "exception=${error::class.java.simpleName}: ${error.message}"
            logDebug(debugSteps)
            mapOf(
                "lyrics" to "No fue posible consultar lrclib en este momento.",
                "debug" to debugSteps,
                "metadata" to null,
            )
        }
    }

    override fun searchLyricsCandidates(query: String): List<Map<String, String>> {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) {
            return emptyList()
        }

        val debugSteps = mutableListOf<String>()
        val queryUrl = buildUrl(
            path = "/api/search",
            params = mapOf("q" to cleanQuery),
        )
        debugSteps += "CANDIDATES(q) $queryUrl"

        val candidates = try {
            val response = apiHttpHelper.getWithRetry(queryUrl, debugSteps = debugSteps)
            if (!response.isSuccess) {
                emptyList()
            } else {
                extractCandidatesFromSearch(response.body)
            }
        } catch (error: Exception) {
            debugSteps += "candidates_q_exception=${error::class.java.simpleName}: ${error.message}"
            emptyList()
        }

        debugSteps += "CANDIDATES(q) count=${candidates.size}"
        logDebug(debugSteps)
        return candidates
    }

    private fun requestLyricsResult(
        url: String,
        debugSteps: MutableList<String>,
        preferSynced: Boolean,
    ): RequestResult {
        val response = apiHttpHelper.getWithRetry(url, debugSteps = debugSteps)
        val lyrics = extractLyrics(response.body, response.statusCode, preferSynced)
        val metadata = extractMetadata(response.body, response.statusCode)
        return RequestResult(
            status = response.statusCode,
            lyrics = lyrics,
            metadata = metadata,
        )
    }

    private fun buildUrl(path: String, params: Map<String, String>): String {
        val query = params.entries.joinToString("&") {
            "${it.key}=${URLEncoder.encode(it.value, Charsets.UTF_8.name())}"
        }
        return "https://lrclib.net$path?$query"
    }

    private fun extractCandidatesFromSearch(body: String): List<Map<String, String>> {
        if (body.isBlank() || !body.trim().startsWith("[")) {
            return emptyList()
        }

        val arr = JSONArray(body)
        if (arr.length() == 0) {
            return emptyList()
        }

        val items = mutableListOf<Map<String, String>>()
        for (index in 0 until arr.length()) {
            val obj = arr.optJSONObject(index) ?: continue
            val trackName = cleanJsonString(obj.optString("trackName", ""))
            val artistName = cleanJsonString(obj.optString("artistName", ""))
            val albumName = cleanJsonString(obj.optString("albumName", ""))
            val plain = cleanJsonString(obj.optString("plainLyrics", ""))
            val synced = cleanJsonString(obj.optString("syncedLyrics", ""))
            val lyrics = if (synced.isNotEmpty()) synced else plain

            if (trackName.isEmpty() || artistName.isEmpty() || lyrics.isEmpty()) {
                continue
            }

            items += mapOf(
                "trackName" to trackName,
                "artistName" to artistName,
                "albumName" to albumName,
                "lyrics" to lyrics,
            )
        }

        return items
    }

    private fun extractMetadata(body: String, status: Int): Map<String, Any?>? {
        if (status !in 200..299 || body.isBlank()) {
            return null
        }

        return when {
            body.trim().startsWith("[") -> {
                val arr = JSONArray(body)
                if (arr.length() == 0) {
                    null
                } else {
                    val first = arr.optJSONObject(0) ?: return null
                    metadataFromObject(first)
                }
            }

            body.trim().startsWith("{") -> metadataFromObject(JSONObject(body))
            else -> null
        }
    }

    private fun metadataFromObject(obj: JSONObject): Map<String, Any?> {
        val metadata = mutableMapOf<String, Any?>()

        val plainLyrics = cleanJsonString(obj.optString("plainLyrics", ""))
        if (plainLyrics.isNotEmpty()) {
            metadata["plainLyrics"] = plainLyrics
        }

        val syncedLyrics = cleanJsonString(obj.optString("syncedLyrics", ""))
        if (syncedLyrics.isNotEmpty()) {
            metadata["syncedLyrics"] = syncedLyrics
        }

        val trackName = cleanJsonString(obj.optString("trackName", ""))
        if (trackName.isNotEmpty()) {
            metadata["trackName"] = trackName
        }

        val artistName = cleanJsonString(obj.optString("artistName", ""))
        if (artistName.isNotEmpty()) {
            metadata["artistName"] = artistName
        }

        val albumName = cleanJsonString(obj.optString("albumName", ""))
        if (albumName.isNotEmpty()) {
            metadata["albumName"] = albumName
        }

        if (!obj.isNull("duration")) {
            metadata["durationSec"] = obj.optDouble("duration")
        }

        if (!obj.isNull("instrumental")) {
            metadata["instrumental"] = obj.optBoolean("instrumental")
        }

        var releaseYear: Int? = null
        if (!obj.isNull("releaseYear")) {
            releaseYear = obj.optInt("releaseYear")
        } else if (!obj.isNull("year")) {
            releaseYear = obj.optInt("year")
        } else {
            val releaseDate = cleanJsonString(obj.optString("releaseDate", ""))
            val yearMatch = Regex("(\\d{4})").find(releaseDate)
            releaseYear = yearMatch?.groupValues?.getOrNull(1)?.toIntOrNull()
        }

        if (releaseYear != null && releaseYear > 0) {
            metadata["releaseYear"] = releaseYear
        }

        return metadata
    }

    private fun extractLyrics(body: String, status: Int, preferSynced: Boolean): String? {
        if (status !in 200..299 || body.isBlank()) {
            return null
        }

        return when {
            body.trim().startsWith("[") -> extractFromArray(body, preferSynced)
            body.trim().startsWith("{") -> extractFromObject(body, preferSynced)
            else -> null
        }
    }

    private fun extractFromObject(body: String, preferSynced: Boolean): String? {
        val obj = JSONObject(body)
        val plain = cleanJsonString(obj.optString("plainLyrics", ""))
        val synced = cleanJsonString(obj.optString("syncedLyrics", ""))
        if (preferSynced) {
            if (synced.isNotEmpty()) {
                return synced
            }
            return plain.ifEmpty { null }
        }

        if (plain.isNotEmpty()) {
            return plain
        }
        return synced.ifEmpty { null }
    }

    private fun extractFromArray(body: String, preferSynced: Boolean): String? {
        val arr = JSONArray(body)
        if (arr.length() == 0) {
            return null
        }

        val first = arr.optJSONObject(0) ?: return null
        val plain = cleanJsonString(first.optString("plainLyrics", ""))
        val synced = cleanJsonString(first.optString("syncedLyrics", ""))
        if (preferSynced) {
            if (synced.isNotEmpty()) {
                return synced
            }
            return plain.ifEmpty { null }
        }

        if (plain.isNotEmpty()) {
            return plain
        }
        return synced.ifEmpty { null }
    }

    private fun logDebug(steps: List<String>) {
        steps.forEach { Log.i(TAG, it) }
    }

    private fun cleanJsonString(value: String?): String {
        val normalized = value?.trim().orEmpty()
        if (normalized.equals("null", ignoreCase = true)) {
            return ""
        }
        return normalized
    }

    private data class RequestResult(
        val status: Int,
        val lyrics: String?,
        val metadata: Map<String, Any?>?,
    )
}
