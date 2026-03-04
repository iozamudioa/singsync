import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/artist_insight.dart';

class CachedSong {
  const CachedSong({
    required this.title,
    required this.artist,
    required this.lyrics,
    required this.artworkUrl,
    required this.artistInsight,
    required this.metadata,
  });

  final String title;
  final String artist;
  final String lyrics;
  final String? artworkUrl;
  final ArtistInsight? artistInsight;
  final Map<String, dynamic>? metadata;
}

class CatchemCaptureEvent {
  const CatchemCaptureEvent({
    required this.capturedAtMs,
    required this.captureMode,
  });

  final int capturedAtMs;
  final String captureMode;
}

class PlaybackHistoryEvent {
  const PlaybackHistoryEvent({
    required this.playedAtMs,
    required this.sourceType,
    required this.sourcePackage,
    required this.latitude,
    required this.longitude,
  });

  final int playedAtMs;
  final String sourceType;
  final String? sourcePackage;
  final double? latitude;
  final double? longitude;
}

class CatchemSongSummary {
  const CatchemSongSummary({
    required this.title,
    required this.artist,
    required this.albumName,
    required this.lyrics,
    required this.artworkUrl,
    required this.listenCount,
    required this.captureCount,
    required this.firstSeenAtMs,
    required this.lastSeenAtMs,
    required this.sourceType,
    required this.sourcePackage,
    required this.lastCaptureMode,
    required this.latitude,
    required this.longitude,
    required this.captureHistory,
  });

  final String title;
  final String artist;
  final String? albumName;
  final String lyrics;
  final String? artworkUrl;
  final int listenCount;
  final int captureCount;
  final int firstSeenAtMs;
  final int lastSeenAtMs;
  final String sourceType;
  final String? sourcePackage;
  final String lastCaptureMode;
  final double? latitude;
  final double? longitude;
  final List<CatchemCaptureEvent> captureHistory;
}

class CatchemMapPointSummary {
  const CatchemMapPointSummary({
    required this.title,
    required this.artist,
    required this.albumName,
    required this.artworkUrl,
    required this.detectedAtMs,
    required this.latitude,
    required this.longitude,
    required this.sourceType,
    required this.sourcePackage,
  });

  final String title;
  final String artist;
  final String? albumName;
  final String? artworkUrl;
  final int detectedAtMs;
  final double latitude;
  final double longitude;
  final String sourceType;
  final String? sourcePackage;
}

