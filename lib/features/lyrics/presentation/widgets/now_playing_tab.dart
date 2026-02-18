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
    this.onExpandedLandscapeModeChanged,
  });

  final LyricsController controller;
  final ThemeData theme;
  final VoidCallback onSearchManually;
  final ValueChanged<bool>? onExpandedLandscapeModeChanged;

  @override
  State<NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends State<NowPlayingTab> with TickerProviderStateMixin {
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
  late final AnimationController _vinylSpinController;
  late final AnimationController _seekNudgeController;
  late Animation<double> _seekNudgeTurns;
  double _seekCarryTurns = 0;
  double _seekNudgeTargetTurns = 0;
  bool _isVinylScrubbing = false;
  bool _isVinylTouchActive = false;
  double _touchSeekTurns = 0;
  double _scrubStartCarryTurns = 0;
  int _scrubStartPositionMs = 0;
  int _scrubPreviewPositionMs = 0;
  int _lastScrubSeekDispatchAtMs = 0;
  int? _lastScrubSeekDispatchedPositionMs;

  static const double _dragSeekMsPerTurn = 45000;
  static const int _dragSeekDispatchIntervalMs = 120;
  static const int _dragSeekMinPositionDeltaMs = 500;
  Timer? _autoExpandVinylTimer;
  String? _autoExpandPendingKey;
  String? _autoExpandedForKey;
  bool? _lastExpandedLandscapeModeReported;

  @override
  void initState() {
    super.initState();
    _vinylSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _seekNudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _seekNudgeTurns = const AlwaysStoppedAnimation<double>(0);
    _seekNudgeController.addStatusListener((status) {
      if (!mounted || status != AnimationStatus.completed) {
        return;
      }
      setState(() {
        _seekCarryTurns = (_seekCarryTurns + _seekNudgeTargetTurns) % 1.0;
        _seekNudgeTargetTurns = 0;
        _seekNudgeTurns = const AlwaysStoppedAnimation<double>(0);
      });
    });
    _queryController = TextEditingController(text: widget.controller.searchQuery)
      ..addListener(() {
        widget.controller.updateSearchQuery(_queryController.text);
      });
  }

  @override
  void dispose() {
    widget.onExpandedLandscapeModeChanged?.call(false);
    _autoExpandVinylTimer?.cancel();
    _seekNudgeController.dispose();
    _vinylSpinController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _syncVinylSpinState(bool shouldSpin) {
    if (_isVinylScrubbing) {
      if (_vinylSpinController.isAnimating) {
        _vinylSpinController.stop();
      }
      return;
    }

    if (shouldSpin) {
      if (!_vinylSpinController.isAnimating) {
        _vinylSpinController.repeat();
      }
      return;
    }

    if (_vinylSpinController.isAnimating) {
      _vinylSpinController.stop();
    }
  }

  bool get _canScrubVinyl {
    final controller = widget.controller;
    return controller.isNowPlayingFromMediaPlayer && controller.hasActiveNowPlaying;
  }

  void _onVinylScrubStart() {
    if (!_canScrubVinyl) {
      return;
    }

    _seekNudgeController.stop();
    _seekNudgeTargetTurns = 0;
    _seekNudgeTurns = const AlwaysStoppedAnimation<double>(0);
    _touchSeekTurns = 0;
    _scrubStartCarryTurns = _seekCarryTurns;
    _scrubStartPositionMs = widget.controller.nowPlayingPlaybackPositionMs;
    _scrubPreviewPositionMs = _scrubStartPositionMs;
    _lastScrubSeekDispatchAtMs = 0;
    _lastScrubSeekDispatchedPositionMs = null;

    if (!_isVinylScrubbing) {
      setState(() {
        _isVinylScrubbing = true;
      });
    }
  }

  Future<void> _onVinylScrubUpdate(double deltaTurns) async {
    if (!_isVinylScrubbing || !_canScrubVinyl) {
      return;
    }

    _touchSeekTurns += deltaTurns;
    final offsetMs = (_touchSeekTurns * _dragSeekMsPerTurn).round();
    final candidateMs = (_scrubStartPositionMs + offsetMs).clamp(0, 1 << 31).toInt();
    _scrubPreviewPositionMs = candidateMs;

    setState(() {
      _seekCarryTurns = (_scrubStartCarryTurns + _touchSeekTurns) % 1.0;
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    final enoughTime = now - _lastScrubSeekDispatchAtMs >= _dragSeekDispatchIntervalMs;
    final previous = _lastScrubSeekDispatchedPositionMs;
    final enoughDelta =
        previous == null || (candidateMs - previous).abs() >= _dragSeekMinPositionDeltaMs;
    if (!enoughTime || !enoughDelta) {
      return;
    }

    _lastScrubSeekDispatchAtMs = now;
    _lastScrubSeekDispatchedPositionMs = candidateMs;
    await widget.controller.seekNowPlayingTo(candidateMs);
  }

  Future<void> _onVinylScrubEnd() async {
    if (!_isVinylScrubbing || !_canScrubVinyl) {
      return;
    }

    final targetMs = _scrubPreviewPositionMs;
    setState(() {
      _isVinylScrubbing = false;
    });
    await widget.controller.seekNowPlayingTo(targetMs);
  }

  void _onVinylTouchActiveChanged(bool isActive) {
    if (_isVinylTouchActive == isActive) {
      return;
    }
    setState(() {
      _isVinylTouchActive = isActive;
    });
  }

  void _animateVinylSeekNudge({
    required int fromMs,
    required int toMs,
  }) {
    final deltaMs = toMs - fromMs;
    if (deltaMs == 0) {
      return;
    }

    final normalized = (deltaMs.abs() / 14000).clamp(0.10, 0.24);
    final direction = deltaMs > 0 ? 1.0 : -1.0;
    final targetTurns = normalized * direction;
    _seekNudgeTargetTurns = targetTurns;

    _seekNudgeController.stop();
    _seekNudgeController.duration = const Duration(milliseconds: 220);
    setState(() {
      _seekNudgeTurns = Tween<double>(
        begin: 0,
        end: targetTurns,
      ).animate(CurvedAnimation(
        parent: _seekNudgeController,
        curve: Curves.easeOutCubic,
      ));
    });
    _seekNudgeController.forward(from: 0);
  }

  void _onNowPlayingTimedLineTap(int targetMs) {
    final currentMs = widget.controller.nowPlayingPlaybackPositionMs;
    _animateVinylSeekNudge(fromMs: currentMs, toMs: targetMs);
    widget.controller.seekNowPlayingTo(targetMs);
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
    final theme = widget.theme;
    final artworkUrl = controller.isAdLikeNowPlaying ? null : controller.nowPlayingArtworkUrl;
    final hasActiveNowPlaying = controller.hasActiveNowPlaying;
    final canOpenMediaApps = controller.hasNotificationListenerAccess;
    final adSourceIcon = controller.isAdLikeNowPlaying
        ? _activePlayerIcon(controller.nowPlayingSourcePackage ?? controller.preferredMediaAppPackage)
        : null;

    final viewPadding = MediaQuery.of(context).viewPadding;
    final insetDelta = viewPadding.right - viewPadding.left;
    final landscapeOpticalDx = isLandscape
      ? (insetDelta * 0.9).clamp(-36.0, 36.0)
      : 0.0;

    final size = isLandscape
        ? math.min(360.0, math.max(220.0, constraints.maxHeight * 0.72))
        : math.min(380.0, math.max(220.0, constraints.maxWidth * 0.86));
    final collapsedSizeEstimate = isLandscape
      ? math.min(420.0, math.max(280.0, constraints.maxHeight * 0.66))
      : math.min(250.0, math.max(180.0, constraints.maxWidth * 0.64));
    final startDx = isLandscape ? -constraints.maxWidth * 0.18 : 0.0;
    final startDy = isLandscape ? -constraints.maxHeight * 0.06 : -constraints.maxHeight * 0.21;
    final displayTitle = controller.songTitle.trim().isEmpty
      ? 'Now Playing'
      : controller.songTitle.trim();
    final displayArtist = controller.artistName.trim().isEmpty
      ? 'Artista desconocido'
      : controller.artistName.trim();

    Widget buildRightControlsColumn() {
      if (hasActiveNowPlaying && controller.isNowPlayingFromMediaPlayer) {
        final shortestSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final iconSize = shortestSide >= 700 ? 42.0 : 36.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: controller.mediaPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                  iconSize: iconSize,
                  tooltip: 'Anterior',
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: controller.mediaPlayPause,
                  icon: const Icon(Icons.play_arrow_rounded),
                  iconSize: iconSize + 4,
                  tooltip: 'Play/Pause',
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: controller.mediaNext,
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: iconSize,
                  tooltip: 'Siguiente',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildActivePlayerButton(),
            if (controller.canShowManualSearchButton) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _onSearchManuallyPressed,
                icon: const MusicSearchIcon(size: 18),
                label: const Text('Buscar manualmente'),
              ),
            ],
          ],
        );
      }

      if (hasActiveNowPlaying || canOpenMediaApps) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlatformButtonsRow(artistOnly: false),
            if (controller.canShowManualSearchButton) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _onSearchManuallyPressed,
                icon: const MusicSearchIcon(size: 18),
                label: const Text('Buscar manualmente'),
              ),
            ],
          ],
        );
      }

      return const SizedBox.shrink();
    }

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
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, progress, _) {
                  final animatedSize = ui.lerpDouble(collapsedSizeEstimate, size, progress)!;

                  if (!isLandscape) {
                    return Transform.translate(
                      offset: Offset(startDx * (1 - progress), startDy * (1 - progress)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ArtworkCover(
                            url: artworkUrl,
                            size: animatedSize,
                            isSpinning: controller.isNowPlayingPlaybackActive,
                            spinAnimation: _vinylSpinController,
                            seekOffsetTurns: _seekNudgeTurns,
                            seekCarryTurns: _seekCarryTurns,
                            canScrub: _canScrubVinyl,
                            onTouchActiveChanged: _onVinylTouchActiveChanged,
                            onScrubStart: _onVinylScrubStart,
                            onScrubUpdate: _onVinylScrubUpdate,
                            onScrubEnd: _onVinylScrubEnd,
                            centerIcon: adSourceIcon,
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
                    );
                  }

                  final maxVinylSizeByWidth = (constraints.maxWidth * 0.95).clamp(220.0, 980.0);
                  final maxVinylSizeByHeight = (constraints.maxHeight * 0.92).clamp(220.0, 980.0);
                  final landscapeTargetSize = math.min(maxVinylSizeByWidth, maxVinylSizeByHeight);
                  final landscapeAnimatedSize = ui.lerpDouble(
                    collapsedSizeEstimate,
                    landscapeTargetSize,
                    progress,
                  )!;

                  return Transform.translate(
                    offset: Offset(startDx * (1 - progress), startDy * (1 - progress)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: _ArtworkCover(
                            url: artworkUrl,
                            size: landscapeAnimatedSize,
                            isSpinning: controller.isNowPlayingPlaybackActive,
                            spinAnimation: _vinylSpinController,
                            seekOffsetTurns: _seekNudgeTurns,
                            seekCarryTurns: _seekCarryTurns,
                            canScrub: _canScrubVinyl,
                            onTouchActiveChanged: _onVinylTouchActiveChanged,
                            onScrubStart: _onVinylScrubStart,
                            onScrubUpdate: _onVinylScrubUpdate,
                            onScrubEnd: _onVinylScrubEnd,
                            centerIcon: adSourceIcon,
                            onTap: _toggleVinylExpanded,
                          ),
                        ),
                        Positioned(
                          left: 10,
                          top: 0,
                          bottom: 56,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: math.min(260.0, math.max(140.0, constraints.maxWidth * 0.22)),
                              child: IgnorePointer(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: theme.colorScheme.onSurface.withOpacity(0.96),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      displayArtist,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface.withOpacity(0.78),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 56,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: buildRightControlsColumn(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
    final isExpandedLandscapeMode = isLandscape && _isVinylExpanded;
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
      _vinylSpinController.value = 0;
    }
    if (isLandscape) {
      _isNowPlayingHeaderVisible = true;
    }

    if (_lastExpandedLandscapeModeReported != isExpandedLandscapeMode) {
      _lastExpandedLandscapeModeReported = isExpandedLandscapeMode;
      widget.onExpandedLandscapeModeChanged?.call(isExpandedLandscapeMode);
    }

    _syncVinylSpinState(controller.isNowPlayingPlaybackActive);
    _handleAutoExpandOnManualPrompt(
      controller: controller,
      nowPlayingKey: currentNowPlayingKey,
    );

    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            physics: (_isVinylTouchActive || _isVinylScrubbing)
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(bottom: _isCopyToastVisible ? 64 : 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return currentChild ?? const SizedBox.shrink();
                    },
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final scale = Tween<double>(begin: 0.92, end: 1.0).animate(curved);
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.025),
                        end: Offset.zero,
                      ).animate(curved);

                      return SlideTransition(
                        position: slide,
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
                              width: math.min(420, constraints.maxWidth * 0.46),
                              child: LayoutBuilder(
                                builder: (context, sideConstraints) {
                                  final artworkSize = math.min(
                                    420.0,
                                    math.max(280.0, sideConstraints.maxHeight * 0.66),
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
                                                url: controller.isAdLikeNowPlaying
                                                    ? null
                                                    : controller.nowPlayingArtworkUrl,
                                                size: artworkSize,
                                                isSpinning: controller.isNowPlayingPlaybackActive,
                                                spinAnimation: _vinylSpinController,
                                                seekOffsetTurns: _seekNudgeTurns,
                                                seekCarryTurns: _seekCarryTurns,
                                                canScrub: _canScrubVinyl,
                                                onTouchActiveChanged: _onVinylTouchActiveChanged,
                                                onScrubStart: _onVinylScrubStart,
                                                onScrubUpdate: _onVinylScrubUpdate,
                                                onScrubEnd: _onVinylScrubEnd,
                                                centerIcon: controller.isAdLikeNowPlaying
                                                    ? _activePlayerIcon(
                                                        controller.nowPlayingSourcePackage ??
                                                            controller.preferredMediaAppPackage,
                                                      )
                                                    : null,
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
                                        onTimedLineTap: _onNowPlayingTimedLineTap,
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
                                        250.0,
                                        math.max(180.0, headerConstraints.maxWidth * 0.64),
                                      );
                                      return Center(
                                        child: _ArtworkCover(
                                          url: controller.isAdLikeNowPlaying
                                              ? null
                                              : controller.nowPlayingArtworkUrl,
                                          size: responsiveSize,
                                          isSpinning: controller.isNowPlayingPlaybackActive,
                                          spinAnimation: _vinylSpinController,
                                          seekOffsetTurns: _seekNudgeTurns,
                                          seekCarryTurns: _seekCarryTurns,
                                          canScrub: _canScrubVinyl,
                                          onTouchActiveChanged: _onVinylTouchActiveChanged,
                                          onScrubStart: _onVinylScrubStart,
                                          onScrubUpdate: _onVinylScrubUpdate,
                                          onScrubEnd: _onVinylScrubEnd,
                                          centerIcon: controller.isAdLikeNowPlaying
                                              ? _activePlayerIcon(
                                                  controller.nowPlayingSourcePackage ??
                                                      controller.preferredMediaAppPackage,
                                                )
                                              : null,
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
                                        onTimedLineTap: _onNowPlayingTimedLineTap,
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
    required this.spinAnimation,
    required this.seekOffsetTurns,
    required this.seekCarryTurns,
    required this.canScrub,
    required this.onTouchActiveChanged,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    this.centerIcon,
    this.size = 122,
    this.isSpinning = false,
    required this.onTap,
  });

  final String? url;
  final Animation<double> spinAnimation;
  final Animation<double> seekOffsetTurns;
  final double seekCarryTurns;
  final bool canScrub;
  final ValueChanged<bool> onTouchActiveChanged;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final Future<void> Function() onScrubEnd;
  final IconData? centerIcon;
  final double size;
  final bool isSpinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vinylBaseColor = Color.lerp(Colors.black, theme.colorScheme.onSurface, 0.12)!;
    final grooveColor = Color.lerp(Colors.white, theme.colorScheme.onSurface, 0.35)!
        .withOpacity(isDark ? 0.10 : 0.14);
    final separatorColor = isDark ? Colors.white.withOpacity(0.78) : Colors.black.withOpacity(0.68);
    final centerLabelColor = Color.lerp(theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest, 0.55)!;
    final centerArtworkSize = size * 0.50;
    final separatorOuterSize = size * 0.56;

    return Center(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(size),
        child: _VinylGestureSurface(
          size: size,
          canScrub: canScrub,
          onTap: onTap,
          onTouchActiveChanged: onTouchActiveChanged,
          onScrubStart: onScrubStart,
          onScrubUpdate: onScrubUpdate,
          onScrubEnd: onScrubEnd,
          child: AnimatedBuilder(
            animation: Listenable.merge([spinAnimation, seekOffsetTurns]),
            builder: (context, child) {
              return Transform.rotate(
                angle: (spinAnimation.value + seekCarryTurns + seekOffsetTurns.value) * 2 * math.pi,
                child: child,
              );
            },
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
                      color: vinylBaseColor,
                    ),
                  ),
                  CustomPaint(
                    size: Size.square(size),
                    painter: _VinylGroovesPainter(
                      grooveColor: grooveColor,
                    ),
                  ),
                  Positioned.fill(
                    child: ClipOval(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(isDark ? 0.20 : 0.16),
                              Colors.white.withOpacity(0.04),
                              Colors.transparent,
                              Colors.black.withOpacity(isDark ? 0.18 : 0.10),
                            ],
                            stops: const [0.0, 0.24, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: separatorOuterSize,
                    height: separatorOuterSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: separatorColor,
                        width: math.max(1.6, size * 0.014),
                      ),
                    ),
                  ),
                  ClipOval(
                    child: (url ?? '').trim().isNotEmpty
                        ? Image.network(
                            url!,
                            width: centerArtworkSize,
                            height: centerArtworkSize,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              return Container(
                                width: centerArtworkSize,
                                height: centerArtworkSize,
                                color: centerLabelColor,
                                alignment: Alignment.center,
                                child: const Icon(Icons.album_rounded, size: 30),
                              );
                            },
                          )
                        : Container(
                            width: centerArtworkSize,
                            height: centerArtworkSize,
                            color: centerLabelColor,
                            alignment: Alignment.center,
                            child: centerIcon != null
                                ? Icon(
                                    centerIcon,
                                    size: size * 0.26,
                                    color: theme.colorScheme.onSurface,
                                  )
                                : const Icon(Icons.album_rounded, size: 30),
                          ),
                  ),
                  Container(
                    width: size * 0.072,
                    height: size * 0.072,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: size * 0.026,
                        height: size * 0.026,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
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

class _VinylGestureSurface extends StatefulWidget {
  const _VinylGestureSurface({
    required this.size,
    required this.canScrub,
    required this.onTap,
    required this.onTouchActiveChanged,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.child,
  });

  final double size;
  final bool canScrub;
  final VoidCallback onTap;
  final ValueChanged<bool> onTouchActiveChanged;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final Future<void> Function() onScrubEnd;
  final Widget child;

  @override
  State<_VinylGestureSurface> createState() => _VinylGestureSurfaceState();
}

class _VinylGestureSurfaceState extends State<_VinylGestureSurface> {
  bool _isScrubbing = false;
  double? _lastAngle;

  double _angleFromPoint(Offset localPoint) {
    final center = Offset(widget.size / 2, widget.size / 2);
    return math.atan2(localPoint.dy - center.dy, localPoint.dx - center.dx);
  }

  double _normalizeDelta(double delta) {
    if (delta > math.pi) {
      return delta - (2 * math.pi);
    }
    if (delta < -math.pi) {
      return delta + (2 * math.pi);
    }
    return delta;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => widget.onTouchActiveChanged(true),
      onPointerUp: (_) => widget.onTouchActiveChanged(false),
      onPointerCancel: (_) => widget.onTouchActiveChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: widget.canScrub
            ? (details) {
                _isScrubbing = true;
                _lastAngle = _angleFromPoint(details.localPosition);
                widget.onScrubStart();
              }
            : null,
        onPanUpdate: widget.canScrub
            ? (details) {
                if (!_isScrubbing) {
                  return;
                }
                final nextAngle = _angleFromPoint(details.localPosition);
                final previousAngle = _lastAngle;
                _lastAngle = nextAngle;
                if (previousAngle == null) {
                  return;
                }
                final delta = _normalizeDelta(nextAngle - previousAngle);
                widget.onScrubUpdate(delta / (2 * math.pi));
              }
            : null,
        onPanEnd: widget.canScrub
            ? (_) {
                if (!_isScrubbing) {
                  return;
                }
                _isScrubbing = false;
                _lastAngle = null;
                widget.onTouchActiveChanged(false);
                unawaited(widget.onScrubEnd());
              }
            : null,
        onPanCancel: widget.canScrub
            ? () {
                if (!_isScrubbing) {
                  return;
                }
                _isScrubbing = false;
                _lastAngle = null;
                widget.onTouchActiveChanged(false);
                unawaited(widget.onScrubEnd());
              }
            : null,
        child: widget.child,
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  const _VinylGroovesPainter({
    required this.grooveColor,
  });

  final Color grooveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    final minRadius = maxRadius * 0.37;
    final tracks = 24;

    for (var index = 0; index < tracks; index++) {
      final t = index / (tracks - 1);
      final radius = ui.lerpDouble(minRadius, maxRadius * 0.97, t)!;
      final opacity = 0.12 + (0.10 * (1 - t));
      final stroke = 0.8 + (0.35 * (1 - t));

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = grooveColor.withOpacity(opacity);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) {
    return oldDelegate.grooveColor != grooveColor;
  }
}
