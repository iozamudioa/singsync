import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme_controller.dart';
import 'lyrics_controller.dart';
import 'widgets/home_header.dart';
import 'widgets/now_playing_tab.dart';

class LyricsHomeScreen extends StatefulWidget {
  const LyricsHomeScreen({
    super.key,
    required this.themeController,
    required this.controller,
  });

  final ThemeController themeController;
  final LyricsController controller;

  @override
  State<LyricsHomeScreen> createState() => _LyricsHomeScreenState();
}

class _LyricsHomeScreenState extends State<LyricsHomeScreen> with WidgetsBindingObserver {
  bool _isPermissionDialogOpen = false;
  bool _hideHomeHeaderForExpandedVinyl = false;
  bool? _lastWakeLockDesired;

  void _syncWakeLockWithPlayback({required bool shouldKeepAwake}) {
    if (_lastWakeLockDesired == shouldKeepAwake) {
      return;
    }
    _lastWakeLockDesired = shouldKeepAwake;
    unawaited(shouldKeepAwake ? WakelockPlus.enable() : WakelockPlus.disable());
  }

  void _handleExpandedLandscapeModeChanged(bool isExpandedLandscapeMode) {
    if (_hideHomeHeaderForExpandedVinyl == isExpandedLandscapeMode) {
      return;
    }
    setState(() {
      _hideHomeHeaderForExpandedVinyl = isExpandedLandscapeMode;
    });
  }

  void _schedulePermissionCheck({Duration delay = const Duration(milliseconds: 350)}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(delay, () {
        if (!mounted) {
          return;
        }
        _checkAndShowPermissionDialog();
      });
    });
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
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.28),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) {
        final theme = Theme.of(context);
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.36,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return ClipRRect(
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
                      SingleChildScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.network(
                                  artworkUrl,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      width: 220,
                                      height: 220,
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
                            if (songTitle.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                songTitle,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 14),
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

                                if (genre.isEmpty && country.isEmpty && shortBio.isEmpty) {
                                  return Text(
                                    'No hay más datos del artista por ahora.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
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
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncWakeLockWithPlayback(
      shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
    );
    _schedulePermissionCheck();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncWakeLockWithPlayback(
        shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
      );
      _schedulePermissionCheck(delay: const Duration(milliseconds: 450));
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      WakelockPlus.disable();
    }
  }

  Future<void> _openPermissionSettings() async {
    await widget.controller.openNotificationListenerSettings();
  }

  Future<void> _checkAndShowPermissionDialog() async {
    await widget.controller.refreshNotificationPermissionStatus();
    if (!mounted || widget.controller.hasNotificationListenerAccess || _isPermissionDialogOpen) {
      return;
    }

    _isPermissionDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Permiso necesario'),
            content: const Text(
              'SingSync necesita acceso a notificaciones para detectar la canción actual y buscar su letra automáticamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _openPermissionSettings();
                },
                child: const Text('Ir a permisos'),
              ),
            ],
          );
        },
      );
    } finally {
      _isPermissionDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.themeController, widget.controller]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final artworkUrl = widget.controller.nowPlayingArtworkUrl;
        _syncWakeLockWithPlayback(
          shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
        );

        return Scaffold(
          body: Stack(
            children: [
              if ((artworkUrl ?? '').isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.30,
                            child: ClipRect(
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Image.network(
                                  artworkUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withOpacity(0.58),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_hideHomeHeaderForExpandedVinyl)
                        HomeHeader(
                          theme: theme,
                          songTitle: widget.controller.songTitle,
                          artistName: widget.controller.artistName,
                          isDarkMode: widget.themeController.isDarkMode,
                          onToggleTheme: widget.themeController.toggleTheme,
                          onHeaderTap: _showArtistInfoModal,
                        ),
                      if (!widget.controller.hasNotificationListenerAccess) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.notifications_active_outlined,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Activa acceso a notificaciones para detectar canciones.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _openPermissionSettings,
                                  child: const Text('Permitir'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Expanded(
                        child: NowPlayingTab(
                          controller: widget.controller,
                          theme: theme,
                          onSearchManually: widget.controller.startManualCandidatesFromNowPlaying,
                          onExpandedLandscapeModeChanged: _handleExpandedLandscapeModeChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
