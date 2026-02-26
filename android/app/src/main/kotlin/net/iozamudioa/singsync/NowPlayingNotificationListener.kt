package net.iozamudioa.singsync

import android.app.Notification
import android.app.PendingIntent
import android.app.SearchManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.media.MediaMetadata
import android.media.Rating
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

class NowPlayingNotificationListener : NotificationListenerService() {
    private var lastEventKey: String? = null
    private lateinit var artistMemoryStore: ArtistMemoryStore

    override fun onCreate() {
        super.onCreate()
        artistMemoryStore = ArtistMemoryStore(applicationContext)
        activeInstance = this
        Log.i(TAG, "onCreate")
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        if (this::artistMemoryStore.isInitialized) {
            artistMemoryStore.close()
        }
        if (activeInstance === this) {
            activeInstance = null
        }
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "onListenerConnected")

        val currentPayload = activeNotifications
            ?.asSequence()
            ?.mapNotNull { payloadFromNotification(it) }
            ?.filter { shouldEmitPayload(it) }
            ?.maxByOrNull { scorePayload(it) }

        if (currentPayload != null) {
            logActiveSessionSnapshot(currentPayload.sourcePackage)
            emitPayloadIfNew(currentPayload)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        Log.i(TAG, "onNotificationPosted package=${sbn?.packageName}")
        if (sbn == null) {
            return
        }

        processNowPlayingNotification(sbn)
    }

    private fun processNowPlayingNotification(sbn: StatusBarNotification) {
        val payload = payloadFromNotification(sbn) ?: return
        if (!shouldEmitPayload(payload)) {
            return
        }
        logActiveSessionSnapshot(payload.sourcePackage)
        emitPayloadIfNew(payload)
    }

    private fun isPlaybackStateActive(state: Int?): Boolean {
        return state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING
    }

    private fun isAnyPlaybackActive(): Boolean {
        val manager = getSystemService(MediaSessionManager::class.java) ?: return false
        val component = ComponentName(this, NowPlayingNotificationListener::class.java)
        val sessions = try {
            manager.getActiveSessions(component)
        } catch (_: SecurityException) {
            emptyList()
        }

        return sessions.any { isPlaybackStateActive(it.playbackState?.state) }
    }

    private fun isPlaybackActiveForPackage(sourcePackage: String?): Boolean {
        val controller = findBestMediaController(sourcePackage) ?: return false
        return isPlaybackStateActive(controller.playbackState?.state)
    }

    private fun shouldEmitPayload(payload: NowPlayingPayload): Boolean {
        return when (payload.sourceType) {
            SOURCE_TYPE_PLAYER -> isPlaybackActiveForPackage(payload.sourcePackage)
            SOURCE_TYPE_PIXEL -> true
            else -> true
        }
    }

