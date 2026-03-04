import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme_controller.dart';
import '../../../l10n/app_localizations.dart';
import 'lyrics_controller.dart';
import 'widgets/app_top_feedback.dart';
import 'widgets/home_header.dart';
import 'widgets/now_playing_tab.dart';
import 'widgets/snapshot_editor_support.dart';

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
  static const String _appProfile = String.fromEnvironment('APP_PROFILE', defaultValue: 'dev');
  static final bool _isDevProfile = _appProfile.trim().toLowerCase() == 'dev';
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.singsync/lyrics',
  );
  static const MethodChannel _nowPlayingMethodsChannel = MethodChannel(
    'net.iozamudioa.singsync/now_playing_methods',
  );
  bool _isPermissionDialogOpen = false;
  bool _hideHomeHeaderForExpandedVinyl = false;
  bool _useArtworkBackground = true;
  bool? _lastWakeLockDesired;
  int _activeNavIndex = 0;
  VoidCallback? _openInfoModalAction;
  final Map<String, Future<Uint8List?>> _snapshotBytesFutureByUri = <String, Future<Uint8List?>>{};
  final Map<String, Future<Uint8List?>> _mediaAppIconFutureByPackage = <String, Future<Uint8List?>>{};
  final Map<String, DateTime> _savedSnapshotDateByUri = <String, DateTime>{};
  final Map<String, String> _savedSnapshotDisplayNameByUri = <String, String>{};
  final Map<String, String> _savedSnapshotTitleByUri = <String, String>{};
  final Map<String, String> _savedSnapshotArtistByUri = <String, String>{};
  final Map<String, String> _savedSnapshotSourcePackageByUri = <String, String>{};
  List<String> _savedSnapshotUris = const <String>[];
  bool _isLoadingSavedSnapshots = false;
  int _snapshotGridCrossAxisCount = 3;
  double _snapshotGridScaleAnchor = 1;
  bool _isGalleryPinching = false;
  int _galleryActivePointers = 0;
  bool _isGallerySearchOpen = false;
  final TextEditingController _gallerySearchController = TextEditingController();
  final FocusNode _gallerySearchFocusNode = FocusNode();
  bool _isFavoritesSearchOpen = false;
  bool _groupCatchemByArtist = false;
  bool _groupCatchemByAlbum = false;
  bool _groupCatchemByNowPlaying = false;
  bool _showOnlyCatchemFavorites = false;
  final TextEditingController _favoritesSearchController = TextEditingController();
  final FocusNode _favoritesSearchFocusNode = FocusNode();
  final ScrollController _catchemScrollController = ScrollController();
  final Map<String, Timer> _pendingCatchemDeleteTimers = <String, Timer>{};
  final Map<String, CatchemSongEntry> _pendingCatchemDeleteEntries = <String, CatchemSongEntry>{};
  int _lastTodayAutoLoadAtMs = 0;
  final Set<String> _expandedCatchemMonths = <String>{};
  final Set<int> _expandedCatchemYears = <int>{};
  final Set<String> _expandedCatchemYearMonths = <String>{};
  final GlobalKey _galleryNavIconKey = GlobalKey();
  Timer? _sleepTimerTicker;
  DateTime? _sleepTimerEndsAt;
  int? _sleepSongsRemaining;
  String _sleepTimerLastTrackKey = '';
  final ValueNotifier<int> _sleepTimerPulse = ValueNotifier<int>(0);

  bool get _isSleepTimerActive => _sleepTimerEndsAt != null || _sleepSongsRemaining != null;

  ImageProvider<Object>? _buildArtworkImageProvider(String? rawUrl) {
    final artworkUrl = rawUrl?.trim() ?? '';
    if (artworkUrl.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(artworkUrl);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return FileImage(File.fromUri(uri));
    }

    return NetworkImage(artworkUrl);
  }

  Future<Uint8List?> _loadMediaAppIconBytes(String packageName) async {
    final normalizedPackage = packageName.trim();
    if (normalizedPackage.isEmpty) {
      return null;
    }

    try {
      final bytes = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
        'getMediaAppIcon',
        {
          'packageName': normalizedPackage,
          'maxPx': 112,
        },
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

  Widget _buildMediaSourceIcon(String? packageName, {double size = 20}) {
    final normalizedPackage = (packageName ?? '').trim();
    final fallback = Icon(
      Icons.music_note_rounded,
      size: size,
    );
    if (normalizedPackage.isEmpty) {
      return fallback;
    }

    final iconFuture = _mediaAppIconFutureByPackage.putIfAbsent(
      normalizedPackage,
      () => _loadMediaAppIconBytes(normalizedPackage),
    );

    return FutureBuilder<Uint8List?>(
      future: iconFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return fallback;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  String _mediaPlayerLabelForPackage(AppLocalizations l10n, String packageName) {
    switch (packageName) {
      case 'com.spotify.music':
        return l10n.spotifyLabel;
      case 'com.google.android.apps.youtube.music':
        return l10n.youtubeMusicLabel;
      case 'com.amazon.mp3':
        return l10n.amazonMusicLabel;
      case 'com.apple.android.music':
        return l10n.appleMusicLabel;
      default:
        return packageName;
    }
  }

  Future<void> _openCatchemPlayer(CatchemSongEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final sourceType = entry.sourceType.trim().toLowerCase();
    final hasSourcePackage = (entry.sourcePackage ?? '').trim().isNotEmpty;

    if (sourceType == 'pixel_now_playing' || !hasSourcePackage) {
      final installed = widget.controller.installedMediaAppPackages;
      final available = LyricsController.knownMediaAppPackages
          .where(installed.contains)
          .toList(growable: false);

      if (available.isEmpty) {
        AppTopFeedback.show(context, l10n.catchemNoPlayersAvailable);
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.catchemChoosePlayerTitle),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              ...available.map(
                (packageName) => ListTile(
                  leading: _buildMediaSourceIcon(packageName, size: 22),
                  title: Text(_mediaPlayerLabelForPackage(l10n, packageName)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await widget.controller.openCatchemEntryInPlayer(
                      entry: entry,
                      selectedPackage: packageName,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      );
      return;
    }

    await widget.controller.openCatchemEntryInPlayer(entry: entry);
  }

  Future<void> _handleSnapshotSavedToGallery() async {
    await _loadSavedSnapshots(force: true);
  }

  void _onControllerChanged() {
    if (!mounted || _sleepSongsRemaining == null || _sleepSongsRemaining! <= 0) {
      return;
    }

    final songTitle = widget.controller.songTitle.trim();
    final defaultTitle = AppLocalizations.of(context).nowPlayingDefaultTitle;
    final isMeaningfulTrack =
        songTitle.isNotEmpty && songTitle.toLowerCase() != defaultTitle.toLowerCase();
    if (!isMeaningfulTrack) {
      return;
    }

    final currentTrackKey = songTitle.toLowerCase();
    if (_sleepTimerLastTrackKey.isEmpty) {
      _sleepTimerLastTrackKey = currentTrackKey;
      return;
    }

    if (_sleepTimerLastTrackKey == currentTrackKey) {
      return;
    }

    _sleepTimerLastTrackKey = currentTrackKey;
    final nextRemaining = (_sleepSongsRemaining! - 1).clamp(0, 9999);
    if (mounted) {
      setState(() {
        _sleepSongsRemaining = nextRemaining;
      });
    }
    if (nextRemaining == 0) {
      unawaited(_triggerSleepTimerStop());
    }
  }

  Future<void> _handleNavTap(int index) async {
    final hasSnapshotsDestination = _savedSnapshotUris.isNotEmpty;
    const homeIndex = 0;
    final galleryIndex = hasSnapshotsDestination ? 1 : -1;
    final mySongsIndex = hasSnapshotsDestination ? 2 : 1;
    final moreIndex = hasSnapshotsDestination ? 3 : 2;

    if (index == homeIndex || index == galleryIndex || index == mySongsIndex) {
      if (mounted) {
        setState(() {
          _activeNavIndex = index;
          if (index == homeIndex) {
            _isGallerySearchOpen = false;
            _isFavoritesSearchOpen = false;
            _gallerySearchController.clear();
            _favoritesSearchController.clear();
          }
        });
      }
      if (index == homeIndex) {
        _gallerySearchFocusNode.unfocus();
        _favoritesSearchFocusNode.unfocus();
      }
      if (index == galleryIndex) {
        await _loadSavedSnapshots();
      }
      if (index == mySongsIndex) {
        await widget.controller.loadCatchemLibrary();
      }
      return;
    }

    if (index == moreIndex) {
      _showMoreActionsSubmenu();
      return;
    }
  }

  Future<void> _showMoreActionsSubmenu() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.snooze_outlined),
                  title: Text(l10n.sleepTimerMenuTitle),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showSleepTimerSetupModal();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(l10n.appInfoMenuTitle),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openInfoModalAction?.call();
                  },
                ),
                if (_isDevProfile)
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Debug (perfil dev)'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showDebugProfileSubmenu();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDebugProfileSubmenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: const Text('Capturar JSON de MediaSession'),
                  subtitle: const Text('Copiar JSON completo al portapapeles'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_copyActiveSessionSnapshotToClipboard());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyActiveSessionSnapshotToClipboard() async {
    try {
      final response = await _nowPlayingMethodsChannel.invokeMethod<dynamic>(
        'getActiveSessionSnapshot',
        <String, dynamic>{
          'sourcePackage': widget.controller.nowPlayingSourcePackage,
        },
      );

      if (response is! Map) {
        if (!mounted) {
          return;
        }
        AppTopFeedback.show(context, 'No hay snapshot de MediaSession activo');
        return;
      }

      final normalized = response.map((key, value) => MapEntry(key.toString(), value));
      final jsonText = const JsonEncoder.withIndent('  ').convert(normalized);
      await Clipboard.setData(ClipboardData(text: jsonText));

      if (!mounted) {
        return;
      }
      AppTopFeedback.show(context, 'Snapshot JSON copiado al portapapeles');
    } catch (_) {
      if (!mounted) {
        return;
      }
      AppTopFeedback.show(context, 'Error al capturar snapshot de MediaSession');
    }
  }

  Future<void> _triggerSleepTimerStop() async {
    final hadActiveTimer = _isSleepTimerActive;
    _clearSleepTimer();
    if (!hadActiveTimer) {
      return;
    }

    if (widget.controller.isNowPlayingPlaybackActive) {
      await widget.controller.mediaPlayPause();
    }
    await _turnScreenOffIfPossible();
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    AppTopFeedback.show(
      context,
      l10n.sleepTimerCompleted,
    );
  }

  Future<bool> _turnScreenOffIfPossible() async {
    try {
      final result = await _nowPlayingMethodsChannel.invokeMethod<dynamic>('turnScreenOffIfPossible');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  void _clearSleepTimer({bool notify = true}) {
    _sleepTimerTicker?.cancel();
    _sleepTimerTicker = null;
    if (!mounted) {
      _sleepTimerEndsAt = null;
      _sleepSongsRemaining = null;
      _sleepTimerLastTrackKey = '';
      return;
    }
    setState(() {
      _sleepTimerEndsAt = null;
      _sleepSongsRemaining = null;
      _sleepTimerLastTrackKey = '';
    });
    _sleepTimerPulse.value++;
    if (!notify) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    AppTopFeedback.show(
      context,
      l10n.sleepTimerCanceled,
    );
  }

  void _startSleepTimerByDuration(Duration duration) {
    if (duration.inSeconds <= 0) {
      return;
    }
    _sleepTimerTicker?.cancel();
    if (mounted) {
      setState(() {
        _sleepSongsRemaining = null;
        _sleepTimerLastTrackKey = '';
        _sleepTimerEndsAt = DateTime.now().add(duration);
      });
    }
    _sleepTimerTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final endsAt = _sleepTimerEndsAt;
      if (endsAt == null) {
        timer.cancel();
        return;
      }
      final remaining = endsAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        timer.cancel();
        unawaited(_triggerSleepTimerStop());
        return;
      }
      if (mounted) {
        setState(() {});
        _sleepTimerPulse.value++;
      }
    });
    _sleepTimerPulse.value++;
  }

  void _startSleepTimerBySongs(int songs) {
    if (songs <= 0) {
      return;
    }
    _sleepTimerTicker?.cancel();
    final currentTrackKey = widget.controller.songTitle.trim().toLowerCase();
    if (mounted) {
      setState(() {
        _sleepTimerEndsAt = null;
        _sleepSongsRemaining = songs;
        _sleepTimerLastTrackKey = currentTrackKey;
      });
      _sleepTimerPulse.value++;
    }
  }

  String _formatDurationHhMmSs(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 24 * 3600 * 7);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _sleepTimerStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_sleepTimerEndsAt != null) {
      final remaining = _sleepTimerEndsAt!.difference(DateTime.now());
      final pretty = _formatDurationHhMmSs(remaining.isNegative ? Duration.zero : remaining);
      return l10n.sleepTimerStatusIn(pretty);
    }
    if (_sleepSongsRemaining != null) {
      final n = _sleepSongsRemaining!;
      if (n <= 1) {
        return 'Última canción, se apagará el reproductor';
      }
      return 'Apagado después de $n canciones';
    }
    return l10n.sleepTimerStatusNone;
  }

  Future<Duration?> _showSleepCustomTimeInputDialog() async {
    var selectedDuration = const Duration(minutes: 5);
    final l10n = AppLocalizations.of(context);

    return showDialog<Duration>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
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
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.sleepTimerSelectShutdownTime,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 170,
                            child: CupertinoTheme(
                              data: CupertinoThemeData(
                                brightness: theme.brightness,
                                primaryColor: theme.colorScheme.primary,
                                textTheme: CupertinoTextThemeData(
                                  pickerTextStyle: theme.textTheme.titleMedium ??
                                      TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontSize: 22,
                                      ),
                                ),
                              ),
                              child: CupertinoTimerPicker(
                                mode: CupertinoTimerPickerMode.hm,
                                initialTimerDuration: selectedDuration,
                                onTimerDurationChanged: (value) {
                                  selectedDuration = value;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: Text(l10n.cancel),
                              ),
                              FilledButton(
                                onPressed: () {
                                  if (selectedDuration.inMinutes <= 0) {
                                    Navigator.of(dialogContext).pop();
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(selectedDuration);
                                },
                                child: Text(l10n.accept),
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
  }

  Future<int?> _showSleepCustomSongsInputDialog() async {
    final songsController = TextEditingController();
    final l10n = AppLocalizations.of(context);

    try {
      return await showDialog<int>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
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
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.sleepTimerCustomSongCountTitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: songsController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: l10n.songsLabel),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: Text(l10n.cancel),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    final value = int.tryParse(songsController.text.trim()) ?? 0;
                                    Navigator.of(dialogContext).pop(value > 0 ? value : null);
                                  },
                                  child: Text(l10n.accept),
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
    } finally {
      songsController.dispose();
    }
  }

  Future<void> _showSleepTimerSetupModal() async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
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
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                        ),
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _sleepTimerPulse,
                        builder: (context, _, __) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sleepTimerSectionTitle(
                                context,
                                l10n.sleepTimerSectionByTime,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _startSleepTimerByDuration(const Duration(minutes: 15));
                                        Navigator.of(dialogContext).pop();
                                      },
                                      child: const Text('0:15:00'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _startSleepTimerByDuration(const Duration(minutes: 90));
                                        Navigator.of(dialogContext).pop();
                                      },
                                      child: const Text('1:30:00'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        final duration = await _showSleepCustomTimeInputDialog();
                                        if (!mounted || duration == null) {
                                          return;
                                        }
                                        _startSleepTimerByDuration(duration);
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                      },
                                      child: Text(l10n.sleepTimerCustomTimeButton),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.18)),
                              const SizedBox(height: 14),
                              _sleepTimerSectionTitle(
                                context,
                                l10n.sleepTimerSectionBySongs,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _startSleepTimerBySongs(5);
                                        Navigator.of(dialogContext).pop();
                                      },
                                      child: const Text('N = 5'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _startSleepTimerBySongs(10);
                                        Navigator.of(dialogContext).pop();
                                      },
                                      child: const Text('N = 10'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        final songs = await _showSleepCustomSongsInputDialog();
                                        if (!mounted || songs == null) {
                                          return;
                                        }
                                        _startSleepTimerBySongs(songs);
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                      },
                                      child: const Text('N = ?'),
                                    ),
                                  ),
                                ],
                              ),
                              if (_isSleepTimerActive) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _sleepTimerStatusText(dialogContext),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      _clearSleepTimer();
                                      Navigator.of(dialogContext).pop();
                                    },
                                    icon: const Icon(Icons.timer_off_outlined),
                                    label: Text(l10n.cancelSleepTimer),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
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
  }

  Widget _sleepTimerSectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _showSleepTimerDetailModal() async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
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
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                        ),
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _sleepTimerPulse,
                        builder: (context, _, __) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.sleepTimerActiveTitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _sleepTimerStatusText(dialogContext),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.of(dialogContext).pop(),
                                    child: Text(AppLocalizations.of(context).close),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                      _showSleepTimerSetupModal();
                                    },
                                    child: Text(l10n.configure),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      _clearSleepTimer();
                                      Navigator.of(dialogContext).pop();
                                    },
                                    child: Text(l10n.cancel),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
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

  String _pendingCatchemDeleteKey(CatchemSongEntry entry) {
    return '${entry.key}|${entry.lastDetectedAtMs}';
  }

  void _undoPendingCatchemDelete(String pendingKey) {
    final timer = _pendingCatchemDeleteTimers.remove(pendingKey);
    timer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingCatchemDeleteEntries.remove(pendingKey);
    });
  }

  void _scheduleCatchemDeleteWithUndo(CatchemSongEntry entry, AppLocalizations l10n) {
    final pendingKey = _pendingCatchemDeleteKey(entry);

    final existingTimer = _pendingCatchemDeleteTimers.remove(pendingKey);
    existingTimer?.cancel();

    setState(() {
      _pendingCatchemDeleteEntries[pendingKey] = entry;
    });

    final timer = Timer(const Duration(seconds: 5), () async {
      _pendingCatchemDeleteTimers.remove(pendingKey);
      final pendingEntry = _pendingCatchemDeleteEntries[pendingKey];
      if (pendingEntry == null) {
        return;
      }

      final removed = await widget.controller.removeCatchemEntry(pendingEntry);
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingCatchemDeleteEntries.remove(pendingKey);
      });

      if (!removed) {
        return;
      }

      AppTopFeedback.show(
        context,
        l10n.catchemDeleted,
        duration: const Duration(milliseconds: 1300),
      );
    });

    _pendingCatchemDeleteTimers[pendingKey] = timer;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(l10n.catchemDeleted),
        action: SnackBarAction(
          label: 'Volver a agregar canción',
          onPressed: () => _undoPendingCatchemDelete(pendingKey),
        ),
      ),
    );
  }

  String _mapPlayCountLabel(BuildContext context, int count) {
    final localeCode = Localizations.localeOf(context).languageCode.toLowerCase();
    if (localeCode == 'es') {
      return count == 1 ? '$count reproducción' : '$count reproducciones';
    }
    return count == 1 ? '$count play' : '$count plays';
  }

  Widget _buildMySongsPage({
    required ThemeData theme,
    required AppLocalizations l10n,
  }) {
    final favoritesSearchQuery = _normalizeSearchText(_favoritesSearchController.text);
    final languageCode = Localizations.localeOf(context).languageCode.toLowerCase();
    final albumChipLabel = languageCode == 'es' ? 'Álbum' : 'Album';
    final unknownAlbumLabel = languageCode == 'es' ? 'Álbum desconocido' : 'Unknown album';

    String monthKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);
    String monthLabel(DateTime date) {
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      return DateFormat('MMMM', localeTag).format(DateTime(date.year, date.month));
    }
    String monthYearLabel(DateTime date) {
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      return DateFormat('MMMM yyyy', localeTag).format(DateTime(date.year, date.month));
    }
    Widget buildSongRow(
      CatchemSongEntry currentItem, {
      bool showArtistInTitle = true,
    }) {
      final isFavorite = widget.controller.isSongFavorite(
        title: currentItem.title,
        artist: currentItem.artist,
      );
      final listens = currentItem.detectCount <= 0 ? 1 : currentItem.detectCount;
      final obsessionEmoji = _catchemObsessionEmoji(
        l10n,
        listens,
        currentItem.lastDetectedAtMs,
      );
      final timestampLabel = _catchemTimeLabel(currentItem.lastDetectedAtMs);
      final titleText = '$obsessionEmoji ${currentItem.title}';
      final artistText = currentItem.artist.trim();
      final subtitleText = showArtistInTitle && artistText.isNotEmpty
          ? '$artistText • $timestampLabel'
          : timestampLabel;
      final playsLabel = _mapPlayCountLabel(context, listens);
      return Dismissible(
        key: ValueKey('catchem_${currentItem.key}_${currentItem.lastDetectedAtMs}'),
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
        onDismissed: (_) {
          _scheduleCatchemDeleteWithUndo(currentItem, l10n);
        },
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12, top: 6, bottom: 6),
              child: GestureDetector(
                onTap: () => _showSongPlaybackLocationsMap(currentItem),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildArtworkImageProvider(currentItem.artworkUrl) == null
                      ? const SizedBox(
                          width: 64,
                          height: 64,
                          child: ColoredBox(color: Colors.black12),
                        )
                      : Image(
                          image: _buildArtworkImageProvider(currentItem.artworkUrl)!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 64,
                            height: 64,
                            child: ColoredBox(color: Colors.black12),
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () async {
                  await widget.controller.showCatchemInNowPlaying(currentItem);
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _activeNavIndex = 0;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (showArtistInTitle && artistText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                      ],
                      Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        playsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                tooltip: isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
                onPressed: () async {
                  final toggledToFavorite = await widget.controller.toggleCatchemFavorite(currentItem);
                  if (!mounted || toggledToFavorite == null) {
                    return;
                  }
                  AppTopFeedback.show(
                    context,
                    toggledToFavorite ? l10n.favoriteAdded : l10n.favoriteRemoved,
                  );
                },
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: l10n.openActivePlayer,
                onPressed: () => unawaited(_openCatchemPlayer(currentItem)),
                icon: SizedBox(
                  width: 22,
                  height: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildMediaSourceIcon(currentItem.sourcePackage, size: 20),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.catchemTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _showCatchemMap,
                icon: const Icon(Icons.public_rounded),
                tooltip: l10n.catchemOpenMap,
              ),
              IconButton(
                onPressed: _toggleFavoritesSearch,
                icon: Icon(
                  _isFavoritesSearchOpen ? Icons.close_rounded : Icons.search_rounded,
                ),
                tooltip: _isFavoritesSearchOpen ? l10n.close : l10n.search,
              ),
            ],
          ),
          if (_isFavoritesSearchOpen) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _favoritesSearchController,
              focusNode: _favoritesSearchFocusNode,
              autofocus: true,
              onTapOutside: (_) {
                _favoritesSearchFocusNode.unfocus();
              },
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                if (!mounted) {
                  return;
                }
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: l10n.searchBySongOrArtist,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final hasNowPlayingEntries = widget.controller.catchemLibrary.any(
                  (entry) => entry.sourceType.trim().toLowerCase() == 'pixel_now_playing',
                );
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l10n.artistLabel),
                      selected: _groupCatchemByArtist,
                      onSelected: (selected) {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _groupCatchemByArtist = selected;
                          if (selected) {
                            _groupCatchemByAlbum = false;
                            _groupCatchemByNowPlaying = false;
                            _showOnlyCatchemFavorites = false;
                          }
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(albumChipLabel),
                      selected: _groupCatchemByAlbum,
                      onSelected: (selected) {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _groupCatchemByAlbum = selected;
                          if (selected) {
                            _groupCatchemByArtist = false;
                            _groupCatchemByNowPlaying = false;
                            _showOnlyCatchemFavorites = false;
                          }
                        });
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.favoritesLabel),
                      selected: _showOnlyCatchemFavorites,
                      onSelected: (selected) {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _showOnlyCatchemFavorites = selected;
                          if (selected) {
                            _groupCatchemByArtist = false;
                            _groupCatchemByAlbum = false;
                            _groupCatchemByNowPlaying = false;
                          }
                        });
                      },
                    ),
                    if (hasNowPlayingEntries)
                      FilterChip(
                        label: Text(l10n.nowPlayingDefaultTitle),
                        selected: _groupCatchemByNowPlaying,
                        onSelected: (selected) {
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _groupCatchemByNowPlaying = selected;
                            if (selected) {
                              _groupCatchemByArtist = false;
                              _groupCatchemByAlbum = false;
                              _showOnlyCatchemFavorites = false;
                            }
                          });
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final entries = widget.controller.catchemLibrary;
                var filteredEntries = entries.where((item) {
                  if (favoritesSearchQuery.isEmpty) {
                    return true;
                  }
                  final title = _normalizeSearchText(item.title);
                  final artist = _normalizeSearchText(item.artist);
                  final searchable = '$title $artist';
                  final terms = favoritesSearchQuery
                      .split(' ')
                      .map((term) => term.trim())
                      .where((term) => term.isNotEmpty)
                      .toList(growable: false);
                  return terms.every(searchable.contains);
                }).toList(growable: false);

                final hasNowPlayingEntries = entries.any(
                  (item) => item.sourceType.trim().toLowerCase() == 'pixel_now_playing',
                );

                if (_groupCatchemByNowPlaying && hasNowPlayingEntries) {
                  filteredEntries = filteredEntries
                      .where((item) => item.sourceType.trim().toLowerCase() == 'pixel_now_playing')
                      .toList(growable: false);
                }

                if (_showOnlyCatchemFavorites) {
                  filteredEntries = filteredEntries
                      .where(
                        (item) => widget.controller.isSongFavorite(
                          title: item.title,
                          artist: item.artist,
                        ),
                      )
                      .toList(growable: false);
                }

                filteredEntries = filteredEntries
                    .where(
                      (item) => !_pendingCatchemDeleteEntries.containsKey(
                        _pendingCatchemDeleteKey(item),
                      ),
                    )
                    .toList(growable: false);

                if (filteredEntries.isEmpty) {
                  return Center(
                    child: Text(
                      favoritesSearchQuery.isEmpty ? l10n.noCatchemYet : l10n.noResults,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final now = DateTime.now();
                final todayStart = dayStart(now);
                final yesterdayStart = todayStart.subtract(const Duration(days: 1));
                final monthStart = DateTime(now.year, now.month, 1);

                if (favoritesSearchQuery.isEmpty &&
                    !_groupCatchemByArtist &&
                    !_groupCatchemByAlbum &&
                    !_groupCatchemByNowPlaying &&
                  !_showOnlyCatchemFavorites &&
                    widget.controller.hasMoreCatchem &&
                    !widget.controller.isLoadingMoreCatchem &&
                    entries.isNotEmpty) {
                  final lastLoaded = entries.last;
                  final lastLoadedAt = DateTime.fromMillisecondsSinceEpoch(
                    lastLoaded.lastDetectedAtMs <= 0 ? 0 : lastLoaded.lastDetectedAtMs,
                  );
                  final lastLoadedDay = dayStart(lastLoadedAt);
                  if (lastLoadedDay == todayStart) {
                    final nowMs = DateTime.now().millisecondsSinceEpoch;
                    if (nowMs - _lastTodayAutoLoadAtMs > 650) {
                      _lastTodayAutoLoadAtMs = nowMs;
                      unawaited(widget.controller.loadMoreCatchemPage());
                    }
                  }
                }

                final today = <CatchemSongEntry>[];
                final yesterday = <CatchemSongEntry>[];
                final thisMonth = <CatchemSongEntry>[];
                final previousMonthsCurrentYear = <String, List<CatchemSongEntry>>{};
                final previousYears = <int, Map<String, List<CatchemSongEntry>>>{};

                for (final item in filteredEntries) {
                  final detectedAt = DateTime.fromMillisecondsSinceEpoch(
                    item.lastDetectedAtMs <= 0 ? 0 : item.lastDetectedAtMs,
                  );
                  final detectedDay = dayStart(detectedAt);

                  if (detectedDay == todayStart) {
                    today.add(item);
                    continue;
                  }
                  if (detectedDay == yesterdayStart) {
                    yesterday.add(item);
                    continue;
                  }
                  if (detectedAt.year == now.year &&
                      detectedAt.month == now.month &&
                      detectedDay.isBefore(yesterdayStart)) {
                    thisMonth.add(item);
                    continue;
                  }

                  if (detectedAt.year == now.year && detectedAt.isBefore(monthStart)) {
                    final key = monthKey(detectedAt);
                    previousMonthsCurrentYear.putIfAbsent(key, () => <CatchemSongEntry>[]).add(item);
                    continue;
                  }

                  final yearMap = previousYears.putIfAbsent(detectedAt.year, () => <String, List<CatchemSongEntry>>{});
                  final key = monthKey(detectedAt);
                  yearMap.putIfAbsent(key, () => <CatchemSongEntry>[]).add(item);
                }

                final content = <Widget>[];

                int compareByMostPlayed(CatchemSongEntry a, CatchemSongEntry b) {
                  final playsA = a.detectCount <= 0 ? 1 : a.detectCount;
                  final playsB = b.detectCount <= 0 ? 1 : b.detectCount;
                  final byPlays = playsB.compareTo(playsA);
                  if (byPlays != 0) {
                    return byPlays;
                  }
                  return b.lastDetectedAtMs.compareTo(a.lastDetectedAtMs);
                }

                void addSectionHeader(String text) {
                  content.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: Text(
                        text,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                }

                void addVisibleRows({
                  required String sectionKey,
                  required List<CatchemSongEntry> rows,
                  bool showArtistInTitle = true,
                }) {
                  if (rows.isEmpty) {
                    return;
                  }
                  final visibleRows = rows;

                  for (final row in visibleRows) {
                    content.add(buildSongRow(row, showArtistInTitle: showArtistInTitle));
                  }
                }

                if (_groupCatchemByArtist) {
                  final groupedByArtist = <String, List<CatchemSongEntry>>{};
                  for (final row in filteredEntries) {
                    final artistKey = row.artist.trim().isEmpty ? l10n.unknownArtist : row.artist.trim();
                    groupedByArtist.putIfAbsent(artistKey, () => <CatchemSongEntry>[]).add(row);
                  }

                  final artistKeys = groupedByArtist.keys.toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                  for (final artistKey in artistKeys) {
                    final artistRows = List<CatchemSongEntry>.from(
                      groupedByArtist[artistKey] ?? const <CatchemSongEntry>[],
                    )
                      ..sort(compareByMostPlayed);
                    if (artistRows.isEmpty) {
                      continue;
                    }
                    addSectionHeader(artistKey);
                    addVisibleRows(
                      sectionKey: 'artist-$artistKey',
                      rows: artistRows,
                      showArtistInTitle: false,
                    );
                  }
                } else if (_groupCatchemByAlbum) {
                  final groupedByAlbum = <String, List<CatchemSongEntry>>{};
                  for (final row in filteredEntries) {
                    final albumKey = (row.albumName ?? '').trim().isEmpty
                        ? unknownAlbumLabel
                        : row.albumName!.trim();
                    groupedByAlbum.putIfAbsent(albumKey, () => <CatchemSongEntry>[]).add(row);
                  }

                  final albumKeys = groupedByAlbum.keys.toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                  for (final albumKey in albumKeys) {
                    final albumRows = List<CatchemSongEntry>.from(
                      groupedByAlbum[albumKey] ?? const <CatchemSongEntry>[],
                    )
                      ..sort(compareByMostPlayed);
                    if (albumRows.isEmpty) {
                      continue;
                    }
                    addSectionHeader(albumKey);
                    addVisibleRows(
                      sectionKey: 'album-$albumKey',
                      rows: albumRows,
                      showArtistInTitle: true,
                    );
                  }
                } else if (_showOnlyCatchemFavorites) {
                  final favoriteRows = List<CatchemSongEntry>.from(filteredEntries)
                    ..sort(compareByMostPlayed);
                  addVisibleRows(
                    sectionKey: 'favorites-most-played',
                    rows: favoriteRows,
                    showArtistInTitle: true,
                  );
                } else {
                  if (today.isNotEmpty) {
                    addSectionHeader(l10n.todayLabel);
                    addVisibleRows(sectionKey: 'today', rows: today);
                  }

                  if (yesterday.isNotEmpty) {
                    addSectionHeader(l10n.yesterdayLabel);
                    addVisibleRows(sectionKey: 'yesterday', rows: yesterday);
                  }

                  if (thisMonth.isNotEmpty) {
                    addSectionHeader(l10n.thisMonthLabel);
                    addVisibleRows(sectionKey: 'this-month', rows: thisMonth);
                  }

                  final previousMonthKeys = previousMonthsCurrentYear.keys.toList()
                    ..sort((a, b) => b.compareTo(a));
                  for (final key in previousMonthKeys) {
                    final rows = previousMonthsCurrentYear[key] ?? const <CatchemSongEntry>[];
                    if (rows.isEmpty) {
                      continue;
                    }
                    final sampleDate = DateTime.parse('$key-01');
                    final expanded = _expandedCatchemMonths.contains(key);
                    content.add(
                      ListTile(
                        dense: true,
                        title: Text(monthLabel(sampleDate)),
                        subtitle: Text(l10n.catchemPlayedSongsCount(rows.length)),
                        trailing: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                        onTap: () {
                          setState(() {
                            if (expanded) {
                              _expandedCatchemMonths.remove(key);
                            } else {
                              _expandedCatchemMonths.add(key);
                            }
                          });
                        },
                      ),
                    );
                    if (expanded) {
                      addVisibleRows(sectionKey: 'month-$key', rows: rows);
                    }
                  }

                  final yearKeys = previousYears.keys.toList()..sort((a, b) => b.compareTo(a));
                  for (final year in yearKeys) {
                    final expandedYear = _expandedCatchemYears.contains(year);
                    final months = previousYears[year] ?? const <String, List<CatchemSongEntry>>{};
                    final totalYearSongs = months.values.fold<int>(0, (acc, value) => acc + value.length);
                    content.add(
                      ListTile(
                        dense: true,
                        title: Text('$year'),
                        subtitle: Text(l10n.catchemPlayedSongsCount(totalYearSongs)),
                        trailing: Icon(expandedYear ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                        onTap: () {
                          setState(() {
                            if (expandedYear) {
                              _expandedCatchemYears.remove(year);
                            } else {
                              _expandedCatchemYears.add(year);
                            }
                          });
                        },
                      ),
                    );

                    if (!expandedYear) {
                      continue;
                    }

                    final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
                    for (final key in monthKeys) {
                      final rows = months[key] ?? const <CatchemSongEntry>[];
                      if (rows.isEmpty) {
                        continue;
                      }
                      final monthId = '$year-$key';
                      final expandedMonth = _expandedCatchemYearMonths.contains(monthId);
                      final sampleDate = DateTime.parse('$key-01');
                      content.add(
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: ListTile(
                            dense: true,
                            title: Text(monthYearLabel(sampleDate)),
                            subtitle: Text(l10n.catchemPlayedSongsCount(rows.length)),
                            trailing: Icon(expandedMonth ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                            onTap: () {
                              setState(() {
                                if (expandedMonth) {
                                  _expandedCatchemYearMonths.remove(monthId);
                                } else {
                                  _expandedCatchemYearMonths.add(monthId);
                                }
                              });
                            },
                          ),
                        ),
                      );
                      if (expandedMonth) {
                        addVisibleRows(sectionKey: 'year-month-$monthId', rows: rows);
                      }
                    }
                  }
                }

                if (content.isEmpty) {
                  return Center(
                    child: Text(
                      favoritesSearchQuery.isEmpty ? l10n.noCatchemYet : l10n.noResults,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView(
                  controller: _catchemScrollController,
                  children: content,
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              if (!widget.controller.isLoadingMoreCatchem) {
                return const SizedBox.shrink();
              }
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catchemScrollController.addListener(() {
      if (!_catchemScrollController.hasClients) {
        return;
      }
      final position = _catchemScrollController.position;
      if (position.pixels + 320 >= position.maxScrollExtent) {
        unawaited(
          widget.controller.loadMoreCatchemLibraryIfNeeded(
            visibleIndex: widget.controller.catchemLibrary.length - 1,
          ),
        );
      }
    });
    widget.controller.addListener(_onControllerChanged);
    unawaited(_loadAppearancePreferences());
    _syncWakeLockWithPlayback(
      shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
    );
    _schedulePermissionCheck();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final timer in _pendingCatchemDeleteTimers.values) {
      timer.cancel();
    }
    _pendingCatchemDeleteTimers.clear();
    _pendingCatchemDeleteEntries.clear();
    _catchemScrollController.dispose();
    _sleepTimerTicker?.cancel();
    _sleepTimerPulse.dispose();
    WakelockPlus.disable();
    _gallerySearchController.dispose();
    _gallerySearchFocusNode.dispose();
    _favoritesSearchController.dispose();
    _favoritesSearchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggleGallerySearch() {
    setState(() {
      _isGallerySearchOpen = !_isGallerySearchOpen;
      if (!_isGallerySearchOpen) {
        _gallerySearchController.clear();
      }
    });

    if (_isGallerySearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _gallerySearchFocusNode.requestFocus();
      });
    } else {
      _gallerySearchFocusNode.unfocus();
    }
  }

  void _toggleFavoritesSearch() {
    setState(() {
      _isFavoritesSearchOpen = !_isFavoritesSearchOpen;
      if (!_isFavoritesSearchOpen) {
        _favoritesSearchController.clear();
      }
    });

    if (_isFavoritesSearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _favoritesSearchFocusNode.requestFocus();
      });
    } else {
      _favoritesSearchFocusNode.unfocus();
    }
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
      final snapshotDates = <String, DateTime>{};
      final snapshotDisplayNames = <String, String>{};
      final snapshotTitles = <String, String>{};
      final snapshotArtists = <String, String>{};
      final snapshotSourcePackages = <String, String>{};
      final pendingScreenshotSync = <Future<void>>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map) {
            final uri = (entry['uri'] ?? '').toString().trim();
            if (uri.isEmpty) {
              continue;
            }
            uris.add(uri);
            final rawMs = entry['dateAddedMs'];
            int? ms;
            if (rawMs is int) {
              ms = rawMs;
            } else if (rawMs is num) {
              ms = rawMs.toInt();
            } else if (rawMs is String) {
              ms = int.tryParse(rawMs);
            }
            snapshotDates[uri] = DateTime.fromMillisecondsSinceEpoch(ms ?? 0);
            snapshotDisplayNames[uri] = (entry['displayName'] ?? '').toString().trim();
            snapshotTitles[uri] = (entry['title'] ?? '').toString().trim();
            snapshotArtists[uri] = (entry['artist'] ?? '').toString().trim();
            snapshotSourcePackages[uri] = (entry['sourcePackage'] ?? '').toString().trim();
            pendingScreenshotSync.add(
              widget.controller.registerSavedScreenshot(
                uri: uri,
                dateAddedMs: ms ?? 0,
                displayName: snapshotDisplayNames[uri],
                title: snapshotTitles[uri],
                artist: snapshotArtists[uri],
                sourcePackage: snapshotSourcePackages[uri],
              ),
            );
            continue;
          }

          final value = (entry ?? '').toString().trim();
          if (value.isNotEmpty) {
            uris.add(value);
            snapshotDates[value] = DateTime.fromMillisecondsSinceEpoch(0);
          }
        }
      }

      if (pendingScreenshotSync.isNotEmpty) {
        await Future.wait(pendingScreenshotSync);
      }

      uris.sort((a, b) {
        final aMs = snapshotDates[a]?.millisecondsSinceEpoch ?? 0;
        final bMs = snapshotDates[b]?.millisecondsSinceEpoch ?? 0;
        return bMs.compareTo(aMs);
      });

      if (!mounted) {
        return;
      }

      final hadSnapshotsBefore = _savedSnapshotUris.isNotEmpty;
      setState(() {
        _savedSnapshotUris = uris;
        _savedSnapshotDateByUri
          ..clear()
          ..addAll(snapshotDates);
        _savedSnapshotDisplayNameByUri
          ..clear()
          ..addAll(snapshotDisplayNames);
        _savedSnapshotTitleByUri
          ..clear()
          ..addAll(snapshotTitles);
        _savedSnapshotArtistByUri
          ..clear()
          ..addAll(snapshotArtists);
        _savedSnapshotSourcePackageByUri
          ..clear()
          ..addAll(snapshotSourcePackages);
        final updatedCache = <String, Future<Uint8List?>>{};
        for (final uri in uris) {
          updatedCache[uri] = force
              ? _readSnapshotImageBytes(uri)
              : (_snapshotBytesFutureByUri[uri] ?? _readSnapshotImageBytes(uri));
        }
        _snapshotBytesFutureByUri
          ..clear()
          ..addAll(updatedCache);
        if (hadSnapshotsBefore && uris.isEmpty && _activeNavIndex == 1) {
          _activeNavIndex = 0;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      final hadSnapshotsBefore = _savedSnapshotUris.isNotEmpty;
      setState(() {
        _savedSnapshotUris = const <String>[];
        _savedSnapshotDateByUri.clear();
        _savedSnapshotDisplayNameByUri.clear();
        _savedSnapshotTitleByUri.clear();
        _savedSnapshotArtistByUri.clear();
        _savedSnapshotSourcePackageByUri.clear();
        _snapshotBytesFutureByUri.clear();
        if (hadSnapshotsBefore && _activeNavIndex == 1) {
          _activeNavIndex = 0;
        }
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

  Future<bool> _saveSnapshotBytesToGallery(
    Uint8List bytes, {
    required String fileName,
    String? replaceUri,
  }) async {
    try {
      final saved = await _lyricsMethodsChannel.invokeMethod<dynamic>(
        'saveSnapshotImage',
        {
          'bytes': bytes,
          'fileName': fileName,
          if ((replaceUri ?? '').trim().isNotEmpty) 'replaceUri': replaceUri,
        },
      );
      return saved == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editSavedSnapshotFromGallery(String uri) async {
    final displayName = _savedSnapshotDisplayNameByUri[uri] ?? '';
    final l10n = AppLocalizations.of(context);
    if (displayName.trim().isEmpty) {
      AppTopFeedback.show(context, 'No se pudo leer metadata de esta imagen');
      return;
    }

    final metadata = await SnapshotEditorStore.readMetadataForDisplayName(displayName);
    if (!mounted) {
      return;
    }
    if (metadata == null || metadata.lyricsLines.isEmpty) {
      AppTopFeedback.show(context, 'Esta imagen no tiene datos editables guardados');
      return;
    }

    final artworkImage = await SnapshotArtworkTools.loadArtworkImage(metadata.artworkUrl);
    final extractedPalette = await SnapshotArtworkTools.extractPalette(artworkImage);
    if (!mounted) {
      return;
    }

    var persistedSelectedLineIndices = metadata.activeLineIndexes
        .where((index) => index >= 0 && index < metadata.lyricsLines.length)
        .toSet();
    if (persistedSelectedLineIndices.isEmpty &&
        metadata.activeLineIndex >= 0 &&
        metadata.activeLineIndex < metadata.lyricsLines.length) {
      persistedSelectedLineIndices = <int>{metadata.activeLineIndex};
    }
    if (persistedSelectedLineIndices.isEmpty && metadata.lyricsLines.isNotEmpty) {
      persistedSelectedLineIndices = <int>{0};
    }

    SnapshotDialogResult? preview;
    while (mounted) {
      final lineSelection = await _showSnapshotLineSelectionDialog(
        lines: metadata.lyricsLines,
        initialIndexes: persistedSelectedLineIndices,
      );
      if (!mounted || lineSelection == null) {
        return;
      }
      persistedSelectedLineIndices = lineSelection;

      final stepPreview = await _showSnapshotEditPreviewDialog(
        metadata: metadata,
        selectedLineIndices: persistedSelectedLineIndices,
        artworkImage: artworkImage,
        extractedPalette: extractedPalette,
      );
      if (!mounted) {
        return;
      }
      if (stepPreview == null) {
        continue;
      }
      if (stepPreview.action == SnapshotDialogAction.back) {
        continue;
      }

      preview = stepPreview;
      break;
    }
    if (!mounted || preview == null) {
      return;
    }

    final fileName = displayName;
    final sortedSelectedIndices = persistedSelectedLineIndices.toList()..sort();
    final metadataToSave = metadata.copyWith(
      useArtworkBackground: preview.useArtworkBackground,
      generatedThemeBrightness:
          preview.generatedBrightness == Brightness.dark ? 'dark' : 'light',
      activeLineIndex: sortedSelectedIndices.isEmpty ? -1 : sortedSelectedIndices.first,
      activeLineIndexes: sortedSelectedIndices,
      selectedColorValue: preview.selectedColor?.toARGB32(),
    );

    if (preview.action == SnapshotDialogAction.save) {
      final saved = await _saveSnapshotBytesToGallery(
        preview.pngBytes,
        fileName: fileName,
        replaceUri: uri,
      );
      if (!mounted) {
        return;
      }
      if (!saved) {
        AppTopFeedback.show(context, l10n.snapshotError);
        return;
      }

      await SnapshotEditorStore.saveMetadataForDisplayName(
        displayName: displayName,
        metadata: metadataToSave,
      );
      _snapshotBytesFutureByUri.remove(uri);
      await _loadSavedSnapshots(force: true);
      if (mounted) {
        AppTopFeedback.show(context, l10n.snapshotSaved);
      }
      return;
    }

    final shared = await _shareSnapshotBytes(preview.pngBytes, fileName: fileName);
    if (!mounted) {
      return;
    }
    if (!shared) {
      AppTopFeedback.show(context, l10n.snapshotError);
    }
  }

  Future<Set<int>?> _showSnapshotLineSelectionDialog({
    required List<String> lines,
    required Set<int> initialIndexes,
  }) async {
    final l10n = AppLocalizations.of(context);
    return SnapshotDialogTools.showLineSelectionDialog(
      context: context,
      lines: lines,
      initialIndexes: initialIndexes,
      title: l10n.snapshotLineSelectionTitle,
      nextLabel: l10n.next,
    );
  }

  Future<SnapshotDialogResult?> _showSnapshotEditPreviewDialog({
    required SnapshotEditorMetadata metadata,
    required Set<int> selectedLineIndices,
    required ui.Image? artworkImage,
    required List<Color> extractedPalette,
  }) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final themeDefaultColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerHighest;
    final fallbackIndex = metadata.activeLineIndexes.isNotEmpty
        ? metadata.activeLineIndexes.first
        : metadata.activeLineIndex;
    final window = SnapshotFlowTools.buildWindowAroundSelection(
      sourceLines: metadata.lyricsLines,
      selectedLineIndices: selectedLineIndices,
      linesAbove: 2,
      linesBelow: 2,
      fallbackIndex: fallbackIndex,
    );
    final dominantColor = await SnapshotArtworkTools.extractDominantColor(artworkImage);
    final palette = SnapshotFlowTools.buildPaletteOptions(
      extractedPalette: extractedPalette,
      defaultColor: themeDefaultColor,
      fallbackColor: dominantColor ?? themeDefaultColor,
      theme: theme,
    );
    var selectedColor = metadata.selectedColorValue == null
        ? palette.first
        : Color(metadata.selectedColorValue!);
    var useArtworkBackground = metadata.useArtworkBackground;
    var generatedBrightness = switch (metadata.generatedThemeBrightness) {
      'dark' => Brightness.dark,
      'light' => Brightness.light,
      _ => theme.brightness,
    };
    if (!palette.any((color) => color.toARGB32() == selectedColor.toARGB32())) {
      selectedColor = palette.first;
    }

    final generationTheme = SnapshotFlowTools.buildGenerationTheme(
      baseTheme: theme,
      brightness: generatedBrightness,
    );
    final initialPreviewCardAlpha = generatedBrightness == Brightness.light ? 0.66 : 0.80;

    final initialBytes = await SnapshotRenderer.buildPng(
      SnapshotRenderRequest(
        theme: generationTheme,
        songTitle: metadata.songTitle,
        artistName: metadata.artistName,
        useArtworkBackground: useArtworkBackground,
        lyricsLines: window.lines,
        activeLineIndex: window.activeLineIndices.isEmpty ? -1 : window.activeLineIndices.first,
        activeLineIndices: window.activeLineIndices,
        noLyricsFallback: l10n.snapshotNoLyrics,
        generatedWithBrand: l10n.snapshotGeneratedWithBrand,
        artworkUrl: metadata.artworkUrl,
        selectedColor: selectedColor,
        preloadedArtworkImage: artworkImage,
        renderScale: 0.95,
        cardSurfaceAlpha: initialPreviewCardAlpha,
      ),
    );
    if (initialBytes == null || initialBytes.isEmpty || !mounted) {
      return null;
    }

    final result = await SnapshotDialogTools.showPreviewDialog(
      context: context,
      initialBytes: initialBytes,
      initialColor: selectedColor,
      initialUseArtworkBackground: useArtworkBackground,
      initialGeneratedBrightness: generatedBrightness,
      canUseArtworkBackground: artworkImage != null,
      palette: palette,
      backTooltip: AppLocalizations.of(context).back,
      saveTooltip: l10n.saveToGallery,
      shareTooltip: l10n.share,
      useArtworkBackgroundLabel: l10n.useArtworkBackground,
      lightThemeLabel: l10n.switchToLightMode,
      darkThemeLabel: l10n.switchToDarkMode,
      onShareInPlace: (currentState) async {
        final shared = await _shareSnapshotBytes(
          currentState.pngBytes,
          fileName: 'singsync_snapshot_edit_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        if (mounted && !shared) {
          AppTopFeedback.show(context, l10n.snapshotError);
        }
        return false;
      },
      rerender: (color, shouldUseArtworkBackground, brightness) {
        useArtworkBackground = shouldUseArtworkBackground;
        generatedBrightness = brightness;
        final rerenderTheme = SnapshotFlowTools.buildGenerationTheme(
          baseTheme: theme,
          brightness: brightness,
        );
        final previewCardAlpha = brightness == Brightness.light ? 0.66 : 0.80;
        return SnapshotRenderer.buildPng(
          SnapshotRenderRequest(
            theme: rerenderTheme,
            songTitle: metadata.songTitle,
            artistName: metadata.artistName,
            useArtworkBackground: shouldUseArtworkBackground,
            lyricsLines: window.lines,
            activeLineIndex: window.activeLineIndices.isEmpty ? -1 : window.activeLineIndices.first,
            activeLineIndices: window.activeLineIndices,
            noLyricsFallback: l10n.snapshotNoLyrics,
            generatedWithBrand: l10n.snapshotGeneratedWithBrand,
            artworkUrl: metadata.artworkUrl,
            selectedColor: color,
            preloadedArtworkImage: artworkImage,
            renderScale: 0.95,
            cardSurfaceAlpha: previewCardAlpha,
          ),
        );
      },
    );

    if (result == null || result.action != SnapshotDialogAction.save) {
      return result;
    }

    final finalTheme = SnapshotFlowTools.buildGenerationTheme(
      baseTheme: theme,
      brightness: result.generatedBrightness,
    );
    final finalCardAlpha = result.generatedBrightness == Brightness.light ? 0.66 : 0.80;
    final fullBytes = await SnapshotRenderer.buildPng(
      SnapshotRenderRequest(
        theme: finalTheme,
        songTitle: metadata.songTitle,
        artistName: metadata.artistName,
        useArtworkBackground: result.useArtworkBackground,
        lyricsLines: window.lines,
        activeLineIndex: window.activeLineIndices.isEmpty ? -1 : window.activeLineIndices.first,
        activeLineIndices: window.activeLineIndices,
        noLyricsFallback: l10n.snapshotNoLyrics,
        generatedWithBrand: l10n.snapshotGeneratedWithBrand,
        artworkUrl: metadata.artworkUrl,
        selectedColor: result.selectedColor ?? selectedColor,
        preloadedArtworkImage: artworkImage,
        cardSurfaceAlpha: finalCardAlpha,
      ),
    );

    if (!mounted || fullBytes == null || fullBytes.isEmpty) {
      return result;
    }

    return SnapshotDialogResult(
      pngBytes: fullBytes,
      selectedColor: result.selectedColor,
      useArtworkBackground: result.useArtworkBackground,
      generatedBrightness: result.generatedBrightness,
      action: result.action,
    );
  }

  Future<void> _showSavedSnapshotPreview({required int startIndex}) async {
    if (_savedSnapshotUris.isEmpty) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final initialIndex = startIndex.clamp(0, _savedSnapshotUris.length - 1);
    final localUris = List<String>.from(_savedSnapshotUris);
    final pageController = PageController(initialPage: initialIndex);
    final thumbnailScrollController = ScrollController();
    final thumbnailKeys = List<GlobalKey>.generate(
      localUris.length,
      (_) => GlobalKey(),
      growable: false,
    );
    var currentIndex = initialIndex;

    void scrollToCurrentThumbnail() {
      if (currentIndex < 0 || currentIndex >= thumbnailKeys.length) {
        return;
      }
      final thumbnailContext = thumbnailKeys[currentIndex].currentContext;
      if (thumbnailContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        thumbnailContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }

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
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        scrollToCurrentThumbnail();
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
                                  controller: thumbnailScrollController,
                                  scrollDirection: Axis.horizontal,
                                  itemCount: localUris.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final uri = localUris[index];
                                    final isSelected = index == currentIndex;
                                    return InkWell(
                                      key: thumbnailKeys[index],
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
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    onPressed: localUris.isEmpty
                                        ? null
                                        : () async {
                                              final uri = localUris[currentIndex];
                                              Navigator.of(dialogContext).pop();
                                              await _editSavedSnapshotFromGallery(uri);
                                            },
                                    tooltip: 'Editar',
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
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
                                                  _savedSnapshotDateByUri.remove(uri);
                                                  _savedSnapshotDisplayNameByUri.remove(uri);
                                                  _savedSnapshotTitleByUri.remove(uri);
                                                  _savedSnapshotArtistByUri.remove(uri);
                                                  _savedSnapshotSourcePackageByUri.remove(uri);
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
                                    tooltip: l10n.delete,
                                    icon: const Icon(Icons.delete_outline_rounded),
                                  ),
                                  IconButton(
                                    onPressed: localUris.isEmpty
                                        ? null
                                        : () async {
                                              final uri = localUris[currentIndex];
                                              final bytes = await loadBytesForUri(uri);
                                              if (bytes == null || bytes.isEmpty) {
                                                if (mounted) {
                                                  AppTopFeedback.show(this.context, l10n.snapshotError);
                                                }
                                                return;
                                              }

                                              if (!dialogContext.mounted) {
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
                                              AppTopFeedback.show(this.context, l10n.snapshotError);
                                            },
                                    tooltip: l10n.share,
                                    icon: const Icon(Icons.share_rounded),
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
    thumbnailScrollController.dispose();
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
    final searchQuery = _gallerySearchController.text.trim();
    final snapshotSections = _buildSnapshotSections(context, query: searchQuery);
    final hasSearchQuery = searchQuery.isNotEmpty;
    final hasFilteredResults = snapshotSections.any((section) => section.uris.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.savedSnapshotsTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _toggleGallerySearch,
                icon: Icon(
                  _isGallerySearchOpen ? Icons.close_rounded : Icons.search_rounded,
                ),
                tooltip: _isGallerySearchOpen ? l10n.close : l10n.search,
              ),
            ],
          ),
          if (_isGallerySearchOpen) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _gallerySearchController,
              focusNode: _gallerySearchFocusNode,
              autofocus: true,
              onTapOutside: (_) {
                _gallerySearchFocusNode.unfocus();
              },
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                if (!mounted) {
                  return;
                }
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: l10n.searchBySongOrArtist,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_isGalleryPinching) {
                  return;
                }
                await _loadSavedSnapshots(force: true);
              },
              notificationPredicate: (_) => !_isGalleryPinching,
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
                      : (hasSearchQuery && !hasFilteredResults)
                          ? ListView(
                              children: [
                                const SizedBox(height: 140),
                                Center(
                                  child: Text(
                                    l10n.noResults,
                                    style: theme.textTheme.bodyLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                      : Listener(
                          onPointerDown: (_) {
                            _galleryActivePointers += 1;
                            if (_galleryActivePointers >= 2 && !_isGalleryPinching) {
                              setState(() {
                                _isGalleryPinching = true;
                                _snapshotGridScaleAnchor = 1;
                              });
                            }
                          },
                          onPointerUp: (_) {
                            _galleryActivePointers = (_galleryActivePointers - 1).clamp(0, 10);
                            if (_galleryActivePointers < 2 && _isGalleryPinching) {
                              setState(() {
                                _isGalleryPinching = false;
                              });
                            }
                          },
                          onPointerCancel: (_) {
                            _galleryActivePointers = (_galleryActivePointers - 1).clamp(0, 10);
                            if (_galleryActivePointers < 2 && _isGalleryPinching) {
                              setState(() {
                                _isGalleryPinching = false;
                              });
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onScaleStart: (_) {
                              _snapshotGridScaleAnchor = 1;
                            },
                            onScaleUpdate: (details) {
                              if (_galleryActivePointers < 2) {
                                return;
                              }
                              final ratio = details.scale / _snapshotGridScaleAnchor;
                              if (ratio > 1.10 && _snapshotGridCrossAxisCount > 1) {
                                setState(() {
                                  _snapshotGridCrossAxisCount -= 1;
                                });
                                _snapshotGridScaleAnchor = details.scale;
                              } else if (ratio < 0.90 && _snapshotGridCrossAxisCount < 6) {
                                setState(() {
                                  _snapshotGridCrossAxisCount += 1;
                                });
                                _snapshotGridScaleAnchor = details.scale;
                              }
                            },
                            onScaleEnd: (_) {
                              if (_galleryActivePointers < 2 && _isGalleryPinching) {
                                setState(() {
                                  _isGalleryPinching = false;
                                });
                              }
                            },
                            child: CustomScrollView(
                            physics: _isGalleryPinching
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              for (final section in snapshotSections) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8, top: 6),
                                    child: Text(
                                      section.title,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                SliverGrid(
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _snapshotGridCrossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, sectionIndex) {
                                      final uri = section.uris[sectionIndex];
                                      final globalIndex = _savedSnapshotUris.indexOf(uri);
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
                                              if (!mounted || globalIndex < 0) {
                                                return;
                                              }
                                              await _showSavedSnapshotPreview(startIndex: globalIndex);
                                            },
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                DecoratedBox(
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
                                                if (_snapshotGridCrossAxisCount == 1)
                                                  Positioned(
                                                    right: 8,
                                                    bottom: 8,
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Material(
                                                          color: theme.colorScheme.surface.withValues(alpha: 0.70),
                                                          shape: const CircleBorder(),
                                                          child: IconButton(
                                                            icon: const Icon(Icons.delete_outline_rounded),
                                                            tooltip: l10n.delete,
                                                            onPressed: () async {
                                                              final deleted = await _deleteSavedSnapshotByUri(uri);
                                                              if (!mounted) {
                                                                return;
                                                              }
                                                              if (!deleted) {
                                                                AppTopFeedback.show(this.context, l10n.snapshotError);
                                                                return;
                                                              }
                                                              setState(() {
                                                                _savedSnapshotUris = _savedSnapshotUris
                                                                    .where((item) => item != uri)
                                                                    .toList(growable: false);
                                                                _savedSnapshotDateByUri.remove(uri);
                                                                _savedSnapshotDisplayNameByUri.remove(uri);
                                                                _savedSnapshotTitleByUri.remove(uri);
                                                                _savedSnapshotArtistByUri.remove(uri);
                                                                _savedSnapshotSourcePackageByUri.remove(uri);
                                                                _snapshotBytesFutureByUri.remove(uri);
                                                              });
                                                              AppTopFeedback.show(this.context, l10n.snapshotDeleted);
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Material(
                                                          color: theme.colorScheme.surface.withValues(alpha: 0.70),
                                                          shape: const CircleBorder(),
                                                          child: IconButton(
                                                            icon: const Icon(Icons.edit_outlined),
                                                            tooltip: 'Editar',
                                                            onPressed: () async {
                                                              await _editSavedSnapshotFromGallery(uri);
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Material(
                                                          color: theme.colorScheme.surface.withValues(alpha: 0.70),
                                                          shape: const CircleBorder(),
                                                          child: IconButton(
                                                            icon: const Icon(Icons.share_rounded),
                                                            tooltip: l10n.share,
                                                            onPressed: () async {
                                                              final bytes = await bytesFuture;
                                                              if (!mounted) {
                                                                return;
                                                              }
                                                              if (bytes == null || bytes.isEmpty) {
                                                                AppTopFeedback.show(this.context, l10n.snapshotError);
                                                                return;
                                                              }
                                                              final shared = await _shareSnapshotBytes(
                                                                bytes,
                                                                fileName:
                                                                    'singsync_snapshot_gallery_${DateTime.now().millisecondsSinceEpoch}.png',
                                                              );
                                                              if (!mounted || shared) {
                                                                return;
                                                              }
                                                              AppTopFeedback.show(this.context, l10n.snapshotError);
                                                            },
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    childCount: section.uris.length,
                                  ),
                                ),
                                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                              ],
                            ],
                          ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  List<_SnapshotSection> _buildSnapshotSections(BuildContext context, {String query = ''}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
    final l10n = AppLocalizations.of(context);

    final todayLabel = l10n.todayLabel;
    final weekLabel = l10n.thisWeekLabel;
    final olderLabel = l10n.olderLabel;

    final today = <String>[];
    final week = <String>[];
    final older = <String>[];
    final normalizedQuery = _normalizeSearchText(query);
    final queryTerms = normalizedQuery
        .split(' ')
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    for (final uri in _savedSnapshotUris) {
      if (queryTerms.isNotEmpty) {
        final title = _savedSnapshotTitleByUri[uri] ?? '';
        final artist = _savedSnapshotArtistByUri[uri] ?? '';
        final displayName = _savedSnapshotDisplayNameByUri[uri] ?? '';
        final searchable = _normalizeSearchText('$title $artist $displayName');
        final matchesAllTerms = queryTerms.every(searchable.contains);
        if (!matchesAllTerms) {
          continue;
        }
      }

      final shotDate = _savedSnapshotDateByUri[uri] ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (shotDate.isAfter(todayStart) || shotDate.isAtSameMomentAs(todayStart)) {
        today.add(uri);
      } else if (shotDate.isAfter(weekStart) || shotDate.isAtSameMomentAs(weekStart)) {
        week.add(uri);
      } else {
        older.add(uri);
      }
    }

    final sections = <_SnapshotSection>[];
    if (today.isNotEmpty) {
      sections.add(_SnapshotSection(title: todayLabel, uris: today));
    }
    if (week.isNotEmpty) {
      sections.add(_SnapshotSection(title: weekLabel, uris: week));
    }
    if (older.isNotEmpty) {
      sections.add(_SnapshotSection(title: olderLabel, uris: older));
    }

    return sections;
  }

  String _normalizeSearchText(String input) {
    final lower = input.toLowerCase();
    const replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'ā': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'ē': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ī': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ø': 'o',
      'ō': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ū': 'u',
      'ñ': 'n',
      'ç': 'c',
      'ý': 'y',
      'ÿ': 'y',
      'ß': 'ss',
      'æ': 'ae',
      'œ': 'oe',
    };

    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final replaced = replacements[char] ?? char;
      if (RegExp(r'[a-z0-9\s]').hasMatch(replaced)) {
        buffer.write(replaced);
      } else {
        buffer.write(' ');
      }
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _catchemTimeLabel(int epochMs) {
    if (epochMs <= 0) {
      return '--:--';
    }
    final dateTime = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diffDays = today.difference(target).inDays;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    if (diffDays > 1) {
      return DateFormat('dd/MM/yyyy HH:mm', localeTag).format(dateTime);
    }
    return DateFormat('h:mm a', localeTag).format(dateTime).toLowerCase();
  }

  String _catchemObsessionEmoji(AppLocalizations l10n, int count, int lastDetectedAtMs) {
    final normalized = count <= 0 ? 1 : count;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final detectedAt = DateTime.fromMillisecondsSinceEpoch(lastDetectedAtMs <= 0 ? 0 : lastDetectedAtMs);
    final detectedDay = DateTime(detectedAt.year, detectedAt.month, detectedAt.day);
    if (normalized <= 1) {
      return '🕵️';
    }
    if (normalized >= 10 && detectedDay == today) {
      return '🔥';
    }
    if (normalized > 5) {
      return '🔄';
    }
    return '🛰️';
  }

  Future<void> _showCatchemCaptureHistory(CatchemSongEntry item) async {
    final l10n = AppLocalizations.of(context);
    final playbackHistory = await widget.controller.loadPlaybackHistoryForSong(
      title: item.title,
      artist: item.artist,
    );
    if (!mounted) {
      return;
    }

    String playedAtLabel(int epochMs) {
      if (epochMs <= 0) {
        return l10n.catchemTimestampUnknown;
      }
      final localeTag = Localizations.localeOf(context).toLanguageTag();
      return DateFormat('dd/MM/yyyy • h:mm a', localeTag)
          .format(DateTime.fromMillisecondsSinceEpoch(epochMs))
          .toLowerCase();
    }

    Future<void> openPlaybackOnMap(CatchemPlaybackRecord record) async {
      final lat = record.latitude;
      final lng = record.longitude;
      if (lat == null || lng == null) {
        AppTopFeedback.show(context, l10n.catchemMapNoPoints);
        return;
      }

      final center = LatLng(lat, lng);
      final infoLine = '${item.title} - ${item.artist} • ${playedAtLabel(record.playedAtMs)}';
      final artwork = _buildArtworkImageProvider(item.artworkUrl);

      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (mapContext) {
          final theme = Theme.of(mapContext);
          final isDarkMap = theme.brightness == Brightness.dark;
          final tileUrlTemplate = isDarkMap
              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
          final mapController = MapController();

          return SizedBox(
            height: MediaQuery.of(mapContext).size.height * 0.68,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    infoLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(mapContext).pop(),
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 17,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: tileUrlTemplate,
                        subdomains: const <String>['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'net.iozamudioa.singsync',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: center,
                            width: 84,
                            height: 84,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 2,
                                ),
                                image: artwork != null
                                    ? DecorationImage(image: artwork, fit: BoxFit.cover)
                                    : null,
                                color: artwork == null
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                              ),
                              child: artwork == null
                                  ? Icon(
                                      Icons.music_note_rounded,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  '${item.title} - ${item.artist}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_catchemObsessionEmoji(l10n, playbackHistory.length, item.lastDetectedAtMs)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              Expanded(
                child: playbackHistory.isEmpty
                    ? Center(
                        child: Text(
                          l10n.catchemNoPlaybackHistoryYet,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: playbackHistory.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final record = playbackHistory[index];
                          final timestamp = playedAtLabel(record.playedAtMs);
                          return ListTile(
                            leading: _buildMediaSourceIcon(record.sourcePackage),
                            title: Text(timestamp),
                            onTap: () => unawaited(openPlaybackOnMap(record)),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSongPlaybackLocationsMap(CatchemSongEntry item) async {
    final l10n = AppLocalizations.of(context);
    final playbackHistory = await widget.controller.loadPlaybackHistoryForSong(
      title: item.title,
      artist: item.artist,
    );
    if (!mounted) {
      return;
    }

    final geolocatedRecords = playbackHistory
      .where((record) => record.latitude != null && record.longitude != null)
      .toList(growable: false);

    final rawPoints = geolocatedRecords
      .map((record) => LatLng(record.latitude!, record.longitude!))
      .toList(growable: false);

    if (rawPoints.isEmpty) {
      AppTopFeedback.show(context, l10n.catchemMapNoPoints);
      return;
    }

    double minLat = rawPoints.first.latitude;
    double maxLat = rawPoints.first.latitude;
    double minLng = rawPoints.first.longitude;
    double maxLng = rawPoints.first.longitude;
    for (final point in rawPoints) {
      if (point.latitude < minLat) {
        minLat = point.latitude;
      }
      if (point.latitude > maxLat) {
        maxLat = point.latitude;
      }
      if (point.longitude < minLng) {
        minLng = point.longitude;
      }
      if (point.longitude > maxLng) {
        maxLng = point.longitude;
      }
    }

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final maxSpan = math.max(latSpan, lngSpan);
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    double zoomForSpan(double span) {
      if (span > 20) return 3.2;
      if (span > 8) return 4.6;
      if (span > 3) return 6.0;
      if (span > 1) return 7.4;
      if (span > 0.3) return 9.0;
      if (span > 0.08) return 10.8;
      if (span > 0.02) return 12.8;
      if (span > 0.005) return 14.4;
      return 16.0;
    }

    final initialZoom = zoomForSpan(maxSpan);
    final artwork = _buildArtworkImageProvider(item.artworkUrl);

    final pointsPerBucket = <String, int>{};
    final songMarkers = <_SongPlaybackMapMarker>[];
    for (final record in geolocatedRecords) {
      final lat = record.latitude!;
      final lng = record.longitude!;
      final bucket = '${lat.toStringAsFixed(5)}|${lng.toStringAsFixed(5)}';
      final localIndex = pointsPerBucket[bucket] ?? 0;
      pointsPerBucket[bucket] = localIndex + 1;

      final scattered = _buildScatteredPoint(
        lat: lat,
        lng: lng,
        seedKey: '${item.title}|${item.artist}|${record.playedAtMs}|$localIndex',
        localIndex: localIndex,
        zoom: initialZoom,
      );

      songMarkers.add(
        _SongPlaybackMapMarker(
          markerId: '$bucket|$localIndex|${record.playedAtMs}',
          point: scattered.point,
          rotation: scattered.rotation,
          playedAtMs: record.playedAtMs,
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (mapContext) {
        final theme = Theme.of(mapContext);
        final isDarkMap = theme.brightness == Brightness.dark;
        final tileUrlTemplate = isDarkMap
            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
            : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
        final localeTag = Localizations.localeOf(mapContext).toLanguageTag();
        String? selectedMarkerId;

        return StatefulBuilder(
          builder: (context, setModalState) {
            String playbackLabel(int epochMs) {
              if (epochMs <= 0) {
                return l10n.catchemTimestampUnknown;
              }
              return DateFormat('dd/MM/yyyy • h:mm a', localeTag)
                  .format(DateTime.fromMillisecondsSinceEpoch(epochMs))
                  .toLowerCase();
            }

            return SizedBox(
              height: MediaQuery.of(mapContext).size.height * 0.72,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      '${item.title} - ${item.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_mapPlayCountLabel(mapContext, playbackHistory.length)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.close,
                      onPressed: () => Navigator.of(mapContext).pop(),
                    ),
                  ),
                  Expanded(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: initialZoom,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: tileUrlTemplate,
                          subdomains: const <String>['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'net.iozamudioa.singsync',
                        ),
                        MarkerLayer(
                          markers: songMarkers
                              .map(
                                (marker) => Marker(
                                  point: marker.point,
                                  width: 82,
                                  height: 82,
                                  child: Transform.rotate(
                                    angle: marker.rotation,
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedMarkerId = marker.markerId;
                                        });
                                      },
                                      child: _buildUnifiedMapArtworkMarker(
                                        theme: theme,
                                        artwork: artwork,
                                        showTooltip: selectedMarkerId == marker.markerId,
                                        tooltipText: playbackLabel(marker.playedAtMs),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnifiedMapArtworkMarker({
    required ThemeData theme,
    required ImageProvider<Object>? artwork,
    bool showTooltip = false,
    String? tooltipText,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.surface,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            image: artwork != null
                ? DecorationImage(image: artwork, fit: BoxFit.cover)
                : null,
            color: artwork == null
                ? theme.colorScheme.primaryContainer
                : null,
          ),
          child: artwork == null
              ? Icon(
                  Icons.music_note_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                )
              : null,
        ),
        if (showTooltip && (tooltipText ?? '').trim().isNotEmpty)
          Positioned(
            top: -52,
            left: -52,
            child: SizedBox(
              width: 170,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '🕒 ${tooltipText!.trim()}',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  _ScatteredMapPoint _buildScatteredPoint({
    required double lat,
    required double lng,
    required String seedKey,
    required int localIndex,
    required double zoom,
  }) {
    final hash = seedKey.hashCode;
    final jitter = ((hash & 0xFF) / 255.0) - 0.5;
    final ring = (localIndex ~/ 10) + 1;
    final angle = ((localIndex * 137.5) + (hash % 37)) * (math.pi / 180);
    final baseAmplitude = (0.020 / math.pow(2, zoom.clamp(8.0, 20.0) - 8)).clamp(0.00006, 0.0020);
    final radius = baseAmplitude * ring;
    final deltaLat = math.sin(angle) * radius;
    final deltaLng = math.cos(angle) * radius;
    final rotation = (((hash ~/ 541) & 0x7fffffff) / 0x7fffffff - 0.5) * 0.52 + (jitter * 0.06);

    return _ScatteredMapPoint(
      point: LatLng(lat + deltaLat, lng + deltaLng),
      rotation: rotation,
    );
  }

  Future<LatLng?> _tryGetCurrentMapLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LatLng(lastKnown.latitude, lastKnown.longitude);
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
          ),
        );
        return LatLng(position.latitude, position.longitude);
      } catch (_) {
        if (lastKnown != null) {
          return LatLng(lastKnown.latitude, lastKnown.longitude);
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  String _mapCoordinateBucketKey(double lat, double lng) {
    return '${lat.toStringAsFixed(4)}|${lng.toStringAsFixed(4)}';
  }

  String _mapAlbumGroupKeyFromPoint(CatchemMapPointRecord point) {
    final normalizedArtist = point.artist.trim().toLowerCase();
    final normalizedAlbum = (point.albumName ?? '').trim().toLowerCase();
    if (normalizedAlbum.isNotEmpty) {
      return 'album::$normalizedArtist::$normalizedAlbum';
    }
    return 'artist::$normalizedArtist';
  }

  List<_MapLocationGroup> _groupMapPointsByLocation({
    required List<CatchemMapPointRecord> points,
    required Map<String, int> visibleLimitByLocation,
  }) {
    final grouped = <String, List<CatchemMapPointRecord>>{};
    for (final point in points) {
      final locationKey = _mapCoordinateBucketKey(point.latitude, point.longitude);
      grouped.putIfAbsent(locationKey, () => <CatchemMapPointRecord>[]).add(point);
    }

    final groups = <_MapLocationGroup>[];
    for (final entry in grouped.entries) {
      final allLocationPoints = List<CatchemMapPointRecord>.from(entry.value)
        ..sort((a, b) => b.detectedAtMs.compareTo(a.detectedAtMs));

      final dedupedAlbumMarkers = <CatchemMapPointRecord>[];
      final seenAlbumKeys = <String>{};
      for (final point in allLocationPoints) {
        final albumKey = _mapAlbumGroupKeyFromPoint(point);
        if (seenAlbumKeys.add(albumKey)) {
          dedupedAlbumMarkers.add(point);
        }
      }

      if (dedupedAlbumMarkers.isEmpty) {
        continue;
      }

      final visibleLimit = (visibleLimitByLocation[entry.key] ?? 1).clamp(1, 5000);
      final visibleMarkers = dedupedAlbumMarkers.take(visibleLimit).toList(growable: false);

      groups.add(
        _MapLocationGroup(
          key: entry.key,
          latitude: allLocationPoints.first.latitude,
          longitude: allLocationPoints.first.longitude,
          allLocationPoints: allLocationPoints,
          allAlbumMarkers: dedupedAlbumMarkers,
          visibleAlbumMarkers: visibleMarkers,
        ),
      );
    }

    return groups;
  }

  List<_MapLocationGroup> _visibleLocationGroupsForMap({
    required List<_MapLocationGroup> groups,
    required LatLng center,
    required double zoom,
  }) {
    if (groups.isEmpty) {
      return const <_MapLocationGroup>[];
    }

    final latRadius = (0.16 / math.pow(2, zoom.clamp(9.0, 20.0) - 9)).clamp(0.0045, 0.22);
    final lngRadius = latRadius * 1.28;

    final visible = groups.where((group) {
      return (group.latitude - center.latitude).abs() <= latRadius &&
          (group.longitude - center.longitude).abs() <= lngRadius;
    }).toList(growable: false);

    if (visible.isNotEmpty) {
      return visible;
    }

    final fallback = List<_MapLocationGroup>.from(groups)
      ..sort((a, b) {
        final da = math.pow(a.latitude - center.latitude, 2) +
            math.pow(a.longitude - center.longitude, 2);
        final db = math.pow(b.latitude - center.latitude, 2) +
            math.pow(b.longitude - center.longitude, 2);
        return da.compareTo(db);
      });
    return fallback.take(14).toList(growable: false);
  }

  Future<void> _showMapAlbumAtLocationDetail({
    required BuildContext sheetContext,
    required AppLocalizations l10n,
    required _MapLocationGroup group,
    required CatchemMapPointRecord selectedAlbumMarker,
  }) async {
    final selectedAlbumKey = _mapAlbumGroupKeyFromPoint(selectedAlbumMarker);
    final albumPlays = group.allLocationPoints
        .where((point) => _mapAlbumGroupKeyFromPoint(point) == selectedAlbumKey)
        .toList(growable: false)
      ..sort((a, b) => b.detectedAtMs.compareTo(a.detectedAtMs));

    if (albumPlays.isEmpty) {
      return;
    }

    final representative = albumPlays.first;
    final totalPlayCount = albumPlays.length;
    final playCountBySong = <String, int>{};
    final latestPlayBySong = <String, CatchemMapPointRecord>{};
    for (final play in albumPlays) {
      final songKey = '${play.title.trim().toLowerCase()}|${play.artist.trim().toLowerCase()}';
      playCountBySong[songKey] = (playCountBySong[songKey] ?? 0) + 1;
      latestPlayBySong.putIfAbsent(songKey, () => play);
    }
    final groupedSongs = latestPlayBySong.values.toList(growable: false)
      ..sort((a, b) => b.detectedAtMs.compareTo(a.detectedAtMs));

    final headerArtwork = _buildArtworkImageProvider(representative.artworkUrl);
    final headerTitle = (representative.albumName ?? '').trim().isNotEmpty
        ? representative.albumName!.trim()
        : representative.artist;

    await showModalBottomSheet<void>(
      context: sheetContext,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (detailContext) {
        final detailTheme = Theme.of(detailContext);
        return SizedBox(
          height: MediaQuery.of(detailContext).size.height * 0.72,
          child: Column(
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: headerArtwork != null
                      ? Image(
                          image: headerArtwork,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          color: detailTheme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.music_note_rounded),
                        ),
                ),
                title: Text(
                  headerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_mapPlayCountLabel(detailContext, totalPlayCount)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(detailContext).pop(),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: groupedSongs.length,
                  itemBuilder: (context, index) {
                    final song = groupedSongs[index];
                    final songKey = '${song.title.trim().toLowerCase()}|${song.artist.trim().toLowerCase()}';
                    final songPlayCount = playCountBySong[songKey] ?? 1;
                    final obsessionEmoji = songPlayCount >= 10
                        ? '🔥'
                        : (songPlayCount > 5
                            ? '🔄'
                            : (songPlayCount >= 2 ? '🛰️' : '🕵️'));
                    final mapSongEntry = CatchemSongEntry(
                      title: song.title,
                      artist: song.artist,
                      albumName: song.albumName,
                      lyrics: '',
                      artworkUrl: song.artworkUrl,
                      detectCount: songPlayCount,
                      firstDetectedAtMs: song.detectedAtMs,
                      lastDetectedAtMs: song.detectedAtMs,
                      sourceType: song.sourceType,
                      sourcePackage: song.sourcePackage,
                      lyricsSource: '',
                      captureMode: 'automatic',
                      captureHistory: const <CatchemCaptureRecord>[],
                      latitude: song.latitude,
                      longitude: song.longitude,
                    );
                    final isFavorite = widget.controller.isSongFavorite(
                      title: song.title,
                      artist: song.artist,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 12, top: 10, bottom: 10),
                            child: GestureDetector(
                              onTap: () => _showCatchemCaptureHistory(mapSongEntry),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _buildArtworkImageProvider(song.artworkUrl) == null
                                    ? const SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: ColoredBox(color: Colors.black12),
                                      )
                                    : Image(
                                        image: _buildArtworkImageProvider(song.artworkUrl)!,
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
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                await widget.controller.showCatchemInNowPlaying(mapSongEntry);
                                if (!mounted) {
                                  return;
                                }
                                Navigator.of(detailContext).pop();
                                setState(() {
                                  _activeNavIndex = 0;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$obsessionEmoji ${song.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: detailTheme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${song.artist.trim()} • ${_catchemTimeLabel(song.detectedAtMs)} • ${_mapPlayCountLabel(detailContext, songPlayCount)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: detailTheme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: IconButton(
                              tooltip: isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
                              onPressed: () async {
                                final toggledToFavorite = await widget.controller.toggleCatchemFavorite(mapSongEntry);
                                if (!mounted || toggledToFavorite == null) {
                                  return;
                                }
                                AppTopFeedback.show(
                                  context,
                                  toggledToFavorite ? l10n.favoriteAdded : l10n.favoriteRemoved,
                                );
                              },
                              icon: Icon(
                                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              tooltip: l10n.openActivePlayer,
                              onPressed: () => unawaited(_openCatchemPlayer(mapSongEntry)),
                              icon: SizedBox(
                                width: 22,
                                height: 22,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    _buildMediaSourceIcon(mapSongEntry.sourcePackage, size: 20),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        size: 12,
                                        color: detailTheme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCatchemMap() async {
    final mapPoints = await widget.controller.loadCatchemMapPoints();
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final entries = List<CatchemMapPointRecord>.from(mapPoints)
      ..sort((a, b) => b.detectedAtMs.compareTo(a.detectedAtMs));

    if (entries.isEmpty) {
      AppTopFeedback.show(context, l10n.catchemMapNoPoints);
      return;
    }

    final first = entries.first;
    final center = LatLng(first.latitude, first.longitude);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDarkMap = theme.brightness == Brightness.dark;
        final tileUrlTemplate = isDarkMap
            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
            : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
        final mapController = MapController();
        var currentZoom = 16.2;
        var currentCenter = center;
        var locationRequested = false;
        final visibleLimitByLocation = <String, int>{};
        final firstSeenZoomBucketByLocation = <String, int>{};
        var lastMapDebugSignature = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!locationRequested) {
              locationRequested = true;
              unawaited(() async {
                final currentLocation = await _tryGetCurrentMapLocation();
                if (!mounted || currentLocation == null) {
                  return;
                }
                setModalState(() {
                  currentCenter = currentLocation;
                });
                mapController.move(currentLocation, currentZoom);
              }());
            }

            final zoomBucket = currentZoom.floor();
            final groupedByLocation = _groupMapPointsByLocation(
              points: entries,
              visibleLimitByLocation: visibleLimitByLocation,
            );

            final visibleGroups = _visibleLocationGroupsForMap(
              groups: groupedByLocation,
              center: currentCenter,
              zoom: currentZoom,
            );

            final renderPoints = <_MapRenderedPoint>[];
            for (final group in visibleGroups) {
              final slotByAlbumKey = <String, int>{};
              for (var i = 0; i < group.allAlbumMarkers.length; i++) {
                final albumKey = _mapAlbumGroupKeyFromPoint(group.allAlbumMarkers[i]);
                slotByAlbumKey.putIfAbsent(albumKey, () => i);
              }

              final visibleMarkersSorted = List<CatchemMapPointRecord>.from(group.visibleAlbumMarkers)
                ..sort((a, b) => b.detectedAtMs.compareTo(a.detectedAtMs));
              for (var index = 0; index < visibleMarkersSorted.length; index++) {
                final point = visibleMarkersSorted[index];
                final albumKey = _mapAlbumGroupKeyFromPoint(point);
                final stableSlot = slotByAlbumKey[albumKey] ?? index;
                final markerId = '${group.key}|$albumKey';
                renderPoints.add(
                  _MapRenderedPoint(
                    locationKey: group.key,
                    markerId: markerId,
                    localIndex: stableSlot,
                    point: point,
                    group: group,
                  ),
                );
              }
            }

            final renderPointsForLayer = List<_MapRenderedPoint>.from(renderPoints)
              ..sort((a, b) => a.point.detectedAtMs.compareTo(b.point.detectedAtMs));

            final signature = [
              'allPoints=${entries.length}',
              'visibleGroups=${visibleGroups.length}',
              'renderPoints=${renderPoints.length}',
              ...visibleGroups.map((group) => '${group.key}:${group.visibleAlbumMarkers.length}/${group.allAlbumMarkers.length}'),
            ].join('|');
            if (signature != lastMapDebugSignature) {
              lastMapDebugSignature = signature;
              debugPrint(
                '[MAP_GROUP] modal_state all=${entries.length} groups=${visibleGroups.length} rendered=${renderPoints.length}',
              );
            }

            for (final group in visibleGroups) {
              firstSeenZoomBucketByLocation.putIfAbsent(group.key, () => zoomBucket);
            }

            final pointsByMarkerKey = <String, _ScatteredMapPoint>{};
            for (final renderPoint in renderPointsForLayer) {
              final lat = renderPoint.point.latitude;
              final lng = renderPoint.point.longitude;
              final markerKey = renderPoint.markerId;
              pointsByMarkerKey[markerKey] = _buildScatteredPoint(
                lat: lat,
                lng: lng,
                seedKey: '${renderPoint.point.title}|${renderPoint.point.artist}|${renderPoint.point.detectedAtMs}',
                localIndex: renderPoint.localIndex,
                zoom: currentZoom,
              );
            }

            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      l10n.catchemMapTitle,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.close,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: currentZoom,
                            onPositionChanged: (position, _) {
                              final nextZoom = position.zoom;
                              final nextCenter = position.center;
                              final movedEnough =
                                  (nextCenter.latitude - currentCenter.latitude).abs() > 0.0008 ||
                                  (nextCenter.longitude - currentCenter.longitude).abs() > 0.0008;
                              if ((nextZoom - currentZoom).abs() < 0.08 && !movedEnough) {
                                return;
                              }

                              final nextZoomBucket = nextZoom.floor();
                              final priorZoomBucket = currentZoom.floor();
                              final groupedAtNext = _groupMapPointsByLocation(
                                points: entries,
                                visibleLimitByLocation: visibleLimitByLocation,
                              );
                              final visibleAtNext = _visibleLocationGroupsForMap(
                                groups: groupedAtNext,
                                center: nextCenter,
                                zoom: nextZoom,
                              );

                              setModalState(() {
                                currentZoom = nextZoom;
                                currentCenter = nextCenter;

                                for (final group in visibleAtNext) {
                                  firstSeenZoomBucketByLocation.putIfAbsent(group.key, () => nextZoomBucket);
                                  visibleLimitByLocation.putIfAbsent(group.key, () => 1);

                                  final firstSeenBucket = firstSeenZoomBucketByLocation[group.key] ?? nextZoomBucket;
                                  if (nextZoomBucket > priorZoomBucket && nextZoomBucket > firstSeenBucket) {
                                    final steps = nextZoomBucket - firstSeenBucket;
                                    final targetLimit = 1 + (steps * 10);
                                    final currentLimit = visibleLimitByLocation[group.key] ?? 1;
                                    if (targetLimit > currentLimit) {
                                      visibleLimitByLocation[group.key] = targetLimit;
                                    }
                                  }
                                }
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: tileUrlTemplate,
                              subdomains: const <String>['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'net.iozamudioa.singsync',
                            ),
                            MarkerLayer(
                              markers: renderPointsForLayer.map((renderPoint) {
                                final markerKey = renderPoint.markerId;
                                final markerPoint = pointsByMarkerKey[markerKey];
                                final entry = renderPoint.point;
                                final artwork = _buildArtworkImageProvider(entry.artworkUrl);
                                final position = markerPoint?.point ?? LatLng(entry.latitude, entry.longitude);
                                final angle = markerPoint?.rotation ?? 0;
                                return Marker(
                                  point: position,
                                  width: 82,
                                  height: 82,
                                  child: Transform.rotate(
                                    angle: angle,
                                    child: GestureDetector(
                                      onTap: () {
                                        debugPrint(
                                          '[MAP_TAP] location="${renderPoint.group.key}" visible=${renderPoint.group.visibleAlbumMarkers.length} total=${renderPoint.group.allAlbumMarkers.length}',
                                        );
                                        unawaited(
                                          _showMapAlbumAtLocationDetail(
                                            sheetContext: sheetContext,
                                            l10n: l10n,
                                            group: renderPoint.group,
                                            selectedAlbumMarker: renderPoint.point,
                                          ),
                                        );
                                      },
                                      child: _buildUnifiedMapArtworkMarker(
                                        theme: theme,
                                        artwork: artwork,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(growable: false),
                            ),
                          ],
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: FloatingActionButton.small(
                            heroTag: 'map_go_to_current_location',
                            onPressed: () async {
                              final currentLocation = await _tryGetCurrentMapLocation();
                              if (!mounted || currentLocation == null) {
                                return;
                              }
                              setModalState(() {
                                currentCenter = currentLocation;
                              });
                              mapController.move(currentLocation, currentZoom);

                              unawaited(() async {
                                try {
                                  final refined = await Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(
                                      accuracy: LocationAccuracy.high,
                                      timeLimit: Duration(seconds: 5),
                                    ),
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  final refinedPoint = LatLng(refined.latitude, refined.longitude);
                                  setModalState(() {
                                    currentCenter = refinedPoint;
                                  });
                                  mapController.move(refinedPoint, currentZoom);
                                } catch (_) {}
                              }());
                            },
                            tooltip: Localizations.localeOf(sheetContext).languageCode.toLowerCase() == 'es'
                                ? 'Ir a mi ubicación'
                                : 'Go to my location',
                            child: const Icon(Icons.my_location_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
              isSleepTimerActive: _isSleepTimerActive,
              sleepTimerTooltip: _sleepTimerStatusText(context),
              onSleepTimerTap: _showSleepTimerDetailModal,
              onInfoActionReady: (action) {
                _openInfoModalAction = action;
              },
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
              useArtworkBackground: _useArtworkBackground,
              isDarkMode: widget.themeController.isDarkMode,
              onToggleTheme: widget.themeController.toggleTheme,
              onSearchManually: widget.controller.startManualCandidatesFromNowPlaying,
              onExpandedLandscapeModeChanged: _handleExpandedLandscapeModeChanged,
              onSnapshotSavedToGallery: _handleSnapshotSavedToGallery,
              snapshotSaveTargetCenterProvider: _galleryNavIconCenter,
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

  Offset? _galleryNavIconCenter() {
    final targetContext = _galleryNavIconKey.currentContext;
    if (targetContext == null) {
      return null;
    }
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) {
      return null;
    }
    return targetBox.localToGlobal(targetBox.size.center(Offset.zero));
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
        final artworkProvider = _buildArtworkImageProvider(artworkUrl);
        final navHorizontalInset =
          (MediaQuery.of(context).size.width * 0.16).clamp(20.0, 88.0).toDouble();
        final hasSnapshotsDestination = _savedSnapshotUris.isNotEmpty;
        final effectiveNavIndex = hasSnapshotsDestination
            ? _activeNavIndex.clamp(0, 3)
            : _activeNavIndex.clamp(0, 2);
        final backgroundTransitionKey =
            '${widget.controller.songTitle.trim()}|${(artworkUrl ?? '').trim()}';
        _syncWakeLockWithPlayback(
          shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
        );

        return Scaffold(
          resizeToAvoidBottomInset: false,
          extendBody: true,
          bottomNavigationBar: _hideHomeHeaderForExpandedVinyl
              ? null
              : SafeArea(
                  top: false,
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      height: MediaQuery.of(context).orientation == Orientation.landscape ? 58 : 66,
                      backgroundColor: Colors.transparent,
                      indicatorColor: Colors.transparent,
                      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
                        final isSelected = states.contains(WidgetState.selected);
                        return IconThemeData(
                          size: isSelected ? 28 : 24,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: isSelected ? 0.96 : 0.58,
                          ),
                        );
                      }),
                      indicatorShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: navHorizontalInset),
                      child: NavigationBar(
                        backgroundColor: Colors.transparent,
                        selectedIndex: effectiveNavIndex,
                        onDestinationSelected: (index) {
                          unawaited(_handleNavTap(index));
                        },
                        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                        destinations: [
                          const NavigationDestination(
                            icon: Icon(Icons.album_outlined),
                            selectedIcon: Icon(Icons.album_rounded),
                            label: '',
                          ),
                          if (hasSnapshotsDestination)
                            NavigationDestination(
                              icon: Icon(Icons.photo_library_outlined, key: _galleryNavIconKey),
                              selectedIcon: const Icon(Icons.photo_library_rounded),
                              label: '',
                            ),
                          const NavigationDestination(
                            icon: Icon(Icons.library_music_outlined),
                            selectedIcon: Icon(Icons.library_music_rounded),
                            label: '',
                          ),
                          const NavigationDestination(
                            icon: Icon(Icons.more_vert_rounded),
                            selectedIcon: Icon(Icons.more_vert_rounded),
                            label: '',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          body: Stack(
            children: [
              if (_useArtworkBackground && artworkProvider != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 560),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: SizedBox.expand(
                        key: ValueKey(backgroundTransitionKey),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Opacity(
                                opacity: 0.30,
                                child: ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                    child: Image(
                                      image: artworkProvider,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
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
                  child: IndexedStack(
                    index: hasSnapshotsDestination
                        ? _activeNavIndex.clamp(0, 2)
                        : (_activeNavIndex == 0 ? 0 : 1),
                    children: [
                      _buildMainPlaybackPage(theme: theme, l10n: l10n),
                      if (hasSnapshotsDestination)
                        _buildSavedSnapshotsGalleryPage(theme: theme, l10n: l10n),
                      _buildMySongsPage(theme: theme, l10n: l10n),
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

class _SnapshotSection {
  const _SnapshotSection({required this.title, required this.uris});

  final String title;
  final List<String> uris;
}

class _ScatteredMapPoint {
  const _ScatteredMapPoint({
    required this.point,
    required this.rotation,
  });

  final LatLng point;
  final double rotation;
}

class _MapLocationGroup {
  const _MapLocationGroup({
    required this.key,
    required this.latitude,
    required this.longitude,
    required this.allLocationPoints,
    required this.allAlbumMarkers,
    required this.visibleAlbumMarkers,
  });

  final String key;
  final double latitude;
  final double longitude;
  final List<CatchemMapPointRecord> allLocationPoints;
  final List<CatchemMapPointRecord> allAlbumMarkers;
  final List<CatchemMapPointRecord> visibleAlbumMarkers;
}

class _MapRenderedPoint {
  const _MapRenderedPoint({
    required this.locationKey,
    required this.markerId,
    required this.localIndex,
    required this.point,
    required this.group,
  });

  final String locationKey;
  final String markerId;
  final int localIndex;
  final CatchemMapPointRecord point;
  final _MapLocationGroup group;
}

class _SongPlaybackMapMarker {
  const _SongPlaybackMapMarker({
    required this.markerId,
    required this.point,
    required this.rotation,
    required this.playedAtMs,
  });

  final String markerId;
  final LatLng point;
  final double rotation;
  final int playedAtMs;
}
