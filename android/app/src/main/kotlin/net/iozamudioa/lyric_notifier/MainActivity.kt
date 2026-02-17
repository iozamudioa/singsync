package net.iozamudioa.lyric_notifier

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

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
				else -> result.notImplemented()
			}
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

	companion object {
		const val NOW_PLAYING_CHANNEL = "net.iozamudioa.lyric_notifier/now_playing"
		const val NOW_PLAYING_METHODS_CHANNEL = "net.iozamudioa.lyric_notifier/now_playing_methods"
		const val LYRICS_CHANNEL = "net.iozamudioa.lyric_notifier/lyrics"
	}
}
