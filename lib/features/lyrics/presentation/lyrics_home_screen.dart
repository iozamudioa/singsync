import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme_controller.dart';
import '../../../l10n/app_localizations.dart';
import 'lyrics_controller.dart';
import 'widgets/app_top_feedback.dart';
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
  static const int _initialCarouselPage = 10000;
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.lyric_notifier/lyrics',
  );
  bool _isPermissionDialogOpen = false;
  bool _hideHomeHeaderForExpandedVinyl = false;
  bool _useArtworkBackground = true;
  bool? _lastWakeLockDesired;
  late final PageController _homePageController;
  final Map<String, Future<Uint8List?>> _snapshotBytesFutureByUri = <String, Future<Uint8List?>>{};
  List<String> _savedSnapshotUris = const <String>[];
  bool _isLoadingSavedSnapshots = false;

  Future<void> _animateToGalleryPage() async {
    if (!_homePageController.hasClients) {
      return;
    }

    final currentIndex = (_homePageController.page ?? _homePageController.initialPage.toDouble()).round();
    final targetIndex = currentIndex + 1;
    if (targetIndex != currentIndex) {
      await _homePageController.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    await _loadSavedSnapshots(force: true);
  }

  Future<void> _handleSnapshotSavedToGallery() async {
    await _animateToGalleryPage();
  }

  void _syncWakeLockWithPlayback({
    required bool shouldKeepAwake,
    bool force = false,
  }) {
    if (!force && _lastWakeLockDesired == shouldKeepAwake) {
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

  Future<void> _toggleCurrentFavorite() async {
    final toggledToFavorite = await widget.controller.toggleCurrentFavorite();
    if (!mounted || toggledToFavorite == null) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    AppTopFeedback.show(
      context,
      toggledToFavorite
          ? l10n.favoriteAdded
          : l10n.favoriteRemoved,
    );
  }

  void _openFavoritesLibraryModal() {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: screenSize.width,
        maxHeight: screenSize.height * (isLandscape ? 0.90 : 0.82),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final favorites = widget.controller.favoriteLibrary;
            if (favorites.isEmpty) {
              return SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    l10n.noFavoritesYet,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              );
            }

            return SafeArea(
              child: ListView.separated(
                itemCount: favorites.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = favorites[index];
                  return Dismissible(
                    key: ValueKey('favorite_${item.key}_${item.createdAtMs}'),
                    direction: DismissDirection.horizontal,
                    background: Container(
                      color: theme.colorScheme.errorContainer,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    secondaryBackground: Container(
                      color: theme.colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    onDismissed: (_) async {
                      final removed = await widget.controller.removeFavoriteEntry(item);
                      if (!removed || !mounted) {
                        return;
                      }
                      AppTopFeedback.show(
                        this.context,
                        AppLocalizations.of(this.context).favoriteDeleted,
                        duration: const Duration(milliseconds: 1300),
                      );
                    },
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (item.artworkUrl ?? '').trim().isEmpty
                            ? const SizedBox(
                                width: 42,
                                height: 42,
                                child: ColoredBox(color: Colors.black12),
                              )
                            : Image.network(
                                item.artworkUrl!,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: ColoredBox(color: Colors.black12),
                                ),
                              ),
                      ),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await widget.controller.showFavoriteInNowPlaying(item);
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _homePageController = PageController(initialPage: _initialCarouselPage);
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
    _homePageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSavedSnapshots({bool force = false}) async {
    if (_isLoadingSavedSnapshots) {
      return;
    }
    if (!force && _savedSnapshotUris.isNotEmpty) {
      return;
    }

    setState(() {
      _isLoadingSavedSnapshots = true;
    });

    try {
      final raw = await _lyricsMethodsChannel.invokeMethod<dynamic>('listSavedSnapshots');
      final uris = <String>[];
      if (raw is List) {
        for (final entry in raw) {
          final value = (entry ?? '').toString().trim();
          if (value.isNotEmpty) {
            uris.add(value);
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _savedSnapshotUris = uris;
        final updatedCache = <String, Future<Uint8List?>>{};
        for (final uri in uris) {
          updatedCache[uri] = _snapshotBytesFutureByUri[uri] ?? _readSnapshotImageBytes(uri);
        }
        _snapshotBytesFutureByUri
          ..clear()
          ..addAll(updatedCache);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savedSnapshotUris = const <String>[];
        _snapshotBytesFutureByUri.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSavedSnapshots = false;
        });
      }
    }
  }

  Future<bool> _deleteSavedSnapshotByUri(String uri) async {
    try {
      final deleted = await _lyricsMethodsChannel.invokeMethod<dynamic>(
        'deleteSnapshotImage',
        {'uri': uri},
      );
      return deleted == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _shareSnapshotBytes(Uint8List bytes, {required String fileName}) async {
    try {
      final launched = await _lyricsMethodsChannel.invokeMethod<dynamic>(
        'shareSnapshotWithSaveOption',
        {
          'bytes': bytes,
          'fileName': fileName,
        },
      );
      return launched == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showSavedSnapshotPreview({required int startIndex}) async {
    if (_savedSnapshotUris.isEmpty) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final initialIndex = startIndex.clamp(0, _savedSnapshotUris.length - 1);
    final localUris = List<String>.from(_savedSnapshotUris);
    final pageController = PageController(initialPage: initialIndex);
    var currentIndex = initialIndex;

    Future<Uint8List?> loadBytesForUri(String uri) {
      return _snapshotBytesFutureByUri.putIfAbsent(uri, () => _readSnapshotImageBytes(uri));
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
                    ),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: size.width * 0.88,
                          maxHeight: size.height * 0.76,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: size.height * 0.43,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: PageView.builder(
                                    controller: pageController,
                                    itemCount: localUris.length,
                                    onPageChanged: (index) {
                                      modalSetState(() {
                                        currentIndex = index;
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      final uri = localUris[index];
                                      return FutureBuilder<Uint8List?>(
                                        future: loadBytesForUri(uri),
                                        builder: (context, snapshot) {
                                          final bytes = snapshot.data;
                                          if (bytes == null || bytes.isEmpty) {
                                            return Center(
                                              child: Icon(
                                                Icons.photo_library_outlined,
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                              ),
                                            );
                                          }
                                          return InteractiveViewer(
                                            minScale: 1,
                                            maxScale: 3.2,
                                            child: Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 62,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: localUris.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final uri = localUris[index];
                                    final isSelected = index == currentIndex;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        pageController.animateToPage(
                                          index,
                                          duration: const Duration(milliseconds: 180),
                                          curve: Curves.easeOut,
                                        );
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 170),
                                        width: 62,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface.withValues(alpha: 0.16),
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: FutureBuilder<Uint8List?>(
                                          future: loadBytesForUri(uri),
                                          builder: (context, snapshot) {
                                            final bytes = snapshot.data;
                                            if (bytes == null || bytes.isEmpty) {
                                              return DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.surface.withValues(alpha: 0.38),
                                                ),
                                                child: Icon(
                                                  Icons.photo_library_outlined,
                                                  size: 18,
                                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                                ),
                                              );
                                            }
                                            return Image.memory(
                                              bytes,
                                              fit: BoxFit.cover,
                                              filterQuality: FilterQuality.low,
                                              cacheWidth: 180,
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: localUris.isEmpty
                                          ? null
                                          : () async {
                                              final uri = localUris[currentIndex];
                                              final deleted = await _deleteSavedSnapshotByUri(uri);
                                              if (!dialogContext.mounted) {
                                                return;
                                              }
                                              if (!deleted) {
                                                AppTopFeedback.show(context, l10n.snapshotError);
                                                return;
                                              }

                                              if (mounted) {
                                                setState(() {
                                                  _savedSnapshotUris = _savedSnapshotUris
                                                      .where((item) => item != uri)
                                                      .toList(growable: false);
                                                  _snapshotBytesFutureByUri.remove(uri);
                                                });
                                              }

                                              modalSetState(() {
                                                localUris.removeAt(currentIndex);
                                                if (localUris.isNotEmpty) {
                                                  currentIndex = currentIndex.clamp(0, localUris.length - 1);
                                                  pageController.jumpToPage(currentIndex);
                                                }
                                              });

                                              AppTopFeedback.show(context, l10n.snapshotDeleted);

                                              if (localUris.isEmpty && dialogContext.mounted) {
                                                Navigator.of(dialogContext).pop();
                                              }
                                            },
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      label: Text(l10n.delete),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: localUris.isEmpty
                                          ? null
                                          : () async {
                                              final uri = localUris[currentIndex];
                                              final bytes = await loadBytesForUri(uri);
                                              if (bytes == null || bytes.isEmpty) {
                                                if (mounted) {
                                                  AppTopFeedback.show(context, l10n.snapshotError);
                                                }
                                                return;
                                              }

                                              Navigator.of(dialogContext).pop();
                                              final shared = await _shareSnapshotBytes(
                                                bytes,
                                                fileName:
                                                    'singsync_snapshot_gallery_${DateTime.now().millisecondsSinceEpoch}.png',
                                              );
                                              if (!mounted || shared) {
                                                return;
                                              }
                                              AppTopFeedback.show(context, l10n.snapshotError);
                                            },
                                      icon: const Icon(Icons.share_rounded),
                                      label: Text(l10n.share),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pageController.dispose();
  }

  Future<Uint8List?> _readSnapshotImageBytes(String uri) async {
    try {
      final bytes = await _lyricsMethodsChannel.invokeMethod<dynamic>(
        'readSnapshotImageBytes',
        {'uri': uri},
      );
      if (bytes is Uint8List) {
        return bytes;
      }
      if (bytes is List<int>) {
        return Uint8List.fromList(bytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Widget _buildSavedSnapshotsGalleryPage({
    required ThemeData theme,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.savedSnapshotsTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadSavedSnapshots(force: true),
              child: _isLoadingSavedSnapshots
                  ? const Center(child: CircularProgressIndicator())
                  : _savedSnapshotUris.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 140),
                            Center(
                              child: Text(
                                l10n.noSavedSnapshotsYet,
                                style: theme.textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _savedSnapshotUris.length,
                          itemBuilder: (context, index) {
                            final uri = _savedSnapshotUris[index];
                            final bytesFuture = _snapshotBytesFutureByUri.putIfAbsent(
                              uri,
                              () => _readSnapshotImageBytes(uri),
                            );

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    if (!mounted) {
                                      return;
                                    }
                                    await _showSavedSnapshotPreview(startIndex: index);
                                  },
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface.withValues(alpha: 0.42),
                                      border: Border.all(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                                      ),
                                    ),
                                    child: FutureBuilder<Uint8List?>(
                                      future: bytesFuture,
                                      builder: (context, snapshot) {
                                        final bytes = snapshot.data;
                                        if (bytes == null || bytes.isEmpty) {
                                          return Center(
                                            child: Icon(
                                              Icons.photo_library_outlined,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                            ),
                                          );
                                        }
                                        return Image.memory(
                                          bytes,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.low,
                                          cacheWidth: 420,
                                        );
                                      },
                                    ),
                                  ),
                                ),
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

  Widget _buildMainPlaybackPage({
    required ThemeData theme,
    required AppLocalizations l10n,
  }) {
    return Padding(
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
              isCurrentFavorite: widget.controller.isCurrentNowPlayingFavorite,
              onToggleFavorite: _toggleCurrentFavorite,
              onOpenFavorites: _openFavoritesLibraryModal,
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
              onSnapshotSavedToGallery: _handleSnapshotSavedToGallery,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncWakeLockWithPlayback(
        shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
        force: true,
      );
      _schedulePermissionCheck(delay: const Duration(milliseconds: 450));
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _syncWakeLockWithPlayback(shouldKeepAwake: false, force: true);
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
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppTopFeedback.visibility,
                  builder: (context, isFeedbackVisible, child) {
                    return AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(bottom: isFeedbackVisible ? 70 : 0),
                      child: child,
                    );
                  },
                  child: PageView.builder(
                    controller: _homePageController,
                    onPageChanged: (index) {
                      if (index.isOdd) {
                        unawaited(_loadSavedSnapshots());
                      }
                    },
                    itemBuilder: (context, index) {
                      if (index.isOdd) {
                        return _buildSavedSnapshotsGalleryPage(theme: theme, l10n: l10n);
                      }
                      return _buildMainPlaybackPage(theme: theme, l10n: l10n);
                    },
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
