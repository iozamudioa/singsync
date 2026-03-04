import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';

import '../data/local_song_cache_repository.dart';
import '../data/platform_lyrics_gateway.dart';
import '../domain/artist_insight.dart';
import '../domain/lyrics_candidate.dart';
import '../domain/lyrics_lookup_result.dart';
import '../domain/music_metadata_search_port.dart';

class LyricsController extends ChangeNotifier {
  LyricsController({
    required PlatformLyricsGateway gateway,
    required MusicMetadataSearchPort metadataSearchPort,
    required LocalSongCacheRepository songCache,
  })  : _gateway = gateway,
      _metadataSearchPort = metadataSearchPort,
      _songCache = songCache {
    final l10n = _l10n;
    songTitle = l10n.nowPlayingDefaultTitle;
    artistName = l10n.motivationStartPlayback;
    nowPlayingLyrics = l10n.permissionMissingMessage;
    searchLyrics = l10n.searchLyricsDefaultPrompt;
  }

  final PlatformLyricsGateway _gateway;
  final MusicMetadataSearchPort _metadataSearchPort;
  final LocalSongCacheRepository _songCache;
  StreamSubscription<dynamic>? _subscription;
  Timer? _playbackPollTimer;
  bool _disposed = false;

  AppLocalizations get _l10n => lookupAppLocalizations(_effectiveLocale());

  Locale _effectiveLocale() {
    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return languageCode == 'es' ? const Locale('es') : const Locale('en');
  }

  String get _notFoundMessage => _l10n.notFoundMessage;
  String get _permissionMissingMessage => _l10n.permissionMissingMessage;
  String get _waitingPlaybackMessage => _l10n.waitingPlaybackMessage;
  String get _adDetectedMessage => _l10n.adDetectedMessage;
  String get _tuningLyricsMessage => _l10n.tuningLyricsMessage;
  static const int _autoRetryAttempts = 5;
  static const Duration _autoRetryDelay = Duration(seconds: 2);
  static const List<String> knownMediaAppPackages = <String>[
    'com.spotify.music',
    'com.google.android.apps.youtube.music',
    'com.amazon.mp3',
    'com.apple.android.music',
  ];
  static const String _favoritesPrefKey = 'favorite_library_v1';
  static const String _catchemPrefKey = 'catchem_library_v1';

  String songTitle = 'Now Playing';
  String artistName = '';
  String? nowPlayingAlbumName;
  int? nowPlayingDurationSec;
  String nowPlayingSourceType = '';
  String? nowPlayingSourcePackage;
  String? preferredMediaAppPackage;
  Set<String> installedMediaAppPackages = const <String>{};
  String nowPlayingLyrics = '';
  String? nowPlayingArtworkUrl;
  bool hasNotificationListenerAccess = false;
  bool isLoadingNowPlayingLyrics = false;
  bool isAdLikeNowPlaying = false;
  int nowPlayingPlaybackPositionMs = 0;
  bool isNowPlayingPlaybackActive = false;
  bool hasActiveNowPlaying = false;
  int _noPlaybackStateMisses = 0;
  int _suppressNoPlaybackUntilEpochMs = 0;
  String? _lastAutoLookupKey;
  int _nowPlayingRequestId = 0;

  String searchQuery = '';
  String searchLyrics = '';
  String? searchArtworkUrl;
  List<LyricsCandidate> searchCandidates = const [];
  LyricsCandidate? _selectedSearchCandidate;
  bool isChoosingSearchCandidate = false;
  bool isViewingSearchChosenCandidate = false;
  bool isSearchingLyrics = false;
  bool isManualSearchMode = false;
  bool isManualSearchFormVisible = false;
  String? _artistInsightCacheKey;
  ArtistInsight? _artistInsightCacheValue;
  bool _artistInsightCacheReady = false;
  String? _artistInsightInFlightKey;
  Future<ArtistInsight?>? _artistInsightInFlight;
  List<FavoriteSongEntry> _favoriteLibrary = const <FavoriteSongEntry>[];
  List<CatchemSongEntry> _catchemLibrary = const <CatchemSongEntry>[];
  String? _lastNowPlayingSongKey;
  bool _hasPausedPlaybackForFavorite = false;
  String? _pausedPlaybackSourcePackageForFavorite;
  String? _pausedPlaybackPreferredPackageForFavorite;

  void start() {
    refreshNotificationPermissionStatus();
    unawaited(refreshInstalledMediaApps());
    unawaited(loadFavoriteLibrary());
    unawaited(loadCatchemLibrary());

    _subscription = _gateway.nowPlayingStream().listen(
      onNowPlayingEvent,
      onError: (Object error) {
        artistName = _l10n.listeningErrorArtist;
        nowPlayingLyrics = '$error';
        _notifySafely();
      },
    );

    loadCurrentNowPlayingOnStartup();
  }

  List<FavoriteSongEntry> get favoriteLibrary => List<FavoriteSongEntry>.unmodifiable(_favoriteLibrary);

  List<CatchemSongEntry> get catchemLibrary {
    final ranking = List<CatchemSongEntry>.from(_catchemLibrary);
    ranking.sort((a, b) {
      final byDetectCount = b.detectCount.compareTo(a.detectCount);
      if (byDetectCount != 0) {
        return byDetectCount;
      }
      return b.lastDetectedAtMs.compareTo(a.lastDetectedAtMs);
    });
    return List<CatchemSongEntry>.unmodifiable(ranking);
  }

  bool get canResumePausedPlaybackAfterFavorite {
    return _hasPausedPlaybackForFavorite && nowPlayingSourceType == 'favorite';
  }

  bool get isCurrentNowPlayingFavorite {
    final title = songTitle.trim();
    final artist = artistName.trim();
    if (title.isEmpty || artist.isEmpty || title == _l10n.nowPlayingDefaultTitle) {
      return false;
    }

    final key = _favoriteKey(title: title, artist: artist);
    return _favoriteLibrary.any((entry) => entry.key == key);
  }

  String _favoriteKey({required String title, required String artist}) {
    return '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
  }

