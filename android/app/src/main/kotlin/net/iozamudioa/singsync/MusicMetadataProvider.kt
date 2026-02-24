package net.iozamudioa.singsync

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

object MusicMetadataProvider {
    private val apiHttpHelper = ApiHttpHelper()

    fun fetchArtworkUrl(title: String, artist: String): String? {
        val query = "$title $artist".trim()
        if (query.isBlank()) {
            return null
        }

        val url = buildUrl(
            host = "itunes.apple.com",
            path = "/search",
            params = mapOf(
                "term" to query,
                "entity" to "song",
                "limit" to "1",
            ),
        )

        val response = try {
            apiHttpHelper.getWithRetry(url)
        } catch (_: Exception) {
            return null
        }

        if (!response.isSuccess) {
            return null
        }

        val root = response.json as? JSONObject ?: return null
        val results = root.optJSONArray("results") ?: return null
        if (results.length() == 0) {
            return null
        }

        val first = results.optJSONObject(0) ?: return null
        val rawUrl = first.optString("artworkUrl100", "").trim()
        if (rawUrl.isBlank()) {
            return null
        }

        return rawUrl.replace("100x100bb", "600x600bb")
    }

    fun fetchArtistInsight(artist: String): Map<String, Any?>? {
        val query = artist.trim()
        if (query.isBlank()) {
            return null
        }

        val basic = findArtistBasicInfo(query)
        val releasesResult = findPopularReleases(query)
        val bio = findWikipediaSummary(query)

        val artistName = (basic?.artistName ?: query).trim()
        val genre = (basic?.primaryGenre ?: "").trim()
        val country = (basic?.country ?: "").trim()
        val releases = releasesResult.first
        val firstYear = releasesResult.second
        val latestYear = releasesResult.third
        val shortBio = bio.trim()

        val hasAnyInfo =
            artistName.isNotBlank() ||
                genre.isNotBlank() ||
                country.isNotBlank() ||
                shortBio.isNotBlank() ||
                releases.isNotEmpty() ||
                firstYear != null ||
                latestYear != null

        if (!hasAnyInfo) {
            return null
        }

        return mapOf(
            "artistName" to artistName,
            "primaryGenre" to genre,
            "country" to country,
            "shortBio" to shortBio,
            "popularReleases" to releases,
            "firstReleaseYear" to firstYear,
            "latestReleaseYear" to latestYear,
        )
    }

    private fun findArtistBasicInfo(artist: String): ArtistBasicInfo? {
        val url = buildUrl(
            host = "itunes.apple.com",
            path = "/search",
            params = mapOf(
                "term" to artist,
                "entity" to "musicArtist",
                "limit" to "1",
            ),
        )

        val response = try {
            apiHttpHelper.getWithRetry(url)
        } catch (_: Exception) {
            return null
        }

        if (!response.isSuccess) {
            return null
        }

        val root = response.json as? JSONObject ?: return null
        val results = root.optJSONArray("results") ?: return null
        if (results.length() == 0) {
            return null
        }

        val first = results.optJSONObject(0) ?: return null
        val artistName = first.optString("artistName", "").trim()
        val primaryGenre = first.optString("primaryGenreName", "").trim()
        val country = first.optString("country", "").trim()

        if (artistName.isBlank() && primaryGenre.isBlank() && country.isBlank()) {
            return null
        }

        return ArtistBasicInfo(
            artistName = artistName,
            primaryGenre = primaryGenre,
            country = country,
        )
    }

    private fun findPopularReleases(artist: String): Triple<List<String>, Int?, Int?> {
        val url = buildUrl(
            host = "itunes.apple.com",
            path = "/search",
            params = mapOf(
                "term" to artist,
                "entity" to "song",
                "attribute" to "artistTerm",
                "limit" to "12",
            ),
        )

        val response = try {
            apiHttpHelper.getWithRetry(url)
        } catch (_: Exception) {
            return Triple(emptyList(), null, null)
        }

        if (!response.isSuccess) {
            return Triple(emptyList(), null, null)
        }

        val root = response.json as? JSONObject ?: return Triple(emptyList(), null, null)
        val results = root.optJSONArray("results") ?: return Triple(emptyList(), null, null)
        if (results.length() == 0) {
            return Triple(emptyList(), null, null)
        }

        val uniqueTracks = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        val years = mutableListOf<Int>()

        for (index in 0 until results.length()) {
            val item = results.optJSONObject(index) ?: continue
            val trackName = item.optString("trackName", "").trim()
            if (trackName.isNotBlank()) {
                val key = trackName.lowercase()
                if (!seen.contains(key)) {
                    seen.add(key)
                    uniqueTracks += trackName
                }
            }

            val releaseDate = item.optString("releaseDate", "").trim()
            if (releaseDate.length >= 4) {
                val year = releaseDate.substring(0, 4).toIntOrNull()
                if (year != null) {
                    years += year
                }
            }
        }

        val firstYear = years.minOrNull()
        val latestYear = years.maxOrNull()
        return Triple(uniqueTracks.take(5), firstYear, latestYear)
    }

    private fun findWikipediaSummary(artist: String): String {
        val searchUrl = buildUrl(
            host = "es.wikipedia.org",
            path = "/w/api.php",
            params = mapOf(
                "action" to "opensearch",
                "search" to artist,
                "limit" to "1",
                "namespace" to "0",
                "format" to "json",
            ),
        )

        val searchResponse = try {
            apiHttpHelper.getWithRetry(searchUrl)
        } catch (_: Exception) {
            return ""
        }

        if (!searchResponse.isSuccess) {
            return ""
        }

        val searchPayload = searchResponse.json as? JSONArray ?: return ""
        if (searchPayload.length() < 2) {
            return ""
        }

        val titles = searchPayload.optJSONArray(1) ?: return ""
        if (titles.length() == 0) {
            return ""
        }

        val title = titles.optString(0, "").trim()
        if (title.isBlank()) {
            return ""
        }

        val summaryUrl = "https://es.wikipedia.org/api/rest_v1/page/summary/${URLEncoder.encode(title.replace(" ", "_"), Charsets.UTF_8.name())}"
        val summaryResponse = try {
            apiHttpHelper.getWithRetry(
                summaryUrl,
                headers = mapOf("Accept" to "application/json"),
            )
        } catch (_: Exception) {
            return ""
        }

        if (!summaryResponse.isSuccess) {
            return ""
        }

        val summaryPayload = summaryResponse.json as? JSONObject ?: return ""
        return summaryPayload.optString("extract", "").trim()
    }

    private fun buildUrl(host: String, path: String, params: Map<String, String>): String {
        val query = params.entries.joinToString("&") { (key, value) ->
            "$key=${URLEncoder.encode(value, Charsets.UTF_8.name())}"
        }
        return "https://$host$path?$query"
    }

    private data class ArtistBasicInfo(
        val artistName: String,
        val primaryGenre: String,
        val country: String,
    )
}
