package net.iozamudioa.lyric_notifier

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class ArtistMemoryStore(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION,
) {

    data class MemoryArtist(
        val name: String,
        val nameLower: String,
        val confidence: Int,
        val occurrences: Int,
    )

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS artists_memory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE,
                confidence INTEGER NOT NULL,
                occurrences INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            onCreate(db)
        }
    }

    @Synchronized
    fun getAllArtists(): List<MemoryArtist> {
        val artists = mutableListOf<MemoryArtist>()
        val db = readableDatabase
        db.query(
            TABLE_NAME,
            arrayOf(COL_NAME, COL_CONFIDENCE, COL_OCCURRENCES),
            null,
            null,
            null,
            null,
            "${COL_CONFIDENCE} DESC, ${COL_OCCURRENCES} DESC, ${COL_NAME} ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(0)?.trim().orEmpty()
                if (name.isBlank()) {
                    continue
                }

                artists.add(
                    MemoryArtist(
                        name = name,
                        nameLower = name.lowercase(),
                        confidence = cursor.getInt(1),
                        occurrences = cursor.getInt(2),
                    ),
                )
            }
        }
        return artists
    }

    @Synchronized
    fun learnArtist(artistName: String, insertScore: Int, incrementScore: Int) {
        val normalized = normalize(artistName)
        if (normalized.length < 2) {
            return
        }

        val existing = findArtist(normalized)
        val db = writableDatabase
        if (existing != null) {
            val values = ContentValues().apply {
                put(COL_CONFIDENCE, existing.confidence + incrementScore)
                put(COL_OCCURRENCES, existing.occurrences + 1)
            }
            db.update(TABLE_NAME, values, "$COL_NAME = ?", arrayOf(normalized))
        } else {
            val values = ContentValues().apply {
                put(COL_NAME, normalized)
                put(COL_CONFIDENCE, insertScore)
                put(COL_OCCURRENCES, 1)
            }
            db.insertWithOnConflict(TABLE_NAME, null, values, SQLiteDatabase.CONFLICT_IGNORE)
        }
    }

    @Synchronized
    fun insertAliasIfMissing(alias: String) {
        val normalized = normalize(alias)
        if (normalized.length < 3) {
            return
        }

        if (findArtist(normalized) != null) {
            return
        }

        val values = ContentValues().apply {
            put(COL_NAME, normalized)
            put(COL_CONFIDENCE, 1)
            put(COL_OCCURRENCES, 1)
        }

        writableDatabase.insertWithOnConflict(
            TABLE_NAME,
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    @Synchronized
    private fun findArtist(name: String): MemoryArtist? {
        val normalized = normalize(name)
        if (normalized.isBlank()) {
            return null
        }

        val db = readableDatabase
        db.query(
            TABLE_NAME,
            arrayOf(COL_NAME, COL_CONFIDENCE, COL_OCCURRENCES),
            "$COL_NAME = ?",
            arrayOf(normalized),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) {
                return null
            }

            val existingName = cursor.getString(0)?.trim().orEmpty()
            if (existingName.isBlank()) {
                return null
            }

            return MemoryArtist(
                name = existingName,
                nameLower = existingName.lowercase(),
                confidence = cursor.getInt(1),
                occurrences = cursor.getInt(2),
            )
        }
    }

    private fun normalize(value: String): String {
        return value.trim().replace(Regex("\\s+"), " ")
    }

    companion object {
        private const val DATABASE_NAME = "artist_memory.db"
        private const val DATABASE_VERSION = 2

        private const val TABLE_NAME = "artists_memory"
        private const val COL_NAME = "name"
        private const val COL_CONFIDENCE = "confidence"
        private const val COL_OCCURRENCES = "occurrences"
    }
}
