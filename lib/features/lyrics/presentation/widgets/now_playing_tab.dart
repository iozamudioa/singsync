import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/lyrics_candidate.dart';
import '../lyrics_controller.dart';
import 'app_top_feedback.dart';
import 'lyrics_panel.dart';
import 'music_search_icon.dart';

part 'now_playing_tab_logic.dart';
part 'now_playing_tab_ui.dart';
part 'now_playing_tab_modes.dart';

class NowPlayingTab extends StatefulWidget {
  const NowPlayingTab({
    super.key,
    required this.controller,
    required this.theme,
    required this.useArtworkBackground,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onSearchManually,
    this.onExpandedLandscapeModeChanged,
    this.onSnapshotSavedToGallery,
  });

  final LyricsController controller;
  final ThemeData theme;
  final bool useArtworkBackground;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onSearchManually;
  final ValueChanged<bool>? onExpandedLandscapeModeChanged;
  final Future<void> Function()? onSnapshotSavedToGallery;

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
  static const int _dragSeekHapticIntervalMs = 180;
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.lyric_notifier/lyrics',
  );
  static const MethodChannel _nowPlayingMethodsChannel = MethodChannel(
    'net.iozamudioa.lyric_notifier/now_playing_methods',
  );
  final Map<String, Future<Uint8List?>> _playerIconFutureByPackage = <String, Future<Uint8List?>>{};
  Timer? _autoExpandVinylTimer;
  String? _autoExpandPendingKey;
  String? _autoExpandedForKey;
  bool? _lastExpandedLandscapeModeReported;
  bool _isBasicSnapshotBusy = false;
  int _lastScrubHapticAtMs = 0;

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
    _lastScrubHapticAtMs = 0;

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
    if (now - _lastScrubHapticAtMs >= _dragSeekHapticIntervalMs) {
      _lastScrubHapticAtMs = now;
      unawaited(HapticFeedback.vibrate());
    }
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
    setState(() {
      _isVinylExpanded = !_isVinylExpanded;
    });
  }

  Future<void> _shareBasicSnapshotFromExpanded() async {
    if (_isBasicSnapshotBusy) {
      return;
    }

    _isBasicSnapshotBusy = true;
    final l10n = AppLocalizations.of(context);
    try {
      final pngBytes = await _buildBasicSnapshotPng();
      if (!mounted) {
        _isBasicSnapshotBusy = false;
        return;
      }

      if (pngBytes == null || pngBytes.isEmpty) {
        _showFeedback(l10n.snapshotError);
        _isBasicSnapshotBusy = false;
        return;
      }

      if (Platform.isAndroid) {
        final snapshotFileName = _buildSnapshotFileName(prefix: 'singsync_snapshot_basic');
        final skipPreviewAndShare = _isVinylExpanded;
        final saved = await _saveSnapshotToGallery(pngBytes);
        if (!mounted) {
          _isBasicSnapshotBusy = false;
          return;
        }
        if (saved) {
          _showFeedback(l10n.snapshotSaved);
          await widget.onSnapshotSavedToGallery?.call();
        }

        if (skipPreviewAndShare) {
          _isBasicSnapshotBusy = false;
          return;
        }

        final shouldShare = await _showSnapshotPreviewDialog(pngBytes);
        if (!mounted) {
          _isBasicSnapshotBusy = false;
          return;
        }
        if (!shouldShare) {
          _isBasicSnapshotBusy = false;
          return;
        }

        final shared = await _shareSnapshotViaAndroidChooser(
          pngBytes,
          fileName: snapshotFileName,
        );
        if (!mounted) {
          _isBasicSnapshotBusy = false;
          return;
        }
        if (!shared) {
          _showFeedback(l10n.snapshotError);
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}singsync_snapshot_basic_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(pngBytes, flush: true);
        await Share.shareXFiles([XFile(file.path)]);
      }
    } catch (_) {
      if (mounted) {
        _showFeedback(l10n.snapshotError);
      }
    } finally {
      _isBasicSnapshotBusy = false;
    }
  }

  Future<bool> _showSnapshotPreviewDialog(Uint8List pngBytes) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(false),
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
                      maxWidth: math.min(520.0, size.width * 0.92),
                      maxHeight: size.height * 0.84,
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
                          Flexible(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: InteractiveViewer(
                                minScale: 1,
                                maxScale: 3.2,
                                child: Image.memory(
                                  pngBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
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
    return result == true;
  }

  String _buildSnapshotFileName({String prefix = 'singsync_snapshot'}) {
    final title = Uri.encodeComponent(widget.controller.songTitle.trim());
    final artist = Uri.encodeComponent(widget.controller.artistName.trim());
    final sourcePackage = Uri.encodeComponent(
      (widget.controller.nowPlayingSourcePackage ?? widget.controller.preferredMediaAppPackage ?? '').trim(),
    );
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}__t_${title}__a_${artist}__p_$sourcePackage.png';
  }

  Future<bool> _shareSnapshotViaAndroidChooser(
    Uint8List pngBytes, {
    required String fileName,
  }) async {
    final launched = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'shareSnapshotWithSaveOption',
      {
        'bytes': pngBytes,
        'fileName': fileName,
      },
    );
    return launched == true;
  }

  Future<bool> _saveSnapshotToGallery(Uint8List pngBytes) async {
    final fileName = _buildSnapshotFileName(prefix: 'singsync_snapshot_basic');
    final saved = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'saveSnapshotImage',
      {
        'bytes': pngBytes,
        'fileName': fileName,
      },
    );
    return saved == true;
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    AppTopFeedback.show(context, message);
  }

  ButtonStyle _snapshotActionButtonStyle(ThemeData theme) {
    return IconButton.styleFrom(
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.32),
      foregroundColor: theme.colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<Uint8List?> _buildBasicSnapshotPng() async {
    final l10n = AppLocalizations.of(context);
    final theme = widget.theme;
    const baseWidth = 1080.0;
    const baseHeight = 1350.0;
    const exportScale = 2.0;
    final exportWidth = (baseWidth * exportScale).round();
    final exportHeight = (baseHeight * exportScale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, exportWidth.toDouble(), exportHeight.toDouble()),
    );
    canvas.scale(exportScale, exportScale);

    final artworkImage = await _loadBasicSnapshotArtworkImage();
    final dominantArtworkColor = await _extractDominantArtworkColor(artworkImage);
    const rect = Rect.fromLTWH(0, 0, baseWidth, baseHeight);
    final shouldUseArtworkBackground = widget.useArtworkBackground && artworkImage != null;
    if (shouldUseArtworkBackground) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: artworkImage,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        opacity: 0.30,
      );
      canvas.drawRect(
        rect,
        Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.58),
      );
    } else {
      final gradientStartColor = dominantArtworkColor == null
          ? theme.colorScheme.surface
          : Color.lerp(theme.colorScheme.surface, dominantArtworkColor, 0.18)!;
      final gradientEndColor = dominantArtworkColor == null
          ? theme.colorScheme.surfaceContainerHighest
          : Color.lerp(theme.colorScheme.surfaceContainerHighest, dominantArtworkColor, 0.10)!;
      final backgroundPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(baseWidth, baseHeight),
          [gradientStartColor, gradientEndColor],
        );
      canvas.drawRect(rect, backgroundPaint);
    }

    final cardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(70, 70, baseWidth - 140, baseHeight - 140),
      const Radius.circular(42),
    );
    canvas.drawRRect(
      cardRect,
      Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.92),
    );

    const centerX = baseWidth / 2;
    const vinylCenterY = 500.0;
    const vinylRadius = 262.0;

    final isDark = theme.brightness == Brightness.dark;
    final vinylBaseColor = Color.lerp(Colors.black, theme.colorScheme.onSurface, 0.12)!;
    final grooveColor = Color.lerp(Colors.white, theme.colorScheme.onSurface, 0.35)!;
    final separatorColor =
        isDark ? Colors.white.withValues(alpha: 0.78) : Colors.black.withValues(alpha: 0.68);
    final centerLabelColor =
        Color.lerp(theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest, 0.55)!;

    canvas.drawCircle(const Offset(centerX, vinylCenterY), vinylRadius, Paint()..color = vinylBaseColor);

    for (var index = 0; index < 24; index++) {
      final t = index / 23;
      final radius = ui.lerpDouble(vinylRadius * 0.37, vinylRadius * 0.97, t)!;
      final opacity = 0.12 + (0.10 * (1 - t));
      final stroke = 0.8 + (0.35 * (1 - t));
      canvas.drawCircle(
        const Offset(centerX, vinylCenterY),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = grooveColor.withValues(alpha: (isDark ? 0.10 : 0.14) * (opacity / 0.14)),
      );
    }

    final vinylRect = Rect.fromCircle(center: const Offset(centerX, vinylCenterY), radius: vinylRadius);
    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      vinylRadius,
      Paint()
        ..shader = ui.Gradient.linear(
          vinylRect.topLeft,
          vinylRect.bottomRight,
          [
            Colors.white.withValues(alpha: isDark ? 0.20 : 0.16),
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
            Colors.black.withValues(alpha: isDark ? 0.18 : 0.10),
          ],
          const [0.0, 0.24, 0.55, 1.0],
        ),
    );

    const separatorRadius = vinylRadius * 0.56;
    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      separatorRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, (vinylRadius * 2) * 0.014)
        ..color = separatorColor,
    );

    const artworkRadius = vinylRadius * 0.50;
    final artworkRect = Rect.fromCircle(center: const Offset(centerX, vinylCenterY), radius: artworkRadius);
    if (artworkImage != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(artworkRect));
      paintImage(
        canvas: canvas,
        rect: artworkRect,
        image: artworkImage,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawOval(artworkRect, Paint()..color = centerLabelColor);
    }

    const centerOuterRadius = vinylRadius * 0.036;
    canvas.drawCircle(const Offset(centerX, vinylCenterY), centerOuterRadius, Paint()..color = theme.colorScheme.surface);
    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      vinylRadius * 0.013,
      Paint()..color = theme.colorScheme.onSurface.withValues(alpha: 0.90),
    );

    final title = widget.controller.songTitle.trim().isEmpty
        ? l10n.nowPlayingDefaultTitle
        : widget.controller.songTitle.trim();
    final artist = widget.controller.artistName.trim().isEmpty
        ? l10n.unknownArtist
        : widget.controller.artistName.trim();

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontSize: (theme.textTheme.headlineSmall?.fontSize ?? 24) + 13,
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
      textAlign: TextAlign.center,
    )..layout(maxWidth: 820);
    const titleTop = 830.0;
    titlePainter.paint(canvas, Offset((baseWidth - titlePainter.width) / 2, titleTop));

    final artistPainter = TextPainter(
      text: TextSpan(
        text: artist,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) + 3,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.90),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
    )..layout(maxWidth: 820);
    const artistTop = 938.0;
    artistPainter.paint(canvas, Offset((baseWidth - artistPainter.width) / 2, artistTop));

    final footerPainter = TextPainter(
      text: TextSpan(
        text: l10n.snapshotGeneratedWithBrand,
        style: theme.textTheme.labelLarge?.copyWith(
          fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) + 2,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    footerPainter.paint(canvas, Offset((baseWidth - footerPainter.width) / 2, baseHeight - 112));

    final picture = recorder.endRecording();
    final image = await picture.toImage(exportWidth, exportHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<ui.Image?> _loadBasicSnapshotArtworkImage() async {
    final artworkUrl = widget.controller.nowPlayingArtworkUrl?.trim();
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.tryParse(artworkUrl);
      if (uri == null) {
        return null;
      }
      final data = await NetworkAssetBundle(uri).load(artworkUrl);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<Color?> _extractDominantArtworkColor(ui.Image? artworkImage) async {
    if (artworkImage == null) {
      return null;
    }

    try {
      final byteData = await artworkImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      final width = artworkImage.width;
      final height = artworkImage.height;
      final stepX = math.max(1, width ~/ 36);
      final stepY = math.max(1, height ~/ 36);

      var totalRed = 0;
      var totalGreen = 0;
      var totalBlue = 0;
      var totalWeight = 0;

      for (var y = 0; y < height; y += stepY) {
        for (var x = 0; x < width; x += stepX) {
          final index = ((y * width) + x) * 4;
          if (index + 3 >= bytes.length) {
            continue;
          }

          final red = bytes[index];
          final green = bytes[index + 1];
          final blue = bytes[index + 2];
          final alpha = bytes[index + 3];

          if (alpha < 24) {
            continue;
          }

          final weight = alpha;
          totalRed += red * weight;
          totalGreen += green * weight;
          totalBlue += blue * weight;
          totalWeight += weight;
        }
      }

      if (totalWeight == 0) {
        return null;
      }

      final averagedColor = Color.fromARGB(
        255,
        (totalRed / totalWeight).round().clamp(0, 255),
        (totalGreen / totalWeight).round().clamp(0, 255),
        (totalBlue / totalWeight).round().clamp(0, 255),
      );

      final hsl = HSLColor.fromColor(averagedColor);
      final saturation = (hsl.saturation * 0.78).clamp(0.20, 0.65).toDouble();
      final lightness = hsl.lightness.clamp(0.22, 0.62).toDouble();
      return hsl.withSaturation(saturation).withLightness(lightness).toColor();
    } catch (_) {
      return null;
    }
  }

  void _onSearchManuallyPressed() {
    _autoExpandVinylTimer?.cancel();
    _autoExpandPendingKey = null;
    widget.onSearchManually();
  }

  Future<void> _toggleCurrentFavoriteWithFeedback() async {
    final toggledToFavorite = await widget.controller.toggleCurrentFavorite();
    if (!mounted || toggledToFavorite == null) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    AppTopFeedback.show(
      context,
      toggledToFavorite ? l10n.favoriteAdded : l10n.favoriteRemoved,
    );
  }

  void _handleAutoExpandOnManualPrompt({
    required LyricsController controller,
    required String nowPlayingKey,
  }) {
    final shouldAutoExpand = controller.hasActiveNowPlaying &&
        controller.canShowManualSearchButton &&
        !controller.isManualSearchMode &&
        !controller.isLoadingNowPlayingLyrics &&
      !_isVinylExpanded;

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
                  padding: EdgeInsets.zero,
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
                                                      label: Text(AppLocalizations.of(context).searchManually),
                                                    ),
                                                ],
                                              )
                                            : (hasActiveNowPlaying || canOpenMediaApps)
                                                ? Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    _buildPlatformButtonsRow(artistOnly: false),
                                                    if (controller.canResumePausedPlaybackAfterFavorite) ...[
                                                      const SizedBox(height: 10),
                                                      _buildResumePausedPlaybackButton(),
                                                    ],
                                                    const SizedBox(height: 10),
                                                    if (controller.canShowManualSearchButton)
                                                      OutlinedButton.icon(
                                                        onPressed: _onSearchManuallyPressed,
                                                        icon: const MusicSearchIcon(size: 20),
                                                        label: Text(AppLocalizations.of(context).searchManually),
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
                                      useArtworkBackground: widget.useArtworkBackground,
                                      playbackPositionMs: controller.nowPlayingPlaybackPositionMs,
                                      songTitle: controller.songTitle,
                                      artistName: controller.artistName,
                                      artworkUrl: controller.nowPlayingArtworkUrl,
                                        onTimedLineTap: _onNowPlayingTimedLineTap,
                                      showActionButtons: controller.hasActiveNowPlayingLyrics,
                                      onCopyFeedbackVisibleChanged:
                                          _handleCopyFeedbackVisibility,
                                      onSnapshotSavedToGallery: widget.onSnapshotSavedToGallery,
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
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPlatformButtonsRow(artistOnly: false),
                                  if (controller.canResumePausedPlaybackAfterFavorite) ...[
                                    const SizedBox(height: 10),
                                    _buildResumePausedPlaybackButton(),
                                  ],
                                ],
                              ),
                            const SizedBox(height: 10),
                            if (hasActiveNowPlaying && controller.canShowManualSearchButton)
                              Align(
                                alignment: Alignment.center,
                                child: OutlinedButton.icon(
                                  onPressed: _onSearchManuallyPressed,
                                  icon: const MusicSearchIcon(size: 20),
                                  label: Text(AppLocalizations.of(context).searchManually),
                                ),
                              ),
                            Expanded(
                              child: controller.isManualSearchMode
                                  ? _manualSearchArea()
                                  : LyricsPanel(
                                      theme: theme,
                                      lyrics: controller.nowPlayingLyrics,
                                      useArtworkBackground: widget.useArtworkBackground,
                                      playbackPositionMs: controller.nowPlayingPlaybackPositionMs,
                                      songTitle: controller.songTitle,
                                      artistName: controller.artistName,
                                      artworkUrl: controller.nowPlayingArtworkUrl,
                                        onTimedLineTap: _onNowPlayingTimedLineTap,
                                      showActionButtons: controller.hasActiveNowPlayingLyrics,
                                      onCopyFeedbackVisibleChanged:
                                          _handleCopyFeedbackVisibility,
                                      onSnapshotSavedToGallery: widget.onSnapshotSavedToGallery,
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