  Future<void> loadFavoriteLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesPrefKey);
      if (raw == null || raw.trim().isEmpty) {
        _favoriteLibrary = const <FavoriteSongEntry>[];
        _notifySafely();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _favoriteLibrary = const <FavoriteSongEntry>[];
        _notifySafely();
        return;
      }

      final parsed = <FavoriteSongEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final entry = FavoriteSongEntry.fromJson(item);
          if (entry.title.trim().isNotEmpty && entry.artist.trim().isNotEmpty) {
            parsed.add(entry);
          }
          continue;
        }
        if (item is Map) {
          final normalized = <String, dynamic>{};
          for (final entry in item.entries) {
            normalized[entry.key.toString()] = entry.value;
          }
          final favorite = FavoriteSongEntry.fromJson(normalized);
          if (favorite.title.trim().isNotEmpty && favorite.artist.trim().isNotEmpty) {
            parsed.add(favorite);
          }
        }
      }

      _favoriteLibrary = parsed;
      _notifySafely();
    } catch (_) {
      _favoriteLibrary = const <FavoriteSongEntry>[];
      _notifySafely();
    }
  }

  Future<void> _persistFavoriteLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _favoriteLibrary.map((entry) => entry.toJson()).toList(growable: false);
    await prefs.setString(_favoritesPrefKey, jsonEncode(payload));
  }

  Future<void> loadCatchemLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_catchemPrefKey);
      if (raw == null || raw.trim().isEmpty) {
        _catchemLibrary = const <CatchemSongEntry>[];
        _notifySafely();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _catchemLibrary = const <CatchemSongEntry>[];
        _notifySafely();
        return;
      }

      final parsed = <CatchemSongEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final entry = CatchemSongEntry.fromJson(item);
          if (entry.title.trim().isNotEmpty && entry.artist.trim().isNotEmpty) {
            parsed.add(entry);
          }
          continue;
        }
        if (item is Map) {
          final normalized = <String, dynamic>{};
          for (final entry in item.entries) {
            normalized[entry.key.toString()] = entry.value;
          }
          final parsedEntry = CatchemSongEntry.fromJson(normalized);
          if (parsedEntry.title.trim().isNotEmpty && parsedEntry.artist.trim().isNotEmpty) {
            parsed.add(parsedEntry);
          }
        }
      }

      _catchemLibrary = parsed;
      _notifySafely();
    } catch (_) {
      _catchemLibrary = const <CatchemSongEntry>[];
      _notifySafely();
    }
  }

  Future<void> _persistCatchemLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _catchemLibrary.map((entry) => entry.toJson()).toList(growable: false);
    await prefs.setString(_catchemPrefKey, jsonEncode(payload));
  }

  Future<bool> removeCatchemEntry(CatchemSongEntry entry) async {
    final existingIndex = _catchemLibrary.indexWhere((item) => item.key == entry.key);
    if (existingIndex < 0) {
      return false;
    }
    final next = List<CatchemSongEntry>.from(_catchemLibrary)..removeAt(existingIndex);
    _catchemLibrary = next;
    await _persistCatchemLibrary();
    _notifySafely();
    return true;
  }

  Future<bool?> toggleCurrentFavorite() async {
    final title = songTitle.trim();
    final artist = artistName.trim();
    if (title.isEmpty || artist.isEmpty || title == _l10n.nowPlayingDefaultTitle) {
      return null;
    }

    final key = _favoriteKey(title: title, artist: artist);
    final existingIndex = _favoriteLibrary.indexWhere((entry) => entry.key == key);
    if (existingIndex >= 0) {
      final next = List<FavoriteSongEntry>.from(_favoriteLibrary)..removeAt(existingIndex);
      _favoriteLibrary = next;
      await _persistFavoriteLibrary();
      _notifySafely();
      return false;
    }

    final lyrics = _looksLikeUiStateMessage(nowPlayingLyrics) ? '' : nowPlayingLyrics;
    final favorite = FavoriteSongEntry(
      title: title,
      artist: artist,
      lyrics: lyrics,
      artworkUrl: nowPlayingArtworkUrl,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final next = <FavoriteSongEntry>[favorite, ..._favoriteLibrary]
        .fold<List<FavoriteSongEntry>>(<FavoriteSongEntry>[], (acc, item) {
      if (acc.any((entry) => entry.key == item.key)) {
        return acc;
      }
      acc.add(item);
      return acc;
    });
    _favoriteLibrary = next.take(250).toList(growable: false);
    await _persistFavoriteLibrary();
    await _upsertCatchemManualCapture(
      title: title,
      artist: artist,
      lyrics: lyrics,
      artworkUrl: nowPlayingArtworkUrl,
      sourcePackage: nowPlayingSourcePackage,
    );
    _notifySafely();
    return true;
  }

  Future<bool> removeFavoriteEntry(FavoriteSongEntry favorite) async {
    final existingIndex = _favoriteLibrary.indexWhere((entry) => entry.key == favorite.key);
    if (existingIndex < 0) {
      return false;
    }

    final next = List<FavoriteSongEntry>.from(_favoriteLibrary)..removeAt(existingIndex);
    _favoriteLibrary = next;
    await _persistFavoriteLibrary();
    _notifySafely();
    return true;
  }

  Future<void> showFavoriteInNowPlaying(FavoriteSongEntry favorite) async {
    final shouldPauseCurrentPlayback =
        hasActiveNowPlaying && isNowPlayingFromMediaPlayer && isNowPlayingPlaybackActive;

    if (shouldPauseCurrentPlayback) {
      final sourcePackageBeforePause = nowPlayingSourcePackage;
      final preferredPackageBeforePause = preferredMediaAppPackage;
      _armNoPlaybackGraceWindow();
      final didPause = await _gateway.mediaPlayPause(sourcePackage: sourcePackageBeforePause);

      if (didPause) {
        _hasPausedPlaybackForFavorite = true;
        _pausedPlaybackSourcePackageForFavorite = sourcePackageBeforePause;
        _pausedPlaybackPreferredPackageForFavorite = preferredPackageBeforePause;
      } else if (!_hasPausedPlaybackForFavorite) {
        _clearPausedPlaybackRestoreState();
      }
    }

    ++_nowPlayingRequestId;
    _lastAutoLookupKey = null;
    _stopPlaybackPolling();

    hasActiveNowPlaying = true;
    isNowPlayingPlaybackActive = false;
    nowPlayingPlaybackPositionMs = 0;
    isLoadingNowPlayingLyrics = false;
    isAdLikeNowPlaying = false;
    nowPlayingSourceType = 'favorite';
    nowPlayingSourcePackage = null;
    nowPlayingAlbumName = null;
    nowPlayingDurationSec = null;
    preferredMediaAppPackage = null;

    songTitle = favorite.title;
    artistName = favorite.artist;
    nowPlayingArtworkUrl = favorite.artworkUrl;
    nowPlayingLyrics = favorite.lyrics.trim().isEmpty ? _notFoundMessage : favorite.lyrics;

    isManualSearchMode = false;
    isManualSearchFormVisible = false;
    _notifySafely();
  }

  Future<void> showCatchemInNowPlaying(CatchemSongEntry catchem) async {
    final shouldPauseCurrentPlayback =
        hasActiveNowPlaying && isNowPlayingFromMediaPlayer && isNowPlayingPlaybackActive;

    if (shouldPauseCurrentPlayback) {
      final sourcePackageBeforePause = nowPlayingSourcePackage;
      final preferredPackageBeforePause = preferredMediaAppPackage;
      _armNoPlaybackGraceWindow();
      final didPause = await _gateway.mediaPlayPause(sourcePackage: sourcePackageBeforePause);

      if (didPause) {
        _hasPausedPlaybackForFavorite = true;
        _pausedPlaybackSourcePackageForFavorite = sourcePackageBeforePause;
        _pausedPlaybackPreferredPackageForFavorite = preferredPackageBeforePause;
      } else if (!_hasPausedPlaybackForFavorite) {
        _clearPausedPlaybackRestoreState();
      }
    }

    ++_nowPlayingRequestId;
    _lastAutoLookupKey = null;
    _stopPlaybackPolling();

    hasActiveNowPlaying = true;
    isNowPlayingPlaybackActive = false;
    nowPlayingPlaybackPositionMs = 0;
    isLoadingNowPlayingLyrics = false;
    isAdLikeNowPlaying = false;
    nowPlayingSourceType = 'catchem';
    nowPlayingSourcePackage = null;
    nowPlayingAlbumName = null;
    nowPlayingDurationSec = null;
    preferredMediaAppPackage = null;

    songTitle = catchem.title;
    artistName = catchem.artist;
    nowPlayingArtworkUrl = catchem.artworkUrl;
    nowPlayingLyrics = catchem.lyrics.trim().isEmpty ? _notFoundMessage : catchem.lyrics;

    isManualSearchMode = false;
    isManualSearchFormVisible = false;
    _notifySafely();
  }

  Future<void> _captureCatchemDetection({
    required String title,
    required String artist,
    required String? sourcePackage,
  }) async {
    final songKey = _favoriteKey(title: title, artist: artist);

    final position = await _tryGetLocation();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existingIndex = _catchemLibrary.indexWhere((entry) => entry.key == songKey);

    if (existingIndex >= 0) {
      final existing = _catchemLibrary[existingIndex];
      final history = <CatchemCaptureRecord>[
        ...existing.captureHistory,
        CatchemCaptureRecord(
          capturedAtMs: nowMs,
          captureMode: 'automatic',
        ),
      ];
      final updated = existing.copyWith(
        detectCount: history.length,
        lastDetectedAtMs: nowMs,
        sourcePackage: (sourcePackage ?? '').trim().isEmpty ? existing.sourcePackage : sourcePackage,
        latitude: position?.latitude ?? existing.latitude,
        longitude: position?.longitude ?? existing.longitude,
        artworkUrl: (nowPlayingArtworkUrl ?? '').trim().isEmpty ? existing.artworkUrl : nowPlayingArtworkUrl,
        captureMode: 'automatic',
        captureHistory: history,
      );
      final next = List<CatchemSongEntry>.from(_catchemLibrary);
      next[existingIndex] = updated;
      _catchemLibrary = next;
      await _persistCatchemLibrary();
      _notifySafely();
      return;
    }

    final entry = CatchemSongEntry(
      title: title,
      artist: artist,
      lyrics: '',
      artworkUrl: nowPlayingArtworkUrl,
      detectCount: 1,
      firstDetectedAtMs: nowMs,
      lastDetectedAtMs: nowMs,
      sourceType: nowPlayingSourceType,
      sourcePackage: sourcePackage,
      lyricsSource: '',
      captureMode: 'automatic',
      captureHistory: <CatchemCaptureRecord>[
        CatchemCaptureRecord(capturedAtMs: nowMs, captureMode: 'automatic'),
      ],
      latitude: position?.latitude,
      longitude: position?.longitude,
    );

    _catchemLibrary = <CatchemSongEntry>[entry, ..._catchemLibrary]
        .take(600)
        .toList(growable: false);
    await _persistCatchemLibrary();
    _notifySafely();
  }

  Future<void> _touchCatchemLastHeard({
    required String title,
    required String artist,
    required String sourceType,
    required String? sourcePackage,
  }) async {
    final songKey = _favoriteKey(title: title, artist: artist);
    final existingIndex = _catchemLibrary.indexWhere((entry) => entry.key == songKey);
    if (existingIndex < 0) {
      return;
    }

    final existing = _catchemLibrary[existingIndex];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      detectCount: existing.detectCount + 1,
      lastDetectedAtMs: nowMs,
      sourceType: sourceType,
      sourcePackage: (sourcePackage ?? '').trim().isEmpty ? existing.sourcePackage : sourcePackage,
      artworkUrl: (nowPlayingArtworkUrl ?? '').trim().isEmpty ? existing.artworkUrl : nowPlayingArtworkUrl,
    );

    final next = List<CatchemSongEntry>.from(_catchemLibrary);
    next[existingIndex] = updated;
    _catchemLibrary = next;
    await _persistCatchemLibrary();
    _notifySafely();
  }

  Future<void> resumePausedPlaybackAfterFavorite() async {
    if (!_hasPausedPlaybackForFavorite) {
      return;
    }

    final sourcePackage = _pausedPlaybackSourcePackageForFavorite;
    final preferredPackage = _pausedPlaybackPreferredPackageForFavorite;

    _armNoPlaybackGraceWindow();
    final resumed = await _gateway.mediaPlayPause(sourcePackage: sourcePackage);
    if (!resumed) {
      return;
    }

    if ((preferredPackage ?? '').trim().isNotEmpty) {
      preferredMediaAppPackage = preferredPackage;
    } else if ((sourcePackage ?? '').trim().isNotEmpty) {
      preferredMediaAppPackage = sourcePackage;
    }

    if ((sourcePackage ?? '').trim().isNotEmpty) {
      nowPlayingSourcePackage = sourcePackage;
    }

    nowPlayingSourceType = 'media_player';
    hasActiveNowPlaying = true;
    isNowPlayingPlaybackActive = true;
    _startPlaybackPolling();

    _clearPausedPlaybackRestoreState();
    _notifySafely();
    unawaited(_recoverNowPlayingAfterFavoriteResume());
  }

  Future<void> _recoverNowPlayingAfterFavoriteResume() async {
    for (var attempt = 0; attempt < 14; attempt++) {
      if (_disposed || !isNowPlayingFromMediaPlayer) {
        return;
      }

      await Future.delayed(Duration(milliseconds: 220 * (attempt + 1)));
      if (_disposed || !isNowPlayingFromMediaPlayer) {
        return;
      }

      final payload = await _gateway.getCurrentNowPlaying();
      if (_disposed) {
        return;
      }

      if (payload != null) {
        await onNowPlayingEvent(payload);
        return;
      }
    }
  }

  Future<void> loadCurrentNowPlayingOnStartup() async {
    try {
      final payload = await _gateway.getCurrentNowPlaying();
      if (payload != null) {
        await onNowPlayingEvent(payload);
      } else {
        await _applyNoPlaybackState();
      }
    } catch (error) {
      debugPrint('[NOW_PLAYING] startup load error=$error');
    }
  }

  Future<void> refreshAll() async {
    await refreshNotificationPermissionStatus();
    await refreshInstalledMediaApps();
    await loadCurrentNowPlayingOnStartup();

    final nowTitle = songTitle.trim();
    final nowArtist = artistName.trim();
    if (hasActiveNowPlaying &&
      nowTitle.isNotEmpty &&
      nowArtist.isNotEmpty &&
      nowTitle != _l10n.nowPlayingDefaultTitle) {
      final requestId = ++_nowPlayingRequestId;
      isLoadingNowPlayingLyrics = true;
      nowPlayingLyrics = _tuningLyricsMessage;
      _notifySafely();

      final normalizedTitle = _normalizeTitleForAutoSearch(nowTitle);
      final result = await fetchLyrics(
        title: normalizedTitle,
        artist: nowArtist,
        albumName: nowPlayingAlbumName,
        durationSec: nowPlayingDurationSec,
        preferSynced: isNowPlayingFromMediaPlayer,
      );
      final artworkUrl = await _metadataSearchPort.findArtworkUrl(
        title: nowTitle,
        artist: nowArtist,
      );
      if (_disposed || requestId != _nowPlayingRequestId) {
        return;
      }

      isLoadingNowPlayingLyrics = false;
      nowPlayingLyrics = _sanitizeLyricsText(result.lyrics);
      nowPlayingArtworkUrl = artworkUrl;
      _notifySafely();
    }

    final manualQuery = searchQuery.trim();
    if (manualQuery.isEmpty) {
      return;
    }

    isSearchingLyrics = true;
    searchLyrics = _l10n.updatingLyrics;
    _resetSearchCandidates();
    _notifySafely();

    final candidates = await _gateway.searchLyricsCandidates(query: manualQuery);
    if (_disposed) {
      return;
    }

    isSearchingLyrics = false;
    searchCandidates = candidates;
    isChoosingSearchCandidate = candidates.isNotEmpty;
    isViewingSearchChosenCandidate = false;
    isManualSearchFormVisible = candidates.isEmpty;
    searchLyrics = candidates.isNotEmpty
      ? _l10n.selectMatchToShowLyrics
      : _l10n.noMatchesApiSearch;
    _notifySafely();
  }

  Future<void> refreshNotificationPermissionStatus() async {
    try {
      final enabled = await _gateway.isNotificationListenerEnabled();
      if (_disposed) {
        return;
      }
      hasNotificationListenerAccess = enabled;
      _applyIdleNowPlayingMessageByPermission(hasPermission: enabled);
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }
      hasNotificationListenerAccess = false;
      _applyIdleNowPlayingMessageByPermission(hasPermission: false);
      _notifySafely();
    }
  }

  Future<void> refreshInstalledMediaApps() async {
    try {
      final installed = await _gateway.getInstalledMediaApps(
        packages: knownMediaAppPackages,
      );
      if (_disposed) {
        return;
      }

      installedMediaAppPackages = installed;
      if (preferredMediaAppPackage != null &&
          preferredMediaAppPackage!.isNotEmpty &&
          !installed.contains(preferredMediaAppPackage)) {
        preferredMediaAppPackage = null;
      }
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }
      installedMediaAppPackages = const <String>{};
      _notifySafely();
    }
  }

  void _applyIdleNowPlayingMessageByPermission({required bool hasPermission}) {
    if (hasActiveNowPlaying || isLoadingNowPlayingLyrics) {
      return;
    }

    final nextMessage = hasPermission ? _waitingPlaybackMessage : _permissionMissingMessage;
    if (nowPlayingLyrics == nextMessage) {
      return;
    }

    final canReplaceCurrent =
        _looksLikeUiStateMessage(nowPlayingLyrics) ||
        nowPlayingLyrics.trim().isEmpty ||
        nowPlayingLyrics == _permissionMissingMessage ||
        nowPlayingLyrics == _waitingPlaybackMessage;

    if (canReplaceCurrent) {
      nowPlayingLyrics = nextMessage;
    }
  }

  Future<void> _applyNoPlaybackState() async {
    ++_nowPlayingRequestId;
    _lastAutoLookupKey = null;
    _clearPausedPlaybackRestoreState();
    hasActiveNowPlaying = false;
    _stopPlaybackPolling();
    isNowPlayingPlaybackActive = false;
    nowPlayingPlaybackPositionMs = 0;
    isLoadingNowPlayingLyrics = false;
    isAdLikeNowPlaying = false;
    nowPlayingSourceType = '';
    nowPlayingSourcePackage = null;
    nowPlayingAlbumName = null;
    nowPlayingDurationSec = null;
    songTitle = _l10n.nowPlayingDefaultTitle;
    artistName = _l10n.motivationStartPlayback;
    nowPlayingArtworkUrl = null;
    isManualSearchMode = false;
    isManualSearchFormVisible = false;

    nowPlayingLyrics = hasNotificationListenerAccess
      ? _waitingPlaybackMessage
      : _permissionMissingMessage;

    _notifySafely();
  }

  Future<void> openNotificationListenerSettings() async {
    await _gateway.openNotificationListenerSettings();
  }

  void onNowPlayingLyricsTap() {
    if (!hasNotificationListenerAccess) {
      unawaited(openNotificationListenerSettings());
      return;
    }

    unawaited(retryNowPlayingLyricsIfNeeded());
  }

  void updateSearchQuery(String value) {
    searchQuery = value;
  }

  void prefillManualSearchFromNowPlaying() {
    final title = songTitle.trim();

    if (title.isEmpty || title == _l10n.nowPlayingDefaultTitle) {
      return;
    }

    searchQuery = title;
    _notifySafely();
  }

  Future<void> startManualCandidatesFromNowPlaying() async {
    prefillManualSearchFromNowPlaying();

    isManualSearchMode = true;
    isManualSearchFormVisible = true;
    isSearchingLyrics = false;
    searchArtworkUrl = nowPlayingArtworkUrl;
    _resetSearchCandidates();
    searchLyrics = _l10n.manualSearchPrompt;
    _notifySafely();
  }

  void exitManualSearchMode() {
    isManualSearchMode = false;
    isManualSearchFormVisible = false;
    _notifySafely();
  }

  void showManualSearchForm() {
    isManualSearchMode = true;
    isManualSearchFormVisible = true;
    _notifySafely();
  }

  bool get canShowManualSearchButton {
    if (isManualSearchMode) {
      return false;
    }

    if (isLoadingNowPlayingLyrics) {
      return false;
    }

    final hasSong =
      songTitle.trim().isNotEmpty && songTitle.trim() != _l10n.nowPlayingDefaultTitle;
    if (!hasSong) {
      return false;
    }

    final message = nowPlayingLyrics.trim().toLowerCase();
    final notFoundLike = message.contains('no se encontró letra') ||
      message.contains('no se encontro letra') ||
      message.contains('no fue posible consultar') ||
      message.contains('no lyrics were found') ||
      message.contains('could not query');

    return notFoundLike || _isRetryableMessage(nowPlayingLyrics);
  }

  bool get isNowPlayingFromMediaPlayer => nowPlayingSourceType == 'media_player';

  Future<void> openActivePlayer() async {
    final selectedPackage = preferredMediaAppPackage;
    final hasDetectedSong = hasActiveNowPlaying &&
        songTitle.trim().isNotEmpty &&
      songTitle.trim() != _l10n.nowPlayingDefaultTitle;
    final shouldSearchInSelected = hasDetectedSong && nowPlayingSourceType == 'pixel_now_playing';
    final query = shouldSearchInSelected
        ? '${songTitle.trim()} ${artistName.trim()}'.trim()
        : null;

    await _gateway.openActivePlayer(
      sourcePackage: nowPlayingSourcePackage,
      selectedPackage: selectedPackage,
      searchQuery: query,
    );
  }

  void setPreferredMediaAppPackage(String? packageName) {
    final normalized = packageName?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    preferredMediaAppPackage = normalized;
    _notifySafely();
  }

  Future<void> mediaPrevious() async {
    _armNoPlaybackGraceWindow();
    final success = await _gateway.mediaPrevious(sourcePackage: nowPlayingSourcePackage);
    if (success) {
      unawaited(_syncNowPlayingSnapshotAfterTransport());
    }
  }

  Future<void> mediaPlayPause() async {
    _armNoPlaybackGraceWindow();
    await _gateway.mediaPlayPause(sourcePackage: nowPlayingSourcePackage);
  }

  Future<void> mediaNext() async {
    _armNoPlaybackGraceWindow();
    final success = await _gateway.mediaNext(sourcePackage: nowPlayingSourcePackage);
    if (success) {
      unawaited(_syncNowPlayingSnapshotAfterTransport());
    }
  }

  Future<void> _syncNowPlayingSnapshotAfterTransport() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (_disposed || !isNowPlayingFromMediaPlayer) {
        return;
      }

      await Future.delayed(Duration(milliseconds: 220 * (attempt + 1)));
      if (_disposed) {
        return;
      }

      final payload = await _gateway.getCurrentNowPlaying();
      if (_disposed || payload == null) {
        continue;
      }

      await onNowPlayingEvent(payload);
      return;
    }
  }

  void _armNoPlaybackGraceWindow([Duration duration = const Duration(seconds: 4)]) {
    _suppressNoPlaybackUntilEpochMs =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    _noPlaybackStateMisses = 0;
  }

  Future<void> seekNowPlayingTo(int positionMs) async {
    if (!isNowPlayingFromMediaPlayer) {
      return;
    }

    if (positionMs < 0) {
      return;
    }

    final success = await _gateway.mediaSeekTo(
      sourcePackage: nowPlayingSourcePackage,
      positionMs: positionMs,
    );
    if (!success || _disposed) {
      return;
    }

    nowPlayingPlaybackPositionMs = positionMs;
    _notifySafely();
  }

  Future<void> onNowPlayingEvent(dynamic event) async {
    if (event is! Map) {
      return;
    }

    final title = (event['title'] ?? '').toString().trim();
    final artist = (event['artist'] ?? '').toString().trim();
    final sourceType = (event['sourceType'] ?? '').toString().trim();
    final sourcePackageRaw = (event['sourcePackage'] ?? '').toString().trim();
    final sourcePackage = sourcePackageRaw.isEmpty ? null : sourcePackageRaw;
    final albumNameRaw = (event['albumName'] ?? '').toString().trim();
    final albumName = albumNameRaw.isEmpty ? null : albumNameRaw;
    final durationSec = _parsePositiveInt(event['durationSec']);
    final artworkFromEventRaw = (event['artworkUrl'] ?? '').toString().trim();
    final artworkFromEvent = artworkFromEventRaw.isEmpty ? null : artworkFromEventRaw;

    debugPrint('[NOW_PLAYING] title="$title" artist="$artist"');

    if (title.isEmpty || artist.isEmpty) {
      return;
    }

    final eventKey =
      '$title|$artist|${albumName ?? ''}|${durationSec ?? 0}|$sourceType|${sourcePackage ?? ''}';
    if (isLoadingNowPlayingLyrics && _lastAutoLookupKey == eventKey) {
      return;
    }
    _lastAutoLookupKey = eventKey;
    final requestId = ++_nowPlayingRequestId;
    _clearPausedPlaybackRestoreState();
    hasActiveNowPlaying = true;

    isManualSearchMode = false;
    isManualSearchFormVisible = false;

    songTitle = title;
    artistName = artist;
    nowPlayingAlbumName = albumName;
    nowPlayingDurationSec = durationSec;
    nowPlayingSourceType = sourceType;
    nowPlayingSourcePackage = sourcePackage;
    if (sourcePackage != null && sourcePackage.isNotEmpty) {
      preferredMediaAppPackage = sourcePackage;
    }
    if (isNowPlayingFromMediaPlayer) {
      _startPlaybackPolling();
    } else {
      _stopPlaybackPolling();
      nowPlayingPlaybackPositionMs = 0;
      isNowPlayingPlaybackActive = false;
    }

    final songKey = _favoriteKey(title: title, artist: artist);
    final songChanged = _lastNowPlayingSongKey != songKey;
    _lastNowPlayingSongKey = songKey;

    if (songChanged) {
      if (sourceType == 'pixel_now_playing') {
        unawaited(
          _captureCatchemDetection(
            title: title,
            artist: artist,
            sourcePackage: sourcePackage,
          ),
        );
      } else if (sourceType == 'media_player') {
        unawaited(
          _touchCatchemLastHeard(
            title: title,
            artist: artist,
            sourceType: sourceType,
            sourcePackage: sourcePackage,
          ),
        );
      }
    }

    final isAdLikeTrack = _looksLikeAdOrAnnouncement(
      title: title,
      artist: artist,
    );

    if (isAdLikeTrack) {
      isLoadingNowPlayingLyrics = false;
      isAdLikeNowPlaying = true;
      nowPlayingLyrics = _adDetectedMessage;
      if (artworkFromEvent != null && artworkFromEvent.isNotEmpty) {
        nowPlayingArtworkUrl = artworkFromEvent;
      }
      _notifySafely();
      return;
    }

    isLoadingNowPlayingLyrics = true;
    isAdLikeNowPlaying = false;
    nowPlayingLyrics = _tuningLyricsMessage;
    if (artworkFromEvent != null && artworkFromEvent.isNotEmpty) {
      nowPlayingArtworkUrl = artworkFromEvent;
    }
    _notifySafely();

    unawaited(
      _resolveAndApplyNowPlayingArtwork(
        requestId: requestId,
        title: title,
        artist: artist,
        sourceType: sourceType,
        artworkFromEvent: artworkFromEvent,
      ),
    );

    unawaited(
      _resolveAndApplyNowPlayingLyrics(
        requestId: requestId,
        title: title,
        artist: artist,
        albumName: albumName,
        durationSec: durationSec,
        sourcePackage: sourcePackage,
        sourceType: sourceType,
      ),
    );
  }

  Future<void> _resolveAndApplyNowPlayingLyrics({
    required int requestId,
    required String title,
    required String artist,
    required String? albumName,
    required int? durationSec,
    required String? sourcePackage,
    required String sourceType,
  }) async {
    final cachedSong = await _songCache.findSong(title: title, artist: artist);
    if (_disposed || requestId != _nowPlayingRequestId) {
      return;
    }

    final preferSynced = sourceType == 'media_player';
    final cachedVariantLyrics = _pickLyricsVariantFromCache(
      song: cachedSong,
      preferSynced: preferSynced,
    );

    final shouldForceSyncedLookup =
        sourceType == 'media_player' &&
        cachedVariantLyrics.isNotEmpty &&
      !_looksLikeSyncedLyrics(cachedVariantLyrics);

    if (cachedSong != null && cachedVariantLyrics.isNotEmpty && !shouldForceSyncedLookup) {
      isLoadingNowPlayingLyrics = false;
      nowPlayingLyrics = cachedVariantLyrics;
      nowPlayingArtworkUrl = cachedSong.artworkUrl ?? nowPlayingArtworkUrl;
      await _upsertCatchemLyricsSnapshot(
        title: title,
        artist: artist,
        lyrics: _sanitizeLyricsText(cachedVariantLyrics),
        lyricsSource: 'cache_local',
      );
      _applyArtistInsightCache(
        songTitle: title,
        artist: artist,
        insight: cachedSong.artistInsight,
      );
      _notifySafely();
      return;
    }

    final normalizedTitle = _normalizeTitleForAutoSearch(title);
    final result = await _fetchLyricsWithAutoRetries(
      requestId: requestId,
      title: normalizedTitle,
      artist: artist,
      albumName: albumName,
      durationSec: durationSec,
      preferSynced: isNowPlayingFromMediaPlayer,
    );
    if (_disposed || requestId != _nowPlayingRequestId) {
      return;
    }

    isLoadingNowPlayingLyrics = false;
    nowPlayingLyrics = _sanitizeLyricsText(result.lyrics);
    songTitle = title;
    artistName = artist;

    final sanitizedLyrics = _sanitizeLyricsText(result.lyrics);
    if (_isCacheableLyrics(sanitizedLyrics)) {
      final metadata = <String, dynamic>{
        ...(result.metadata ?? const <String, dynamic>{}),
        'sourcePackage': sourcePackage ?? '',
        'sourceType': sourceType,
      };
      await _songCache.upsertSong(
        title: title,
        artist: artist,
        lyrics: sanitizedLyrics,
        artworkUrl: nowPlayingArtworkUrl,
        artistInsight: _artistInsightCacheValue,
        metadata: metadata,
      );
    }

    await _upsertCatchemLyricsSnapshot(
      title: title,
      artist: artist,
      lyrics: sanitizedLyrics,
      lyricsSource: _resolveLyricsSourceCode(result),
    );

    _notifySafely();
  }

  Future<LyricsLookupResult> _fetchLyricsWithAutoRetries({
    required int requestId,
    required String title,
    required String artist,
    required String? albumName,
    required int? durationSec,
    required bool preferSynced,
  }) async {
    var lastResult = LyricsLookupResult(
      lyrics: _notFoundMessage,
      debugSteps: const [],
    );

    for (var attempt = 1; attempt <= _autoRetryAttempts; attempt++) {
      if (_disposed || requestId != _nowPlayingRequestId) {
        return lastResult;
      }

      if (attempt > 1) {
        nowPlayingLyrics = _tuningLyricsMessage;
        _notifySafely();
      }

      final result = await fetchLyrics(
        title: title,
        artist: artist,
        albumName: albumName,
        durationSec: durationSec,
        preferSynced: preferSynced,
      );

      if (_disposed || requestId != _nowPlayingRequestId) {
        return result;
      }

      lastResult = result;
      final sanitized = _sanitizeLyricsText(result.lyrics);
      if (_isCacheableLyrics(sanitized)) {
        return result;
      }

      if (attempt < _autoRetryAttempts) {
        await Future.delayed(_autoRetryDelay);
      }
    }

    return lastResult;
  }

  Future<void> _resolveAndApplyNowPlayingArtwork({
    required int requestId,
    required String title,
    required String artist,
    required String sourceType,
    required String? artworkFromEvent,
  }) async {
    final hasEventArtwork = artworkFromEvent != null && artworkFromEvent.trim().isNotEmpty;
    final shouldAlwaysSearchArtwork = sourceType == 'pixel_now_playing';

    if (shouldAlwaysSearchArtwork) {
      debugPrint(
        '[PIXEL_ARTWORK] lookup start title="$title" artist="$artist" eventArtworkPresent=$hasEventArtwork',
      );
    }

    if (hasEventArtwork && !shouldAlwaysSearchArtwork) {
      if (_disposed || requestId != _nowPlayingRequestId) {
        return;
      }
      if (nowPlayingArtworkUrl != artworkFromEvent) {
        nowPlayingArtworkUrl = artworkFromEvent;
        _notifySafely();
      }
      return;
    }

    final artworkUrl = await _metadataSearchPort.findArtworkUrl(
      title: title,
      artist: artist,
    );

    if (shouldAlwaysSearchArtwork) {
      debugPrint('[PIXEL_ARTWORK] lookup result url="${artworkUrl ?? ''}"');
    }

    if (_disposed || requestId != _nowPlayingRequestId) {
      return;
    }

    if ((artworkUrl ?? '').isEmpty) {
      if (shouldAlwaysSearchArtwork) {
        debugPrint('[PIXEL_ARTWORK] lookup miss');
      }
      return;
    }

    if (nowPlayingArtworkUrl != artworkUrl) {
      nowPlayingArtworkUrl = artworkUrl;
      if (shouldAlwaysSearchArtwork) {
        debugPrint('[PIXEL_ARTWORK] applied artworkUrl');
      }
      _notifySafely();
    }
  }

  void _startPlaybackPolling() {
    _playbackPollTimer?.cancel();
    _noPlaybackStateMisses = 0;
    _playbackPollTimer = Timer.periodic(const Duration(milliseconds: 320), (_) async {
      if (_disposed || !isNowPlayingFromMediaPlayer) {
        return;
      }

      try {
        final state = await _gateway.getMediaPlaybackState(sourcePackage: nowPlayingSourcePackage);
        if (_disposed) {
          return;
        }

        final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
        final inNoPlaybackGraceWindow = nowEpochMs < _suppressNoPlaybackUntilEpochMs;

        if (state == null) {
          if (inNoPlaybackGraceWindow) {
            _noPlaybackStateMisses = 0;
            return;
          }
          _noPlaybackStateMisses += 1;
          if (_noPlaybackStateMisses >= 6) {
            _noPlaybackStateMisses = 0;
            await _applyNoPlaybackState();
          }
          return;
        }

        final bool nextPlaying = state['isPlaying'] == true;
        if (!nextPlaying) {
          _noPlaybackStateMisses = 0;

          final dynamic pausedPositionRaw = state['positionMs'];
          final int pausedPosition = switch (pausedPositionRaw) {
            int value => value,
            double value => value.toInt(),
            String value => int.tryParse(value) ?? nowPlayingPlaybackPositionMs,
            _ => nowPlayingPlaybackPositionMs,
          };

          final shouldNotifyPaused =
              (pausedPosition - nowPlayingPlaybackPositionMs).abs() >= 250 ||
              isNowPlayingPlaybackActive;

          nowPlayingPlaybackPositionMs = pausedPosition < 0 ? 0 : pausedPosition;
          isNowPlayingPlaybackActive = false;

          if (shouldNotifyPaused) {
            _notifySafely();
          }
          return;
        }

        _noPlaybackStateMisses = 0;

        final dynamic positionRaw = state['positionMs'];
        final int nextPosition = switch (positionRaw) {
          int value => value,
          double value => value.toInt(),
          String value => int.tryParse(value) ?? nowPlayingPlaybackPositionMs,
          _ => nowPlayingPlaybackPositionMs,
        };

        final shouldNotify =
            (nextPosition - nowPlayingPlaybackPositionMs).abs() >= 250 ||
            nextPlaying != isNowPlayingPlaybackActive;

        nowPlayingPlaybackPositionMs = nextPosition < 0 ? 0 : nextPosition;
        isNowPlayingPlaybackActive = nextPlaying;

        if (shouldNotify) {
          _notifySafely();
        }
      } catch (_) {}
    });
  }

  void _stopPlaybackPolling() {
    _playbackPollTimer?.cancel();
    _playbackPollTimer = null;
    _noPlaybackStateMisses = 0;
    _suppressNoPlaybackUntilEpochMs = 0;
  }

  void _clearPausedPlaybackRestoreState() {
    _hasPausedPlaybackForFavorite = false;
    _pausedPlaybackSourcePackageForFavorite = null;
    _pausedPlaybackPreferredPackageForFavorite = null;
  }

  Future<void> searchLyricsManually() async {
    final query = searchQuery.trim();

    if (query.isEmpty) {
      searchLyrics = _l10n.completeSearchField;
      _notifySafely();
      return;
    }

    isSearchingLyrics = true;
    isManualSearchMode = true;
    isManualSearchFormVisible = false;
    searchLyrics = _l10n.searchingMatches;
    searchArtworkUrl = null;
    _resetSearchCandidates();
    _notifySafely();

    try {
      final candidates = await _gateway.searchLyricsCandidates(query: query);
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchCandidates = candidates;
      isChoosingSearchCandidate = candidates.isNotEmpty;
      isViewingSearchChosenCandidate = false;
        isManualSearchFormVisible = candidates.isEmpty;
      searchLyrics = candidates.isNotEmpty
          ? _l10n.selectMatchToShowLyrics
          : _l10n.noMatchesApiSearch;
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchLyrics = _l10n.apiSearchUnavailable;
      _notifySafely();
    }
  }

  bool get canRetryNowPlayingLyrics {
    if (isLoadingNowPlayingLyrics) {
      return false;
    }
    return _isRetryableMessage(nowPlayingLyrics);
  }

  bool get canRetrySearchLyrics {
    if (isSearchingLyrics || isChoosingSearchCandidate) {
      return false;
    }
    return _isRetryableMessage(searchLyrics);
  }

  bool get hasActiveNowPlayingLyrics {
    return !_looksLikeUiStateMessage(nowPlayingLyrics);
  }

  bool get hasActiveSearchLyrics {
    return !_looksLikeUiStateMessage(searchLyrics);
  }

  bool get canAssociateSelectedSearchLyrics {
    final title = songTitle.trim();
    final artist = artistName.trim();
    if (title.isEmpty || artist.isEmpty || title == _l10n.nowPlayingDefaultTitle) {
      return false;
    }
    if (!isViewingSearchChosenCandidate || _selectedSearchCandidate == null) {
      return false;
    }
    return _isCacheableLyrics(searchLyrics);
  }

  Future<void> retryNowPlayingLyricsIfNeeded() async {
    if (!canRetryNowPlayingLyrics) {
      return;
    }

    final title = songTitle.trim();
    final artist = artistName.trim();
    if (title.isEmpty || artist.isEmpty || title == _l10n.nowPlayingDefaultTitle) {
      return;
    }

    final requestId = ++_nowPlayingRequestId;

    isLoadingNowPlayingLyrics = true;
    nowPlayingLyrics = _tuningLyricsMessage;
    _notifySafely();

    final normalizedTitle = _normalizeTitleForAutoSearch(title);
    final result = await fetchLyrics(
      title: normalizedTitle,
      artist: artist,
      albumName: nowPlayingAlbumName,
      durationSec: nowPlayingDurationSec,
      preferSynced: isNowPlayingFromMediaPlayer,
    );
    final artworkUrl = await _metadataSearchPort.findArtworkUrl(
      title: title,
      artist: artist,
    );
    if (_disposed || requestId != _nowPlayingRequestId) {
      return;
    }

    isLoadingNowPlayingLyrics = false;
    final sanitizedLyrics = _sanitizeLyricsText(result.lyrics);
    nowPlayingLyrics = sanitizedLyrics;
    nowPlayingArtworkUrl = artworkUrl;

    if (_isCacheableLyrics(sanitizedLyrics)) {
      await _songCache.upsertSong(
        title: title,
        artist: artist,
        lyrics: sanitizedLyrics,
        artworkUrl: artworkUrl,
        artistInsight: _artistInsightCacheValue,
        metadata: result.metadata,
      );
    }

    _notifySafely();
  }

  Future<void> retrySearchLyricsIfNeeded() async {
    if (!canRetrySearchLyrics) {
      return;
    }

    final query = searchQuery.trim();
    if (query.isEmpty) {
      return;
    }

    isSearchingLyrics = true;
    searchLyrics = _l10n.retryingMatches;
    _resetSearchCandidates();
    _notifySafely();

    try {
      final candidates = await _gateway.searchLyricsCandidates(query: query);
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchCandidates = candidates;
      isChoosingSearchCandidate = candidates.isNotEmpty;
      isViewingSearchChosenCandidate = false;
      searchLyrics = candidates.isNotEmpty
          ? _l10n.selectMatchToShowLyrics
          : _l10n.noMatchesApiSearch;
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchLyrics = _l10n.apiSearchUnavailable;
      _notifySafely();
    }
  }

  void selectSearchCandidate(LyricsCandidate candidate) {
    searchLyrics = candidate.lyrics;
    _selectedSearchCandidate = candidate;
    isChoosingSearchCandidate = false;
    isViewingSearchChosenCandidate = true;
    _notifySafely();
  }

  void returnToSearchCandidates() {
    if (searchCandidates.isEmpty) {
      return;
    }

    isChoosingSearchCandidate = true;
    isViewingSearchChosenCandidate = false;
    _selectedSearchCandidate = null;
    searchLyrics = _l10n.selectMatchToShowLyrics;
    _notifySafely();
  }

  Future<bool> associateSelectedSearchLyricsToCurrentSong() async {
    if (!canAssociateSelectedSearchLyrics) {
      return false;
    }

    final title = songTitle.trim();
    final artist = artistName.trim();
    final candidate = _selectedSearchCandidate;
    final lyrics = searchLyrics.trim();
    if (candidate == null || lyrics.isEmpty) {
      return false;
    }

    final metadata = <String, dynamic>{
      'sourceType': 'manual_association',
      'trackName': candidate.trackName,
      'artistName': candidate.artistName,
      if (candidate.albumName != null && candidate.albumName!.trim().isNotEmpty)
        'albumName': candidate.albumName!.trim(),
    };

    await _songCache.upsertSong(
      title: title,
      artist: artist,
      lyrics: lyrics,
      artworkUrl: nowPlayingArtworkUrl ?? searchArtworkUrl,
      artistInsight: _artistInsightCacheValue,
      metadata: metadata,
    );

    nowPlayingLyrics = lyrics;
    isManualSearchMode = false;
    isManualSearchFormVisible = false;
    _notifySafely();
    return true;
  }

  Future<LyricsLookupResult> fetchLyrics({
    required String title,
    required String artist,
    required bool preferSynced,
    String? albumName,
    int? durationSec,
  }) async {
    try {
      final result = await _gateway.fetchLyrics(
        title: title,
        artist: artist,
        preferSynced: preferSynced,
        albumName: albumName,
        durationSec: durationSec,
      );

      if (result.lyrics.isNotEmpty) {
        return result;
      }
    } catch (error) {
      debugPrint('[LRCLIB] exception=$error');
      return LyricsLookupResult(
        lyrics: _l10n.lrclibUnavailable,
        debugSteps: const [],
      );
    }

    return LyricsLookupResult(
      lyrics: _l10n.notFoundMessage,
      debugSteps: const [],
    );
  }

  Future<ArtistInsight?> fetchArtistInsight({
    required String artist,
    required String songTitle,
  }) async {
    final normalizedArtist = artist.trim();
    final normalizedSongTitle = songTitle.trim();
    final cacheKey = '$normalizedSongTitle|$normalizedArtist';
    if (normalizedArtist.isEmpty || normalizedSongTitle.isEmpty) {
      return null;
    }

    if (_artistInsightCacheReady && _artistInsightCacheKey == cacheKey) {
      return _artistInsightCacheValue;
    }

    if (_artistInsightInFlightKey == cacheKey && _artistInsightInFlight != null) {
      return await _artistInsightInFlight;
    }

    final future = _loadArtistInsight(artist: normalizedArtist);
    _artistInsightInFlightKey = cacheKey;
    _artistInsightInFlight = future;

    final value = await future;
    _artistInsightCacheKey = cacheKey;
    _artistInsightCacheValue = value;
    _artistInsightCacheReady = true;

    if (value != null) {
      await _songCache.attachArtistInsight(
        title: normalizedSongTitle,
        artist: normalizedArtist,
        insight: value,
      );
    }

    if (_artistInsightInFlightKey == cacheKey) {
      _artistInsightInFlightKey = null;
      _artistInsightInFlight = null;
    }

    return value;
  }

  Future<ArtistInsight?> _loadArtistInsight({required String artist}) async {
    try {
      return await _metadataSearchPort.findArtistInsight(artist: artist);
    } catch (_) {
      return null;
    }
  }

  void _applyArtistInsightCache({
    required String songTitle,
    required String artist,
    required ArtistInsight? insight,
  }) {
    if (insight == null) {
      return;
    }

    _artistInsightCacheKey = '${songTitle.trim()}|${artist.trim()}';
    _artistInsightCacheValue = insight;
    _artistInsightCacheReady = true;
  }

  bool _isRetryableMessage(String message) {
    final normalized = _sanitizeLyricsText(message);
    return normalized == _l10n.lrclibUnavailable || normalized == _notFoundMessage;
  }

  int? _parsePositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is double) {
      return value > 0 ? value.round() : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  String _resolveLyricsSourceCode(LyricsLookupResult result) {
    for (final step in result.debugSteps) {
      final normalized = step.toLowerCase();
      if (normalized.contains('get-cached hit')) {
        return 'lrclib_get_cached';
      }
      if (normalized.contains('get hit')) {
        return 'lrclib_get';
      }
      if (normalized.contains('search(track/artist) hit')) {
        return 'lrclib_search_track_artist';
      }
      if (normalized.contains('search(q) hit')) {
        return 'lrclib_search_q';
      }
    }

    final metadata = result.metadata ?? const <String, dynamic>{};
    final metadataAlbum = (metadata['albumName'] ?? '').toString().trim();
    if (metadataAlbum.isNotEmpty) {
      return 'lrclib';
    }
    return '';
  }

  Future<Position?> _tryGetLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _upsertCatchemLyricsSnapshot({
    required String title,
    required String artist,
    required String lyrics,
    required String lyricsSource,
  }) async {
    final songKey = _favoriteKey(title: title, artist: artist);
    final existingIndex = _catchemLibrary.indexWhere((entry) => entry.key == songKey);
    if (existingIndex < 0) {
      return;
    }

    final existing = _catchemLibrary[existingIndex];
    final nextLyrics = lyrics.trim().isEmpty ? existing.lyrics : lyrics;
    final nextSource = lyricsSource.trim().isEmpty ? existing.lyricsSource : lyricsSource;
    final nextArtwork = (nowPlayingArtworkUrl ?? '').trim().isEmpty
        ? existing.artworkUrl
        : nowPlayingArtworkUrl;

    final updated = existing.copyWith(
      lyrics: nextLyrics,
      lyricsSource: nextSource,
      artworkUrl: nextArtwork,
    );

    if (updated.lyrics == existing.lyrics &&
        updated.lyricsSource == existing.lyricsSource &&
        updated.artworkUrl == existing.artworkUrl) {
      return;
    }

    final next = List<CatchemSongEntry>.from(_catchemLibrary);
    next[existingIndex] = updated;
    _catchemLibrary = next;
    await _persistCatchemLibrary();
    _notifySafely();
  }

  Future<void> _upsertCatchemManualCapture({
    required String title,
    required String artist,
    required String lyrics,
    required String? artworkUrl,
    required String? sourcePackage,
  }) async {
    final songKey = _favoriteKey(title: title, artist: artist);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existingIndex = _catchemLibrary.indexWhere((entry) => entry.key == songKey);

    if (existingIndex >= 0) {
      final existing = _catchemLibrary[existingIndex];
      final history = <CatchemCaptureRecord>[
        ...existing.captureHistory,
        CatchemCaptureRecord(
          capturedAtMs: nowMs,
          captureMode: 'manual',
        ),
      ];
      final updated = existing.copyWith(
        detectCount: history.length,
        lastDetectedAtMs: nowMs,
        lyrics: lyrics.trim().isEmpty ? existing.lyrics : lyrics,
        artworkUrl: (artworkUrl ?? '').trim().isEmpty ? existing.artworkUrl : artworkUrl,
        sourcePackage: (sourcePackage ?? '').trim().isEmpty ? existing.sourcePackage : sourcePackage,
        captureMode: 'manual',
        captureHistory: history,
      );
      final next = List<CatchemSongEntry>.from(_catchemLibrary);
      next[existingIndex] = updated;
      _catchemLibrary = next;
      await _persistCatchemLibrary();
      return;
    }

    final entry = CatchemSongEntry(
      title: title,
      artist: artist,
      lyrics: lyrics,
      artworkUrl: artworkUrl,
      detectCount: 1,
      firstDetectedAtMs: nowMs,
      lastDetectedAtMs: nowMs,
      sourceType: nowPlayingSourceType,
      sourcePackage: sourcePackage,
      lyricsSource: '',
      captureMode: 'manual',
      captureHistory: <CatchemCaptureRecord>[
        CatchemCaptureRecord(capturedAtMs: nowMs, captureMode: 'manual'),
      ],
      latitude: null,
      longitude: null,
    );

    _catchemLibrary = <CatchemSongEntry>[entry, ..._catchemLibrary]
        .take(600)
        .toList(growable: false);
    await _persistCatchemLibrary();
  }

  bool _isCacheableLyrics(String lyrics) {
    final trimmed = _sanitizeLyricsText(lyrics).trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return !_looksLikeUiStateMessage(trimmed);
  }

  bool _looksLikeSyncedLyrics(String lyrics) {
    final value = lyrics.trim();
    if (value.isEmpty) {
      return false;
    }

    final lrcTag = RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,2})?\]', multiLine: true);
    return lrcTag.hasMatch(value);
  }

  String _pickLyricsVariantFromCache({
    required CachedSong? song,
    required bool preferSynced,
  }) {
    if (song == null) {
      return '';
    }

    final metadata = song.metadata ?? const <String, dynamic>{};
    final plain = _sanitizeLyricsText((metadata['plainLyrics'] ?? '').toString());
    final synced = _sanitizeLyricsText((metadata['syncedLyrics'] ?? '').toString());
    final base = _sanitizeLyricsText(song.lyrics);

    if (preferSynced) {
      if (synced.isNotEmpty) {
        return synced;
      }
      if (plain.isNotEmpty) {
        return plain;
      }
      return base;
    }

    if (plain.isNotEmpty) {
      return plain;
    }
    if (synced.isNotEmpty) {
      return synced;
    }
    return base;
  }

  String _sanitizeLyricsText(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase() == 'null') {
      return '';
    }
    return trimmed;
  }

  bool _looksLikeUiStateMessage(String value) {
    final message = value.trim().toLowerCase();
    if (message.isEmpty) {
      return true;
    }

    final markers = <String>[
      'activa el acceso a notificaciones',
      'esperando notificación',
      'permiso activo. comienza a reproducir una canción',
      'permiso activo. reproduce una canción',
      'anuncio detectado. esperando el siguiente cambio de canción',
      'buscando letra en lrclib',
      'actualizando letra en lrclib',
      'reintentando búsqueda en lrclib',
      'sintonizando letra',
      'no se encontró letra para esta canción en lrclib',
      'no se encontro letra para esta canción en lrclib',
      'no se encontro letra para esta cancion en lrclib',
      'no fue posible consultar lrclib en este momento',
      'escribe lo que quieras buscar para encontrar una letra',
      'escribe una búsqueda manual para ver coincidencias',
      'escribe una busqueda manual para ver coincidencias',
      'completa el campo de búsqueda para continuar',
      'completa el campo de busqueda para continuar',
      'buscando coincidencias en lrclib',
      'reintentando coincidencias en lrclib',
      'selecciona una coincidencia para mostrar la letra',
      'no se encontraron coincidencias en /api/search',
      'no fue posible consultar /api/search en este momento',
      'enable notification access',
      'permission active',
      'ad detected',
      'updating lyrics on lrclib',
      'retrying matches on lrclib',
      'select a match to show lyrics',
      'no matches found in /api/search',
      'could not query /api/search right now',
      'could not query lrclib right now',
      _l10n.permissionMissingMessage.toLowerCase(),
      _l10n.waitingPlaybackMessage.toLowerCase(),
      _l10n.adDetectedMessage.toLowerCase(),
      _l10n.searchLyricsDefaultPrompt.toLowerCase(),
      _l10n.manualSearchPrompt.toLowerCase(),
      _l10n.completeSearchField.toLowerCase(),
      _l10n.searchingMatches.toLowerCase(),
      _l10n.retryingMatches.toLowerCase(),
      _l10n.selectMatchToShowLyrics.toLowerCase(),
      _l10n.noMatchesApiSearch.toLowerCase(),
      _l10n.apiSearchUnavailable.toLowerCase(),
      _l10n.lrclibUnavailable.toLowerCase(),
      _l10n.notFoundMessage.toLowerCase(),
    ];

    return markers.any(message.contains);
  }

  bool _looksLikeAdOrAnnouncement({
    required String title,
    required String artist,
  }) {
    final normalized = '${title.trim()} ${artist.trim()}'.toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    const adMarkers = <String>[
      'anuncio',
      'publicidad',
      'advertisement',
      'commercial break',
      'sponsored',
      'sponsor',
      'promo',
      'promocion',
      'promoción',
      'ad break',
      'ads',
    ];

    if (adMarkers.any(normalized.contains)) {
      return true;
    }

    final adWord = RegExp(r'(^|\s)ad(\s|$)', caseSensitive: false);
    return adWord.hasMatch(normalized);
  }

  String _normalizeTitleForAutoSearch(String title) {
    if (title.isEmpty) {
      return title;
    }

    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
      'ñ': 'n',
      'Ñ': 'N',
    };

    final buffer = StringBuffer();
    for (final rune in title.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }

    return buffer.toString();
  }

  void _resetSearchCandidates() {
    searchCandidates = const [];
    _selectedSearchCandidate = null;
    isChoosingSearchCandidate = false;
    isViewingSearchChosenCandidate = false;
  }

  void _notifySafely() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPlaybackPolling();
    _subscription?.cancel();
    super.dispose();
  }
}

