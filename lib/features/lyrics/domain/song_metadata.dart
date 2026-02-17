class SongMetadata {
  const SongMetadata({
    this.trackName,
    this.artistName,
    this.albumName,
    this.releaseYear,
    this.durationSec,
    this.instrumental,
    this.artworkUrl,
  });

  final String? trackName;
  final String? artistName;
  final String? albumName;
  final int? releaseYear;
  final double? durationSec;
  final bool? instrumental;
  final String? artworkUrl;

  factory SongMetadata.fromMap(Map<dynamic, dynamic> map) {
    double? duration;
    final dynamic durationRaw = map['durationSec'];
    if (durationRaw is num) {
      duration = durationRaw.toDouble();
    }

    int? year;
    final dynamic yearRaw = map['releaseYear'];
    if (yearRaw is int) {
      year = yearRaw;
    } else if (yearRaw is num) {
      year = yearRaw.toInt();
    }

    bool? instrumental;
    final dynamic instrumentalRaw = map['instrumental'];
    if (instrumentalRaw is bool) {
      instrumental = instrumentalRaw;
    }

    return SongMetadata(
      trackName: _asNonEmptyString(map['trackName']),
      artistName: _asNonEmptyString(map['artistName']),
      albumName: _asNonEmptyString(map['albumName']),
      releaseYear: year,
      durationSec: duration,
      instrumental: instrumental,
      artworkUrl: _asNonEmptyString(map['artworkUrl']),
    );
  }

  SongMetadata copyWith({
    String? trackName,
    String? artistName,
    String? albumName,
    int? releaseYear,
    double? durationSec,
    bool? instrumental,
    String? artworkUrl,
  }) {
    return SongMetadata(
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      releaseYear: releaseYear ?? this.releaseYear,
      durationSec: durationSec ?? this.durationSec,
      instrumental: instrumental ?? this.instrumental,
      artworkUrl: artworkUrl ?? this.artworkUrl,
    );
  }

  static String? _asNonEmptyString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