    private fun controlActiveMediaPlayer(command: String, sourcePackage: String?): Boolean {
        val controller = findBestMediaController(sourcePackage) ?: return false
        return try {
            val controls = controller.transportControls
            when (command) {
                MEDIA_PREVIOUS -> controls.skipToPrevious()
                MEDIA_NEXT -> controls.skipToNext()
                MEDIA_PLAY_PAUSE -> {
                    val state = controller.playbackState?.state
                    if (state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING) {
                        controls.pause()
                    } else {
                        controls.play()
                    }
                }
                else -> return false
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun openActiveMediaPlayerApp(
        sourcePackage: String?,
        selectedPackage: String?,
        searchQuery: String?,
    ): Boolean {
        val query = searchQuery?.trim().orEmpty()
        val selected = selectedPackage?.trim().orEmpty()

        if (selected.isNotEmpty() && query.isNotEmpty()) {
            if (openSelectedAppWithQuery(packageName = selected, query = query)) {
                return true
            }
        }

        if (selected.isNotEmpty()) {
            if (launchPackageApp(selected)) {
                return true
            }
        }

        val candidates = linkedSetOf<String>()
        sourcePackage?.trim()?.takeIf { it.isNotBlank() }?.let { candidates.add(it) }
        lastPayload?.get("sourcePackage")?.trim()?.takeIf { it.isNotBlank() }?.let {
            candidates.add(it)
        }

        if (candidates.isEmpty()) {
            return false
        }

        for (packageName in candidates) {
            val opened = launchPackageApp(packageName)

            if (opened) {
                return true
            }
        }

        return false
    }

    private fun findBestMediaController(sourcePackage: String?): MediaController? {
        val manager = getSystemService(MediaSessionManager::class.java) ?: return null
        val component = ComponentName(this, NowPlayingNotificationListener::class.java)
        val sessions = try {
            manager.getActiveSessions(component)
        } catch (_: SecurityException) {
            emptyList()
        }

        if (sessions.isEmpty()) {
            return null
        }

        val source = sourcePackage?.trim().orEmpty()
        if (source.isNotEmpty()) {
            sessions.firstOrNull { it.packageName.equals(source, ignoreCase = true) }?.let {
                return it
            }
        }

        val playing = sessions.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING ||
                it.playbackState?.state == PlaybackState.STATE_BUFFERING
        }
        return playing ?: sessions.first()
    }

    private fun getActiveMediaPlaybackState(sourcePackage: String?): Map<String, Any>? {
        val controller = findBestMediaController(sourcePackage) ?: return null
        val playbackState = controller.playbackState ?: return null

        var positionMs = playbackState.position
        val isPlaying =
            playbackState.state == PlaybackState.STATE_PLAYING ||
                playbackState.state == PlaybackState.STATE_BUFFERING

        if (isPlaying && playbackState.lastPositionUpdateTime > 0L) {
            val elapsed = SystemClock.elapsedRealtime() - playbackState.lastPositionUpdateTime
            if (elapsed > 0L) {
                positionMs += (elapsed * playbackState.playbackSpeed).toLong()
            }
        }

        if (positionMs < 0L) {
            positionMs = 0L
        }

        return mapOf(
            "positionMs" to positionMs,
            "isPlaying" to isPlaying,
            "sourcePackage" to controller.packageName,
        )
    }

    private fun getActiveMediaSessionSnapshot(sourcePackage: String?): Map<String, Any?>? {
        val controller = findBestMediaController(sourcePackage) ?: return null
        val playbackState = controller.playbackState
        val metadata = controller.metadata
        val queue = controller.queue.orEmpty()

        val payload = mutableMapOf<String, Any?>(
            "sourcePackage" to controller.packageName,
            "requestedSourcePackage" to sourcePackage,
            "sessionTag" to controller.tag,
            "ratingType" to controller.ratingType,
            "hasSessionActivity" to (controller.sessionActivity != null),
            "sessionExtras" to bundleToMap(controller.extras),
            "sessionInfo" to bundleToMap(controller.sessionInfo),
            "playbackState" to playbackStateToMap(playbackState),
            "metadata" to metadataToMap(metadata),
            "queueTitle" to controller.queueTitle?.toString(),
            "queueSize" to queue.size,
            "queueSample" to queue.take(12).mapIndexed { index, item ->
                queueItemToMap(index, item)
            },
            "playbackInfo" to playbackInfoToMap(controller.playbackInfo),
        )

        return payload
    }

    private fun playbackStateToMap(playbackState: PlaybackState?): Map<String, Any?>? {
        if (playbackState == null) {
            return null
        }

        return mapOf(
            "stateCode" to playbackState.state,
            "stateLabel" to playbackStateLabel(playbackState.state),
            "isActive" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                playbackState.isActive
            } else {
                isPlaybackStateActive(playbackState.state)
            },
            "positionMs" to playbackState.position,
            "bufferedPositionMs" to playbackState.bufferedPosition,
            "playbackSpeed" to playbackState.playbackSpeed,
            "lastPositionUpdateTimeMs" to playbackState.lastPositionUpdateTime,
            "activeQueueItemId" to playbackState.activeQueueItemId,
            "errorMessage" to playbackState.errorMessage?.toString(),
            "actionsMask" to playbackState.actions,
            "actions" to decodePlaybackActions(playbackState.actions),
            "customActions" to playbackState.customActions.orEmpty().map { action ->
                mapOf(
                    "id" to action.action,
                    "name" to action.name?.toString(),
                    "iconResId" to action.icon,
                    "extras" to bundleToMap(action.extras),
                )
            },
            "extras" to bundleToMap(playbackState.extras),
        )
    }

    private fun metadataToMap(metadata: MediaMetadata?): Map<String, Any?>? {
        if (metadata == null) {
            return null
        }

        val values = mutableMapOf<String, Any?>()
        val sortedKeys = metadata.keySet().sorted()
        for (key in sortedKeys) {
            values[key] = readMetadataValue(metadata, key)
        }

        val description = metadata.description
        val descriptionMap = mapOf(
            "mediaId" to description.mediaId,
            "title" to description.title?.toString(),
            "subtitle" to description.subtitle?.toString(),
            "description" to description.description?.toString(),
            "iconUri" to description.iconUri?.toString(),
            "mediaUri" to description.mediaUri?.toString(),
            "extras" to bundleToMap(description.extras),
            "iconBitmap" to bitmapToMap(description.iconBitmap),
        )

        val payload = mutableMapOf<String, Any?>(
            "size" to metadata.size(),
            "keys" to sortedKeys,
            "values" to values,
            "description" to descriptionMap,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            payload["bitmapDimensionLimit"] = metadata.bitmapDimensionLimit
        }

        return payload
    }

    private fun queueItemToMap(index: Int, item: android.media.session.MediaSession.QueueItem): Map<String, Any?> {
        val description = item.description
        return mapOf(
            "index" to index,
            "queueId" to item.queueId,
            "mediaId" to description.mediaId,
            "title" to description.title?.toString(),
            "subtitle" to description.subtitle?.toString(),
            "description" to description.description?.toString(),
            "iconUri" to description.iconUri?.toString(),
            "mediaUri" to description.mediaUri?.toString(),
            "extras" to bundleToMap(description.extras),
        )
    }

    private fun playbackInfoToMap(playbackInfo: MediaController.PlaybackInfo?): Map<String, Any?>? {
        if (playbackInfo == null) {
            return null
        }

        return mapOf(
            "playbackType" to playbackInfo.playbackType,
            "playbackTypeLabel" to if (playbackInfo.playbackType == MediaController.PlaybackInfo.PLAYBACK_TYPE_REMOTE) {
                "remote"
            } else {
                "local"
            },
            "volumeControl" to playbackInfo.volumeControl,
            "maxVolume" to playbackInfo.maxVolume,
            "currentVolume" to playbackInfo.currentVolume,
            "audioAttributes" to playbackInfo.audioAttributes?.toString(),
        )
    }

    private fun readMetadataValue(metadata: MediaMetadata, key: String): Any? {
        return when {
            METADATA_LONG_KEYS.contains(key) -> metadata.getLong(key)
            METADATA_BITMAP_KEYS.contains(key) -> bitmapToMap(metadata.getBitmap(key))
            METADATA_RATING_KEYS.contains(key) -> ratingToMap(metadata.getRating(key))
            else -> metadata.getText(key)?.toString()
                ?: metadata.getString(key)
        }
    }

    private fun bitmapToMap(bitmap: Bitmap?): Map<String, Any?>? {
        if (bitmap == null) {
            return null
        }

        return mapOf(
            "width" to bitmap.width,
            "height" to bitmap.height,
            "byteCount" to bitmap.byteCount,
            "allocationByteCount" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                bitmap.allocationByteCount
            } else {
                bitmap.byteCount
            },
            "config" to bitmap.config?.name,
        )
    }

