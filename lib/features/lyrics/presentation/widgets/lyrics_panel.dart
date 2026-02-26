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
import 'snapshot_editor_support.dart';

class LyricsPanelController {
  Future<void> Function()? _copyAction;
  Future<void> Function()? _shareAction;
  Future<void> Function()? _snapshotAction;

  Future<void> copyLyrics() async {
    await _copyAction?.call();
  }

  Future<void> shareLyrics() async {
    await _shareAction?.call();
  }

  Future<void> shareSnapshot() async {
    await _snapshotAction?.call();
  }

  void _bind({
    required Future<void> Function() onCopy,
    required Future<void> Function() onShare,
    required Future<void> Function() onSnapshot,
  }) {
    _copyAction = onCopy;
    _shareAction = onShare;
    _snapshotAction = onSnapshot;
  }

  void _unbind() {
    _copyAction = null;
    _shareAction = null;
    _snapshotAction = null;
  }
}

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
    this.snapshotSaveTargetCenterProvider,
    this.controller,
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
  final Offset? Function()? snapshotSaveTargetCenterProvider;
  final LyricsPanelController? controller;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel>
  with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Size _snapshotPreviewBaseSize = Size(190, 238);
  static const MethodChannel _lyricsMethodsChannel = MethodChannel(
    'net.iozamudioa.singsync/lyrics',
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
    widget.controller?._bind(
      onCopy: _copyLyrics,
      onShare: _shareLyrics,
      onSnapshot: _shareSnapshot,
    );
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind();
      widget.controller?._bind(
        onCopy: _copyLyrics,
        onShare: _shareLyrics,
        onSnapshot: _shareSnapshot,
      );
    }
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
    widget.controller?._unbind();
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

  Future<void> _copyLyrics() async {
    await Clipboard.setData(ClipboardData(text: _buildShareableLyrics()));
    if (!mounted) {
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
    try {
      final selectableLines = _buildSelectableSnapshotLines(l10n: l10n);
      final artworkImage = await SnapshotArtworkTools.loadArtworkImage(widget.artworkUrl);
      final extractedPalette = await SnapshotArtworkTools.extractPalette(artworkImage);
      var persistedSelectedLineIndices = <int>{
        _defaultSnapshotActiveLineIndex(selectableLines.length),
      }..removeWhere((index) => index < 0 || index >= selectableLines.length);
      if (persistedSelectedLineIndices.isEmpty && selectableLines.isNotEmpty) {
        persistedSelectedLineIndices = <int>{0};
      }
      SnapshotDialogResult? dialogResult;

      while (mounted) {
        final lineSelection = await _showLineSelectionDialog(
          lines: selectableLines,
          initialIndexes: persistedSelectedLineIndices,
        );
        if (!mounted || lineSelection == null) {
          _isSnapshotFlowBusy = false;
          return;
        }
        persistedSelectedLineIndices = lineSelection;

        final previewResult = await _showSnapshotPreviewDialog(
          artworkImage: artworkImage,
          extractedPalette: extractedPalette,
          sourceLines: selectableLines,
          selectedLineIndices: persistedSelectedLineIndices,
        );
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
        if (previewResult == null) {
          continue;
        }
        if (previewResult.action == SnapshotDialogAction.back) {
          continue;
        }

        dialogResult = previewResult;
        break;
      }

      if (!mounted || dialogResult == null) {
        _isSnapshotFlowBusy = false;
        return;
      }

      final shouldAnimateCapture = dialogResult.action == SnapshotDialogAction.save;
      if (shouldAnimateCapture) {
        final previewCompleter = Completer<Uint8List?>();
        final animationFuture = _playSnapshotCaptureAnimation(
          previewBytesFuture: previewCompleter.future,
        );
        previewCompleter.complete(dialogResult.pngBytes);
        await animationFuture;
        if (!mounted) {
          _isSnapshotFlowBusy = false;
          return;
        }
      }

      if (Platform.isAndroid) {
        final snapshotFileName = _buildSnapshotFileName();
        if (dialogResult.action == SnapshotDialogAction.save) {
          final saved = await _saveSnapshotToGallery(
            dialogResult.pngBytes,
            fileName: snapshotFileName,
          );
          if (!mounted) {
            _isSnapshotFlowBusy = false;
            return;
          }
          if (!saved) {
            _showFeedback(context, l10n.snapshotError);
            _isSnapshotFlowBusy = false;
            return;
          }

          final metadata = SnapshotEditorMetadata(
            songTitle: widget.songTitle,
            artistName: widget.artistName,
            artworkUrl: widget.artworkUrl,
            useArtworkBackground: dialogResult.useArtworkBackground,
            generatedThemeBrightness:
                dialogResult.generatedBrightness == Brightness.dark ? 'dark' : 'light',
            lyricsLines: selectableLines,
            activeLineIndex: persistedSelectedLineIndices.isEmpty
                ? -1
              : persistedSelectedLineIndices.reduce(math.min),
            activeLineIndexes: persistedSelectedLineIndices.toList()..sort(),
            selectedColorValue: dialogResult.selectedColor?.toARGB32(),
          );
          await SnapshotEditorStore.saveMetadataForDisplayName(
            displayName: snapshotFileName,
            metadata: metadata,
          );
          if (!mounted) {
            _isSnapshotFlowBusy = false;
            return;
          }
          _showFeedback(context, l10n.snapshotSaved);
          await widget.onSnapshotSavedToGallery?.call();
        }

        if (dialogResult.action == SnapshotDialogAction.share) {
          final shared = await _shareSnapshotViaAndroidChooser(
            dialogResult.pngBytes,
            fileName: snapshotFileName,
          );
          if (!mounted) {
            _isSnapshotFlowBusy = false;
            return;
          }
          if (shared != true) {
            _showFeedback(context, l10n.snapshotError);
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}singsync_snapshot_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(dialogResult.pngBytes, flush: true);
        await Share.shareXFiles(
          [XFile(file.path)],
        );
      }
    } catch (_) {
      if (!mounted) {
        _isSnapshotFlowBusy = false;
        return;
      }
      _showFeedback(context, l10n.snapshotError);
    } finally {
      _isSnapshotFlowBusy = false;
    }
  }

  Future<Set<int>?> _showLineSelectionDialog({
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

  Future<SnapshotDialogResult?> _showSnapshotPreviewDialog({
    required ui.Image? artworkImage,
    required List<Color> extractedPalette,
    required List<String> sourceLines,
    required Set<int> selectedLineIndices,
  }) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final themeDefaultColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerHighest;
    final window = SnapshotFlowTools.buildWindowAroundSelection(
      sourceLines: sourceLines,
      selectedLineIndices: selectedLineIndices,
      linesAbove: 2,
      linesBelow: 2,
      fallbackIndex: _defaultSnapshotActiveLineIndex(sourceLines.length),
    );
    final fallbackColor = await SnapshotArtworkTools.extractDominantColor(artworkImage);
    final palette = SnapshotFlowTools.buildPaletteOptions(
      extractedPalette: extractedPalette,
      defaultColor: themeDefaultColor,
      fallbackColor: fallbackColor ?? themeDefaultColor,
      theme: theme,
    );
    var selectedColor = palette.first;
    var useArtworkBackground = widget.useArtworkBackground;
    var generatedBrightness = widget.theme.brightness;
    final resolvedSongTitle =
        widget.songTitle.trim().isEmpty ? l10n.nowPlayingDefaultTitle : widget.songTitle;
    final resolvedArtistName =
        widget.artistName.trim().isEmpty ? l10n.unknownArtist : widget.artistName;

    Future<Uint8List?> buildPreviewPng({
      required Color? color,
      required bool artworkBackground,
      required Brightness brightness,
      required double renderScale,
      bool isPreview = false,
    }) {
      final generationTheme = SnapshotFlowTools.buildGenerationTheme(
        baseTheme: widget.theme,
        brightness: brightness,
      );
      final previewCardAlpha = brightness == Brightness.light ? 0.66 : 0.80;
      return SnapshotRenderer.buildPng(
        SnapshotRenderRequest(
          theme: generationTheme,
          songTitle: resolvedSongTitle,
          artistName: resolvedArtistName,
          useArtworkBackground: artworkBackground,
          lyricsLines: window.lines,
          activeLineIndex: window.activeLineIndices.isEmpty ? -1 : window.activeLineIndices.first,
          activeLineIndices: window.activeLineIndices,
          noLyricsFallback: l10n.snapshotNoLyrics,
          generatedWithBrand: l10n.snapshotGeneratedWithBrand,
          artworkUrl: widget.artworkUrl,
          selectedColor: color,
          preloadedArtworkImage: artworkImage,
          renderScale: renderScale,
          cardSurfaceAlpha: isPreview ? previewCardAlpha : 0.80,
        ),
      );
    }

    final previewResult = await buildPreviewPng(
      color: selectedColor,
      artworkBackground: useArtworkBackground,
      brightness: generatedBrightness,
      renderScale: 0.95,
      isPreview: true,
    );
    if (previewResult == null || previewResult.isEmpty || !mounted) {
      return null;
    }

    final result = await SnapshotDialogTools.showPreviewDialog(
      context: context,
      initialBytes: previewResult,
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
        if (Platform.isAndroid) {
          final shared = await _shareSnapshotViaAndroidChooser(
            currentState.pngBytes,
            fileName: _buildSnapshotFileName(),
          );
          if (mounted && shared != true) {
            _showFeedback(context, l10n.snapshotError);
          }
          return false;
        }

        final tempDir = await getTemporaryDirectory();
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}singsync_snapshot_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(currentState.pngBytes, flush: true);
        await Share.shareXFiles([XFile(file.path)]);
        return false;
      },
      rerender: (color, shouldUseArtworkBackground, brightness) {
        useArtworkBackground = shouldUseArtworkBackground;
        generatedBrightness = brightness;
        return buildPreviewPng(
          color: color,
          artworkBackground: shouldUseArtworkBackground,
          brightness: brightness,
          renderScale: 0.95,
          isPreview: true,
        );
      },
    );
    if (result == null || result.action != SnapshotDialogAction.save) {
      return result;
    }

    final fullBytes = await buildPreviewPng(
      color: result.selectedColor ?? selectedColor,
      artworkBackground: result.useArtworkBackground,
      brightness: result.generatedBrightness,
      renderScale: 2.2,
      isPreview: true,
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

  List<String> _buildSelectableSnapshotLines({required AppLocalizations l10n}) {
    if (_timedLines.isNotEmpty) {
      final lines = _timedLines
          .map((line) => line.text.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (lines.isNotEmpty) {
        return lines;
      }
    }

    final plain = _toPlainLyrics(widget.lyrics).trim();
    if (plain.isEmpty) {
      return <String>[l10n.snapshotNoLyrics];
    }

    final lines = plain
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return lines.isEmpty ? <String>[l10n.snapshotNoLyrics] : lines;
  }

  int _defaultSnapshotActiveLineIndex(int totalLines) {
    if (totalLines <= 0) {
      return -1;
    }
    if (_timedLines.isNotEmpty && _currentTimedLineIndex >= 0) {
      return _currentTimedLineIndex.clamp(0, totalLines - 1).toInt();
    }
    if (_scrollController.hasClients && totalLines > 1) {
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      if (maxScroll > 0) {
        final ratio = (position.pixels / maxScroll).clamp(0.0, 1.0);
        return (ratio * (totalLines - 1)).round().clamp(0, totalLines - 1);
      }
    }
    return 0;
  }

  Future<void> _playSnapshotCaptureAnimation({
    required Future<Uint8List?> previewBytesFuture,
  }) async {
    final stackContext = _panelStackKey.currentContext;
    if (stackContext == null) {
      return;
    }

    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (stackBox == null) {
      return;
    }

    final providedTargetCenter = widget.snapshotSaveTargetCenterProvider?.call();
    Offset? captureCenter;
    if (providedTargetCenter == null) {
      final captureContext = _captureButtonKey.currentContext;
      final captureBox = captureContext?.findRenderObject() as RenderBox?;
      if (captureBox != null) {
        captureCenter = captureBox.localToGlobal(captureBox.size.center(Offset.zero));
      }
    }

    final endCenter = providedTargetCenter ?? captureCenter;
    if (endCenter == null) {
      return;
    }

    final overlayState = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlayState == null) {
      return;
    }

    final stackSize = stackBox.size;
    final startCenter = stackBox.localToGlobal(Offset(stackSize.width / 2, stackSize.height * 0.46));

    _removeSnapshotOverlay();

    setState(() {
      _snapshotStartCenter = startCenter;
      _snapshotEndCenter = endCenter;
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

  Future<bool> _shareSnapshotViaAndroidChooser(
    Uint8List pngBytes, {
    String? fileName,
  }) async {
    final resolvedFileName = fileName ?? _buildSnapshotFileName();
    final launched = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'shareSnapshotWithSaveOption',
      {
        'bytes': pngBytes,
        'fileName': resolvedFileName,
      },
    );
    return launched == true;
  }

  Future<bool> _saveSnapshotToGallery(
    Uint8List pngBytes, {
    String? fileName,
  }) async {
    final resolvedFileName = fileName ?? _buildSnapshotFileName();
    final saved = await _lyricsMethodsChannel.invokeMethod<dynamic>(
      'saveSnapshotImage',
      {
        'bytes': pngBytes,
        'fileName': resolvedFileName,
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
                      onPressed: _copyLyrics,
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


