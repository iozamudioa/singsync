part of 'now_playing_tab.dart';

extension _NowPlayingTabModes on _NowPlayingTabState {
  Widget _buildExpandedVinylArea({required bool isLandscape, required BoxConstraints constraints}) {
    final controller = widget.controller;
    final theme = widget.theme;
    final l10n = AppLocalizations.of(context);
    final artworkUrl = controller.isAdLikeNowPlaying ? null : controller.nowPlayingArtworkUrl;
    final hasActiveNowPlaying = controller.hasActiveNowPlaying;
    final canOpenMediaApps = controller.hasNotificationListenerAccess;
    final adSourceIcon = controller.isAdLikeNowPlaying
        ? _activePlayerIcon(controller.nowPlayingSourcePackage ?? controller.preferredMediaAppPackage)
        : null;

    final viewPadding = MediaQuery.of(context).viewPadding;
    final insetDelta = viewPadding.right - viewPadding.left;
    final landscapeOpticalDx = isLandscape ? (insetDelta * 0.9).clamp(-36.0, 36.0) : 0.0;

    final size = isLandscape
        ? math.min(360.0, math.max(220.0, constraints.maxHeight * 0.72))
        : math.min(380.0, math.max(220.0, constraints.maxWidth * 0.86));
    final collapsedSizeEstimate = isLandscape
        ? math.min(420.0, math.max(280.0, constraints.maxHeight * 0.66))
        : math.min(250.0, math.max(180.0, constraints.maxWidth * 0.64));
    final startDx = isLandscape ? -constraints.maxWidth * 0.18 : 0.0;
    final startDy = isLandscape ? -constraints.maxHeight * 0.06 : -constraints.maxHeight * 0.21;
    final displayTitle = controller.songTitle.trim().isEmpty
        ? l10n.nowPlayingDefaultTitle
        : controller.songTitle.trim();
    final displayArtist = controller.artistName.trim().isEmpty
        ? l10n.unknownArtist
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
                  tooltip: l10n.previous,
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: controller.mediaPlayPause,
                  icon: const Icon(Icons.play_arrow_rounded),
                  iconSize: iconSize + 4,
                  tooltip: l10n.playPause,
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: controller.mediaNext,
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: iconSize,
                  tooltip: l10n.next,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildActivePlayerButton(iconSize: iconSize - 2),
          ],
        );
      }

      if (hasActiveNowPlaying || canOpenMediaApps) {
        final shortestSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final iconSize = shortestSide >= 700 ? 40.0 : 34.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlatformButtonsRow(artistOnly: false),
            if (controller.canShowManualSearchButton) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _onSearchManuallyPressed,
                icon: const MusicSearchIcon(size: 18),
                label: Text(l10n.searchManually),
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
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.96),
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
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
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
                          bottom: 0,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: buildRightControlsColumn(),
                            ),
                          ),
                        ),
                        if (isLandscape)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: IconButton(
                              style: _snapshotActionButtonStyle(theme),
                              onPressed: _shareBasicSnapshotFromExpanded,
                              tooltip: l10n.shareSnapshot,
                              icon: const Icon(Icons.photo_camera_outlined),
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
}