    private fun ratingToMap(rating: Rating?): Map<String, Any?>? {
        if (rating == null) {
            return null
        }

        return mapOf(
            "isRated" to rating.isRated,
            "style" to rating.ratingStyle,
            "hasHeart" to if (rating.ratingStyle == Rating.RATING_HEART) {
                rating.hasHeart()
            } else {
                null
            },
            "isThumbUp" to if (rating.ratingStyle == Rating.RATING_THUMB_UP_DOWN) {
                rating.isThumbUp()
            } else {
                null
            },
            "starRating" to if (
                rating.ratingStyle == Rating.RATING_3_STARS ||
                rating.ratingStyle == Rating.RATING_4_STARS ||
                rating.ratingStyle == Rating.RATING_5_STARS
            ) {
                rating.starRating
            } else {
                null
            },
            "percentRating" to if (rating.ratingStyle == Rating.RATING_PERCENTAGE) {
                rating.percentRating
            } else {
                null
            },
        )
    }

    private fun bundleToMap(bundle: Bundle?): Map<String, Any?>? {
        if (bundle == null) {
            return null
        }

        val map = mutableMapOf<String, Any?>()
        for (key in bundle.keySet()) {
            map[key] = anyToJsonCompatible(bundle.get(key))
        }
        return map
    }

    private fun anyToJsonCompatible(value: Any?): Any? {
        return when (value) {
            null -> null
            is Bundle -> bundleToMap(value)
            is CharSequence -> value.toString()
            is Uri -> value.toString()
            is Bitmap -> bitmapToMap(value)
            is Rating -> ratingToMap(value)
            is Array<*> -> value.map { anyToJsonCompatible(it) }
            is Iterable<*> -> value.map { anyToJsonCompatible(it) }
            is Boolean, is Number, is String -> value
            else -> value.toString()
        }
    }

    private fun playbackStateLabel(state: Int): String {
        return when (state) {
            PlaybackState.STATE_NONE -> "none"
            PlaybackState.STATE_STOPPED -> "stopped"
            PlaybackState.STATE_PAUSED -> "paused"
            PlaybackState.STATE_PLAYING -> "playing"
            PlaybackState.STATE_FAST_FORWARDING -> "fast_forwarding"
            PlaybackState.STATE_REWINDING -> "rewinding"
            PlaybackState.STATE_BUFFERING -> "buffering"
            PlaybackState.STATE_ERROR -> "error"
            PlaybackState.STATE_CONNECTING -> "connecting"
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS -> "skipping_to_previous"
            PlaybackState.STATE_SKIPPING_TO_NEXT -> "skipping_to_next"
            PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM -> "skipping_to_queue_item"
            else -> "unknown"
        }
    }

    private fun decodePlaybackActions(actions: Long): List<String> {
        val decoded = mutableListOf<String>()
        for ((mask, label) in PLAYBACK_ACTION_LABELS) {
            if ((actions and mask) != 0L) {
                decoded += label
            }
        }
        return decoded
    }

    private fun logActiveSessionSnapshot(sourcePackage: String?) {
        if (!DEBUG_SESSION_SNAPSHOT_LOGS) {
            return
        }

        val snapshot = getActiveMediaSessionSnapshot(sourcePackage) ?: return
        try {
            val json = JSONObject.wrap(snapshot)?.toString() ?: return
            logChunkedSnapshotJson(json)
        } catch (_: Throwable) {
            Log.i(TAG, "session_snapshot_json_fallback=$snapshot")
        }
    }

    private fun logChunkedSnapshotJson(json: String) {
        val chunkSize = 2800
        val total = (json.length + chunkSize - 1) / chunkSize
        val snapshotId = SystemClock.elapsedRealtime()

        Log.i(
            TAG,
            "SESSION_SNAPSHOT_JSON_BEGIN id=$snapshotId total=$total length=${json.length}",
        )

        var index = 0
        var part = 1
        while (index < json.length) {
            val end = (index + chunkSize).coerceAtMost(json.length)
            val chunk = json.substring(index, end)
            Log.i(
                TAG,
                "SESSION_SNAPSHOT_JSON_PART id=$snapshotId index=$part/$total payload=$chunk",
            )
            index = end
            part += 1
        }

        Log.i(TAG, "SESSION_SNAPSHOT_JSON_END id=$snapshotId")
    }

