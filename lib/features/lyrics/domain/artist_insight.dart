class ArtistInsight {
  const ArtistInsight({
    required this.artistName,
    required this.primaryGenre,
    required this.country,
    required this.shortBio,
    required this.popularReleases,
    required this.firstReleaseYear,
    required this.latestReleaseYear,
  });

  final String artistName;
  final String primaryGenre;
  final String country;
  final String shortBio;
  final List<String> popularReleases;
  final int? firstReleaseYear;
  final int? latestReleaseYear;
}
