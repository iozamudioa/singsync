class LyricsLookupResult {
  const LyricsLookupResult({
    required this.lyrics,
    required this.debugSteps,
    this.metadata,
  });

  final String lyrics;
  final List<String> debugSteps;
  final Map<String, dynamic>? metadata;
}