class LocalSongCacheRepository {
  static const String _databaseName = 'singsync_song_cache.db';
  static const int _databaseVersion = 2;

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, _databaseName);

    _db = await openDatabase(
      fullPath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSchema(db);
          await _migrateLegacySongCache(db);
        }
      },
    );

    return _db!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS artista(
        id_artista INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        nombre_normalizado TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS album(
        id_album INTEGER PRIMARY KEY AUTOINCREMENT,
        id_artista INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        nombre_normalizado TEXT NOT NULL,
        FOREIGN KEY(id_artista) REFERENCES artista(id_artista) ON DELETE CASCADE,
        UNIQUE(id_artista, nombre_normalizado)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cancion(
        id_cancion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_artista INTEGER NOT NULL,
        id_album INTEGER,
        titulo TEXT NOT NULL,
        titulo_normalizado TEXT NOT NULL,
        song_key TEXT NOT NULL UNIQUE,
        duracion_seg INTEGER,
        lyrics TEXT,
        artwork_url TEXT,
        artist_insight_json TEXT,
        metadata_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(id_artista) REFERENCES artista(id_artista) ON DELETE CASCADE,
        FOREIGN KEY(id_album) REFERENCES album(id_album) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tipo_deteccion(
        id_tipo_deteccion INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT NOT NULL UNIQUE,
        descripcion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS deteccion(
        id_deteccion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cancion INTEGER NOT NULL,
        id_tipo_deteccion INTEGER NOT NULL,
        fecha_hora INTEGER NOT NULL,
        latitud REAL,
        longitud REAL,
        source_type TEXT,
        source_package TEXT,
        FOREIGN KEY(id_cancion) REFERENCES cancion(id_cancion) ON DELETE CASCADE,
        FOREIGN KEY(id_tipo_deteccion) REFERENCES tipo_deteccion(id_tipo_deteccion)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reproduccion(
        id_reproduccion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cancion INTEGER NOT NULL,
        fecha_hora INTEGER NOT NULL,
        source_type TEXT,
        source_package TEXT,
        id_deteccion INTEGER,
        FOREIGN KEY(id_cancion) REFERENCES cancion(id_cancion) ON DELETE CASCADE,
        FOREIGN KEY(id_deteccion) REFERENCES deteccion(id_deteccion) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS screenshot(
        id_screenshot INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cancion INTEGER,
        uri TEXT NOT NULL UNIQUE,
        display_name TEXT,
        title TEXT,
        artist TEXT,
        source_package TEXT,
        fecha_hora INTEGER NOT NULL,
        FOREIGN KEY(id_cancion) REFERENCES cancion(id_cancion) ON DELETE SET NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_album_artista ON album(id_artista)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cancion_artista ON cancion(id_artista)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cancion_album ON cancion(id_album)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reproduccion_cancion_fecha ON reproduccion(id_cancion, fecha_hora DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_deteccion_cancion_fecha ON deteccion(id_cancion, fecha_hora DESC)');

    await db.insert(
      'tipo_deteccion',
      const <String, Object?>{'codigo': 'automatic', 'descripcion': 'Deteccion automatica (Now Playing)'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'tipo_deteccion',
      const <String, Object?>{'codigo': 'manual', 'descripcion': 'Captura manual (corazon)'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _migrateLegacySongCache(Database db) async {
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='song_cache'");
    if (tables.isEmpty) {
      return;
    }

    final rows = await db.query('song_cache');
    for (final row in rows) {
      final title = (row['title'] ?? '').toString().trim();
      final artist = (row['artist'] ?? '').toString().trim();
      if (title.isEmpty || artist.isEmpty) {
        continue;
      }

      final updatedAt = _toNullableInt(row['updated_at']) ?? DateTime.now().millisecondsSinceEpoch;
      final songId = await _ensureSong(
        db,
        title: title,
        artist: artist,
        albumName: null,
        durationSec: null,
        lyrics: (row['lyrics'] ?? '').toString(),
        artworkUrl: (row['artwork_url'] ?? '').toString().trim().isEmpty ? null : (row['artwork_url'] ?? '').toString().trim(),
        artistInsightJson: (row['artist_insight_json'] ?? '').toString().trim().isEmpty ? null : (row['artist_insight_json'] ?? '').toString(),
        metadataJson: (row['metadata_json'] ?? '').toString().trim().isEmpty ? null : (row['metadata_json'] ?? '').toString(),
        nowMs: updatedAt,
      );

      await db.insert(
        'reproduccion',
        <String, Object?>{
          'id_cancion': songId,
          'fecha_hora': updatedAt,
          'source_type': 'legacy_song_cache',
          'source_package': null,
          'id_deteccion': null,
        },
      );
    }
  }

  String _cacheKey({required String title, required String artist}) {
    return '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
  }

  String _normalizeText(String value) => value.trim().toLowerCase();

  Future<int> _ensureArtist(DatabaseExecutor db, String artist) async {
    final normalized = _normalizeText(artist);
    final existing = await db.query(
      'artista',
      columns: ['id_artista'],
      where: 'nombre_normalizado = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return _toNullableInt(existing.first['id_artista']) ?? 0;
    }

    return await db.insert(
      'artista',
      <String, Object?>{
        'nombre': artist.trim(),
        'nombre_normalizado': normalized,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int?> _ensureAlbum(DatabaseExecutor db, {required int artistId, required String? albumName}) async {
    final normalizedName = (albumName ?? '').trim();
    if (normalizedName.isEmpty) {
      return null;
    }

    final normalized = _normalizeText(normalizedName);
    final existing = await db.query(
      'album',
      columns: ['id_album'],
      where: 'id_artista = ? AND nombre_normalizado = ?',
      whereArgs: [artistId, normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return _toNullableInt(existing.first['id_album']);
    }

    final insertedId = await db.insert(
      'album',
      <String, Object?>{
        'id_artista': artistId,
        'nombre': normalizedName,
        'nombre_normalizado': normalized,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (insertedId > 0) {
      return insertedId;
    }

    final fallback = await db.query(
      'album',
      columns: ['id_album'],
      where: 'id_artista = ? AND nombre_normalizado = ?',
      whereArgs: [artistId, normalized],
      limit: 1,
    );
    return fallback.isNotEmpty ? _toNullableInt(fallback.first['id_album']) : null;
  }

  Future<int> _ensureSong(
    DatabaseExecutor db, {
    required String title,
    required String artist,
    required String? albumName,
    required int? durationSec,
    required String? lyrics,
    required String? artworkUrl,
    required String? artistInsightJson,
    required String? metadataJson,
    required int nowMs,
  }) async {
    final titleTrimmed = title.trim();
    final artistTrimmed = artist.trim();
    final songKey = _cacheKey(title: titleTrimmed, artist: artistTrimmed);

    final artistId = await _ensureArtist(db, artistTrimmed);
    final albumId = await _ensureAlbum(db, artistId: artistId, albumName: albumName);

    final existing = await db.query(
      'cancion',
      columns: ['id_cancion', 'lyrics', 'artwork_url', 'artist_insight_json', 'metadata_json', 'duracion_seg', 'id_album'],
      where: 'song_key = ?',
      whereArgs: [songKey],
      limit: 1,
    );

    if (existing.isEmpty) {
      return await db.insert(
        'cancion',
        <String, Object?>{
          'id_artista': artistId,
          'id_album': albumId,
          'titulo': titleTrimmed,
          'titulo_normalizado': _normalizeText(titleTrimmed),
          'song_key': songKey,
          'duracion_seg': durationSec,
          'lyrics': lyrics,
          'artwork_url': artworkUrl,
          'artist_insight_json': artistInsightJson,
          'metadata_json': metadataJson,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );
    }

    final row = existing.first;
    final currentDuration = _toNullableInt(row['duracion_seg']);
    final currentAlbum = _toNullableInt(row['id_album']);
    final nextDuration = durationSec ?? currentDuration;
    final nextAlbum = albumId ?? currentAlbum;

    final nextLyrics = (lyrics ?? '').trim().isEmpty
        ? (row['lyrics'] ?? '').toString()
        : lyrics;
    final nextArtwork = (artworkUrl ?? '').trim().isEmpty
        ? (row['artwork_url'] as String?)
        : artworkUrl;
    final nextInsight = (artistInsightJson ?? '').trim().isEmpty
        ? (row['artist_insight_json'] as String?)
        : artistInsightJson;
    final nextMetadata = (metadataJson ?? '').trim().isEmpty
        ? (row['metadata_json'] as String?)
        : metadataJson;

    final songId = _toNullableInt(row['id_cancion']) ?? 0;
    await db.update(
      'cancion',
      <String, Object?>{
        'id_artista': artistId,
        'id_album': nextAlbum,
        'duracion_seg': nextDuration,
        'lyrics': nextLyrics,
        'artwork_url': nextArtwork,
        'artist_insight_json': nextInsight,
        'metadata_json': nextMetadata,
        'updated_at': nowMs,
      },
      where: 'id_cancion = ?',
      whereArgs: [songId],
    );

    return songId;
  }

  Future<CachedSong?> findSong({required String title, required String artist}) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);
    final rows = await db.rawQuery(
      '''
      SELECT c.titulo, a.nombre AS artista, c.lyrics, c.artwork_url, c.artist_insight_json, c.metadata_json
      FROM cancion c
      INNER JOIN artista a ON a.id_artista = c.id_artista
      WHERE c.song_key = ?
      LIMIT 1
      ''',
      [key],
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawLyrics = (row['lyrics'] ?? '').toString().trim();
    return CachedSong(
      title: (row['titulo'] ?? '').toString(),
      artist: (row['artista'] ?? '').toString(),
      lyrics: rawLyrics.toLowerCase() == 'null' ? '' : rawLyrics,
      artworkUrl: (row['artwork_url'] as String?)?.trim().isEmpty == true
          ? null
          : row['artwork_url'] as String?,
      artistInsight: _artistInsightFromJson(row['artist_insight_json'] as String?),
      metadata: _mapFromJson(row['metadata_json'] as String?),
    );
  }

  Future<CachedSong?> findMostRecentSong() async {
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT c.titulo, a.nombre AS artista, c.lyrics, c.artwork_url, c.artist_insight_json, c.metadata_json
      FROM cancion c
      INNER JOIN artista a ON a.id_artista = c.id_artista
      ORDER BY c.updated_at DESC
      LIMIT 1
      ''',
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawLyrics = (row['lyrics'] ?? '').toString().trim();
    return CachedSong(
      title: (row['titulo'] ?? '').toString(),
      artist: (row['artista'] ?? '').toString(),
      lyrics: rawLyrics.toLowerCase() == 'null' ? '' : rawLyrics,
      artworkUrl: (row['artwork_url'] as String?)?.trim().isEmpty == true
          ? null
          : row['artwork_url'] as String?,
      artistInsight: _artistInsightFromJson(row['artist_insight_json'] as String?),
      metadata: _mapFromJson(row['metadata_json'] as String?),
    );
  }

  Future<void> upsertSong({
    required String title,
    required String artist,
    required String lyrics,
    String? albumName,
    int? durationSec,
    String? artworkUrl,
    ArtistInsight? artistInsight,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await _database();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await _ensureSong(
        txn,
        title: title,
        artist: artist,
        albumName: albumName,
        durationSec: durationSec,
        lyrics: lyrics,
        artworkUrl: artworkUrl,
        artistInsightJson: artistInsight == null ? null : jsonEncode(_artistInsightToMap(artistInsight)),
        metadataJson: metadata == null ? null : jsonEncode(metadata),
        nowMs: nowMs,
      );
    });
  }

  Future<void> attachArtistInsight({
    required String title,
    required String artist,
    required ArtistInsight insight,
  }) async {
    final db = await _database();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = _cacheKey(title: title, artist: artist);
    await db.update(
      'cancion',
      <String, Object?>{
        'artist_insight_json': jsonEncode(_artistInsightToMap(insight)),
        'updated_at': nowMs,
      },
      where: 'song_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> recordNowPlayingPlayback({
    required String title,
    required String artist,
    String? albumName,
    int? durationSec,
    String? lyrics,
    String? artworkUrl,
    required String sourceType,
    String? sourcePackage,
    required bool createDetection,
    String detectionCode = 'automatic',
    double? latitude,
    double? longitude,
    int dedupeWindowMs = 0,
    int? occurredAtMs,
  }) async {
    final db = await _database();
    final nowMs = occurredAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedSourcePackage = (sourcePackage ?? '').trim().isEmpty ? null : sourcePackage!.trim();

    await db.transaction((txn) async {
      final songId = await _ensureSong(
        txn,
        title: title,
        artist: artist,
        albumName: albumName,
        durationSec: durationSec,
        lyrics: lyrics,
        artworkUrl: artworkUrl,
        artistInsightJson: null,
        metadataJson: null,
        nowMs: nowMs,
      );

      if (dedupeWindowMs > 0) {
        final duplicateRows = await txn.query(
          'reproduccion',
          columns: ['id_reproduccion', 'fecha_hora', 'id_deteccion'],
          where: 'id_cancion = ?',
          whereArgs: [songId],
          orderBy: 'fecha_hora DESC',
          limit: 1,
        );

        if (duplicateRows.isNotEmpty) {
          final row = duplicateRows.first;
          final lastMs = _toNullableInt(row['fecha_hora']) ?? 0;
          final withinWindow = (nowMs - lastMs).abs() <= dedupeWindowMs;
          if (withinWindow) {
            final detectionId = _toNullableInt(row['id_deteccion']);
            final hasLocation = latitude != null || longitude != null;
            if (createDetection && hasLocation && detectionId != null) {
              await txn.rawUpdate(
                'UPDATE deteccion SET latitud = COALESCE(latitud, ?), longitud = COALESCE(longitud, ?) WHERE id_deteccion = ?',
                [latitude, longitude, detectionId],
              );
            }
            return;
          }
        }
      }

      final playbackId = await txn.insert(
        'reproduccion',
        <String, Object?>{
          'id_cancion': songId,
          'fecha_hora': nowMs,
          'source_type': sourceType,
          'source_package': normalizedSourcePackage,
          'id_deteccion': null,
        },
      );

      if (!createDetection) {
        return;
      }

      final detectionTypeId = await _ensureDetectionType(txn, detectionCode);
      final detectionId = await txn.insert(
        'deteccion',
        <String, Object?>{
          'id_cancion': songId,
          'id_tipo_deteccion': detectionTypeId,
          'fecha_hora': nowMs,
          'latitud': latitude,
          'longitud': longitude,
          'source_type': sourceType,
          'source_package': normalizedSourcePackage,
        },
      );

      await txn.update(
        'reproduccion',
        <String, Object?>{'id_deteccion': detectionId},
        where: 'id_reproduccion = ?',
        whereArgs: [playbackId],
      );
    });
  }

  Future<void> recordManualDetection({
    required String title,
    required String artist,
    String? albumName,
    int? durationSec,
    String? lyrics,
    String? artworkUrl,
    required String sourceType,
    String? sourcePackage,
    String detectionCode = 'manual',
    double? latitude,
    double? longitude,
    int? occurredAtMs,
  }) async {
    final db = await _database();
    final nowMs = occurredAtMs ?? DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final songId = await _ensureSong(
        txn,
        title: title,
        artist: artist,
        albumName: albumName,
        durationSec: durationSec,
        lyrics: lyrics,
        artworkUrl: artworkUrl,
        artistInsightJson: null,
        metadataJson: null,
        nowMs: nowMs,
      );

      final detectionTypeId = await _ensureDetectionType(txn, detectionCode);
      await txn.insert(
        'deteccion',
        <String, Object?>{
          'id_cancion': songId,
          'id_tipo_deteccion': detectionTypeId,
          'fecha_hora': nowMs,
          'latitud': latitude,
          'longitud': longitude,
          'source_type': sourceType,
          'source_package': sourcePackage,
        },
      );
    });
  }

  Future<int> _ensureDetectionType(DatabaseExecutor db, String code) async {
    final normalized = _normalizeText(code);
    final existing = await db.query(
      'tipo_deteccion',
      columns: ['id_tipo_deteccion'],
      where: 'codigo = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return _toNullableInt(existing.first['id_tipo_deteccion']) ?? 0;
    }

    final insertedId = await db.insert(
      'tipo_deteccion',
      <String, Object?>{
        'codigo': normalized,
        'descripcion': normalized,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (insertedId > 0) {
      return insertedId;
    }

    final fallback = await db.query(
      'tipo_deteccion',
      columns: ['id_tipo_deteccion'],
      where: 'codigo = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    return fallback.isNotEmpty ? (_toNullableInt(fallback.first['id_tipo_deteccion']) ?? 0) : 0;
  }

  Future<List<CatchemSongSummary>> listCatchemSongs({
    int? limit,
    int? offset,
  }) async {
    final db = await _database();
    final sql = StringBuffer('''
      SELECT
        c.id_cancion,
        c.titulo,
        a.nombre AS artista,
        al.nombre AS album_name,
        c.lyrics,
        c.artwork_url,
        COALESCE((SELECT COUNT(*) FROM reproduccion r WHERE r.id_cancion = c.id_cancion), 0) AS listens,
        COALESCE((SELECT COUNT(*) FROM deteccion d WHERE d.id_cancion = c.id_cancion), 0) AS captures,
        COALESCE(
          (SELECT MIN(d.fecha_hora) FROM deteccion d WHERE d.id_cancion = c.id_cancion),
          (SELECT MIN(r.fecha_hora) FROM reproduccion r WHERE r.id_cancion = c.id_cancion),
          c.created_at
        ) AS first_seen,
        COALESCE(
          (SELECT MAX(r.fecha_hora) FROM reproduccion r WHERE r.id_cancion = c.id_cancion),
          (SELECT MAX(d.fecha_hora) FROM deteccion d WHERE d.id_cancion = c.id_cancion),
          c.updated_at
        ) AS last_seen,
        COALESCE(
          (SELECT r.source_type FROM reproduccion r WHERE r.id_cancion = c.id_cancion ORDER BY r.fecha_hora DESC LIMIT 1),
          (SELECT d.source_type FROM deteccion d WHERE d.id_cancion = c.id_cancion ORDER BY d.fecha_hora DESC LIMIT 1),
          ''
        ) AS source_type,
        (SELECT r.source_package FROM reproduccion r WHERE r.id_cancion = c.id_cancion ORDER BY r.fecha_hora DESC LIMIT 1) AS source_package,
        COALESCE(
          (SELECT td.codigo
           FROM deteccion d
           INNER JOIN tipo_deteccion td ON td.id_tipo_deteccion = d.id_tipo_deteccion
           WHERE d.id_cancion = c.id_cancion
           ORDER BY d.fecha_hora DESC
           LIMIT 1),
          'automatic'
        ) AS last_capture_mode,
        (SELECT d.latitud FROM deteccion d WHERE d.id_cancion = c.id_cancion ORDER BY d.fecha_hora DESC LIMIT 1) AS latitud,
        (SELECT d.longitud FROM deteccion d WHERE d.id_cancion = c.id_cancion ORDER BY d.fecha_hora DESC LIMIT 1) AS longitud
      FROM cancion c
      INNER JOIN artista a ON a.id_artista = c.id_artista
      LEFT JOIN album al ON al.id_album = c.id_album
      WHERE
        EXISTS (SELECT 1 FROM reproduccion r WHERE r.id_cancion = c.id_cancion)
        OR EXISTS (SELECT 1 FROM deteccion d WHERE d.id_cancion = c.id_cancion)
      ORDER BY last_seen DESC
    ''');

    final args = <Object?>[];
    if (limit != null && limit > 0) {
      sql.write(' LIMIT ?');
      args.add(limit);
      if (offset != null && offset > 0) {
        sql.write(' OFFSET ?');
        args.add(offset);
      }
    }

    debugPrint('[MAP_QUERY] listCatchemSongs.sql=${sql.toString()}');
    debugPrint('[MAP_QUERY] listCatchemSongs.args=$args');

    final rows = await db.rawQuery(sql.toString(), args);
    debugPrint('[MAP_QUERY] listCatchemSongs.rows=${rows.length}');

    final summaries = <CatchemSongSummary>[];
    for (final row in rows) {
      final title = (row['titulo'] ?? '').toString();
      final artist = (row['artista'] ?? '').toString();
        final albumName = (row['album_name'] ?? '').toString().trim().isEmpty
          ? null
          : (row['album_name'] ?? '').toString().trim();
        debugPrint('[MAP_QUERY] relation song="$title" artist="$artist" album="${albumName ?? ''}"');
      final history = await listCaptureHistoryForSong(title: title, artist: artist);

      summaries.add(
        CatchemSongSummary(
          title: title,
          artist: artist,
          albumName: albumName,
          lyrics: (row['lyrics'] ?? '').toString(),
          artworkUrl: (row['artwork_url'] as String?)?.trim().isEmpty == true
              ? null
              : row['artwork_url'] as String?,
          listenCount: _toNullableInt(row['listens']) ?? 0,
          captureCount: _toNullableInt(row['captures']) ?? 0,
          firstSeenAtMs: _toNullableInt(row['first_seen']) ?? 0,
          lastSeenAtMs: _toNullableInt(row['last_seen']) ?? 0,
          sourceType: (row['source_type'] ?? '').toString(),
          sourcePackage: (row['source_package'] ?? '').toString().trim().isEmpty
              ? null
              : (row['source_package'] ?? '').toString(),
          lastCaptureMode: (row['last_capture_mode'] ?? 'automatic').toString(),
          latitude: (row['latitud'] as num?)?.toDouble(),
          longitude: (row['longitud'] as num?)?.toDouble(),
          captureHistory: history,
        ),
      );
    }

    return summaries;
  }

  Future<List<CatchemCaptureEvent>> listCaptureHistoryForSong({
    required String title,
    required String artist,
  }) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);
    final rows = await db.rawQuery(
      '''
      SELECT d.fecha_hora, td.codigo
      FROM deteccion d
      INNER JOIN cancion c ON c.id_cancion = d.id_cancion
      INNER JOIN tipo_deteccion td ON td.id_tipo_deteccion = d.id_tipo_deteccion
      WHERE c.song_key = ?
      ORDER BY d.fecha_hora ASC
      ''',
      [key],
    );

    return rows
        .map(
          (row) => CatchemCaptureEvent(
            capturedAtMs: _toNullableInt(row['fecha_hora']) ?? 0,
            captureMode: (row['codigo'] ?? 'automatic').toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<CatchemMapPointSummary>> listCatchemMapPoints() async {
    final db = await _database();
    final rows = await db.rawQuery(
      '''
      SELECT
        d.fecha_hora,
        d.latitud,
        d.longitud,
        d.source_type,
        d.source_package,
        c.titulo,
        a.nombre AS artista,
        al.nombre AS album_name,
        c.artwork_url
      FROM deteccion d
      INNER JOIN cancion c ON c.id_cancion = d.id_cancion
      INNER JOIN artista a ON a.id_artista = c.id_artista
      LEFT JOIN album al ON al.id_album = c.id_album
      WHERE d.latitud IS NOT NULL AND d.longitud IS NOT NULL
      ORDER BY d.fecha_hora DESC
      ''',
    );

    return rows.map((row) {
      return CatchemMapPointSummary(
        title: (row['titulo'] ?? '').toString(),
        artist: (row['artista'] ?? '').toString(),
        albumName: (row['album_name'] ?? '').toString().trim().isEmpty
            ? null
            : (row['album_name'] ?? '').toString().trim(),
        artworkUrl: (row['artwork_url'] as String?)?.trim().isEmpty == true
            ? null
            : row['artwork_url'] as String?,
        detectedAtMs: _toNullableInt(row['fecha_hora']) ?? 0,
        latitude: (row['latitud'] as num?)?.toDouble() ?? 0,
        longitude: (row['longitud'] as num?)?.toDouble() ?? 0,
        sourceType: (row['source_type'] ?? '').toString(),
        sourcePackage: (row['source_package'] ?? '').toString().trim().isEmpty
            ? null
            : (row['source_package'] ?? '').toString(),
      );
    }).toList(growable: false);
  }

  Future<List<PlaybackHistoryEvent>> listPlaybackHistoryForSong({
    required String title,
    required String artist,
  }) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);
    final rows = await db.rawQuery(
      '''
      SELECT r.fecha_hora, r.source_type, r.source_package, d.latitud, d.longitud
      FROM reproduccion r
      INNER JOIN cancion c ON c.id_cancion = r.id_cancion
      LEFT JOIN deteccion d ON d.id_deteccion = r.id_deteccion
      WHERE c.song_key = ?
      ORDER BY r.fecha_hora DESC
      ''',
      [key],
    );

    return rows
        .map(
          (row) => PlaybackHistoryEvent(
            playedAtMs: _toNullableInt(row['fecha_hora']) ?? 0,
            sourceType: (row['source_type'] ?? '').toString(),
            sourcePackage: (row['source_package'] ?? '').toString().trim().isEmpty
                ? null
                : (row['source_package'] ?? '').toString(),
            latitude: (row['latitud'] as num?)?.toDouble(),
            longitude: (row['longitud'] as num?)?.toDouble(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> clearSongActivity({
    required String title,
    required String artist,
  }) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cancion',
        columns: ['id_cancion'],
        where: 'song_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final songId = _toNullableInt(rows.first['id_cancion']);
      if (songId == null) {
        return;
      }

      await txn.delete('reproduccion', where: 'id_cancion = ?', whereArgs: [songId]);
      await txn.delete('deteccion', where: 'id_cancion = ?', whereArgs: [songId]);
    });
  }

  Future<void> upsertScreenshot({
    required String uri,
    required int fechaHoraMs,
    String? displayName,
    String? title,
    String? artist,
    String? sourcePackage,
  }) async {
    final db = await _database();
    final normalizedUri = uri.trim();
    if (normalizedUri.isEmpty) {
      return;
    }

    await db.transaction((txn) async {
      int? songId;
      final normalizedTitle = (title ?? '').trim();
      final normalizedArtist = (artist ?? '').trim();
      if (normalizedTitle.isNotEmpty && normalizedArtist.isNotEmpty) {
        songId = await _ensureSong(
          txn,
          title: normalizedTitle,
          artist: normalizedArtist,
          albumName: null,
          durationSec: null,
          lyrics: null,
          artworkUrl: null,
          artistInsightJson: null,
          metadataJson: null,
          nowMs: fechaHoraMs,
        );
      }

      await txn.insert(
        'screenshot',
        <String, Object?>{
          'id_cancion': songId,
          'uri': normalizedUri,
          'display_name': (displayName ?? '').trim(),
          'title': normalizedTitle,
          'artist': normalizedArtist,
          'source_package': (sourcePackage ?? '').trim(),
          'fecha_hora': fechaHoraMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Map<String, dynamic> _artistInsightToMap(ArtistInsight insight) {
    return {
      'artistName': insight.artistName,
      'primaryGenre': insight.primaryGenre,
      'country': insight.country,
      'shortBio': insight.shortBio,
      'popularReleases': insight.popularReleases,
      'firstReleaseYear': insight.firstReleaseYear,
      'latestReleaseYear': insight.latestReleaseYear,
    };
  }

  ArtistInsight? _artistInsightFromJson(String? raw) {
    final map = _mapFromJson(raw);
    if (map == null) {
      return null;
    }

    final releasesRaw = map['popularReleases'];
    final releases = <String>[];
    if (releasesRaw is List) {
      for (final item in releasesRaw) {
        releases.add(item.toString());
      }
    }

    return ArtistInsight(
      artistName: (map['artistName'] ?? '').toString(),
      primaryGenre: (map['primaryGenre'] ?? '').toString(),
      country: (map['country'] ?? '').toString(),
      shortBio: (map['shortBio'] ?? '').toString(),
      popularReleases: releases,
      firstReleaseYear: _toNullableInt(map['firstReleaseYear']),
      latestReleaseYear: _toNullableInt(map['latestReleaseYear']),
    );
  }

  Map<String, dynamic>? _mapFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}