    private fun launchPackageApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun openSelectedAppWithQuery(packageName: String, query: String): Boolean {
        val encoded = Uri.encode(query)
        val candidates = mutableListOf<Intent>()

        if (packageName.contains("spotify", ignoreCase = true)) {
            candidates += Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:$encoded"))
                .setPackage(packageName)
        }

        if (packageName.contains("youtube", ignoreCase = true)) {
            candidates += Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://music.youtube.com/search?q=$encoded"),
            ).setPackage(packageName)
        }

        if (packageName.contains("amazon", ignoreCase = true)) {
            candidates += Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://music.amazon.com/search/$encoded"),
            ).setPackage(packageName)
        }

        if (packageName.contains("apple", ignoreCase = true)) {
            candidates += Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://music.apple.com/us/search?term=$encoded"),
            ).setPackage(packageName)
        }

        candidates += Intent(Intent.ACTION_SEARCH).apply {
            setPackage(packageName)
            putExtra(SearchManager.QUERY, query)
        }

        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val opened = try {
                startActivity(intent)
                true
            } catch (_: Throwable) {
                false
            }

            if (opened) {
                return true
            }
        }

        return false
    }

    private fun seekActiveMediaPlayer(positionMs: Long, sourcePackage: String?): Boolean {
        if (positionMs < 0L) {
            return false
        }

        val controller = findBestMediaController(sourcePackage) ?: return false
        return try {
            controller.transportControls.seekTo(positionMs)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun emitPayloadIfNew(payload: NowPlayingPayload) {
        val eventKey = "${payload.title}|${payload.artist}|${payload.sourceType}|${payload.sourcePackage}"
        if (eventKey == lastEventKey) {
            Log.i(TAG, "ignored duplicate eventKey=$eventKey")
            return
        }

        lastEventKey = eventKey
        Log.i(
            TAG,
            "emit title='${payload.title}' artist='${payload.artist}' source=${payload.sourceType} package=${payload.sourcePackage}",
        )

        lastPayload = payload.toMap()
        NowPlayingNotificationBridge.emitNowPlaying(
            title = payload.title,
            artist = payload.artist,
            sourcePackage = payload.sourcePackage,
            sourceType = payload.sourceType,
            artworkUrl = payload.artworkUrl,
        )
    }

    private fun payloadFromNotification(sbn: StatusBarNotification): NowPlayingPayload? {
        val packageName = sbn.packageName
        if (IGNORED_PACKAGES.contains(packageName)) {
            return null
        }

        val extras = sbn.notification.extras ?: return null

        return when {
            PIXEL_NOW_PLAYING_PACKAGES.contains(packageName) ->
                payloadFromPixelNowPlaying(extras, packageName)
            isActiveMediaPlayerNotification(sbn.notification) ->
                payloadFromMediaPlayer(
                    notification = sbn.notification,
                    extras = extras,
                    packageName = packageName,
                )
            else -> null
        }
    }

    private fun payloadFromPixelNowPlaying(
        extras: Bundle,
        packageName: String,
    ): NowPlayingPayload? {
        val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()
            ?.trim()
            .orEmpty()

        val rawBigTitle = extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
            ?.toString()
            ?.trim()
            .orEmpty()

        val rawText = extras.getCharSequence(Notification.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()

        val rawSubText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()

        val directTitle = listOf(rawTitle, rawBigTitle)
            .firstOrNull { it.isNotBlank() && !looksLikeHelperText(it) }

        val directArtist = listOf(rawText, rawSubText)
            .firstOrNull {
                it.isNotBlank() &&
                    !looksLikeHelperText(it) &&
                    !it.equals(directTitle, ignoreCase = true)
            }

        if (!directTitle.isNullOrBlank() && !directArtist.isNullOrBlank()) {
            return NowPlayingPayload(
                title = directTitle,
                artist = directArtist,
                sourcePackage = packageName,
                sourceType = SOURCE_TYPE_PIXEL,
            )
        }

        val prioritizedCandidates = listOf(rawBigTitle, rawTitle)
            .filter { it.isNotBlank() }

        val parsedFromTitleLine = prioritizedCandidates
            .asSequence()
            .mapNotNull { parseSongAndArtistSentence(it) }
            .firstOrNull()

        val textCandidates = listOf(
            rawBigTitle,
            rawTitle,
            rawSubText,
            rawText,
        ).filter { it.isNotBlank() && !looksLikeHelperText(it) }

        val parsedFromSentence = parsedFromTitleLine ?: textCandidates
            .asSequence()
            .mapNotNull { parseSongAndArtistSentence(it) }
            .firstOrNull()

        val title = parsedFromSentence?.first
            ?: directTitle
            ?: rawTitle

        val artist = parsedFromSentence?.second
            ?: directArtist
            ?: rawText.takeUnless { looksLikeHelperText(it) }
            ?: rawSubText.takeUnless { looksLikeHelperText(it) }
            ?: UNKNOWN_ARTIST

        if (title.isBlank() || artist.isBlank()) {
            Log.i(TAG, "ignored blank title/artist title='$title' artist='$artist'")
            return null
        }

        return NowPlayingPayload(
            title = title,
            artist = artist,
            sourcePackage = packageName,
            sourceType = SOURCE_TYPE_PIXEL,
        )
    }

    private fun payloadFromMediaPlayer(
        notification: Notification,
        extras: Bundle,
        packageName: String,
    ): NowPlayingPayload? {
        val controller = findBestMediaController(packageName)
        val metadata = controller?.metadata

        val rawTitle = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()
            ?.trim()
            .orEmpty()
        val rawBigTitle = extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
            ?.toString()
            ?.trim()
            .orEmpty()
        val rawText = extras.getCharSequence(Notification.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()
        val rawSubText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()
        val rawBigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()

        fun metadataText(key: String): String {
            return metadata?.getText(key)
                ?.toString()
                ?.trim()
                .orEmpty()
        }

        val titleCandidates = listOf(
            metadataText(MediaMetadata.METADATA_KEY_TITLE),
            metadataText(MediaMetadata.METADATA_KEY_DISPLAY_TITLE),
            metadata?.description?.title?.toString()?.trim().orEmpty(),
            rawBigTitle,
            rawTitle,
        )
            .filter { it.isNotBlank() && !looksLikeHelperText(it) }

        val resolvedTitle = titleCandidates.firstOrNull().orEmpty()

        val artistCandidates = listOf(
            metadataText(MediaMetadata.METADATA_KEY_ARTIST),
            metadataText(MediaMetadata.METADATA_KEY_ALBUM_ARTIST),
            metadataText(MediaMetadata.METADATA_KEY_AUTHOR),
            metadataText(MediaMetadata.METADATA_KEY_WRITER),
            metadataText(MediaMetadata.METADATA_KEY_COMPOSER),
            metadata?.description?.subtitle?.toString()?.trim().orEmpty(),
            rawText,
            rawSubText,
            rawBigText,
        )
            .filter { it.isNotBlank() && !looksLikeHelperText(it) }

        val title = resolvedTitle
            ?: rawText.takeUnless { looksLikeHelperText(it) }
            ?: rawSubText.takeUnless { looksLikeHelperText(it) }
            ?: rawBigText.takeUnless { looksLikeHelperText(it) }
            ?: ""

        val artist = artistCandidates.firstOrNull {
            !it.equals(title, ignoreCase = true)
        }
            ?: UNKNOWN_ARTIST

        if (title.isBlank()) {
            return null
        }

        val artworkUrl = extractMediaArtworkUrl(
            packageName = packageName,
            notification = notification,
            extras = extras,
        )

        return NowPlayingPayload(
            title = title,
            artist = artist,
            sourcePackage = packageName,
            sourceType = SOURCE_TYPE_PLAYER,
            artworkUrl = artworkUrl,
        )
    }

    private fun extractMediaArtworkUrl(
        packageName: String,
        notification: Notification,
        extras: Bundle,
    ): String? {
        val controller = findBestMediaController(packageName)
        val metadata = controller?.metadata
        val seed = buildArtworkSeed(packageName, extras)

        val candidates = listOf(
            metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI),
            metadata?.getString(MediaMetadata.METADATA_KEY_ART_URI),
            metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI),
        )

        for (candidate in candidates.mapNotNull { it?.trim() }) {
            if (candidate.startsWith("http://") || candidate.startsWith("https://")) {
                return candidate
            }

            persistArtworkFromUri(candidate, seed)?.let { return it }
        }

        val metadataBitmaps = listOf(
            metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART),
            metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART),
            metadata?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON),
            metadata?.description?.iconBitmap,
        )

        for ((index, bitmap) in metadataBitmaps.withIndex()) {
            if (bitmap != null) {
                persistArtworkBitmap(bitmap, "$seed|meta|$index")?.let { return it }
            }
        }

        val extrasBitmaps = listOf(
            getBitmapFromExtras(extras, Notification.EXTRA_LARGE_ICON_BIG),
            getBitmapFromExtras(extras, Notification.EXTRA_LARGE_ICON),
            getBitmapFromExtras(extras, Notification.EXTRA_PICTURE),
        )

        for ((index, bitmap) in extrasBitmaps.withIndex()) {
            if (bitmap != null) {
                persistArtworkBitmap(bitmap, "$seed|notif|$index")?.let { return it }
            }
        }

        return null
    }

    private fun buildArtworkSeed(packageName: String, extras: Bundle): String {
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val artist = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val album = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        return "$packageName|$title|$artist|$album"
    }

    private fun persistArtworkFromUri(rawUri: String, seed: String): String? {
        return try {
            val uri = Uri.parse(rawUri)
            val scheme = uri.scheme?.lowercase().orEmpty()

            if (scheme == "file") {
                return uri.toString()
            }

            val stream = contentResolver.openInputStream(uri) ?: return null
            val bytes = stream.use { it.readBytes() }
            if (bytes.isEmpty()) {
                return null
            }

            val file = buildArtworkCacheFile("$seed|uri|$rawUri")
            FileOutputStream(file).use { it.write(bytes) }
            Uri.fromFile(file).toString()
        } catch (_: Throwable) {
            null
        }
    }

    private fun persistArtworkBitmap(bitmap: Bitmap, seed: String): String? {
        return try {
            val file = buildArtworkCacheFile(seed)
            FileOutputStream(file).use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    return null
                }
            }
            Uri.fromFile(file).toString()
        } catch (_: Throwable) {
            null
        }
    }

    private fun buildArtworkCacheFile(seed: String): File {
        val directory = File(cacheDir, "now_playing_artwork")
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return File(directory, "art_${md5(seed)}.png")
    }

    private fun md5(input: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(input.toByteArray())
        val builder = StringBuilder(digest.size * 2)
        for (byte in digest) {
            builder.append(String.format("%02x", byte))
        }
        return builder.toString()
    }

    private fun getBitmapFromExtras(extras: Bundle, key: String): Bitmap? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(key, Bitmap::class.java)
            } else {
                @Suppress("DEPRECATION")
                (extras.getParcelable(key) as? Bitmap)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return it }
        }

        val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 512
        val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 512
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun isActiveMediaPlayerNotification(notification: Notification): Boolean {
        val hasMediaSession = notification.extras?.get(Notification.EXTRA_MEDIA_SESSION) != null
        val isTransportCategory = notification.category == Notification.CATEGORY_TRANSPORT
        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        return hasMediaSession && (isTransportCategory || isOngoing)
    }

    private fun scorePayload(payload: NowPlayingPayload): Int {
        return when (payload.sourceType) {
            SOURCE_TYPE_PLAYER -> 2
            SOURCE_TYPE_PIXEL -> 1
            else -> 0
        }
    }

    private fun NowPlayingPayload.toMap(): Map<String, String> {
        val payload = mutableMapOf(
            "title" to title,
            "artist" to artist,
            "sourcePackage" to sourcePackage,
            "sourceType" to sourceType,
        )
        if (!artworkUrl.isNullOrBlank()) {
            payload["artworkUrl"] = artworkUrl
        }
        return payload
    }

    private fun findCurrentNowPlayingPayload(): Map<String, String>? {
        val payload = activeNotifications
            ?.asSequence()
            ?.mapNotNull { payloadFromNotification(it) }
            ?.filter { shouldEmitPayload(it) }
            ?.maxByOrNull { scorePayload(it) }
            ?: return null

        return payload.toMap()
    }

    private fun parseSongAndArtistSentence(rawText: String): Pair<String, String>? {
        if (rawText.isBlank() || looksLikeHelperText(rawText)) {
            return null
        }

        parseSongArtistFlexible(rawText)?.let { return it }

        val quotedMatch = SONG_ARTIST_QUOTED_PATTERN.find(rawText)
        if (quotedMatch != null) {
            val song = quotedMatch.groupValues.getOrNull(1)?.trim().orEmpty()
            val artist = quotedMatch.groupValues.getOrNull(2)?.trim().orEmpty()
            if (song.isNotBlank() && artist.isNotBlank()) {
                return song to artist
            }
        }

        val normalized = rawText
            .replace('“', '"')
            .replace('”', '"')
            .trim()

        val fromDe = parseSongArtistFromDeText(normalized)
        if (fromDe != null) {
            return fromDe
        }

        val bySplitRegex = Regex("\\s+by\\s+", RegexOption.IGNORE_CASE)
        val byMatches = bySplitRegex.findAll(normalized).toList()
        if (byMatches.isNotEmpty()) {
            val lastMatch = byMatches.last()
            val song = normalized.substring(0, lastMatch.range.first).trim().trim('"')
            val artist = normalized.substring(lastMatch.range.last + 1).trim().trim('"')
            if (song.isNotBlank() && artist.isNotBlank()) {
                return song to artist
            }
        }

        return null
    }

    private fun parseSongArtistFromDeText(text: String): Pair<String, String>? {
        if (text.isBlank()) {
            return null
        }

        val normalized = normalize(text)
        if (normalized.isBlank()) {
            return null
        }

        val lower = normalized.lowercase()
        val positions = findAllPositions(lower, " de ")

        if (positions.isEmpty()) {
            return null
        }

        val knownArtists = artistMemoryStore.getAllArtists()
        var bestScore = Int.MIN_VALUE
        var bestSong = normalized
        var bestArtist = ""
        var bestWordCount = 0
        var bestPos = -1

        for (pos in positions) {
            val left = normalized.substring(0, pos).trim()
            val right = normalized.substring(pos + 4).trim()
            val heuristicScore = scoreArtist(right)
            val memoryScore = memoryBoost(right, knownArtists)
            var finalScore = heuristicScore + memoryScore
            val wordCount = countWords(right)

            if (wordCount <= 2 && bestWordCount >= 3) {
                finalScore -= 4
            }

            if (right.lowercase().contains(" de ")) {
                finalScore += 2
            }

            if (wordCount <= 2 && allWordsInSet(right, PLACE_WORDS)) {
                finalScore -= 6
            }

            if (finalScore > bestScore || (finalScore == bestScore && pos > bestPos)) {
                bestScore = finalScore
                bestSong = left
                bestArtist = right
                bestWordCount = wordCount
                bestPos = pos
            }
        }

        if (bestScore <= 0) {
            val pos = positions.last()
            bestSong = normalized.substring(0, pos).trim()
            bestArtist = normalized.substring(pos + 4).trim()
        }

        val song = bestSong.trim().trim('"')
        val artist = bestArtist.trim().trim('"')

        if (song.isBlank() || artist.isBlank()) {
            return null
        }

        learnArtist(artist)

        return song to artist
    }

    private fun memoryBoost(candidate: String, knownArtists: List<ArtistMemoryStore.MemoryArtist>): Int {
        val candidateLower = candidate.lowercase()
        var score = 0

        for (artist in knownArtists) {
            val name = artist.nameLower
            if (candidateLower == name) {
                score += MEMORY_MATCH
            } else if (candidateLower.contains(name) || name.contains(candidateLower)) {
                score += MEMORY_CONTAINS
            }
        }

        return score
    }

    private fun learnArtist(artistName: String) {
        val normalizedArtist = normalize(artistName)
        if (normalizedArtist.length < 2) {
            return
        }

        artistMemoryStore.learnArtist(
            artistName = normalizedArtist,
            insertScore = MEMORY_INSERT,
            incrementScore = MEMORY_INC,
        )
        generateAliases(normalizedArtist)
    }

    private fun generateAliases(fullName: String) {
        val words = replaceMultipleSpacesWithSingle(fullName.trim())
            .split(" ")
            .filter { it.isNotBlank() }

        if (words.size < 2) {
            return
        }

        for (i in words.size downTo 1) {
            val alias = words.subList(0, i).joinToString(" ").trim()
            if (alias.length < 3) {
                continue
            }

            artistMemoryStore.insertAliasIfMissing(alias)
        }
    }

    private fun scoreArtist(text: String): Int {
        val words = tokenizeWords(text)

        var score = 0
        if (words.isEmpty()) {
            return score
        }

        val first = words.first()
        if (ARTIST_WORDS.contains(first)) {
            score += 4
        }

        if (words.size >= 2) {
            score += 2
        }

        for (word in words) {
            if (ARTIST_WORDS.contains(word)) {
                score += 3
            }
        }

        if (text.length >= 10) {
            score += 1
        }

        if (POSSESSIVES.contains(first)) {
            score -= 6
        }

        if (VERB_WORDS.contains(first)) {
            score -= 5
        }

        if (words.size > 4) {
            for (word in words) {
                if (POSSESSIVES.contains(word)) {
                    score -= 4
                    break
                }
            }
        }

        return score
    }

    private fun replaceMultipleSpacesWithSingle(str: String): String {
        return str.replace(Regex("\\s+"), " ")
    }

    private fun normalize(text: String): String {
        return replaceMultipleSpacesWithSingle(text.trim())
    }

    private fun countWords(str: String): Int {
        return tokenizeWords(str).size
    }

    private fun allWordsInSet(text: String, set: Set<String>): Boolean {
        val words = tokenizeWords(text)
        if (words.isEmpty()) {
            return false
        }

        for (word in words) {
            if (!set.contains(word)) {
                return false
            }
        }

        return true
    }

    private fun tokenizeWords(text: String): List<String> {
        return replaceMultipleSpacesWithSingle(text.trim())
            .split(" ")
            .filter { it.isNotBlank() }
            .map { it.trim().trim('"', '.', ',', ';', ':', '!', '?', '(', ')').lowercase() }
    }

    private fun findAllPositions(text: String, token: String): List<Int> {
        val positions = mutableListOf<Int>()
        var index = text.indexOf(token)
        while (index != -1) {
            positions.add(index)
            index = text.indexOf(token, index + 1)
        }
        return positions
    }

    private fun parseSongArtistFlexible(rawText: String): Pair<String, String>? {
        if (rawText.isBlank() || looksLikeHelperText(rawText)) {
            return null
        }

        val normalized = rawText
            .replace('“', '"')
            .replace('”', '"')
            .trim()

        val separators = listOf(" • ", " - ", " — ", " – ")
        for (separator in separators) {
            val parts = normalized.split(separator)
            if (parts.size >= 2) {
                val song = parts.first().trim().trim('"')
                val artist = parts.last().trim().trim('"')
                if (song.isNotBlank() && artist.isNotBlank()) {
                    return song to artist
                }
            }
        }

        val bySplitRegex = Regex("\\s+by\\s+", RegexOption.IGNORE_CASE)
        val byMatches = bySplitRegex.findAll(normalized).toList()
        if (byMatches.isNotEmpty()) {
            val lastMatch = byMatches.last()
            val song = normalized.substring(0, lastMatch.range.first).trim().trim('"')
            val artist = normalized.substring(lastMatch.range.last + 1).trim().trim('"')
            if (song.isNotBlank() && artist.isNotBlank()) {
                return song to artist
            }
        }

        return null
    }

    private fun looksLikeHelperText(text: String): Boolean {
        val normalized = text.lowercase()
        return HELPER_TEXT_MARKERS.any { marker -> normalized.contains(marker) }
    }

    companion object {
        private val PIXEL_NOW_PLAYING_PACKAGES = setOf(
            "com.google.android.as",
            "com.google.android.apps.pixel.nowplaying",
        )
        @Volatile
        private var activeInstance: NowPlayingNotificationListener? = null
        @Volatile
        private var lastPayload: Map<String, String>? = null

        fun getCurrentNowPlaying(): Map<String, String>? {
            Log.i(TAG, "getCurrentNowPlaying: querying active instance")
            val live = activeInstance?.findCurrentNowPlayingPayload()
            if (live == null) {
                lastPayload = null
            }
            return live
        }

        fun openActivePlayer(
            sourcePackage: String?,
            selectedPackage: String?,
            searchQuery: String?,
        ): Boolean {
            return activeInstance?.openActiveMediaPlayerApp(
                sourcePackage = sourcePackage,
                selectedPackage = selectedPackage,
                searchQuery = searchQuery,
            ) == true
        }

        fun controlMedia(command: String, sourcePackage: String?): Boolean {
            return activeInstance?.controlActiveMediaPlayer(command, sourcePackage) == true
        }

        fun getMediaPlaybackState(sourcePackage: String?): Map<String, Any>? {
            return activeInstance?.getActiveMediaPlaybackState(sourcePackage)
        }

        fun getActiveSessionSnapshot(sourcePackage: String?): Map<String, Any?>? {
            return activeInstance?.getActiveMediaSessionSnapshot(sourcePackage)
        }

        fun seekMediaTo(positionMs: Long, sourcePackage: String?): Boolean {
            return activeInstance?.seekActiveMediaPlayer(positionMs, sourcePackage) == true
        }

        private data class NowPlayingPayload(
            val title: String,
            val artist: String,
            val sourcePackage: String,
            val sourceType: String,
            val artworkUrl: String? = null,
        )

        private const val UNKNOWN_ARTIST = "Artista desconocido"
        private const val TAG = "PIXEL_NOW_PLAYING"
        private const val SOURCE_TYPE_PIXEL = "pixel_now_playing"
        private const val SOURCE_TYPE_PLAYER = "media_player"
        private const val MEDIA_PREVIOUS = "previous"
        private const val MEDIA_PLAY_PAUSE = "play_pause"
        private const val MEDIA_NEXT = "next"
        private val IGNORED_PACKAGES = setOf(
            "net.iozamudioa.singsync",
            "com.android.systemui",
        )
        private val HELPER_TEXT_MARKERS = listOf(
            "presiona y ve tu historial",
            "historial de canciones",
            "song history",
            "está sonando",
            "esta sonando",
            "ahora",
        )
        private const val DEBUG_SESSION_SNAPSHOT_LOGS = true
        private val METADATA_LONG_KEYS = setOf(
            MediaMetadata.METADATA_KEY_DURATION,
            MediaMetadata.METADATA_KEY_YEAR,
            MediaMetadata.METADATA_KEY_TRACK_NUMBER,
            MediaMetadata.METADATA_KEY_NUM_TRACKS,
            MediaMetadata.METADATA_KEY_DISC_NUMBER,
            MediaMetadata.METADATA_KEY_BT_FOLDER_TYPE,
        )
        private val METADATA_BITMAP_KEYS = setOf(
            MediaMetadata.METADATA_KEY_ART,
            MediaMetadata.METADATA_KEY_ALBUM_ART,
            MediaMetadata.METADATA_KEY_DISPLAY_ICON,
        )
        private val METADATA_RATING_KEYS = setOf(
            MediaMetadata.METADATA_KEY_RATING,
            MediaMetadata.METADATA_KEY_USER_RATING,
        )
        private val PLAYBACK_ACTION_LABELS = linkedMapOf(
            PlaybackState.ACTION_STOP to "stop",
            PlaybackState.ACTION_PAUSE to "pause",
            PlaybackState.ACTION_PLAY to "play",
            PlaybackState.ACTION_REWIND to "rewind",
            PlaybackState.ACTION_SKIP_TO_PREVIOUS to "skip_to_previous",
            PlaybackState.ACTION_SKIP_TO_NEXT to "skip_to_next",
            PlaybackState.ACTION_FAST_FORWARD to "fast_forward",
            PlaybackState.ACTION_SET_RATING to "set_rating",
            PlaybackState.ACTION_SEEK_TO to "seek_to",
            PlaybackState.ACTION_PLAY_PAUSE to "play_pause",
            PlaybackState.ACTION_PLAY_FROM_MEDIA_ID to "play_from_media_id",
            PlaybackState.ACTION_PLAY_FROM_SEARCH to "play_from_search",
            PlaybackState.ACTION_SKIP_TO_QUEUE_ITEM to "skip_to_queue_item",
            PlaybackState.ACTION_PLAY_FROM_URI to "play_from_uri",
            PlaybackState.ACTION_PREPARE to "prepare",
            PlaybackState.ACTION_PREPARE_FROM_MEDIA_ID to "prepare_from_media_id",
            PlaybackState.ACTION_PREPARE_FROM_SEARCH to "prepare_from_search",
            PlaybackState.ACTION_PREPARE_FROM_URI to "prepare_from_uri",
            PlaybackState.ACTION_SET_PLAYBACK_SPEED to "set_playback_speed",
        )
        private val ARTIST_WORDS = setOf(
            "el", "la", "los", "las",
            "grupo", "banda", "dj", "mc", "orquesta", "trio", "sonora",
        )
        private val POSSESSIVES = setOf(
            "mi", "tu", "su", "mis", "tus", "sus",
        )
        private val VERB_WORDS = setOf(
            "quiero", "tengo", "busco", "siento", "necesito", "dime", "dame",
            "traigo", "ando", "vengo", "soy", "eres", "es", "somos",
        )
        private val PLACE_WORDS = setOf(
            "leon", "mexico", "texas", "michoacan", "jalisco", "durango",
            "sinaloa", "sonora", "chihuahua", "tijuana", "juarez",
        )
        private const val MEMORY_MATCH = 12
        private const val MEMORY_CONTAINS = 7
        private const val MEMORY_INSERT = 5
        private const val MEMORY_INC = 2
        private val SONG_ARTIST_QUOTED_PATTERN =
            Regex("[\"“”](.+?)[\"“”]\\s+(?:de|by)\\s+[\"“”](.+?)[\"“”]", RegexOption.IGNORE_CASE)
    }
}
