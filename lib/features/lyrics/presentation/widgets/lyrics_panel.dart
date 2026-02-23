import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../l10n/app_localizations.dart';
import 'app_top_feedback.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.theme,
    required this.lyrics,
    required this.useArtworkBackground,
    this.playbackPositionMs,
    required this.songTitle,
    required this.artistName,
    this.artworkUrl,
    required this.onTap,
    required this.showActionButtons,
    this.onAssociateToSong,
    this.onCopyFeedbackVisibleChanged,
    this.onScrollDirectionChanged,
    this.onTimedLineTap,
    this.onSnapshotSavedToGallery,
  });

  final ThemeData theme;
  final String lyrics;
  final bool useArtworkBackground;
  final int? playbackPositionMs;
  final String songTitle;
  final String artistName;
  final String? artworkUrl;
  final VoidCallback onTap;
  final bool showActionButtons;
  final Future<bool> Function()? onAssociateToSong;
  final ValueChanged<bool>? onCopyFeedbackVisibleChanged;
  final ValueChanged<ScrollDirection>? onScrollDirectionChanged;
  final ValueChanged<int>? onTimedLineTap;
  final Future<void> Function()? onSnapshotSavedToGallery;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel>
  with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Size _snapshotPreviewBaseSize = Size(190, 238);
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.lyric_notifier/lyrics',
  );

  final GlobalKey _panelStackKey = GlobalKey();
  final GlobalKey _captureButtonKey = GlobalKey();
  late final ScrollController _scrollController;
  late final AnimationController _snapshotCaptureController;
  List<_TimedLyricLine> _timedLines = const [];
  int _currentTimedLineIndex = -1;
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  bool? _lastIsLandscape;
  bool _isSnapshotAnimating = false;
  bool _isSnapshotFlowBusy = false;
  bool _snapshotFlightOnlyPass = false;
  Offset _snapshotStartCenter = Offset.zero;
  Offset _snapshotEndCenter = Offset.zero;
  Uint8List? _snapshotPreviewBytes;
  OverlayEntry? _snapshotOverlayEntry;
  int _lastTimedAutoScrollAtMs = 0;
  double _lastTimedAutoScrollTarget = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _snapshotCaptureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _timedLines = _parseTimedLyrics(widget.lyrics);
    _syncTimedLineIndex(widget.playbackPositionMs ?? 0, scrollToLine: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreHeaderWhenNotScrollable();
    });
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _timedLines = _parseTimedLyrics(widget.lyrics);
      _lineKeys.clear();
      _syncTimedLineIndex(widget.playbackPositionMs ?? 0, scrollToLine: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreHeaderWhenNotScrollable();
      });
    }

    if (oldWidget.playbackPositionMs != widget.playbackPositionMs) {
      _syncTimedLineIndex(widget.playbackPositionMs ?? 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (_lastIsLandscape != isLandscape) {
      _lastIsLandscape = isLandscape;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncTimedLineIndex(
          widget.playbackPositionMs ?? 0,
          forceScroll: true,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeSnapshotOverlay();
    _snapshotCaptureController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeSnapshotSavedFeedback();
    }
  }

  Future<void> _consumeSnapshotSavedFeedback() async {
    if (!Platform.isAndroid || !mounted) {
      return;
    }

    final consumed = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'consumeSnapshotSavedFeedback',
    );

    if (!mounted || consumed != true) {
      return;
    }

    _showFeedback(context, _snapshotSavedMessage());
  }

  void _removeSnapshotOverlay() {
    _snapshotOverlayEntry?.remove();
    _snapshotOverlayEntry = null;
  }

  void _restoreHeaderWhenNotScrollable() {
    if (!mounted || widget.onScrollDirectionChanged == null || !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      widget.onScrollDirectionChanged?.call(ScrollDirection.forward);
    }
  }

  Future<void> _copyLyrics(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _buildShareableLyrics()));
    if (!context.mounted) {
      return;
    }

    _showFeedback(context, AppLocalizations.of(context).lyricsCopied);
  }

  Future<void> _shareLyrics() async {
    final text = _buildShareableLyrics().trim();
    if (text.isEmpty) {
      return;
    }
    await Share.share(text);
  }

  Future<void> _shareSnapshot() async {
    if (_isSnapshotFlowBusy) {
      return;
    }

    _isSnapshotFlowBusy = true;
    final l10n = AppLocalizations.of(context);
    final previewCompleter = Completer<Uint8List?>();
    final animationFuture = _playSnapshotCaptureAnimation(
      previewBytesFuture: previewCompleter.future,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      final pngBytes = await _buildSnapshotPng();
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(pngBytes);
      }

      if (!mounted) {
        _isSnapshotFlowBusy = false;
        return;
      }
      if (pngBytes == null || pngBytes.isEmpty) {
        await animationFuture;
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
        _showFeedback(context, l10n.snapshotError);
        _isSnapshotFlowBusy = false;
        return;
      }

      await animationFuture;
      if (!mounted) {
        _isSnapshotFlowBusy = false;
        return;
      }

      if (Platform.isAndroid) {
        final saved = await _saveSnapshotToGallery(pngBytes);
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
        if (saved) {
          _showFeedback(context, l10n.snapshotSaved);
          await widget.onSnapshotSavedToGallery?.call();
        }

        final shouldShare = await _showSnapshotPreviewDialog(pngBytes);
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
        if (!shouldShare) {
          _isSnapshotFlowBusy = false;
          return;
        }

        final shared = await _shareSnapshotViaAndroidChooser(pngBytes);
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
        if (shared != true) {
          _showFeedback(context, l10n.snapshotError);
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}singsync_snapshot_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(pngBytes, flush: true);
        await Share.shareXFiles(
          [XFile(file.path)],
        );
      }
    } catch (_) {
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      await animationFuture;
      if (!mounted) {
        _isSnapshotFlowBusy = false;
        return;
      }
      _showFeedback(context, l10n.snapshotError);
    } finally {
      _isSnapshotFlowBusy = false;
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

  Future<void> _playSnapshotCaptureAnimation({
    required Future<Uint8List?> previewBytesFuture,
  }) async {
    final stackContext = _panelStackKey.currentContext;
    final captureContext = _captureButtonKey.currentContext;
    if (stackContext == null || captureContext == null) {
      return;
    }

    final stackBox = stackContext.findRenderObject() as RenderBox?;
    final captureBox = captureContext.findRenderObject() as RenderBox?;
    if (stackBox == null || captureBox == null) {
      return;
    }

    final overlayState = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlayState == null) {
      return;
    }

    final stackSize = stackBox.size;
    final captureCenter = captureBox.localToGlobal(captureBox.size.center(Offset.zero));
    final startCenter = stackBox.localToGlobal(Offset(stackSize.width / 2, stackSize.height * 0.46));

    _removeSnapshotOverlay();

    setState(() {
      _snapshotStartCenter = startCenter;
      _snapshotEndCenter = captureCenter;
      _isSnapshotAnimating = true;
    });

    _snapshotOverlayEntry = OverlayEntry(
      builder: (context) => _buildSnapshotCaptureOverlay(widget.theme),
    );
    overlayState.insert(_snapshotOverlayEntry!);

    final firstPassFuture = _snapshotCaptureController.forward(from: 0);

    Uint8List? previewBytes;
    try {
      previewBytes = await previewBytesFuture;
    } catch (_) {
      previewBytes = null;
    }

    if (mounted && _isSnapshotAnimating && previewBytes != null && previewBytes.isNotEmpty) {
      setState(() {
        _snapshotPreviewBytes = previewBytes;
      });
      _snapshotOverlayEntry?.markNeedsBuild();
    }

    await firstPassFuture;

    if (!mounted) {
      _removeSnapshotOverlay();
      return;
    }

    setState(() {
      _isSnapshotAnimating = false;
      _snapshotFlightOnlyPass = false;
      _snapshotPreviewBytes = null;
    });

    _removeSnapshotOverlay();
  }

  Widget _buildSnapshotCaptureOverlay(ThemeData theme) {
    if (!_isSnapshotAnimating) {
      return const SizedBox.shrink();
    }

    final previewBytes = _snapshotPreviewBytes;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _snapshotCaptureController,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_snapshotCaptureController.value);
          final flashOpacity = _snapshotFlightOnlyPass
              ? 0.0
              : (1 - ((t - 0.12).abs() / 0.12)).clamp(0.0, 1.0) * 0.38;
          final center = Offset.lerp(_snapshotStartCenter, _snapshotEndCenter, t) ?? _snapshotEndCenter;
          final scale = ui.lerpDouble(1.0, 0.16, t) ?? 0.16;
          final width = _snapshotPreviewBaseSize.width * scale;
          final height = _snapshotPreviewBaseSize.height * scale;

          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: flashOpacity),
                ),
              ),
              Positioned(
                left: center.dx - (width / 2),
                top: center.dy - (height / 2),
                child: previewBytes == null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: Icon(
                              Icons.photo_camera_outlined,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                              size: math.max(18, width * 0.22),
                            ),
                          ),
                        ),
                      )
                    : Opacity(
                        opacity: (1 - (t * 0.15)).clamp(0.0, 1.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Image.memory(
                              previewBytes,
                              width: width,
                              height: height,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
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

  Future<bool> _shareSnapshotViaAndroidChooser(Uint8List pngBytes) async {
    final fileName = _buildSnapshotFileName();
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
    final fileName = _buildSnapshotFileName();
    final saved = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'saveSnapshotImage',
      {
        'bytes': pngBytes,
        'fileName': fileName,
      },
    );
    return saved == true;
  }

  String _buildSnapshotFileName() {
    final title = Uri.encodeComponent(widget.songTitle.trim());
    final artist = Uri.encodeComponent(widget.artistName.trim());
    final sourcePackage = Uri.encodeComponent('');
    return 'singsync_snapshot_${DateTime.now().millisecondsSinceEpoch}__t_${title}__a_${artist}__p_$sourcePackage.png';
  }

  String _snapshotSavedMessage() {
    return AppLocalizations.of(context).snapshotSaved;
  }

  Future<Uint8List?> _buildSnapshotPng() async {
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
    const rect = Rect.fromLTWH(0, 0, baseWidth, baseHeight);

    final artworkImage = await _loadSnapshotArtworkImage();
    final dominantArtworkColor = await _extractDominantArtworkColor(artworkImage);
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
          [
            gradientStartColor,
            gradientEndColor,
          ],
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
    const vinylCenterY = 374.0;
    const vinylRadius = 262.0;

    final isDark = theme.brightness == Brightness.dark;
    final vinylBaseColor = Color.lerp(Colors.black, theme.colorScheme.onSurface, 0.12)!;
    final grooveColor = Color.lerp(Colors.white, theme.colorScheme.onSurface, 0.35)!;
    final separatorColor =
      isDark ? Colors.white.withValues(alpha: 0.78) : Colors.black.withValues(alpha: 0.68);
    final centerLabelColor =
      Color.lerp(theme.colorScheme.surface, theme.colorScheme.surfaceContainerHighest, 0.55)!;

    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      vinylRadius,
      Paint()..color = vinylBaseColor,
    );

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
    final artworkRect = Rect.fromCircle(
      center: const Offset(centerX, vinylCenterY),
      radius: artworkRadius,
    );
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
      final labelPaint = Paint()..color = centerLabelColor;
      canvas.drawOval(artworkRect, labelPaint);
      final logoPainter = TextPainter(
        text: TextSpan(
          text: 'S',
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      logoPainter.paint(
        canvas,
        Offset(centerX - (logoPainter.width / 2), vinylCenterY - (logoPainter.height / 2)),
      );
    }

    const centerOuterRadius = vinylRadius * 0.036;
    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      centerOuterRadius,
      Paint()..color = theme.colorScheme.surface,
    );
    canvas.drawCircle(
      const Offset(centerX, vinylCenterY),
      vinylRadius * 0.013,
      Paint()..color = theme.colorScheme.onSurface.withValues(alpha: 0.90),
    );

    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: (theme.textTheme.headlineSmall?.fontSize ?? 24) + 13,
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurface,
    );
    final artistStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) + 3,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.90),
    );
    final lyricsStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) + 6,
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );
    final activeLyricsStyle = lyricsStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );

    void drawText({
      required String text,
      required TextStyle? style,
      required double top,
      required double maxWidth,
      int? maxLines,
      TextAlign align = TextAlign.center,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
        textAlign: align,
      )..layout(maxWidth: maxWidth);
      final left = align == TextAlign.center ? (baseWidth - painter.width) / 2 : 120.0;
      painter.paint(canvas, Offset(left, top));
    }

    drawText(
      text: widget.songTitle.trim().isEmpty ? l10n.nowPlayingDefaultTitle : widget.songTitle.trim(),
      style: titleStyle,
      top: 690,
      maxWidth: 820,
      maxLines: 2,
    );
    drawText(
      text: widget.artistName.trim().isEmpty ? l10n.unknownArtist : widget.artistName.trim(),
      style: artistStyle,
      top: 796,
      maxWidth: 820,
      maxLines: 1,
    );

    final snapshotLyrics = _buildSnapshotLyricsData(l10n: l10n);
    var currentTop = 868.0;
    const maxBottom = 1212.0;
    for (var lineIndex = 0; lineIndex < snapshotLyrics.lines.length; lineIndex++) {
      final line = snapshotLyrics.lines[lineIndex];
      final isActive = lineIndex == snapshotLyrics.activeLineIndex;
      final lineStyle = (isActive ? activeLyricsStyle : lyricsStyle)?.copyWith(
        fontSize: ((isActive ? activeLyricsStyle : lyricsStyle)?.fontSize ?? 18) +
            (isActive ? 5 : 0),
        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
        color: isActive
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.74),
      );
      final linePainter = TextPainter(
        text: TextSpan(
          text: line,
          style: lineStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
        textAlign: TextAlign.center,
      )..layout(maxWidth: 820);
      if (currentTop + linePainter.height > maxBottom) {
        break;
      }
      linePainter.paint(canvas, Offset((baseWidth - linePainter.width) / 2, currentTop));
      currentTop += linePainter.height + 10;
    }

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

  Future<ui.Image?> _loadSnapshotArtworkImage() async {
    final artworkUrl = widget.artworkUrl?.trim();
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

  _SnapshotLyricsData _buildSnapshotLyricsData({required AppLocalizations l10n}) {
    if (_timedLines.isNotEmpty) {
      final rawActiveIndex = _currentTimedLineIndex
          .clamp(0, math.max(_timedLines.length - 1, 0))
          .toInt();
      final lines = _timedLines
          .map((line) => line.text.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final window = _buildSnapshotWindow(
          sourceLines: lines,
          centerIndex: rawActiveIndex,
          linesAbove: 2,
          linesBelow: 2,
        );
        return _SnapshotLyricsData(lines: window.lines, activeLineIndex: window.activeLineIndex);
      }
    }

    final plain = _toPlainLyrics(widget.lyrics).trim();
    if (plain.isEmpty) {
      return _SnapshotLyricsData(lines: [l10n.snapshotNoLyrics], activeLineIndex: -1);
    }

    final lines = plain
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return _SnapshotLyricsData(lines: [l10n.snapshotNoLyrics], activeLineIndex: -1);
    }
    var centerIndex = 0;
    if (_scrollController.hasClients && lines.length > 1) {
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      if (maxScroll > 0) {
        final ratio = (position.pixels / maxScroll).clamp(0.0, 1.0);
        centerIndex = (ratio * (lines.length - 1)).round().clamp(0, lines.length - 1);
      }
    }

    final window = _buildSnapshotWindow(
      sourceLines: lines,
      centerIndex: centerIndex,
      linesAbove: 2,
      linesBelow: 2,
    );
    return _SnapshotLyricsData(lines: window.lines, activeLineIndex: -1);
  }

  _SnapshotLyricsData _buildSnapshotWindow({
    required List<String> sourceLines,
    required int centerIndex,
    required int linesAbove,
    required int linesBelow,
  }) {
    if (sourceLines.isEmpty) {
      return const _SnapshotLyricsData(lines: <String>[], activeLineIndex: -1);
    }

    var start = (centerIndex - linesAbove).clamp(0, sourceLines.length - 1);
    var end = (centerIndex + linesBelow).clamp(0, sourceLines.length - 1);

    const targetSize = 5;
    while ((end - start + 1) < targetSize && start > 0) {
      start -= 1;
    }
    while ((end - start + 1) < targetSize && end < sourceLines.length - 1) {
      end += 1;
    }

    final windowLines = sourceLines.sublist(start, end + 1);
    final activeIndex = (centerIndex - start).clamp(0, windowLines.length - 1);
    return _SnapshotLyricsData(lines: windowLines, activeLineIndex: activeIndex);
  }

  Future<void> _associateLyrics(BuildContext context) async {
    final action = widget.onAssociateToSong;
    if (action == null) {
      return;
    }

    final associated = await action();
    if (!context.mounted) {
      return;
    }

    _showFeedback(
      context,
      associated
          ? AppLocalizations.of(context).lyricsAssociated
          : AppLocalizations.of(context).lyricsNotAssociated,
    );
  }

  ButtonStyle _actionButtonStyle(ThemeData theme) {
    return IconButton.styleFrom(
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.32),
      foregroundColor: theme.colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    AppTopFeedback.show(
      context,
      message,
      onVisibilityChanged: widget.onCopyFeedbackVisibleChanged,
    );
  }

  String _buildShareableLyrics() {
    final lyricsText = _toPlainLyrics(widget.lyrics);
    if (lyricsText.isEmpty) {
      return '';
    }

    final title = widget.songTitle.trim();
    final artist = widget.artistName.trim();
    final l10n = AppLocalizations.of(context);
    final hasHeader =
        title.isNotEmpty &&
        artist.isNotEmpty &&
      title.toLowerCase() != l10n.nowPlayingDefaultTitle.toLowerCase() &&
      artist.toLowerCase() != l10n.unknownArtist.toLowerCase();

    if (!hasHeader) {
      return lyricsText;
    }

    return '$title - $artist\n\n$lyricsText';
  }

  String _toPlainLyrics(String rawLyrics) {
    if (rawLyrics.trim().isEmpty) {
      return '';
    }

    final lines = rawLyrics.split('\n');
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]');
    final plainLines = <String>[];

    for (final rawLine in lines) {
      final withoutTime = rawLine.replaceAll(timeRegex, '').trim();
      if (withoutTime.isNotEmpty) {
        plainLines.add(withoutTime);
      }
    }

    if (plainLines.isEmpty) {
      return rawLyrics.trim();
    }

    return plainLines.join('\n').trim();
  }

  void _syncTimedLineIndex(
    int playbackPositionMs, {
    bool scrollToLine = true,
    bool forceScroll = false,
  }) {
    if (_timedLines.isEmpty) {
      return;
    }

    final index = _findLineIndexForPlayback(playbackPositionMs);
    if (index == _currentTimedLineIndex) {
      if (forceScroll && scrollToLine && index >= 0) {
        _scrollToTimedLine(index);
      }
      return;
    }

    if (!mounted) {
      _currentTimedLineIndex = index;
      return;
    }

    setState(() {
      _currentTimedLineIndex = index;
    });

    if (!scrollToLine || index < 0) {
      return;
    }

    _scrollToTimedLine(index);
  }

  void _scrollToTimedLine(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        return;
      }
      final key = _lineKeys[index];
      if (key == null) {
        return;
      }
      final context = key.currentContext;
      if (context == null) {
        return;
      }
      final renderObject = context.findRenderObject();
      if (renderObject == null || !renderObject.attached) {
        return;
      }

      final position = _scrollController.position;
      final viewport = RenderAbstractViewport.of(renderObject);

      final revealOffset = viewport.getOffsetToReveal(renderObject, 0.38).offset;
      final targetOffset = revealOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final currentOffset = position.pixels;
      final delta = (targetOffset - currentOffset).abs();
      if (delta < 20) {
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final underCooldown = (nowMs - _lastTimedAutoScrollAtMs) < 260;
      final tinyTargetShift = _lastTimedAutoScrollTarget >= 0
          ? (_lastTimedAutoScrollTarget - targetOffset).abs() < 26
          : false;
      if (underCooldown && tinyTargetShift) {
        return;
      }

      _lastTimedAutoScrollAtMs = nowMs;
      _lastTimedAutoScrollTarget = targetOffset;
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 210),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int _findLineIndexForPlayback(int playbackPositionMs) {
    if (_timedLines.isEmpty) {
      return -1;
    }

    var left = 0;
    var right = _timedLines.length - 1;
    var answer = -1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
      if (_timedLines[mid].timestampMs <= playbackPositionMs) {
        answer = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    return answer;
  }

  List<_TimedLyricLine> _parseTimedLyrics(String rawLyrics) {
    final lines = rawLyrics.split('\n');
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]');
    final parsed = <_TimedLyricLine>[];

    for (final rawLine in lines) {
      final matches = timeRegex.allMatches(rawLine).toList();
      if (matches.isEmpty) {
        continue;
      }

      final text = rawLine.replaceAll(timeRegex, '').trim();
      if (text.isEmpty) {
        continue;
      }

      for (final match in matches) {
        final minute = int.tryParse(match.group(1) ?? '') ?? 0;
        final second = int.tryParse(match.group(2) ?? '') ?? 0;
        final fractionRaw = match.group(3) ?? '0';

        final fractionMs = switch (fractionRaw.length) {
          1 => (int.tryParse(fractionRaw) ?? 0) * 100,
          2 => (int.tryParse(fractionRaw) ?? 0) * 10,
          _ => int.tryParse(fractionRaw.substring(0, 3)) ?? 0,
        };

        final timestampMs = (minute * 60 * 1000) + (second * 1000) + fractionMs;
        parsed.add(_TimedLyricLine(timestampMs: timestampMs, text: text));
      }
    }

    parsed.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final baseStyle = widget.theme.textTheme.bodyLarge;
    final lyricsStyle = baseStyle?.copyWith(
      height: 1.6,
      fontSize: (baseStyle.fontSize ?? 16) + (isLandscape ? 2 : 0),
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
          key: _panelStackKey,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    widget.onScrollDirectionChanged?.call(notification.direction);
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 56),
                    child: _timedLines.isEmpty
                        ? Text(
                            widget.lyrics,
                            textAlign: TextAlign.center,
                            style: lyricsStyle,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var index = 0; index < _timedLines.length; index++)
                                Builder(
                                  builder: (_) {
                                    final line = _timedLines[index];
                                    final isActive = index == _currentTimedLineIndex;
                                    final key = _lineKeys.putIfAbsent(
                                      index,
                                      () => GlobalKey(debugLabel: 'line_$index'),
                                    );

                                    return Container(
                                      key: key,
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: widget.onTimedLineTap == null
                                            ? null
                                            : () => widget.onTimedLineTap!.call(line.timestampMs),
                                        child: AnimatedDefaultTextStyle(
                                          duration: const Duration(milliseconds: 240),
                                          curve: Curves.easeOutCubic,
                                          style: (lyricsStyle ?? const TextStyle()).copyWith(
                                            fontSize: (lyricsStyle?.fontSize ?? 16) +
                                                (isActive ? 5 : 0),
                                            fontWeight:
                                                isActive ? FontWeight.w700 : FontWeight.w400,
                                            color: isActive
                                                ? widget.theme.colorScheme.onSurface
                                                : widget.theme.colorScheme.onSurface.withValues(alpha: 0.74),
                                          ),
                                          child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 240),
                                            opacity: isActive ? 1 : 0.82,
                                            child: Text(line.text, textAlign: TextAlign.center),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (widget.showActionButtons)
              Positioned(
                bottom: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      style: _actionButtonStyle(widget.theme),
                      onPressed: () => _copyLyrics(context),
                      tooltip: l10n.copy,
                      icon: const Icon(Icons.copy_all_rounded),
                    ),
                    IconButton(
                      style: _actionButtonStyle(widget.theme),
                      onPressed: _shareLyrics,
                      tooltip: l10n.share,
                      icon: const Icon(Icons.share_rounded),
                    ),
                    IconButton(
                      key: _captureButtonKey,
                      style: _actionButtonStyle(widget.theme),
                      onPressed: _shareSnapshot,
                      tooltip: l10n.shareSnapshot,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    if (widget.onAssociateToSong != null)
                      IconButton(
                        style: _actionButtonStyle(widget.theme),
                        onPressed: () => _associateLyrics(context),
                        tooltip: l10n.associateToSong,
                        icon: const Icon(Icons.link_rounded),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimedLyricLine {
  const _TimedLyricLine({required this.timestampMs, required this.text});

  final int timestampMs;
  final String text;
}

class _SnapshotLyricsData {
  const _SnapshotLyricsData({required this.lines, required this.activeLineIndex});

  final List<String> lines;
  final int activeLineIndex;
}
