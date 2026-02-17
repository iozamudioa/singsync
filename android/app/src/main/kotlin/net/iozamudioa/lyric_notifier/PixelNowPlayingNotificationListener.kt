package net.iozamudioa.lyric_notifier

import android.app.Notification
import android.app.SearchManager
import android.content.ComponentName
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class PixelNowPlayingNotificationListener : NotificationListenerService() {
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
        emitPayloadIfNew(payload)
    }

    private fun isPlaybackStateActive(state: Int?): Boolean {
        return state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING
    }

    private fun isAnyPlaybackActive(): Boolean {
        val manager = getSystemService(MediaSessionManager::class.java) ?: return false
        val component = ComponentName(this, PixelNowPlayingNotificationListener::class.java)
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
        findBestMediaController(sourcePackage)?.packageName?.let { candidates.add(it) }
        findBestMediaController(null)?.packageName?.let { candidates.add(it) }
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
        val component = ComponentName(this, PixelNowPlayingNotificationListener::class.java)
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
            isActiveMediaPlayerNotification(sbn.notification) -> payloadFromMediaPlayer(extras, packageName)
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
        val rawBigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()

        val titleCandidates = listOf(rawBigTitle, rawTitle)
            .filter { it.isNotBlank() && !looksLikeHelperText(it) }
        val artistCandidates = listOf(rawText, rawSubText, rawBigText)
            .filter { it.isNotBlank() && !looksLikeHelperText(it) }

        val parsed = (titleCandidates + artistCandidates)
            .asSequence()
            .mapNotNull { parseSongArtistFlexible(it) }
            .firstOrNull()

        val title = parsed?.first
            ?: titleCandidates.firstOrNull()
            ?: rawText.takeUnless { looksLikeHelperText(it) }
            ?: rawSubText.takeUnless { looksLikeHelperText(it) }
            ?: rawBigText.takeUnless { looksLikeHelperText(it) }
            ?: ""

        val artist = parsed?.second
            ?: artistCandidates.firstOrNull()
            ?: UNKNOWN_ARTIST

        if (title.isBlank()) {
            return null
        }

        val artworkUrl = extractMediaArtworkUrl(packageName, extras)

        return NowPlayingPayload(
            title = title,
            artist = artist,
            sourcePackage = packageName,
            sourceType = SOURCE_TYPE_PLAYER,
            artworkUrl = artworkUrl,
        )
    }

    private fun extractMediaArtworkUrl(packageName: String, extras: Bundle): String? {
        val controller = findBestMediaController(packageName)
        val metadata = controller?.metadata ?: return null

        val candidates = listOf(
            metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI),
            metadata.getString(MediaMetadata.METADATA_KEY_ART_URI),
            metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI),
        )

        return candidates
            .mapNotNull { it?.trim() }
            .firstOrNull { it.startsWith("http://") || it.startsWith("https://") }
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
        private var activeInstance: PixelNowPlayingNotificationListener? = null
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
            "net.iozamudioa.lyric_notifier",
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
