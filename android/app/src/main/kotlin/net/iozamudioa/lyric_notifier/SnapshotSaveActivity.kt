package net.iozamudioa.lyric_notifier

import android.app.Activity
import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import java.io.File

class SnapshotSaveActivity : Activity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)

		val filePath = intent.getStringExtra("filePath").orEmpty()
		val fileName = intent.getStringExtra("fileName").orEmpty()
		if (filePath.isBlank()) {
			finish()
			return
		}

		Thread {
			val sourceFile = File(filePath)
			val bytes = if (sourceFile.exists()) sourceFile.readBytes() else ByteArray(0)
			val saved = if (bytes.isEmpty()) {
				false
			} else {
				saveSnapshotImage(bytes, fileName)
			}

			runOnUiThread {
				if (saved) {
					SnapshotShareBridge.markSavedFeedback()
				}
				finish()
			}
		}.start()
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
}
