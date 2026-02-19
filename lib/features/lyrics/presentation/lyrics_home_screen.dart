import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme_controller.dart';
import '../../../l10n/app_localizations.dart';
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
  static const String _useArtworkBackgroundPrefKey = 'use_artwork_background';
  bool _isPermissionDialogOpen = false;
  bool _hideHomeHeaderForExpandedVinyl = false;
  bool _useArtworkBackground = true;
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

  void _handleUseArtworkBackgroundChanged(bool enabled) {
    if (_useArtworkBackground == enabled) {
      return;
    }
    setState(() {
      _useArtworkBackground = enabled;
    });
    unawaited(_persistUseArtworkBackground(enabled));
  }

  Future<void> _loadAppearancePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool(_useArtworkBackgroundPrefKey);
    if (!mounted || savedValue == null || savedValue == _useArtworkBackground) {
      return;
    }
    setState(() {
      _useArtworkBackground = savedValue;
    });
  }

  Future<void> _persistUseArtworkBackground(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useArtworkBackgroundPrefKey, enabled);
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadAppearancePreferences());
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
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l10n.permissionNeededTitle),
            content: Text(l10n.permissionDialogMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.notNow),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _openPermissionSettings();
                },
                child: Text(l10n.goToPermissions),
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
        final l10n = AppLocalizations.of(context);
        final artworkUrl = widget.controller.nowPlayingArtworkUrl;
        _syncWakeLockWithPlayback(
          shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
        );

        return Scaffold(
          body: Stack(
            children: [
              if (_useArtworkBackground && (artworkUrl ?? '').isNotEmpty)
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
                              color: theme.colorScheme.surface.withValues(alpha: 0.58),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_useArtworkBackground)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                      ),
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
                          useArtworkBackground: _useArtworkBackground,
                          onUseArtworkBackgroundChanged: _handleUseArtworkBackgroundChanged,
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
                                    l10n.enableNotificationsCard,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _openPermissionSettings,
                                  child: Text(l10n.allow),
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
                          isDarkMode: widget.themeController.isDarkMode,
                          onToggleTheme: widget.themeController.toggleTheme,
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
