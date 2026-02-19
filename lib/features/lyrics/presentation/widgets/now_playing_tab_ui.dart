part of 'now_playing_tab.dart';

extension _NowPlayingTabUi on _NowPlayingTabState {
  Widget _buildPlatformButtonsRow({required bool artistOnly}) {
    final installed = widget.controller.installedMediaAppPackages;
    final l10n = AppLocalizations.of(context);
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
      packageName: _NowPlayingTabState._spotifyPackage,
      onPressed: artistOnly ? _openArtistInSpotify : _openInSpotify,
      icon: const FaIcon(FontAwesomeIcons.spotify),
      tooltip: l10n.spotifyLabel,
    );
    addButton(
      packageName: _NowPlayingTabState._youtubeMusicPackage,
      onPressed: artistOnly ? _openArtistInYouTubeMusic : _openInYouTubeMusic,
      icon: const FaIcon(FontAwesomeIcons.youtube),
      tooltip: l10n.youtubeMusicLabel,
    );
    addButton(
      packageName: _NowPlayingTabState._amazonMusicPackage,
      onPressed: artistOnly ? _openArtistInAmazonMusic : _openInAmazonMusic,
      icon: const FaIcon(FontAwesomeIcons.amazon),
      tooltip: l10n.amazonMusicLabel,
    );
    addButton(
      packageName: _NowPlayingTabState._appleMusicPackage,
      onPressed: artistOnly ? _openArtistInAppleMusic : _openInAppleMusic,
      icon: const FaIcon(FontAwesomeIcons.apple),
      tooltip: l10n.appleMusicLabel,
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
    final l10n = AppLocalizations.of(context);
    return IconButton(
      iconSize: iconSize,
      onPressed: controller.openActivePlayer,
      icon: FaIcon(
        _activePlayerIcon(packageName),
        size: iconSize,
      ),
      tooltip: l10n.openActivePlayer,
    );
  }

  Widget _buildPlayerControlsRow({
    double? iconSizeOverride,
    double spacing = 6,
  }) {
    final controller = widget.controller;
    final l10n = AppLocalizations.of(context);
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
          tooltip: l10n.previous,
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: controller.mediaPlayPause,
          iconSize: iconSize,
          splashRadius: iconSize * 0.8,
          icon: const Icon(Icons.play_arrow_rounded),
          tooltip: l10n.playPause,
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: controller.mediaNext,
          iconSize: iconSize,
          splashRadius: iconSize * 0.8,
          icon: const Icon(Icons.skip_next_rounded),
          tooltip: l10n.next,
        ),
      ],
    );
  }

  Widget _buildResumePausedPlaybackButton() {
    final controller = widget.controller;
    if (!controller.canResumePausedPlaybackAfterFavorite) {
      return const SizedBox.shrink();
    }

    final isSpanish = Localizations.localeOf(context).languageCode.toLowerCase() == 'es';
    final label = isSpanish ? 'Continuar reproducción' : 'Resume playback';
    return OutlinedButton.icon(
      onPressed: controller.resumePausedPlaybackAfterFavorite,
      icon: const Icon(Icons.play_circle_fill_rounded),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
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
              label: Text(AppLocalizations.of(context).back),
            ),
            if (!controller.isManualSearchFormVisible)
              TextButton.icon(
                onPressed: controller.showManualSearchForm,
                icon: const Icon(Icons.search_rounded),
                label: Text(AppLocalizations.of(context).editSearch),
              ),
            if (controller.isViewingSearchChosenCandidate)
              TextButton.icon(
                onPressed: controller.returnToSearchCandidates,
                icon: const Icon(Icons.undo_rounded),
                label: Text(AppLocalizations.of(context).backToMatches),
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
                            AppLocalizations.of(context).manualSearchTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.of(context).manualSearchDescription,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _queryController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => controller.searchLyricsManually(),
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).searchQueryLabel,
                              hintText: AppLocalizations.of(context).searchQueryHint,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed:
                                controller.isSearchingLyrics ? null : controller.searchLyricsManually,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const MusicSearchIcon(size: 18),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context).searchLyrics),
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
                      artworkUrl: controller.searchArtworkUrl ?? controller.nowPlayingArtworkUrl,
                      showActionButtons: controller.hasActiveSearchLyrics,
                      onAssociateToSong: controller.canAssociateSelectedSearchLyrics
                          ? controller.associateSelectedSearchLyricsToCurrentSong
                          : null,
                      onCopyFeedbackVisibleChanged: _handleCopyFeedbackVisibility,
                      onSnapshotSavedToGallery: widget.onSnapshotSavedToGallery,
                      onTap: controller.retrySearchLyricsIfNeeded,
                      onScrollDirectionChanged: _handleLyricsScrollDirection,
                    ),
        ),
      ],
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
      return Center(
        child: Text(AppLocalizations.of(context).noMatchesToChoose),
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
        .withValues(alpha: isDark ? 0.10 : 0.14);
    final separatorColor =
        isDark ? Colors.white.withValues(alpha: 0.78) : Colors.black.withValues(alpha: 0.68);
    final centerLabelColor =
        Color.lerp(theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest, 0.55)!;
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
                              Colors.white.withValues(alpha: isDark ? 0.20 : 0.16),
                              Colors.white.withValues(alpha: 0.04),
                              Colors.transparent,
                              Colors.black.withValues(alpha: isDark ? 0.18 : 0.10),
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
                        ? Transform.rotate(
                            angle: 0,
                            child: Image.network(
                              url!,
                              width: centerArtworkSize,
                              height: centerArtworkSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return ClipOval(
                                  child: Image.asset(
                                    'assets/app_icon/singsync.png',
                                    width: centerArtworkSize,
                                    height: centerArtworkSize,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),
                          )
                        : centerIcon != null
                            ? Container(
                                width: centerArtworkSize,
                                height: centerArtworkSize,
                                color: centerLabelColor,
                                alignment: Alignment.center,
                                child: Icon(
                                  centerIcon,
                                  size: size * 0.26,
                                  color: theme.colorScheme.onSurface,
                                ),
                              )
                            : ClipOval(
                                child: Image.asset(
                                  'assets/app_icon/singsync.png',
                                  width: centerArtworkSize,
                                  height: centerArtworkSize,
                                  fit: BoxFit.cover,
                                ),
                              ),
                  ),
                  Container(
                    width: size * 0.072,
                    height: size * 0.072,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: size * 0.026,
                        height: size * 0.026,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
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
    const tracks = 24;

    for (var index = 0; index < tracks; index++) {
      final t = index / (tracks - 1);
      final radius = ui.lerpDouble(minRadius, maxRadius * 0.97, t)!;
      final opacity = 0.12 + (0.10 * (1 - t));
      final stroke = 0.8 + (0.35 * (1 - t));

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = grooveColor.withValues(alpha: opacity);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) {
    return oldDelegate.grooveColor != grooveColor;
  }
}
