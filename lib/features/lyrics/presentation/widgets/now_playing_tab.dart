import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/lyrics_candidate.dart';
import '../lyrics_controller.dart';
import 'lyrics_panel.dart';
import 'music_search_icon.dart';

class NowPlayingTab extends StatefulWidget {
  const NowPlayingTab({
    super.key,
    required this.controller,
    required this.theme,
    required this.onSearchManually,
  });

  final LyricsController controller;
  final ThemeData theme;
  final VoidCallback onSearchManually;

  @override
  State<NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends State<NowPlayingTab> {
  static const String _spotifyPackage = 'com.spotify.music';
  static const String _youtubeMusicPackage = 'com.google.android.apps.youtube.music';
  static const String _amazonMusicPackage = 'com.amazon.mp3';
  static const String _appleMusicPackage = 'com.apple.android.music';

  late final TextEditingController _queryController;
  bool _isNowPlayingHeaderVisible = true;
  bool _isLandscapeLayout = false;
  String _lastNowPlayingKey = '';
  bool _isCopyToastVisible = false;
  bool _isVinylExpanded = false;
  Timer? _autoExpandVinylTimer;
  String? _autoExpandPendingKey;
  String? _autoExpandedForKey;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.controller.searchQuery)
      ..addListener(() {
        widget.controller.updateSearchQuery(_queryController.text);
      });
  }

  @override
  void dispose() {
    _autoExpandVinylTimer?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _syncSearchInputWithController() {
    final query = widget.controller.searchQuery;
    if (_queryController.text != query) {
      _queryController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
  }

  void _handleLyricsScrollDirection(ScrollDirection direction) {
    if (_isLandscapeLayout) {
      return;
    }

    if (direction == ScrollDirection.idle) {
      return;
    }

    if (direction == ScrollDirection.reverse && _isNowPlayingHeaderVisible) {
      setState(() {
        _isNowPlayingHeaderVisible = false;
      });
      return;
    }

    if (direction == ScrollDirection.forward && !_isNowPlayingHeaderVisible) {
      setState(() {
        _isNowPlayingHeaderVisible = true;
      });
    }
  }

  void _handleCopyFeedbackVisibility(bool visible) {
    if (_isCopyToastVisible == visible) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isCopyToastVisible = visible;
    });
  }

  void _toggleVinylExpanded() {
    if ((widget.controller.nowPlayingArtworkUrl ?? '').isEmpty) {
      return;
    }

    setState(() {
      _isVinylExpanded = !_isVinylExpanded;
    });
  }

  void _onSearchManuallyPressed() {
    _autoExpandVinylTimer?.cancel();
    _autoExpandPendingKey = null;
    widget.onSearchManually();
  }

  void _handleAutoExpandOnManualPrompt({
    required LyricsController controller,
    required String nowPlayingKey,
  }) {
    final shouldAutoExpand = controller.hasActiveNowPlaying &&
        controller.canShowManualSearchButton &&
        !controller.isManualSearchMode &&
        !controller.isLoadingNowPlayingLyrics &&
        !_isVinylExpanded &&
        (controller.nowPlayingArtworkUrl ?? '').isNotEmpty;

    if (!shouldAutoExpand) {
      _autoExpandVinylTimer?.cancel();
      _autoExpandPendingKey = null;
      return;
    }

    if (_autoExpandedForKey == nowPlayingKey || _autoExpandPendingKey == nowPlayingKey) {
      return;
    }

    _autoExpandVinylTimer?.cancel();
    _autoExpandPendingKey = nowPlayingKey;
    _autoExpandVinylTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }

      final latestKey =
          '${widget.controller.songTitle.trim()}|${widget.controller.artistName.trim()}';
      final stillValid = latestKey == nowPlayingKey &&
          widget.controller.canShowManualSearchButton &&
          !widget.controller.isManualSearchMode &&
          !widget.controller.isLoadingNowPlayingLyrics &&
          (widget.controller.nowPlayingArtworkUrl ?? '').isNotEmpty &&
          !_isVinylExpanded;

      if (!stillValid) {
        _autoExpandPendingKey = null;
        return;
      }

      setState(() {
        _isVinylExpanded = true;
        _autoExpandedForKey = nowPlayingKey;
        _autoExpandPendingKey = null;
      });
    });
  }

  Future<void> _openInSpotify() async {
    widget.controller.setPreferredMediaAppPackage(_spotifyPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('open.spotify.com', '/')
        : Uri.https('open.spotify.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInSpotify() async {
    widget.controller.setPreferredMediaAppPackage(_spotifyPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('open.spotify.com', '/')
        : Uri.https('open.spotify.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInYouTubeMusic() async {
    widget.controller.setPreferredMediaAppPackage(_youtubeMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.youtube.com', '/')
        : Uri.https('music.youtube.com', '/search', {'q': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInYouTubeMusic() async {
    widget.controller.setPreferredMediaAppPackage(_youtubeMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.youtube.com', '/')
        : Uri.https('music.youtube.com', '/search', {'q': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInAmazonMusic() async {
    widget.controller.setPreferredMediaAppPackage(_amazonMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.amazon.com', '/')
        : Uri.https('music.amazon.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInAmazonMusic() async {
    widget.controller.setPreferredMediaAppPackage(_amazonMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.amazon.com', '/')
        : Uri.https('music.amazon.com', '/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInAppleMusic() async {
    widget.controller.setPreferredMediaAppPackage(_appleMusicPackage);
    final query = _defaultMusicQuery();
    final uri = query.isEmpty
        ? Uri.https('music.apple.com', '/')
        : Uri.https('music.apple.com', '/us/search', {'term': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openArtistInAppleMusic() async {
    widget.controller.setPreferredMediaAppPackage(_appleMusicPackage);
    final query = _artistOnlyQuery();
    final uri = query.isEmpty
        ? Uri.https('music.apple.com', '/')
        : Uri.https('music.apple.com', '/us/search', {'term': query});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _defaultMusicQuery() {
    final hasDetectedSong = widget.controller.hasActiveNowPlaying &&
        widget.controller.songTitle.trim().isNotEmpty &&
        widget.controller.songTitle.trim() != 'Now Playing';
    if (!hasDetectedSong) {
      return '';
    }

    final typedQuery = widget.controller.searchQuery.trim();
    return typedQuery.isNotEmpty
        ? typedQuery
        : '${widget.controller.songTitle} ${widget.controller.artistName}'.trim();
  }

  String _artistOnlyQuery() {
    if (!widget.controller.hasActiveNowPlaying) {
      return '';
    }

    final artist = widget.controller.artistName.trim();
    if (artist.isNotEmpty && artist != 'Artista desconocido') {
      return artist;
    }

    return _defaultMusicQuery();
  }

  Widget _buildPlatformButtonsRow({required bool artistOnly}) {
    final installed = widget.controller.installedMediaAppPackages;
    final buttons = <Widget>[];

    void addButton({
      required String packageName,
      required VoidCallback onPressed,
      required Widget icon,
      required String tooltip,
    }) {
      if (!installed.contains(packageName)) {
        return;
      }
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 8));
      }
      buttons.add(
        IconButton(
          onPressed: onPressed,
          icon: icon,
          tooltip: tooltip,
        ),
      );
    }

    addButton(
      packageName: _spotifyPackage,
      onPressed: artistOnly ? _openArtistInSpotify : _openInSpotify,
      icon: const FaIcon(FontAwesomeIcons.spotify),
      tooltip: 'Spotify',
    );
    addButton(
      packageName: _youtubeMusicPackage,
      onPressed: artistOnly ? _openArtistInYouTubeMusic : _openInYouTubeMusic,
      icon: const FaIcon(FontAwesomeIcons.youtube),
      tooltip: 'YouTube Music',
    );
    addButton(
      packageName: _amazonMusicPackage,
      onPressed: artistOnly ? _openArtistInAmazonMusic : _openInAmazonMusic,
      icon: const FaIcon(FontAwesomeIcons.amazon),
      tooltip: 'Amazon Music',
    );
    addButton(
      packageName: _appleMusicPackage,
      onPressed: artistOnly ? _openArtistInAppleMusic : _openInAppleMusic,
      icon: const FaIcon(FontAwesomeIcons.apple),
      tooltip: 'Apple Music',
    );

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: buttons,
    );
  }

  IconData _activePlayerIcon(String? packageName) {
    final pkg = (packageName ?? '').toLowerCase();
    if (pkg.contains('spotify')) {
      return FontAwesomeIcons.spotify;
    }
    if (pkg.contains('youtube.music') || pkg.contains('youtube')) {
      return FontAwesomeIcons.youtube;
    }
    if (pkg.contains('amazon')) {
      return FontAwesomeIcons.amazon;
    }
    if (pkg.contains('apple')) {
      return FontAwesomeIcons.apple;
    }
    return FontAwesomeIcons.music;
  }

  Widget _buildActivePlayerButton({double? iconSize}) {
    final controller = widget.controller;
    final packageName = controller.nowPlayingSourcePackage ?? controller.preferredMediaAppPackage;
    return IconButton(
      iconSize: iconSize,
      onPressed: controller.openActivePlayer,
      icon: FaIcon(
        _activePlayerIcon(packageName),
        size: iconSize,
      ),
      tooltip: 'Abrir reproductor activo',
    );
  }

  Widget _buildPlayerControlsRow({
    double? iconSizeOverride,
    double spacing = 6,
  }) {
    final controller = widget.controller;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final iconSize = iconSizeOverride ??
        (shortestSide >= 700
            ? 36.0
            : shortestSide >= 500
                ? 33.0
                : 30.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: controller.mediaPrevious,
          iconSize: iconSize,
          splashRadius: iconSize * 0.8,
          icon: const Icon(Icons.skip_previous_rounded),
          tooltip: 'Anterior',
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: controller.mediaPlayPause,
          iconSize: iconSize,
          splashRadius: iconSize * 0.8,
          icon: const Icon(Icons.play_arrow_rounded),
          tooltip: 'Play/Pause',
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: controller.mediaNext,
          iconSize: iconSize,
          splashRadius: iconSize * 0.8,
          icon: const Icon(Icons.skip_next_rounded),
          tooltip: 'Siguiente',
        ),
      ],
    );
  }

  Widget _buildExpandedVinylArea({required bool isLandscape, required BoxConstraints constraints}) {
    final controller = widget.controller;
    final artworkUrl = controller.nowPlayingArtworkUrl;
    final hasActiveNowPlaying = controller.hasActiveNowPlaying;
    final canOpenMediaApps = controller.hasNotificationListenerAccess;

    final viewPadding = MediaQuery.of(context).viewPadding;
    final insetDelta = viewPadding.right - viewPadding.left;
    final landscapeOpticalDx = isLandscape
      ? (insetDelta * 0.9).clamp(-36.0, 36.0)
      : 0.0;

    final size = isLandscape
        ? math.min(360.0, math.max(220.0, constraints.maxHeight * 0.72))
        : math.min(380.0, math.max(220.0, constraints.maxWidth * 0.86));

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleVinylExpanded,
          ),
          Center(
            child: Transform.translate(
              offset: Offset(landscapeOpticalDx, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ArtworkCover(
                    url: artworkUrl,
                    size: size,
                    isSpinning: controller.isNowPlayingPlaybackActive,
                    onTap: _toggleVinylExpanded,
                  ),
                  const SizedBox(height: 14),
                  if (hasActiveNowPlaying && controller.isNowPlayingFromMediaPlayer) ...[
                    _buildPlayerControlsRow(),
                    _buildActivePlayerButton(),
                  ] else if (hasActiveNowPlaying || canOpenMediaApps)
                    _buildPlatformButtonsRow(artistOnly: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showArtistInfoModal() {
    final controller = widget.controller;
    final artworkUrl = controller.nowPlayingArtworkUrl;
    if (artworkUrl == null || artworkUrl.trim().isEmpty) {
      return;
    }

    final artist = controller.artistName.trim();
    final songTitle = controller.songTitle.trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.28),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) {
        final theme = Theme.of(context);
        final isLandscapeModal = MediaQuery.of(context).orientation == Orientation.landscape;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.16,
                          child: Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withOpacity(0.84),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: isLandscapeModal
                          ? const EdgeInsets.fromLTRB(14, 22, 14, 14)
                          : const EdgeInsets.fromLTRB(16, 52, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isLandscapeModal) ...[
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.network(
                                  artworkUrl,
                                  width: 240,
                                  height: 240,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      width: 240,
                                      height: 240,
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.album_rounded, size: 54),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              artist.isEmpty ? 'Artista' : artist,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            _buildPlatformButtonsRow(artistOnly: true),
                            const SizedBox(height: 14),
                          ],
                          FutureBuilder(
                            future: controller.fetchArtistInsight(
                              artist: artist,
                              songTitle: songTitle,
                            ),
                            builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            );
                          }

                          final info = snapshot.data;
                          final genre = info?.primaryGenre.trim() ?? '';
                          final country = info?.country.trim() ?? '';
                          final shortBio = info?.shortBio.trim() ?? '';
                          final releases = info?.popularReleases ?? const <String>[];
                          final firstYear = info?.firstReleaseYear;
                          final latestYear = info?.latestReleaseYear;

                          final hasPeriod = firstYear != null || latestYear != null;
                          final hasSomething =
                              genre.isNotEmpty ||
                              country.isNotEmpty ||
                              shortBio.isNotEmpty ||
                              releases.isNotEmpty ||
                              hasPeriod;

                          if (!hasSomething) {
                            return Text(
                              'No hay más datos del artista por ahora.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            );
                          }

                          if (isLandscapeModal) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: Image.network(
                                          artworkUrl,
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) {
                                            return Container(
                                              width: 180,
                                              height: 180,
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              child: const Icon(
                                                Icons.album_rounded,
                                                size: 54,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        artist.isEmpty ? 'Artista' : artist,
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildPlatformButtonsRow(artistOnly: true),
                                      if (genre.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          'Género: $genre',
                                          style: theme.textTheme.bodyLarge,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                      if (country.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'País: $country',
                                          style: theme.textTheme.bodyLarge,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                      if (hasPeriod) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Periodo detectado: ${firstYear ?? '?'} - ${latestYear ?? '?'}',
                                          style: theme.textTheme.bodyLarge,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (shortBio.isNotEmpty) ...[
                                        Text(
                                          'Historia breve',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.left,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          shortBio,
                                          style: theme.textTheme.bodyMedium,
                                          textAlign: TextAlign.left,
                                        ),
                                      ],
                                      if (releases.isNotEmpty) ...[
                                        if (shortBio.isNotEmpty) const SizedBox(height: 14),
                                        Text(
                                          'Lanzamientos populares',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.left,
                                        ),
                                        const SizedBox(height: 6),
                                        ...releases.map(
                                          (track) => Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: Text(
                                              '• $track',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (genre.isNotEmpty)
                                Text(
                                  'Género: $genre',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              if (country.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'País: $country',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (hasPeriod) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Periodo detectado: ${firstYear ?? '?'} - ${latestYear ?? '?'}',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (shortBio.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'Historia breve',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  shortBio,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.left,
                                ),
                              ],
                              if (releases.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'Lanzamientos populares',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                                const SizedBox(height: 6),
                                ...releases.map(
                                  (track) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('• $track', style: theme.textTheme.bodyMedium),
                                  ),
                                ),
                              ],
                            ],
                          );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _manualSearchArea() {
    final controller = widget.controller;
    final theme = widget.theme;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: controller.exitManualSearchMode,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Regresar'),
            ),
            if (!controller.isManualSearchFormVisible)
              TextButton.icon(
                onPressed: controller.showManualSearchForm,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Editar búsqueda'),
              ),
            if (controller.isViewingSearchChosenCandidate)
              TextButton.icon(
                onPressed: controller.returnToSearchCandidates,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Regresar a coincidencias'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: controller.isManualSearchFormVisible
              ? Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: keyboardInset > 0 ? 10 : 0),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Búsqueda manual',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Escribe una consulta para buscar coincidencias en lrclib.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _queryController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => controller.searchLyricsManually(),
                            decoration: const InputDecoration(
                              labelText: 'Buscar (query)',
                              hintText: 'Ej. clandestino shakira',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed:
                                controller.isSearchingLyrics ? null : controller.searchLyricsManually,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MusicSearchIcon(size: 18),
                                SizedBox(width: 8),
                                Text('Buscar letra'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : controller.isChoosingSearchCandidate
                  ? _CandidatesList(
                      candidates: controller.searchCandidates,
                      onSelect: controller.selectSearchCandidate,
                    )
                  : LyricsPanel(
                      theme: theme,
                      lyrics: controller.searchLyrics,
                      songTitle: controller.songTitle,
                      artistName: controller.artistName,
                      showActionButtons: controller.hasActiveSearchLyrics,
                      onAssociateToSong: controller.canAssociateSelectedSearchLyrics
                          ? controller.associateSelectedSearchLyricsToCurrentSong
                          : null,
                      onCopyFeedbackVisibleChanged: _handleCopyFeedbackVisibility,
                      onTap: controller.retrySearchLyricsIfNeeded,
                      onScrollDirectionChanged: _handleLyricsScrollDirection,
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncSearchInputWithController();

    final controller = widget.controller;
    final theme = widget.theme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final hasActiveNowPlaying = controller.hasActiveNowPlaying;
    final canOpenMediaApps = controller.hasNotificationListenerAccess;
    _isLandscapeLayout = isLandscape;
    final currentNowPlayingKey =
        '${controller.songTitle.trim()}|${controller.artistName.trim()}';

    if (_lastNowPlayingKey != currentNowPlayingKey) {
      _lastNowPlayingKey = currentNowPlayingKey;
      _isNowPlayingHeaderVisible = true;
      _autoExpandVinylTimer?.cancel();
      _autoExpandPendingKey = null;
    }
    if (isLandscape) {
      _isNowPlayingHeaderVisible = true;
    }

    _handleAutoExpandOnManualPrompt(
      controller: controller,
      nowPlayingKey: currentNowPlayingKey,
    );

    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(bottom: _isCopyToastVisible ? 64 : 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      );
                      final scale = Tween<double>(begin: 0.94, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                      );

                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: _isVinylExpanded
                        ? KeyedSubtree(
                            key: const ValueKey('expanded_vinyl'),
                            child: _buildExpandedVinylArea(
                              isLandscape: isLandscape,
                              constraints: constraints,
                            ),
                          )
                        : isLandscape
                            ? KeyedSubtree(
                                key: const ValueKey('collapsed_landscape'),
                                child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: math.min(380, constraints.maxWidth * 0.40),
                              child: LayoutBuilder(
                                builder: (context, sideConstraints) {
                                  final artworkSize = math.min(
                                    380.0,
                                    math.max(250.0, sideConstraints.maxHeight * 0.58),
                                  );

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 12),
                                      AnimatedCrossFade(
                                        duration: const Duration(milliseconds: 220),
                                        firstCurve: Curves.easeOut,
                                        secondCurve: Curves.easeOut,
                                        sizeCurve: Curves.easeOut,
                                        crossFadeState: _isNowPlayingHeaderVisible
                                            ? CrossFadeState.showFirst
                                            : CrossFadeState.showSecond,
                                        firstChild: Column(
                                          children: [
                                            Center(
                                              child: _ArtworkCover(
                                                url: controller.nowPlayingArtworkUrl,
                                                size: artworkSize,
                                                isSpinning: controller.isNowPlayingPlaybackActive,
                                                onTap: _toggleVinylExpanded,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                        ),
                                        secondChild: const SizedBox.shrink(),
                                      ),
                                      Expanded(
                                        child: hasActiveNowPlaying && controller.isNowPlayingFromMediaPlayer
                                            ? Column(
                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                children: [
                                                  _buildPlayerControlsRow(),
                                                  _buildActivePlayerButton(),
                                                  if (controller.canShowManualSearchButton)
                                                    OutlinedButton.icon(
                                                      onPressed: _onSearchManuallyPressed,
                                                      icon: const MusicSearchIcon(size: 20),
                                                      label: const Text('Buscar manualmente'),
                                                    ),
                                                ],
                                              )
                                            : (hasActiveNowPlaying || canOpenMediaApps)
                                                ? Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    _buildPlatformButtonsRow(artistOnly: false),
                                                    const SizedBox(height: 10),
                                                    if (controller.canShowManualSearchButton)
                                                      OutlinedButton.icon(
                                                        onPressed: _onSearchManuallyPressed,
                                                        icon: const MusicSearchIcon(size: 20),
                                                        label: const Text('Buscar manualmente'),
                                                      ),
                                                  ],
                                                ),
                                              )
                                                : const SizedBox.shrink(),
                                      ),
                                      if (controller.isLoadingNowPlayingLyrics)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 12),
                                          child: LinearProgressIndicator(),
                                        ),
                                      if (controller.isSearchingLyrics)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 12),
                                          child: LinearProgressIndicator(),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: controller.isManualSearchMode
                                  ? _manualSearchArea()
                                  : LyricsPanel(
                                      theme: theme,
                                      lyrics: controller.nowPlayingLyrics,
                                      playbackPositionMs: controller.nowPlayingPlaybackPositionMs,
                                      songTitle: controller.songTitle,
                                      artistName: controller.artistName,
                                      onTimedLineTap: controller.seekNowPlayingTo,
                                      showActionButtons: controller.hasActiveNowPlayingLyrics,
                                      onCopyFeedbackVisibleChanged:
                                          _handleCopyFeedbackVisibility,
                                      onTap: controller.onNowPlayingLyricsTap,
                                      onScrollDirectionChanged: null,
                                    ),
                            ),
                          ],
                          ),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('collapsed_portrait'),
                                child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 220),
                              firstCurve: Curves.easeOut,
                              secondCurve: Curves.easeOut,
                              sizeCurve: Curves.easeOut,
                              crossFadeState: _isNowPlayingHeaderVisible
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              firstChild: Column(
                                children: [
                                  LayoutBuilder(
                                    builder: (context, headerConstraints) {
                                      final responsiveSize = math.min(
                                        210.0,
                                        math.max(150.0, headerConstraints.maxWidth * 0.56),
                                      );
                                      return Center(
                                        child: _ArtworkCover(
                                          url: controller.nowPlayingArtworkUrl,
                                          size: responsiveSize,
                                          isSpinning: controller.isNowPlayingPlaybackActive,
                                          onTap: _toggleVinylExpanded,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                              secondChild: const SizedBox.shrink(),
                            ),
                            if (hasActiveNowPlaying && controller.isNowPlayingFromMediaPlayer) ...[
                              _buildPlayerControlsRow(),
                              _buildActivePlayerButton(),
                            ] else if (hasActiveNowPlaying || canOpenMediaApps)
                              _buildPlatformButtonsRow(artistOnly: false),
                            const SizedBox(height: 10),
                            if (hasActiveNowPlaying && controller.canShowManualSearchButton)
                              Align(
                                alignment: Alignment.center,
                                child: OutlinedButton.icon(
                                  onPressed: _onSearchManuallyPressed,
                                  icon: const MusicSearchIcon(size: 20),
                                  label: const Text('Buscar manualmente'),
                                ),
                              ),
                            Expanded(
                              child: controller.isManualSearchMode
                                  ? _manualSearchArea()
                                  : LyricsPanel(
                                      theme: theme,
                                      lyrics: controller.nowPlayingLyrics,
                                      playbackPositionMs: controller.nowPlayingPlaybackPositionMs,
                                      songTitle: controller.songTitle,
                                      artistName: controller.artistName,
                                      onTimedLineTap: controller.seekNowPlayingTo,
                                      showActionButtons: controller.hasActiveNowPlayingLyrics,
                                      onCopyFeedbackVisibleChanged:
                                          _handleCopyFeedbackVisibility,
                                      onTap: controller.onNowPlayingLyricsTap,
                                      onScrollDirectionChanged: _handleLyricsScrollDirection,
                                    ),
                            ),
                            if (controller.isLoadingNowPlayingLyrics)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                            if (controller.isSearchingLyrics)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                          ],
                        ),
                              ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CandidatesList extends StatelessWidget {
  const _CandidatesList({
    required this.candidates,
    required this.onSelect,
  });

  final List<LyricsCandidate> candidates;
  final ValueChanged<LyricsCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Center(
        child: Text('No se encontraron coincidencias para elegir.'),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      child: ListView.separated(
        itemCount: candidates.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final candidate = candidates[index];
          return ListTile(
            title: Text(candidate.trackName),
            subtitle: Text(candidate.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelect(candidate),
          );
        },
      ),
    );
  }
}

class _ArtworkCover extends StatelessWidget {
  const _ArtworkCover({
    required this.url,
    this.size = 122,
    this.isSpinning = false,
    required this.onTap,
  });

  final String? url;
  final double size;
  final bool isSpinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vinylColor = theme.colorScheme.onSurface.withOpacity(0.88);
    final grooveColor = theme.colorScheme.onSurface.withOpacity(0.18);
    final labelColor = theme.colorScheme.surface.withOpacity(0.82);

    return Center(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(size),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size),
          child: _VinylSpinner(
            isSpinning: isSpinning,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: vinylColor,
                    ),
                  ),
                  Container(
                    width: size * 0.86,
                    height: size * 0.86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: grooveColor, width: 1.2),
                    ),
                  ),
                  Container(
                    width: size * 0.72,
                    height: size * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: grooveColor, width: 1.1),
                    ),
                  ),
                  Container(
                    width: size * 0.58,
                    height: size * 0.58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: grooveColor, width: 1.0),
                    ),
                  ),
                  ClipOval(
                    child: (url ?? '').trim().isNotEmpty
                        ? Image.network(
                            url!,
                            width: size * 0.64,
                            height: size * 0.64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              return Container(
                                width: size * 0.64,
                                height: size * 0.64,
                                color: theme.colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.album_rounded, size: 30),
                              );
                            },
                          )
                        : Container(
                            width: size * 0.64,
                            height: size * 0.64,
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.album_rounded, size: 30),
                          ),
                  ),
                  Container(
                    width: size * 0.1,
                    height: size * 0.1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VinylSpinner extends StatefulWidget {
  const _VinylSpinner({
    required this.child,
    required this.isSpinning,
  });

  final Widget child;
  final bool isSpinning;

  @override
  State<_VinylSpinner> createState() => _VinylSpinnerState();
}

class _VinylSpinnerState extends State<_VinylSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    if (widget.isSpinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _VinylSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSpinning == widget.isSpinning) {
      return;
    }

    if (widget.isSpinning) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
    );
  }
}