class FavoriteSongEntry {
  const FavoriteSongEntry({
    required this.title,
    required this.artist,
    required this.lyrics,
    required this.artworkUrl,
    required this.createdAtMs,
  });

  final String title;
  final String artist;
  final String lyrics;
  final String? artworkUrl;
  final int createdAtMs;

  String get key => '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'artist': artist,
      'lyrics': lyrics,
      'artworkUrl': artworkUrl,
      'createdAtMs': createdAtMs,
    };
  }

  factory FavoriteSongEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteSongEntry(
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      lyrics: (json['lyrics'] ?? '').toString(),
      artworkUrl: (json['artworkUrl'] ?? '').toString().trim().isEmpty
          ? null
          : json['artworkUrl'].toString(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class CatchemSongEntry {
  const CatchemSongEntry({
    required this.title,
    required this.artist,
    required this.lyrics,
    required this.artworkUrl,
    required this.detectCount,
    required this.firstDetectedAtMs,
    required this.lastDetectedAtMs,
    required this.sourceType,
    required this.sourcePackage,
    required this.lyricsSource,
    required this.captureMode,
    required this.captureHistory,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final String artist;
  final String lyrics;
  final String? artworkUrl;
  final int detectCount;
  final int firstDetectedAtMs;
  final int lastDetectedAtMs;
  final String sourceType;
  final String? sourcePackage;
  final String lyricsSource;
  final String captureMode;
  final List<CatchemCaptureRecord> captureHistory;
  final double? latitude;
  final double? longitude;

  String get key => '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  CatchemSongEntry copyWith({
    String? title,
    String? artist,
    String? lyrics,
    String? artworkUrl,
    int? detectCount,
    int? firstDetectedAtMs,
    int? lastDetectedAtMs,
    String? sourceType,
    String? sourcePackage,
    String? lyricsSource,
    String? captureMode,
    List<CatchemCaptureRecord>? captureHistory,
    double? latitude,
    double? longitude,
  }) {
    return CatchemSongEntry(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      lyrics: lyrics ?? this.lyrics,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      detectCount: detectCount ?? this.detectCount,
      firstDetectedAtMs: firstDetectedAtMs ?? this.firstDetectedAtMs,
      lastDetectedAtMs: lastDetectedAtMs ?? this.lastDetectedAtMs,
      sourceType: sourceType ?? this.sourceType,
      sourcePackage: sourcePackage ?? this.sourcePackage,
      lyricsSource: lyricsSource ?? this.lyricsSource,
      captureMode: captureMode ?? this.captureMode,
      captureHistory: captureHistory ?? this.captureHistory,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'artist': artist,
      'lyrics': lyrics,
      'artworkUrl': artworkUrl,
      'detectCount': detectCount,
      'firstDetectedAtMs': firstDetectedAtMs,
      'lastDetectedAtMs': lastDetectedAtMs,
      'sourceType': sourceType,
      'sourcePackage': sourcePackage,
      'lyricsSource': lyricsSource,
      'captureMode': captureMode,
      'captureHistory': captureHistory.map((entry) => entry.toJson()).toList(growable: false),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory CatchemSongEntry.fromJson(Map<String, dynamic> json) {
    final rawDetectCount = (json['detectCount'] as num?)?.toInt() ?? 1;
    final detectCount = rawDetectCount <= 0 ? 1 : rawDetectCount;
    final firstDetectedAtMs = (json['firstDetectedAtMs'] as num?)?.toInt() ?? 0;
    final lastDetectedAtMs = (json['lastDetectedAtMs'] as num?)?.toInt() ?? firstDetectedAtMs;
    final captureMode = (json['captureMode'] ?? 'automatic').toString();

    final rawHistory = json['captureHistory'];
    final parsedHistory = <CatchemCaptureRecord>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map<String, dynamic>) {
          parsedHistory.add(CatchemCaptureRecord.fromJson(item));
        } else if (item is Map) {
          final normalized = <String, dynamic>{};
          for (final entry in item.entries) {
            normalized[entry.key.toString()] = entry.value;
          }
          parsedHistory.add(CatchemCaptureRecord.fromJson(normalized));
        }
      }
    }
    if (parsedHistory.isEmpty) {
      parsedHistory.add(
        CatchemCaptureRecord(
          capturedAtMs: lastDetectedAtMs,
          captureMode: captureMode,
        ),
      );
    }

    return CatchemSongEntry(
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      lyrics: (json['lyrics'] ?? '').toString(),
      artworkUrl: (json['artworkUrl'] ?? '').toString().trim().isEmpty
          ? null
          : json['artworkUrl'].toString(),
      detectCount: detectCount,
      firstDetectedAtMs: firstDetectedAtMs,
      lastDetectedAtMs: lastDetectedAtMs,
      sourceType: (json['sourceType'] ?? '').toString(),
      sourcePackage: (json['sourcePackage'] ?? '').toString().trim().isEmpty
          ? null
          : json['sourcePackage'].toString(),
      lyricsSource: (json['lyricsSource'] ?? '').toString(),
      captureMode: captureMode,
      captureHistory: parsedHistory,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

class CatchemCaptureRecord {
  const CatchemCaptureRecord({
    required this.capturedAtMs,
    required this.captureMode,
  });

  final int capturedAtMs;
  final String captureMode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'capturedAtMs': capturedAtMs,
      'captureMode': captureMode,
    };
  }

  factory CatchemCaptureRecord.fromJson(Map<String, dynamic> json) {
    return CatchemCaptureRecord(
      capturedAtMs: (json['capturedAtMs'] as num?)?.toInt() ?? 0,
      captureMode: (json['captureMode'] ?? 'automatic').toString(),
    );
  }
}
