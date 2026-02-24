package net.iozamudioa.singsync

import android.content.ContentValues
import android.content.ContentUris
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity: FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		EventChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			NOW_PLAYING_CHANNEL,
		).setStreamHandler(
			object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					NowPlayingNotificationBridge.setSink(events)
				}

				override fun onCancel(arguments: Any?) {
					NowPlayingNotificationBridge.setSink(null)
				}
			},
		)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			NOW_PLAYING_METHODS_CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"getActiveSessionSnapshot" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					result.success(
						PixelNowPlayingNotificationListener.getActiveSessionSnapshot(sourcePackage),
					)
				}
				"getCurrentNowPlaying" -> {
					val payload = PixelNowPlayingNotificationListener.getCurrentNowPlaying()
					result.success(payload)
				}
				"openActivePlayer" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					val selectedPackage = call.argument<String>("selectedPackage")
					val searchQuery = call.argument<String>("searchQuery")
					result.success(
						PixelNowPlayingNotificationListener.openActivePlayer(
							sourcePackage = sourcePackage,
							selectedPackage = selectedPackage,
							searchQuery = searchQuery,
						),
					)
				}
				"mediaPrevious" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					result.success(
						PixelNowPlayingNotificationListener.controlMedia("previous", sourcePackage),
					)
				}
				"mediaPlayPause" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					result.success(
						PixelNowPlayingNotificationListener.controlMedia("play_pause", sourcePackage),
					)
				}
				"mediaNext" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					result.success(PixelNowPlayingNotificationListener.controlMedia("next", sourcePackage))
				}
				"mediaSeekTo" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					val positionRaw = call.argument<Number>("positionMs")
					val positionMs = positionRaw?.toLong() ?: -1L
					result.success(
						PixelNowPlayingNotificationListener.seekMediaTo(
							positionMs = positionMs,
							sourcePackage = sourcePackage,
						),
					)
				}
				"getMediaPlaybackState" -> {
					val sourcePackage = call.argument<String>("sourcePackage")
					result.success(
						PixelNowPlayingNotificationListener.getMediaPlaybackState(sourcePackage),
					)
				}
				"isNotificationListenerEnabled" -> {
					result.success(isNotificationListenerEnabled())
				}
				"openNotificationListenerSettings" -> {
					openNotificationListenerSettings()
					result.success(true)
				}
				"getInstalledMediaApps" -> {
					val packages = call.argument<List<String>>("packages") ?: emptyList()
					result.success(getInstalledMediaApps(packages))
				}
				"getMediaAppIcon" -> {
					val packageName = call.argument<String>("packageName").orEmpty()
					val maxPx = call.argument<Int>("maxPx") ?: 96
					result.success(getMediaAppIcon(packageName, maxPx))
				}
				"turnScreenOffIfPossible" -> {
					result.success(turnScreenOffIfPossible())
				}
				else -> result.notImplemented()
			}
		}
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			LYRICS_CHANNEL,
		).setMethodCallHandler { call, result ->
			val title = call.argument<String>("title").orEmpty()
			val artist = call.argument<String>("artist").orEmpty()
			val query = call.argument<String>("query").orEmpty()
			val preferSynced = call.argument<Boolean>("preferSynced") == true

			when (call.method) {
				"fetchLyrics" -> {
					if (title.isBlank() || artist.isBlank()) {
						result.success(mapOf("lyrics" to "No se encontró letra para esta canción en lrclib."))
						return@setMethodCallHandler
					}

					Thread {
						val payload = LyricsProviderRegistry.active.fetchLyrics(title, artist, preferSynced)
						runOnUiThread {
							result.success(payload)
						}
					}.start()
				}
				"searchLyricsCandidates" -> {
					if (query.isBlank()) {
						result.success(emptyList<Map<String, String>>())
						return@setMethodCallHandler
					}

					Thread {
						val payload = LyricsProviderRegistry.active.searchLyricsCandidates(query)
						runOnUiThread {
							result.success(payload)
						}
					}.start()
				}
				"fetchArtworkUrl" -> {
					if (title.isBlank() || artist.isBlank()) {
						result.success(null)
						return@setMethodCallHandler
					}

					Thread {
						val payload = MusicMetadataProvider.fetchArtworkUrl(title, artist)
						runOnUiThread {
							result.success(payload)
						}
					}.start()
				}
				"fetchArtistInsight" -> {
					if (artist.isBlank()) {
						result.success(null)
						return@setMethodCallHandler
					}

					Thread {
						val payload = MusicMetadataProvider.fetchArtistInsight(artist)
						runOnUiThread {
							result.success(payload)
						}
					}.start()
				}
				"saveSnapshotImage" -> {
					val bytes = call.argument<ByteArray>("bytes")
					val fileName = call.argument<String>("fileName").orEmpty()
					if (bytes == null || bytes.isEmpty()) {
						result.success(false)
						return@setMethodCallHandler
					}

					Thread {
						val saved = saveSnapshotImage(bytes, fileName)
						runOnUiThread {
							result.success(saved)
						}
					}.start()
				}
				"shareSnapshotWithSaveOption" -> {
					val bytes = call.argument<ByteArray>("bytes")
					val fileName = call.argument<String>("fileName").orEmpty()
					if (bytes == null || bytes.isEmpty()) {
						result.success(false)
						return@setMethodCallHandler
					}

					val launched = shareSnapshotWithSaveOption(
						bytes = bytes,
						fileName = fileName,
					)
					result.success(launched)
				}
				"consumeSnapshotSavedFeedback" -> {
					result.success(SnapshotShareBridge.consumeSavedFeedback())
				}
				"listSavedSnapshots" -> {
					Thread {
						val snapshots = listSavedSnapshots()
						runOnUiThread {
							result.success(snapshots)
						}
					}.start()
				}
				"readSnapshotImageBytes" -> {
					val uriRaw = call.argument<String>("uri").orEmpty()
					if (uriRaw.isBlank()) {
						result.success(null)
						return@setMethodCallHandler
					}

					Thread {
						val bytes = readSnapshotImageBytes(uriRaw)
						runOnUiThread {
							result.success(bytes)
						}
					}.start()
				}
				"deleteSnapshotImage" -> {
					val uriRaw = call.argument<String>("uri").orEmpty()
					if (uriRaw.isBlank()) {
						result.success(false)
						return@setMethodCallHandler
					}

					Thread {
						val deleted = deleteSnapshotImage(uriRaw)
						runOnUiThread {
							result.success(deleted)
						}
					}.start()
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun listSavedSnapshots(): List<Map<String, Any>> {
		val resolver = contentResolver
		val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
		val projection = arrayOf(
			MediaStore.Images.Media._ID,
			MediaStore.Images.Media.DISPLAY_NAME,
			MediaStore.Images.Media.DATE_ADDED,
		)

		val (selection, selectionArgs) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			Pair(
				"${MediaStore.Images.Media.RELATIVE_PATH}=? AND ${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?",
				arrayOf("${Environment.DIRECTORY_PICTURES}/SingSync/", "singsync_snapshot_%"),
			)
		} else {
			Pair(
				"${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?",
				arrayOf("singsync_snapshot_%"),
			)
		}

		val items = mutableListOf<Map<String, Any>>()
		resolver.query(
			collection,
			projection,
			selection,
			selectionArgs,
			"${MediaStore.Images.Media.DATE_ADDED} DESC",
		)?.use { cursor ->
			val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
			val displayNameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
			val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
			while (cursor.moveToNext()) {
				val id = cursor.getLong(idColumn)
				val displayName = cursor.getString(displayNameColumn).orEmpty()
				val dateAddedSeconds = cursor.getLong(dateAddedColumn)
				val uri = ContentUris.withAppendedId(collection, id)
				val metadata = extractSnapshotMetadata(displayName)
				items += mapOf(
					"uri" to uri.toString(),
					"dateAddedMs" to (dateAddedSeconds * 1000L),
					"displayName" to displayName,
					"title" to (metadata["title"] ?: ""),
					"artist" to (metadata["artist"] ?: ""),
					"sourcePackage" to (metadata["sourcePackage"] ?: ""),
				)
			}
		}

		return items
	}

	private fun extractSnapshotMetadata(fileName: String): Map<String, String> {
		if (fileName.isBlank()) {
			return emptyMap()
		}

		val withoutExtension = fileName.substringBeforeLast('.')
		val title = withoutExtension.substringAfter("__t_", "").substringBefore("__a_", "")
		val artist = withoutExtension.substringAfter("__a_", "").substringBefore("__p_", "")
		val sourcePackage = withoutExtension.substringAfter("__p_", "")

		fun decode(value: String): String {
			return try {
				Uri.decode(value)
			} catch (_: Throwable) {
				""
			}
		}

		val decodedTitle = decode(title).trim()
		val decodedArtist = decode(artist).trim()
		val decodedSource = decode(sourcePackage).trim()

		if (decodedTitle.isEmpty() && decodedArtist.isEmpty() && decodedSource.isEmpty()) {
			return emptyMap()
		}

		return mapOf(
			"title" to decodedTitle,
			"artist" to decodedArtist,
			"sourcePackage" to decodedSource,
		)
	}

	private fun readSnapshotImageBytes(uriRaw: String): ByteArray? {
		return try {
			val uri = Uri.parse(uriRaw)
			contentResolver.openInputStream(uri)?.use { input ->
				input.readBytes()
			}
		} catch (_: Throwable) {
			null
		}
	}

	private fun deleteSnapshotImage(uriRaw: String): Boolean {
		return try {
			val uri = Uri.parse(uriRaw)
			contentResolver.delete(uri, null, null) > 0
		} catch (_: Throwable) {
			false
		}
	}

	private fun isNotificationListenerEnabled(): Boolean {
		val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
		if (flat.isNullOrBlank()) {
			return false
		}

		val me = ComponentName(this, PixelNowPlayingNotificationListener::class.java).flattenToString()
		return flat.split(':').any { it.equals(me, ignoreCase = true) }
	}

	private fun openNotificationListenerSettings() {
		val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
		startActivity(intent)
	}

	private fun getInstalledMediaApps(packages: List<String>): List<String> {
		if (packages.isEmpty()) {
			return emptyList()
		}

		val installed = mutableListOf<String>()
		for (pkg in packages) {
			if (pkg.isBlank()) {
				continue
			}

			val exists = try {
				packageManager.getPackageInfo(pkg, 0)
				true
			} catch (_: Throwable) {
				false
			}

			if (exists) {
				installed += pkg
			}
		}

		return installed
	}

	private fun getMediaAppIcon(packageName: String, maxPx: Int): ByteArray? {
		if (packageName.isBlank()) {
			return null
		}

		return try {
			val appInfo = packageManager.getApplicationInfo(packageName, 0)
			val drawable = packageManager.getApplicationIcon(appInfo)
			val sizePx = maxPx.coerceIn(24, 256)
			val bitmap = drawableToBitmap(drawable, sizePx)
			ByteArrayOutputStream().use { stream ->
				bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
				stream.toByteArray()
			}
		} catch (_: Throwable) {
			null
		}
	}

	private fun drawableToBitmap(drawable: Drawable, sizePx: Int): Bitmap {
		if (drawable is BitmapDrawable) {
			val rawBitmap = drawable.bitmap
			if (rawBitmap != null) {
				if (rawBitmap.width == sizePx && rawBitmap.height == sizePx) {
					return rawBitmap
				}
				return Bitmap.createScaledBitmap(rawBitmap, sizePx, sizePx, true)
			}
		}

		val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
		val canvas = Canvas(bitmap)
		drawable.setBounds(0, 0, canvas.width, canvas.height)
		drawable.draw(canvas)
		return bitmap
	}

	private fun turnScreenOffIfPossible(): Boolean {
		return try {
			val powerManager = getSystemService(POWER_SERVICE) as? PowerManager ?: return false
			val goToSleepMethod = PowerManager::class.java.getMethod(
				"goToSleep",
				Long::class.javaPrimitiveType,
			)
			goToSleepMethod.invoke(powerManager, SystemClock.uptimeMillis())
			true
		} catch (_: Throwable) {
			false
		}
	}

	private fun saveSnapshotImage(bytes: ByteArray, fileName: String): Boolean {
		val safeName = if (fileName.isBlank()) {
			"singsync_snapshot_${System.currentTimeMillis()}.png"
		} else {
			fileName
		}

		val resolver = contentResolver
		val values = ContentValues().apply {
			put(MediaStore.Images.Media.DISPLAY_NAME, safeName)
			put(MediaStore.Images.Media.MIME_TYPE, "image/png")
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/SingSync")
				put(MediaStore.Images.Media.IS_PENDING, 1)
			}
		}

		val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false

		return try {
			resolver.openOutputStream(uri)?.use { stream ->
				stream.write(bytes)
			} ?: return false

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				val completeValues = ContentValues().apply {
					put(MediaStore.Images.Media.IS_PENDING, 0)
				}
				resolver.update(uri, completeValues, null, null)
			}

			true
		} catch (_: Throwable) {
			resolver.delete(uri, null, null)
			false
		}
	}

	private fun shareSnapshotWithSaveOption(
		bytes: ByteArray,
		fileName: String,
	): Boolean {
		val safeName = if (fileName.isBlank()) {
			"singsync_snapshot_${System.currentTimeMillis()}.png"
		} else {
			fileName
		}

		return try {
			val cacheFile = File(cacheDir, safeName)
			cacheFile.outputStream().use { stream ->
				stream.write(bytes)
			}

			val uri: Uri = FileProvider.getUriForFile(
				this,
				"$packageName.fileprovider",
				cacheFile,
			)

			val shareIntent = Intent(Intent.ACTION_SEND).apply {
				type = "image/png"
				putExtra(Intent.EXTRA_STREAM, uri)
				addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			}

			val chooser = Intent.createChooser(shareIntent, null)

			startActivity(chooser)
			true
		} catch (_: Throwable) {
			false
		}
	}

	companion object {
		const val NOW_PLAYING_CHANNEL = "net.iozamudioa.singsync/now_playing"
		const val NOW_PLAYING_METHODS_CHANNEL = "net.iozamudioa.singsync/now_playing_methods"
		const val LYRICS_CHANNEL = "net.iozamudioa.singsync/lyrics"
	}
}
