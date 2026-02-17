import 'package:flutter/services.dart';

import '../domain/artist_insight.dart';
import '../domain/music_metadata_search_port.dart';

class PlatformMusicMetadataSearchAdapter implements MusicMetadataSearchPort {
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.lyric_notifier/lyrics',
  );

  @override
  Future<String?> findArtworkUrl({
    required String title,
    required String artist,
  }) async {
    final response = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'fetchArtworkUrl',
      {
        'title': title,
        'artist': artist,
      },
    );

    final value = response?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  Future<ArtistInsight?> findArtistInsight({required String artist}) async {
    final response = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'fetchArtistInsight',
      {
        'artist': artist,
      },
    );

    if (response is! Map) {
      return null;
    }

    final artistName = (response['artistName'] ?? '').toString().trim();
    final primaryGenre = (response['primaryGenre'] ?? '').toString().trim();
    final country = (response['country'] ?? '').toString().trim();
    final shortBio = (response['shortBio'] ?? '').toString().trim();

    final releases = <String>[];
    final rawReleases = response['popularReleases'];
    if (rawReleases is List) {
      for (final item in rawReleases) {
        final text = item.toString().trim();
        if (text.isNotEmpty) {
          releases.add(text);
        }
      }
    }

    int? parseYear(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '');
    }

    final firstReleaseYear = parseYear(response['firstReleaseYear']);
    final latestReleaseYear = parseYear(response['latestReleaseYear']);

    final hasAnyInfo =
        artistName.isNotEmpty ||
        primaryGenre.isNotEmpty ||
        country.isNotEmpty ||
        shortBio.isNotEmpty ||
        releases.isNotEmpty ||
        firstReleaseYear != null ||
        latestReleaseYear != null;

    if (!hasAnyInfo) {
      return null;
    }

    return ArtistInsight(
      artistName: artistName,
      primaryGenre: primaryGenre,
      country: country,
      shortBio: shortBio,
      popularReleases: releases,
      firstReleaseYear: firstReleaseYear,
      latestReleaseYear: latestReleaseYear,
    );
  }
}
