import 'artist_insight.dart';

abstract class MusicMetadataSearchPort {
  Future<String?> findArtworkUrl({
    required String title,
    required String artist,
  });

  Future<ArtistInsight?> findArtistInsight({
    required String artist,
  });
}
