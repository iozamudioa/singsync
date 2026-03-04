package net.iozamudioa.singsync

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NowPlayingNotificationBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var lastPayload: Map<String, Any>? = null

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
        albumName: String?,
        durationSec: Int?,
    ) {
        val payload = mutableMapOf<String, Any>(
            "title" to title,
            "artist" to artist,
            "sourcePackage" to sourcePackage,
            "sourceType" to sourceType,
        )
        if (!artworkUrl.isNullOrBlank()) {
            payload["artworkUrl"] = artworkUrl
        }
        if (!albumName.isNullOrBlank()) {
            payload["albumName"] = albumName
        }
        if (durationSec != null && durationSec > 0) {
            payload["durationSec"] = durationSec
        }
        lastPayload = payload

        mainHandler.post {
            sink?.success(payload)
        }
    }
}
