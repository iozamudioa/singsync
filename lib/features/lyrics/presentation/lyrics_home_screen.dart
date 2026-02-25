import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
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
  final TextEditingController _favoritesSearchController = TextEditingController();
  final FocusNode _favoritesSearchFocusNode = FocusNode();
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
    if (index == 0 || index == 1 || index == 2) {
      if (mounted) {
        setState(() {
          _activeNavIndex = index;
          if (index == 0) {
            _isGallerySearchOpen = false;
            _isFavoritesSearchOpen = false;
            _gallerySearchController.clear();
            _favoritesSearchController.clear();
          }
        });
      }
      if (index == 0) {
        _gallerySearchFocusNode.unfocus();
        _favoritesSearchFocusNode.unfocus();
      }
      if (index == 1) {
        await _loadSavedSnapshots();
      }
      return;
    }

    if (index == 3) {
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

  Widget _buildMySongsPage({
    required ThemeData theme,
    required AppLocalizations l10n,
  }) {
    final favoritesSearchQuery = _normalizeSearchText(_favoritesSearchController.text);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mySongsTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
          Expanded(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final favorites = widget.controller.favoriteLibrary;
                final filteredFavorites = favorites.where((item) {
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

                if (filteredFavorites.isEmpty) {
                  return Center(
                    child: Text(
                      favoritesSearchQuery.isEmpty ? l10n.noFavoritesYet : l10n.noResults,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filteredFavorites.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filteredFavorites[index];
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
                          child: _buildArtworkImageProvider(item.artworkUrl) == null
                              ? const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: ColoredBox(color: Colors.black12),
                                )
                              : Image(
                                  image: _buildArtworkImageProvider(item.artworkUrl)!,
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
                          await widget.controller.showFavoriteInNowPlaying(item);
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _activeNavIndex = 0;
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
            continue;
          }

          final value = (entry ?? '').toString().trim();
          if (value.isNotEmpty) {
            uris.add(value);
            snapshotDates[value] = DateTime.fromMillisecondsSinceEpoch(0);
          }
        }
      }

      uris.sort((a, b) {
        final aMs = snapshotDates[a]?.millisecondsSinceEpoch ?? 0;
        final bMs = snapshotDates[b]?.millisecondsSinceEpoch ?? 0;
        return bMs.compareTo(aMs);
      });

      if (!mounted) {
        return;
      }

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
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savedSnapshotUris = const <String>[];
        _savedSnapshotDateByUri.clear();
        _savedSnapshotDisplayNameByUri.clear();
        _savedSnapshotTitleByUri.clear();
        _savedSnapshotArtistByUri.clear();
        _savedSnapshotSourcePackageByUri.clear();
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
        final artworkProvider = _buildArtworkImageProvider(artworkUrl);
        final backgroundTransitionKey =
            '${widget.controller.songTitle.trim()}|${(artworkUrl ?? '').trim()}';
        _syncWakeLockWithPlayback(
          shouldKeepAwake: widget.controller.isNowPlayingPlaybackActive,
        );

        return Scaffold(
          resizeToAvoidBottomInset: false,
          bottomNavigationBar: _hideHomeHeaderForExpandedVinyl
              ? null
              : SafeArea(
                  top: false,
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      height: MediaQuery.of(context).orientation == Orientation.landscape ? 58 : 66,
                      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.82),
                      indicatorShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: _activeNavIndex,
                      onDestinationSelected: (index) {
                        unawaited(_handleNavTap(index));
                      },
                      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.album_outlined),
                          selectedIcon: Icon(Icons.album_rounded),
                          label: '',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.photo_library_outlined),
                          selectedIcon: Icon(Icons.photo_library_rounded),
                          label: '',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music_rounded),
                          label: '',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.more_vert_rounded),
                          selectedIcon: Icon(Icons.more_vert_rounded),
                          label: '',
                        ),
                      ],
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
                    index: _activeNavIndex.clamp(0, 2),
                    children: [
                      _buildMainPlaybackPage(theme: theme, l10n: l10n),
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
