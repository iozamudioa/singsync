import 'dart:convert';

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

class LocalSongCacheRepository {
  static const int maxSongs = 20;

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'singsync_song_cache.db');

    _db = await openDatabase(
      fullPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE song_cache(
            cache_key TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            lyrics TEXT NOT NULL,
            artwork_url TEXT,
            artist_insight_json TEXT,
            metadata_json TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );

    return _db!;
  }

  String _cacheKey({required String title, required String artist}) {
    return '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
  }

  Future<CachedSong?> findSong({required String title, required String artist}) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);
    final rows = await db.query(
      'song_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawLyrics = (row['lyrics'] ?? '').toString().trim();
    return CachedSong(
      title: (row['title'] ?? '').toString(),
      artist: (row['artist'] ?? '').toString(),
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
    final rows = await db.query(
      'song_cache',
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawLyrics = (row['lyrics'] ?? '').toString().trim();
    return CachedSong(
      title: (row['title'] ?? '').toString(),
      artist: (row['artist'] ?? '').toString(),
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
    String? artworkUrl,
    ArtistInsight? artistInsight,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);

    await db.insert(
      'song_cache',
      {
        'cache_key': key,
        'title': title.trim(),
        'artist': artist.trim(),
        'lyrics': lyrics,
        'artwork_url': artworkUrl,
        'artist_insight_json': artistInsight == null ? null : jsonEncode(_artistInsightToMap(artistInsight)),
        'metadata_json': metadata == null ? null : jsonEncode(metadata),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _trimToLimit(db);
  }

  Future<void> attachArtistInsight({
    required String title,
    required String artist,
    required ArtistInsight insight,
  }) async {
    final db = await _database();
    final key = _cacheKey(title: title, artist: artist);

    await db.update(
      'song_cache',
      {
        'artist_insight_json': jsonEncode(_artistInsightToMap(insight)),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'cache_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> _trimToLimit(Database db) async {
    final rows = await db.query(
      'song_cache',
      columns: ['cache_key'],
      orderBy: 'updated_at DESC',
      limit: maxSongs,
    );

    final keepKeys = rows.map((row) => (row['cache_key'] ?? '').toString()).where((v) => v.isNotEmpty).toList();
    if (keepKeys.isEmpty) {
      return;
    }

    final placeholders = List.filled(keepKeys.length, '?').join(',');
    await db.delete(
      'song_cache',
      where: 'cache_key NOT IN ($placeholders)',
      whereArgs: keepKeys,
    );
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
