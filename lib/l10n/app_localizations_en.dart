// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Lyric Notifier';

  @override
  String get nowPlayingDefaultTitle => 'Now Playing';

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get artistLabel => 'Artist';

  @override
  String get motivationStartPlayback =>
      'Play your favorite song and let’s start 🎵';

  @override
  String get permissionNeededTitle => 'Permission required';

  @override
  String get permissionDialogMessage =>
      'SingSync needs notification access to detect the current song and automatically fetch lyrics.';

  @override
  String get notNow => 'Not now';

  @override
  String get goToPermissions => 'Go to permissions';

  @override
  String get enableNotificationsCard =>
      'Enable notification access to detect songs.';

  @override
  String get allow => 'Allow';

  @override
  String get accept => 'Accept';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get search => 'Search';

  @override
  String get configure => 'Configure';

  @override
  String get developerBy => 'Developer by: iozamudioa';

  @override
  String get githubLabel => 'Github:';

  @override
  String get privacyPolicyLabel => 'Privacy Policy:';

  @override
  String versionLabel(Object version) {
    return 'Version: $version';
  }

  @override
  String get poweredByLrclib => 'Powered by: LRCLIB';

  @override
  String get useArtworkBackground => 'Use artwork as background';

  @override
  String get useSolidBackgroundDescription =>
      'If disabled, a solid background based on theme is used.';

  @override
  String get infoTooltip => 'Information';

  @override
  String get switchToLightMode => 'Switch to light mode';

  @override
  String get switchToDarkMode => 'Switch to dark mode';

  @override
  String get openActivePlayer => 'Open active player';

  @override
  String get previous => 'Previous';

  @override
  String get playPause => 'Play/Pause';

  @override
  String get next => 'Next';

  @override
  String get searchManually => 'Search manually';

  @override
  String get noArtistDataYet => 'No more artist data available right now.';

  @override
  String genreLabel(Object genre) {
    return 'Genre: $genre';
  }

  @override
  String countryLabel(Object country) {
    return 'Country: $country';
  }

  @override
  String detectedPeriod(Object firstYear, Object latestYear) {
    return 'Detected period: $firstYear - $latestYear';
  }

  @override
  String get shortBioTitle => 'Short bio';

  @override
  String get popularReleases => 'Popular releases';

  @override
  String get back => 'Back';

  @override
  String get editSearch => 'Edit search';

  @override
  String get backToMatches => 'Back to matches';

  @override
  String get manualSearchTitle => 'Manual search';

  @override
  String get manualSearchDescription =>
      'Type a query to search matches on lrclib.';

  @override
  String get searchQueryLabel => 'Search (query)';

  @override
  String get searchQueryHint => 'e.g. clandestino shakira';

  @override
  String get searchLyrics => 'Search lyrics';

  @override
  String get noMatchesToChoose => 'No matches found to choose from.';

  @override
  String get copy => 'Copy';

  @override
  String get share => 'Share';

  @override
  String get saveToGallery => 'Save to gallery';

  @override
  String get associateToSong => 'Associate to song';

  @override
  String get shareSnapshot => 'Capture and share';

  @override
  String get snapshotReady => 'Image ready to share';

  @override
  String get snapshotSaved => 'Image saved';

  @override
  String get snapshotError => 'Could not generate image';

  @override
  String get snapshotActiveLine => 'Active line';

  @override
  String get snapshotVisibleVerse => 'Visible verse';

  @override
  String get snapshotNoLyrics => 'No lyrics available';

  @override
  String get snapshotGeneratedWithBrand => 'Generated with SingSync';

  @override
  String get snapshotLineSelectionTitle => 'Your lyric for the memory';

  @override
  String get lyricsCopied => 'Lyrics copied';

  @override
  String get lyricsAssociated => 'Lyrics associated to song';

  @override
  String get lyricsNotAssociated => 'Could not associate lyrics';

  @override
  String get favoriteAdded => 'Added to your favorites';

  @override
  String get favoriteRemoved => 'Removed from favorites';

  @override
  String get favoriteDeleted => 'Deleted from favorites';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get favoritesLibrary => 'Library';

  @override
  String get mySongsTitle => 'My songs';

  @override
  String get searchBySongOrArtist => 'Search by song or artist';

  @override
  String get noResults => 'No results';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get savedSnapshotsTitle => 'Cover Memories';

  @override
  String get noSavedSnapshotsYet => 'No saved images yet';

  @override
  String get delete => 'Delete';

  @override
  String get snapshotDeleted => 'Image deleted';

  @override
  String get spotifyLabel => 'Spotify';

  @override
  String get youtubeMusicLabel => 'YouTube Music';

  @override
  String get amazonMusicLabel => 'Amazon Music';

  @override
  String get appleMusicLabel => 'Apple Music';

  @override
  String get permissionMissingMessage =>
      'Enable notification access for this app and play a song to load lyrics.';

  @override
  String get waitingPlaybackMessage =>
      'Permission active. Start playing a song to detect now playing and load lyrics.';

  @override
  String get adDetectedMessage =>
      'Ad detected. Waiting for the next song change...';

  @override
  String get tuningLyricsMessage => 'Tuning lyrics ...';

  @override
  String get notFoundMessage => 'No lyrics were found for this song on lrclib.';

  @override
  String get searchLyricsDefaultPrompt =>
      'Type anything you want to search for lyrics.';

  @override
  String get listeningErrorArtist => 'Error listening to notifications';

  @override
  String get updatingLyrics => 'Updating lyrics on lrclib...';

  @override
  String get selectMatchToShowLyrics => 'Select a match to show lyrics.';

  @override
  String get noMatchesApiSearch => 'No matches found in /api/search.';

  @override
  String get manualSearchPrompt => 'Type a manual search to see matches.';

  @override
  String get completeSearchField => 'Complete the search field to continue.';

  @override
  String get searchingMatches => 'Searching matches on lrclib...';

  @override
  String get apiSearchUnavailable => 'Could not query /api/search right now.';

  @override
  String get retryingMatches => 'Retrying matches on lrclib...';

  @override
  String get lrclibUnavailable => 'Could not query lrclib right now.';

  @override
  String get todayLabel => 'Today';

  @override
  String get thisWeekLabel => 'This week';

  @override
  String get olderLabel => 'Older';

  @override
  String get sleepTimerMenuTitle => 'Sleep timer';

  @override
  String get appInfoMenuTitle => 'App info';

  @override
  String get sleepTimerCompleted => 'Sleep timer completed.';

  @override
  String get sleepTimerCanceled => 'Sleep timer canceled';

  @override
  String sleepTimerStatusIn(Object time) {
    return 'Stops in $time';
  }

  @override
  String sleepTimerStatusAfterSongs(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stops after # songs',
      one: 'Stops after # song',
    );
    return '$_temp0';
  }

  @override
  String get sleepTimerStatusNone => 'No sleep timer';

  @override
  String get sleepTimerSelectShutdownTime => 'Select shutdown time';

  @override
  String get sleepTimerCustomSongCountTitle => 'Number of songs';

  @override
  String get songsLabel => 'Songs';

  @override
  String get sleepTimerSectionByTime => 'Stop after hh:mm time';

  @override
  String get sleepTimerCustomTimeButton => 'h : mm ?';

  @override
  String get sleepTimerSectionBySongs => 'Stop after N songs';

  @override
  String get cancelSleepTimer => 'Cancel timer';

  @override
  String get sleepTimerActiveTitle => 'Sleep timer active';
}
