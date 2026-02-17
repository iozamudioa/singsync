import 'dart:async';

import 'package:flutter/material.dart';

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
      _songCache = songCache;

  final PlatformLyricsGateway _gateway;
  final MusicMetadataSearchPort _metadataSearchPort;
  final LocalSongCacheRepository _songCache;
  StreamSubscription<dynamic>? _subscription;
  Timer? _playbackPollTimer;
  bool _disposed = false;

  static const String _notFoundMessage = 'No se encontró letra para esta canción en lrclib.';
    static const String _permissionMissingMessage =
      'Activa el acceso a notificaciones para esta app y reproduce una canción para cargar su letra.';
    static const String _waitingPlaybackMessage =
        'Permiso activo. Comienza a reproducir una canción para detectar el now playing y cargar la letra.';
  static const int _autoRetryAttempts = 5;
  static const Duration _autoRetryDelay = Duration(seconds: 2);
  static const List<String> knownMediaAppPackages = <String>[
    'com.spotify.music',
    'com.google.android.apps.youtube.music',
    'com.amazon.mp3',
    'com.apple.android.music',
  ];

  String songTitle = 'Now Playing';
  String artistName = 'Esperando notificación de Android System Intelligence';
  String nowPlayingSourceType = '';
  String? nowPlayingSourcePackage;
  String? preferredMediaAppPackage;
  Set<String> installedMediaAppPackages = const <String>{};
  String nowPlayingLyrics =
      _permissionMissingMessage;
  String? nowPlayingArtworkUrl;
  bool hasNotificationListenerAccess = false;
  bool isLoadingNowPlayingLyrics = false;
  int nowPlayingPlaybackPositionMs = 0;
  bool isNowPlayingPlaybackActive = false;
  bool hasActiveNowPlaying = false;
  int _noPlaybackStateMisses = 0;
  int _suppressNoPlaybackUntilEpochMs = 0;
  String? _lastAutoLookupKey;
  int _nowPlayingRequestId = 0;

  String searchQuery = '';
  String searchLyrics = 'Escribe lo que quieras buscar para encontrar una letra.';
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

  void start() {
    refreshNotificationPermissionStatus();
    unawaited(refreshInstalledMediaApps());

    _subscription = _gateway.nowPlayingStream().listen(
      onNowPlayingEvent,
      onError: (Object error) {
        artistName = 'Error escuchando notificaciones';
        nowPlayingLyrics = '$error';
        _notifySafely();
      },
    );

    loadCurrentNowPlayingOnStartup();
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
      nowTitle != 'Now Playing') {
      final requestId = ++_nowPlayingRequestId;
      isLoadingNowPlayingLyrics = true;
      nowPlayingLyrics = 'Actualizando letra en lrclib...';
      _notifySafely();

      final normalizedTitle = _normalizeTitleForAutoSearch(nowTitle);
      final result = await fetchLyrics(
        title: normalizedTitle,
        artist: nowArtist,
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
    searchLyrics = 'Actualizando letra en lrclib...';
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
        ? 'Selecciona una coincidencia para mostrar la letra.'
        : 'No se encontraron coincidencias en /api/search.';
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
    hasActiveNowPlaying = false;
    _stopPlaybackPolling();
    isNowPlayingPlaybackActive = false;
    nowPlayingPlaybackPositionMs = 0;
    isLoadingNowPlayingLyrics = false;
    nowPlayingSourceType = '';
    nowPlayingSourcePackage = null;
    songTitle = 'Now Playing';
    artistName = 'Esperando notificación de Android System Intelligence';
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

    if (title.isEmpty || title == 'Now Playing') {
      return;
    }

    searchQuery = title;
    _notifySafely();
  }

  Future<void> startManualCandidatesFromNowPlaying() async {
    prefillManualSearchFromNowPlaying();

    final recoveredLyrics = await _retryNowPlayingLyricsBeforeManualSearch();
    if (_disposed || recoveredLyrics) {
      return;
    }

    isManualSearchMode = true;
    isManualSearchFormVisible = true;
    isSearchingLyrics = false;
    searchArtworkUrl = nowPlayingArtworkUrl;
    _resetSearchCandidates();
    searchLyrics = 'Escribe una búsqueda manual para ver coincidencias.';
    _notifySafely();
  }

  Future<bool> _retryNowPlayingLyricsBeforeManualSearch() async {
    final title = songTitle.trim();
    final artist = artistName.trim();
    if (title.isEmpty || artist.isEmpty || title == 'Now Playing') {
      return false;
    }

    final requestId = ++_nowPlayingRequestId;
    const maxAttempts = 5;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_disposed || requestId != _nowPlayingRequestId) {
        return true;
      }

      isManualSearchMode = false;
      isManualSearchFormVisible = false;
      isLoadingNowPlayingLyrics = true;
      nowPlayingLyrics = 'Reintentando búsqueda en lrclib... ($attempt/$maxAttempts)';
      _notifySafely();

      final normalizedTitle = _normalizeTitleForAutoSearch(title);
      final result = await fetchLyrics(
        title: normalizedTitle,
        artist: artist,
        preferSynced: isNowPlayingFromMediaPlayer,
      );

      if (_disposed || requestId != _nowPlayingRequestId) {
        return true;
      }

      final sanitizedLyrics = _sanitizeLyricsText(result.lyrics);
      if (_isCacheableLyrics(sanitizedLyrics)) {
        isLoadingNowPlayingLyrics = false;
        nowPlayingLyrics = sanitizedLyrics;

        final metadata = <String, dynamic>{
          ...(result.metadata ?? const <String, dynamic>{}),
          'sourcePackage': nowPlayingSourcePackage ?? '',
          'sourceType': nowPlayingSourceType,
        };

        await _songCache.upsertSong(
          title: title,
          artist: artist,
          lyrics: sanitizedLyrics,
          artworkUrl: nowPlayingArtworkUrl,
          artistInsight: _artistInsightCacheValue,
          metadata: metadata,
        );

        _notifySafely();
        return true;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (_disposed || requestId != _nowPlayingRequestId) {
      return true;
    }

    isLoadingNowPlayingLyrics = false;
    nowPlayingLyrics = _notFoundMessage;
    _notifySafely();
    return false;
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

    final hasSong = songTitle.trim().isNotEmpty && songTitle.trim() != 'Now Playing';
    if (!hasSong) {
      return false;
    }

    final message = nowPlayingLyrics.trim().toLowerCase();
    final notFoundLike = message.contains('no se encontró letra') ||
        message.contains('no se encontro letra') ||
        message.contains('no fue posible consultar');

    return notFoundLike || _isRetryableMessage(nowPlayingLyrics);
  }

  bool get isNowPlayingFromMediaPlayer => nowPlayingSourceType == 'media_player';

  Future<void> openActivePlayer() async {
    final selectedPackage = preferredMediaAppPackage;
    final hasDetectedSong = hasActiveNowPlaying &&
        songTitle.trim().isNotEmpty &&
        songTitle.trim() != 'Now Playing';
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
    final artworkFromEventRaw = (event['artworkUrl'] ?? '').toString().trim();
    final artworkFromEvent = artworkFromEventRaw.isEmpty ? null : artworkFromEventRaw;

    debugPrint('[NOW_PLAYING] title="$title" artist="$artist"');

    if (title.isEmpty || artist.isEmpty) {
      return;
    }

    final eventKey = '$title|$artist|$sourceType|${sourcePackage ?? ''}';
    if (isLoadingNowPlayingLyrics && _lastAutoLookupKey == eventKey) {
      return;
    }
    _lastAutoLookupKey = eventKey;
    final requestId = ++_nowPlayingRequestId;
    hasActiveNowPlaying = true;

    isManualSearchMode = false;
    isManualSearchFormVisible = false;

    songTitle = title;
    artistName = artist;
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
    isLoadingNowPlayingLyrics = true;
    nowPlayingLyrics = 'Buscando letra en lrclib...';
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
        sourcePackage: sourcePackage,
        sourceType: sourceType,
      ),
    );
  }

  Future<void> _resolveAndApplyNowPlayingLyrics({
    required int requestId,
    required String title,
    required String artist,
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

    final cachedLyrics = cachedSong == null ? '' : _sanitizeLyricsText(cachedSong.lyrics);
    final shouldForceSyncedLookup =
        sourceType == 'media_player' &&
        cachedVariantLyrics.isNotEmpty &&
      !_looksLikeSyncedLyrics(cachedVariantLyrics);

    if (cachedSong != null && cachedVariantLyrics.isNotEmpty && !shouldForceSyncedLookup) {
      isLoadingNowPlayingLyrics = false;
      nowPlayingLyrics = cachedVariantLyrics;
      nowPlayingArtworkUrl = cachedSong.artworkUrl ?? nowPlayingArtworkUrl;
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

    _notifySafely();
  }

  Future<LyricsLookupResult> _fetchLyricsWithAutoRetries({
    required int requestId,
    required String title,
    required String artist,
    required bool preferSynced,
  }) async {
    var lastResult = const LyricsLookupResult(
      lyrics: _notFoundMessage,
      debugSteps: [],
    );

    for (var attempt = 1; attempt <= _autoRetryAttempts; attempt++) {
      if (_disposed || requestId != _nowPlayingRequestId) {
        return lastResult;
      }

      if (attempt > 1) {
        nowPlayingLyrics = 'Reintentando búsqueda en lrclib... ($attempt/$_autoRetryAttempts)';
        _notifySafely();
      }

      final result = await fetchLyrics(
        title: title,
        artist: artist,
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
    if (artworkFromEvent != null && artworkFromEvent.trim().isNotEmpty) {
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

    if (_disposed || requestId != _nowPlayingRequestId) {
      return;
    }

    if ((artworkUrl ?? '').isEmpty) {
      return;
    }

    if (nowPlayingArtworkUrl != artworkUrl) {
      nowPlayingArtworkUrl = artworkUrl;
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

  Future<void> searchLyricsManually() async {
    final query = searchQuery.trim();

    if (query.isEmpty) {
      searchLyrics = 'Completa el campo de búsqueda para continuar.';
      _notifySafely();
      return;
    }

    isSearchingLyrics = true;
    isManualSearchMode = true;
    isManualSearchFormVisible = false;
    searchLyrics = 'Buscando coincidencias en lrclib...';
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
          ? 'Selecciona una coincidencia para mostrar la letra.'
          : 'No se encontraron coincidencias en /api/search.';
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchLyrics = 'No fue posible consultar /api/search en este momento.';
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
    if (title.isEmpty || artist.isEmpty || title == 'Now Playing') {
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
    if (title.isEmpty || artist.isEmpty || title == 'Now Playing') {
      return;
    }

    final requestId = ++_nowPlayingRequestId;

    isLoadingNowPlayingLyrics = true;
    nowPlayingLyrics = 'Reintentando búsqueda en lrclib...';
    _notifySafely();

    final normalizedTitle = _normalizeTitleForAutoSearch(title);
    final result = await fetchLyrics(
      title: normalizedTitle,
      artist: artist,
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
    searchLyrics = 'Reintentando coincidencias en lrclib...';
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
          ? 'Selecciona una coincidencia para mostrar la letra.'
          : 'No se encontraron coincidencias en /api/search.';
      _notifySafely();
    } catch (_) {
      if (_disposed) {
        return;
      }

      isSearchingLyrics = false;
      searchLyrics = 'No fue posible consultar /api/search en este momento.';
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
    searchLyrics = 'Selecciona una coincidencia para mostrar la letra.';
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
  }) async {
    try {
      final result = await _gateway.fetchLyrics(
        title: title,
        artist: artist,
        preferSynced: preferSynced,
      );
      for (final step in result.debugSteps) {
        debugPrint('[LRCLIB_NATIVE] $step');
      }

      if (result.lyrics.isNotEmpty) {
        return result;
      }
    } catch (error) {
      debugPrint('[LRCLIB] exception=$error');
      return const LyricsLookupResult(
        lyrics: 'No fue posible consultar lrclib en este momento.',
        debugSteps: [],
      );
    }

    return const LyricsLookupResult(
      lyrics: 'No se encontró letra para esta canción en lrclib.',
      debugSteps: [],
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
    return normalized == 'No fue posible consultar lrclib en este momento.' ||
        normalized == _notFoundMessage;
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

    const markers = <String>[
      'activa el acceso a notificaciones',
      'esperando notificación',
      'permiso activo. comienza a reproducir una canción',
      'permiso activo. reproduce una canción',
      'buscando letra en lrclib',
      'actualizando letra en lrclib',
      'reintentando búsqueda en lrclib',
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
    ];

    return markers.any(message.contains);
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
