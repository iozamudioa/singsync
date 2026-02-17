package net.iozamudioa.lyric_notifier

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NowPlayingNotificationBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var lastPayload: Map<String, String>? = null

    fun setSink(eventSink: EventChannel.EventSink?) {
        sink = eventSink

        val payload = lastPayload
        if (eventSink != null && payload != null) {
            mainHandler.post {
                eventSink.success(payload)
            }
        }
    }

    fun emitNowPlaying(
        title: String,
        artist: String,
        sourcePackage: String,
        sourceType: String,
        artworkUrl: String?,
    ) {
        val payload = mutableMapOf<String, String>(
            "title" to title,
            "artist" to artist,
            "sourcePackage" to sourcePackage,
            "sourceType" to sourceType,
        )
        if (!artworkUrl.isNullOrBlank()) {
            payload["artworkUrl"] = artworkUrl
        }
        lastPayload = payload

        mainHandler.post {
            sink?.success(payload)
        }
    }
}
