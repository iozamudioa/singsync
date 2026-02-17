package net.iozamudioa.lyric_notifier

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URL
import javax.net.ssl.HttpsURLConnection

data class ApiHttpResponse(
    val statusCode: Int,
    val body: String,
    val json: Any?,
) {
    val isSuccess: Boolean
        get() = statusCode in 200..299
}

class ApiHttpHelper(
    private val connectTimeoutMs: Int = 20_000,
    private val readTimeoutMs: Int = 25_000,
    private val userAgent: String =
        "SingSync v1.0.0 (https://github.com/irvin/lyric_notifier)",
) {
    fun getWithRetry(
        url: String,
        headers: Map<String, String> = mapOf("Accept" to "application/json"),
        retries: Int = 3,
        debugSteps: MutableList<String>? = null,
    ): ApiHttpResponse {
        var lastIOException: IOException? = null

        repeat(retries) { attempt ->
            try {
                if (attempt > 0) {
                    debugSteps?.add("retry=${attempt + 1} url=$url")
                    Thread.sleep((attempt * 300L).coerceAtLeast(300L))
                }
                return get(url, headers)
            } catch (error: IOException) {
                lastIOException = error
                debugSteps?.add("io_exception attempt=${attempt + 1} message=${error.message}")
            }
        }

        throw lastIOException ?: IOException("Unknown network error")
    }

    fun get(
        url: String,
        headers: Map<String, String> = mapOf("Accept" to "application/json"),
    ): ApiHttpResponse {
        val connection = URL(url).openConnection() as HttpsURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.setRequestProperty("User-Agent", userAgent)
            connection.setRequestProperty("Connection", "close")
            headers.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
            }
            connection.instanceFollowRedirects = true
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs

            val statusCode = connection.responseCode
            val body = (if (statusCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            })?.bufferedReader()?.use { it.readText() }.orEmpty()

            ApiHttpResponse(
                statusCode = statusCode,
                body = body,
                json = parseJsonOrNull(body),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun parseJsonOrNull(body: String): Any? {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) {
            return null
        }

        return try {
            when {
                trimmed.startsWith("{") -> JSONObject(trimmed)
                trimmed.startsWith("[") -> JSONArray(trimmed)
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }
}
