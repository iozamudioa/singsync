class LyricsCandidate {
  const LyricsCandidate({
    required this.trackName,
    required this.artistName,
    required this.lyrics,
    this.albumName,
  });

  final String trackName;
  final String artistName;
  final String lyrics;
  final String? albumName;

  factory LyricsCandidate.fromMap(Map<dynamic, dynamic> map) {
    final track = (map['trackName'] ?? '').toString().trim();
    final artist = (map['artistName'] ?? '').toString().trim();
    final lyrics = (map['lyrics'] ?? '').toString();
    final album = (map['albumName'] ?? '').toString().trim();

    return LyricsCandidate(
      trackName: track,
      artistName: artist,
      lyrics: lyrics,
      albumName: album.isEmpty ? null : album,
    );
  }

  String get subtitle {
    if (albumName == null || albumName!.isEmpty) {
      return artistName;
    }
    return '$artistName · $albumName';
  }
}
