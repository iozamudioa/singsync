import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SnapshotEditorMetadata {
  const SnapshotEditorMetadata({
    required this.songTitle,
    required this.artistName,
    required this.artworkUrl,
    required this.useArtworkBackground,
    required this.lyricsLines,
    required this.activeLineIndex,
    this.activeLineIndexes = const <int>[],
    required this.selectedColorValue,
    this.generatedThemeBrightness,
  });

  final String songTitle;
  final String artistName;
  final String? artworkUrl;
  final bool useArtworkBackground;
  final List<String> lyricsLines;
  final int activeLineIndex;
  final List<int> activeLineIndexes;
  final int? selectedColorValue;
  final String? generatedThemeBrightness;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'songTitle': songTitle,
      'artistName': artistName,
      'artworkUrl': artworkUrl,
      'useArtworkBackground': useArtworkBackground,
      'lyricsLines': lyricsLines,
      'activeLineIndex': activeLineIndex,
      'activeLineIndexes': activeLineIndexes,
      'selectedColorValue': selectedColorValue,
      'generatedThemeBrightness': generatedThemeBrightness,
    };
  }

  factory SnapshotEditorMetadata.fromJson(Map<String, dynamic> json) {
    return SnapshotEditorMetadata(
      songTitle: (json['songTitle'] ?? '').toString(),
      artistName: (json['artistName'] ?? '').toString(),
      artworkUrl: (json['artworkUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (json['artworkUrl'] ?? '').toString().trim(),
      useArtworkBackground: json['useArtworkBackground'] == true,
      lyricsLines: (json['lyricsLines'] is List)
          ? (json['lyricsLines'] as List)
                .map((line) => line.toString().trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      activeLineIndex: (json['activeLineIndex'] is int)
          ? json['activeLineIndex'] as int
          : int.tryParse((json['activeLineIndex'] ?? '').toString()) ?? -1,
        activeLineIndexes: (json['activeLineIndexes'] is List)
          ? (json['activeLineIndexes'] as List)
            .map((value) => value is int ? value : int.tryParse(value.toString()))
            .whereType<int>()
            .toList(growable: false)
          : const <int>[],
      selectedColorValue: (json['selectedColorValue'] is int)
          ? json['selectedColorValue'] as int
          : int.tryParse((json['selectedColorValue'] ?? '').toString()),
      generatedThemeBrightness: () {
        final raw = (json['generatedThemeBrightness'] ?? '').toString().trim().toLowerCase();
        if (raw == 'light' || raw == 'dark') {
          return raw;
        }
        return null;
      }(),
    );
  }

  SnapshotEditorMetadata copyWith({
    bool? useArtworkBackground,
    int? activeLineIndex,
    List<int>? activeLineIndexes,
    int? selectedColorValue,
    String? generatedThemeBrightness,
  }) {
    return SnapshotEditorMetadata(
      songTitle: songTitle,
      artistName: artistName,
      artworkUrl: artworkUrl,
      useArtworkBackground: useArtworkBackground ?? this.useArtworkBackground,
      lyricsLines: lyricsLines,
      activeLineIndex: activeLineIndex ?? this.activeLineIndex,
      activeLineIndexes: activeLineIndexes ?? this.activeLineIndexes,
      selectedColorValue: selectedColorValue ?? this.selectedColorValue,
      generatedThemeBrightness: generatedThemeBrightness ?? this.generatedThemeBrightness,
    );
  }
}

class SnapshotEditorStore {
  static const String _snapshotMetadataKeyPrefix = 'snapshot_meta_v1::';

  static Future<void> saveMetadataForDisplayName({
    required String displayName,
    required SnapshotEditorMetadata metadata,
  }) async {
    final keySuffix = _normalizedDisplayName(displayName);
    if (keySuffix.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_snapshotMetadataKeyPrefix$keySuffix',
      jsonEncode(metadata.toJson()),
    );
  }

  static Future<SnapshotEditorMetadata?> readMetadataForDisplayName(String displayName) async {
    final keySuffix = _normalizedDisplayName(displayName);
    if (keySuffix.isEmpty) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_snapshotMetadataKeyPrefix$keySuffix');
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));
      return SnapshotEditorMetadata.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static String _normalizedDisplayName(String displayName) {
    return displayName.trim();
  }
}

class SnapshotRenderRequest {
  const SnapshotRenderRequest({
    required this.theme,
    required this.songTitle,
    required this.artistName,
    required this.useArtworkBackground,
    required this.lyricsLines,
    required this.activeLineIndex,
    this.activeLineIndices = const <int>[],
    required this.noLyricsFallback,
    required this.generatedWithBrand,
    this.artworkUrl,
    this.selectedColor,
    this.preloadedArtworkImage,
  });

  final ThemeData theme;
  final String songTitle;
  final String artistName;
  final bool useArtworkBackground;
  final List<String> lyricsLines;
  final int activeLineIndex;
  final List<int> activeLineIndices;
  final String noLyricsFallback;
  final String generatedWithBrand;
  final String? artworkUrl;
  final Color? selectedColor;
  final ui.Image? preloadedArtworkImage;
}

class SnapshotArtworkTools {
  static Future<ui.Image?> loadArtworkImage(String? artworkUrl) async {
    final normalized = artworkUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    try {
      final uri = Uri.tryParse(normalized);
      if (uri == null) {
        return null;
      }
      final bytes = uri.scheme.toLowerCase() == 'file'
          ? await File.fromUri(uri).readAsBytes()
          : (await NetworkAssetBundle(uri).load(normalized)).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Future<Color?> extractDominantColor(ui.Image? artworkImage) async {
    final palette = await extractPalette(artworkImage);
    if (palette.isEmpty) {
      return null;
    }
    return palette.first;
  }

  static Future<List<Color>> extractPalette(ui.Image? artworkImage) async {
    if (artworkImage == null) {
      return const <Color>[];
    }

    try {
      final byteData = await artworkImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return const <Color>[];
      }

      final bytes = byteData.buffer.asUint8List();
      final width = artworkImage.width;
      final height = artworkImage.height;
      final stepX = math.max(1, width ~/ 36);
      final stepY = math.max(1, height ~/ 36);

      final buckets = <int, _ColorBucket>{};
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

          final hsl = HSLColor.fromColor(Color.fromARGB(255, red, green, blue));
          final hueBucket = (hsl.hue / 24).floor().clamp(0, 15);
          final satBucket = (hsl.saturation / 0.34).floor().clamp(0, 2);
          final lightBucket = (hsl.lightness / 0.34).floor().clamp(0, 2);
          final key = (hueBucket << 16) | (satBucket << 8) | lightBucket;

          final weight = alpha;
          final bucket = buckets.putIfAbsent(key, () => _ColorBucket());
          bucket.accumulate(red: red, green: green, blue: blue, weight: weight);
        }
      }

      if (buckets.isEmpty) {
        return const <Color>[];
      }

      final sorted = buckets.values.toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));
      final result = <Color>[];
      for (final bucket in sorted.take(9)) {
        final base = bucket.toColor();
        final hsl = HSLColor.fromColor(base);
        final tuned = hsl
            .withSaturation((hsl.saturation * 0.85).clamp(0.22, 0.72).toDouble())
            .withLightness(hsl.lightness.clamp(0.20, 0.76).toDouble())
            .toColor();
        if (result.every((existing) => _colorDistance(existing, tuned) > 0.12)) {
          result.add(tuned);
        }
      }

      return result;
    } catch (_) {
      return const <Color>[];
    }
  }

  static double _colorDistance(Color a, Color b) {
    final ah = HSLColor.fromColor(a);
    final bh = HSLColor.fromColor(b);
    final hueDelta = ((ah.hue - bh.hue).abs() / 360).clamp(0, 1).toDouble();
    final satDelta = (ah.saturation - bh.saturation).abs();
    final lightDelta = (ah.lightness - bh.lightness).abs();
    return (hueDelta * 0.6) + (satDelta * 0.25) + (lightDelta * 0.15);
  }
}

class SnapshotWindowSelection {
  const SnapshotWindowSelection({
    required this.lines,
    required this.activeLineIndices,
  });

  final List<String> lines;
  final List<int> activeLineIndices;
}

class SnapshotFlowTools {
  static ThemeData buildGenerationTheme({
    required ThemeData baseTheme,
    required Brightness brightness,
  }) {
    return ThemeData(
      useMaterial3: baseTheme.useMaterial3,
      brightness: brightness,
      colorSchemeSeed: baseTheme.colorScheme.primary,
      fontFamily: baseTheme.textTheme.bodyMedium?.fontFamily,
    );
  }

  static SnapshotWindowSelection buildWindowAroundSelection({
    required List<String> sourceLines,
    required Set<int> selectedLineIndices,
    required int linesAbove,
    required int linesBelow,
    required int fallbackIndex,
  }) {
    if (sourceLines.isEmpty) {
      return const SnapshotWindowSelection(lines: <String>[], activeLineIndices: <int>[]);
    }

    final normalized = selectedLineIndices
        .where((index) => index >= 0 && index < sourceLines.length)
        .toList(growable: false)
      ..sort();
    final effectiveFallback = fallbackIndex.clamp(0, sourceLines.length - 1);
    final effective = normalized.isEmpty ? <int>[effectiveFallback] : normalized;

    if (effective.length >= 4) {
      final lines = effective.map((index) => sourceLines[index]).toList(growable: false);
      final activeLineIndices = List<int>.generate(lines.length, (index) => index, growable: false);
      return SnapshotWindowSelection(lines: lines, activeLineIndices: activeLineIndices);
    }

    final minSelected = effective.first;
    final maxSelected = effective.last;

    var start = (minSelected - linesAbove).clamp(0, sourceLines.length - 1);
    var end = (maxSelected + linesBelow).clamp(0, sourceLines.length - 1);

    const targetSize = 5;
    while ((end - start + 1) < targetSize && start > 0) {
      start -= 1;
    }
    while ((end - start + 1) < targetSize && end < sourceLines.length - 1) {
      end += 1;
    }

    final lines = sourceLines.sublist(start, end + 1);
    final activeLineIndices = effective
        .map((index) => (index - start).clamp(0, lines.length - 1))
        .toSet()
        .toList(growable: false)
      ..sort();
    return SnapshotWindowSelection(lines: lines, activeLineIndices: activeLineIndices);
  }

  static List<Color> buildPaletteOptions({
    required List<Color> extractedPalette,
    required Color defaultColor,
    required Color fallbackColor,
    required ThemeData theme,
  }) {
    final options = <Color>[];
    final candidates = <Color>[...extractedPalette];
    candidates.addAll(<Color>[
      Color.lerp(theme.colorScheme.primary, fallbackColor, 0.40)!,
      Color.lerp(theme.colorScheme.secondary, fallbackColor, 0.50)!,
      Color.lerp(theme.colorScheme.tertiary, fallbackColor, 0.55)!,
      Color.lerp(theme.colorScheme.error, fallbackColor, 0.35)!,
      Color.lerp(theme.colorScheme.surfaceContainerHighest, fallbackColor, 0.60)!,
      Color.lerp(Colors.white, fallbackColor, 0.16)!,
      Color.lerp(Colors.black, fallbackColor, 0.18)!,
    ]);

    for (final color in candidates) {
      if (options.length >= 7) {
        break;
      }
      if (_paletteDistance(color, defaultColor) <= 0.05) {
        continue;
      }
      if (options.every((existing) => _paletteDistance(existing, color) > 0.10)) {
        options.add(color);
      }
    }

    var hueSeed = HSLColor.fromColor(fallbackColor);
    while (options.length < 7) {
      hueSeed = hueSeed.withHue((hueSeed.hue + 28) % 360);
      final generated = hueSeed
          .withSaturation((hueSeed.saturation * 0.90).clamp(0.24, 0.74).toDouble())
          .withLightness(hueSeed.lightness.clamp(0.22, 0.74).toDouble())
          .toColor();
      if (_paletteDistance(generated, defaultColor) <= 0.05) {
        continue;
      }
      if (options.every((existing) => _paletteDistance(existing, generated) > 0.08)) {
        options.add(generated);
      }
    }

    options.add(defaultColor);
    return options;
  }

  static double _paletteDistance(Color a, Color b) {
    final ah = HSLColor.fromColor(a);
    final bh = HSLColor.fromColor(b);
    final hueDelta = ((ah.hue - bh.hue).abs() / 360).clamp(0, 1).toDouble();
    final satDelta = (ah.saturation - bh.saturation).abs();
    final lightDelta = (ah.lightness - bh.lightness).abs();
    return (hueDelta * 0.6) + (satDelta * 0.25) + (lightDelta * 0.15);
  }
}

enum SnapshotDialogAction { back, share, save }

class SnapshotDialogResult {
  const SnapshotDialogResult({
    required this.pngBytes,
    required this.selectedColor,
    required this.useArtworkBackground,
    required this.generatedBrightness,
    required this.action,
  });

  final Uint8List pngBytes;
  final Color? selectedColor;
  final bool useArtworkBackground;
  final Brightness generatedBrightness;
  final SnapshotDialogAction action;
}

class SnapshotDialogTools {
  static Future<Set<int>?> showLineSelectionDialog({
    required BuildContext context,
    required List<String> lines,
    required Set<int> initialIndexes,
    required String title,
    required String nextLabel,
  }) async {
    final selectedIndexes = <int>{
      ...initialIndexes.where((index) => index >= 0 && index < lines.length),
    };
    final listScrollController = ScrollController();
    final lineKeys = List<GlobalKey>.generate(lines.length, (_) => GlobalKey(), growable: false);
    var didInitialScroll = false;
    if (selectedIndexes.isEmpty && lines.isNotEmpty) {
      selectedIndexes.add(0);
    }

    return showDialog<Set<int>>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;
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
                      maxWidth: math.min(520.0, size.width * 0.92),
                      maxHeight: size.height * 0.88,
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
                      child: StatefulBuilder(
                        builder: (context, modalSetState) {
                          if (!didInitialScroll && selectedIndexes.isNotEmpty) {
                            didInitialScroll = true;
                            Future<void> scrollToFirstSelected() async {
                              if (!dialogContext.mounted || selectedIndexes.isEmpty) {
                                return;
                              }
                              final sorted = selectedIndexes.toList()..sort();
                              final firstSelected = sorted.first;
                              if (firstSelected < 0 || firstSelected >= lineKeys.length) {
                                return;
                              }

                              if (listScrollController.hasClients) {
                                const estimatedTileHeight = 58.0;
                                const estimatedSeparatorHeight = 6.0;
                                final estimatedOffset =
                                    firstSelected * (estimatedTileHeight + estimatedSeparatorHeight);
                                final targetOffset = estimatedOffset.clamp(
                                  listScrollController.position.minScrollExtent,
                                  listScrollController.position.maxScrollExtent,
                                );
                                listScrollController.jumpTo(targetOffset);
                              }

                              await Future<void>.delayed(const Duration(milliseconds: 16));
                              if (!dialogContext.mounted) {
                                return;
                              }
                              final targetContext = lineKeys[firstSelected].currentContext;
                              if (targetContext == null) {
                                return;
                              }
                              Scrollable.ensureVisible(
                                targetContext,
                                alignment: 0.25,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                              );
                            }

                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              unawaited(scrollToFirstSelected());
                            });
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Flexible(
                                child: ListView.separated(
                                  controller: listScrollController,
                                  itemCount: lines.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final isSelected = selectedIndexes.contains(index);
                                    return InkWell(
                                      key: lineKeys[index],
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        modalSetState(() {
                                          if (isSelected) {
                                            selectedIndexes.remove(index);
                                          } else {
                                            selectedIndexes.add(index);
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: isSelected
                                              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.60)
                                              : theme.colorScheme.surface.withValues(alpha: 0.20),
                                        ),
                                        child: Text(
                                          lines[index],
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FilledButton(
                                    onPressed: selectedIndexes.isEmpty
                                        ? null
                                        : () => Navigator.of(dialogContext).pop(selectedIndexes.toSet()),
                                    child: Text(nextLabel),
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

  static Future<SnapshotDialogResult?> showPreviewDialog({
    required BuildContext context,
    required Uint8List initialBytes,
    required Color initialColor,
    required bool initialUseArtworkBackground,
    required Brightness initialGeneratedBrightness,
    required bool canUseArtworkBackground,
    required List<Color> palette,
    required Future<Uint8List?> Function(
      Color color,
      bool useArtworkBackground,
      Brightness generatedBrightness,
    ) rerender,
    required String backTooltip,
    required String saveTooltip,
    required String shareTooltip,
    required String useArtworkBackgroundLabel,
    required String lightThemeLabel,
    required String darkThemeLabel,
    Future<bool> Function(SnapshotDialogResult currentState)? onShareInPlace,
  }) async {
    var previewBytes = initialBytes;
    var selectedColor = initialColor;
    var useArtworkBackground = initialUseArtworkBackground;
    var generatedBrightness = initialGeneratedBrightness;
    var renderRequestId = 0;

    return showDialog<SnapshotDialogResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;

        Future<void> rerenderPreview(StateSetter modalSetState, {
          Color? color,
          bool? artworkBackground,
          Brightness? brightness,
        }) async {
          final nextColor = color ?? selectedColor;
          final nextUseArtworkBackground = artworkBackground ?? useArtworkBackground;
          final nextBrightness = brightness ?? generatedBrightness;
          final hasColorChange = selectedColor.toARGB32() != nextColor.toARGB32();
          final hasBackgroundChange = useArtworkBackground != nextUseArtworkBackground;
          final hasBrightnessChange = generatedBrightness != nextBrightness;
          if (!hasColorChange && !hasBackgroundChange && !hasBrightnessChange) {
            return;
          }

          renderRequestId += 1;
          final currentRequestId = renderRequestId;
          modalSetState(() {
            selectedColor = nextColor;
            useArtworkBackground = nextUseArtworkBackground;
            generatedBrightness = nextBrightness;
          });
          final rerendered = await rerender(
            nextColor,
            nextUseArtworkBackground,
            nextBrightness,
          );
          if (!dialogContext.mounted ||
              currentRequestId != renderRequestId ||
              rerendered == null ||
              rerendered.isEmpty) {
            return;
          }
          modalSetState(() {
            previewBytes = rerendered;
          });
        }

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
                      maxWidth: math.min(540.0, size.width * 0.92),
                      maxHeight: size.height * 0.86,
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
                      child: StatefulBuilder(
                        builder: (context, modalSetState) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    style: _actionButtonStyle(theme),
                                    onPressed: () => Navigator.of(dialogContext).pop(
                                      SnapshotDialogResult(
                                        pngBytes: previewBytes,
                                        selectedColor: selectedColor,
                                        useArtworkBackground: useArtworkBackground,
                                        generatedBrightness: generatedBrightness,
                                        action: SnapshotDialogAction.back,
                                      ),
                                    ),
                                    tooltip: backTooltip,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      useArtworkBackgroundLabel,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: useArtworkBackground,
                                    onChanged: canUseArtworkBackground
                                        ? (value) {
                                            unawaited(
                                              rerenderPreview(
                                                modalSetState,
                                                artworkBackground: value,
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Flexible(
                                child: Stack(
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      switchInCurve: Curves.easeInOut,
                                      switchOutCurve: Curves.easeInOut,
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(opacity: animation, child: child),
                                      child: ClipRRect(
                                        key: ValueKey<int>(previewBytes.hashCode),
                                        borderRadius: BorderRadius.circular(14),
                                        child: InteractiveViewer(
                                          minScale: 1,
                                          maxScale: 3.2,
                                          child: Image.memory(previewBytes, fit: BoxFit.contain),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: IconButton(
                                        style: _actionButtonStyle(theme),
                                        onPressed: () {
                                          final nextBrightness =
                                              generatedBrightness == Brightness.dark
                                                  ? Brightness.light
                                                  : Brightness.dark;
                                          unawaited(
                                            rerenderPreview(
                                              modalSetState,
                                              brightness: nextBrightness,
                                            ),
                                          );
                                        },
                                        tooltip: generatedBrightness == Brightness.dark
                                            ? lightThemeLabel
                                            : darkThemeLabel,
                                        icon: Icon(
                                          generatedBrightness == Brightness.dark
                                              ? Icons.nightlight_round
                                              : Icons.wb_sunny_rounded,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            style: _actionButtonStyle(theme),
                                            onPressed: () => Navigator.of(dialogContext).pop(
                                              SnapshotDialogResult(
                                                pngBytes: previewBytes,
                                                selectedColor: selectedColor,
                                                useArtworkBackground: useArtworkBackground,
                                                generatedBrightness: generatedBrightness,
                                                action: SnapshotDialogAction.save,
                                              ),
                                            ),
                                            icon: const Icon(Icons.save_alt_rounded),
                                            tooltip: saveTooltip,
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            style: _actionButtonStyle(theme),
                                            onPressed: () async {
                                              final current = SnapshotDialogResult(
                                                pngBytes: previewBytes,
                                                selectedColor: selectedColor,
                                                useArtworkBackground: useArtworkBackground,
                                                generatedBrightness: generatedBrightness,
                                                action: SnapshotDialogAction.share,
                                              );
                                              if (onShareInPlace != null) {
                                                final didShare = await onShareInPlace(current);
                                                if (didShare && dialogContext.mounted) {
                                                  Navigator.of(dialogContext).pop(current);
                                                }
                                                return;
                                              }
                                              if (!dialogContext.mounted) {
                                                return;
                                              }
                                              Navigator.of(dialogContext).pop(current);
                                            },
                                            icon: const Icon(Icons.share_rounded),
                                            tooltip: shareTooltip,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (var index = 0; index < palette.length; index++) ...[
                                              if (index > 0) const SizedBox(width: 10),
                                              Builder(
                                                builder: (context) {
                                                  final color = palette[index];
                                                  final selected =
                                                      selectedColor.toARGB32() == color.toARGB32();
                                                  final glowColor = theme.colorScheme.primary;
                                                  return InkWell(
                                                    borderRadius: BorderRadius.circular(999),
                                                    onTap: () {
                                                      unawaited(
                                                        rerenderPreview(
                                                          modalSetState,
                                                          color: color,
                                                        ),
                                                      );
                                                    },
                                                    child: Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: color,
                                                        border: Border.all(
                                                          color: selected
                                                              ? glowColor
                                                              : theme.colorScheme.onSurface.withValues(alpha: 0.24),
                                                          width: selected ? 3 : 1,
                                                        ),
                                                        boxShadow: selected
                                                            ? [
                                                                BoxShadow(
                                                                  color: glowColor.withValues(alpha: 0.55),
                                                                  blurRadius: 14,
                                                                  spreadRadius: 2,
                                                                ),
                                                              ]
                                                            : null,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
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

  static ButtonStyle _actionButtonStyle(ThemeData theme) {
    return IconButton.styleFrom(
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.32),
      foregroundColor: theme.colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class SnapshotRenderer {
  static Future<Uint8List?> buildPng(SnapshotRenderRequest request) async {
    final theme = request.theme;
    const baseWidth = 1080.0;
    const baseHeight = 1350.0;
    const exportScale = 2.2;
    final exportWidth = (baseWidth * exportScale).round();
    final exportHeight = (baseHeight * exportScale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, exportWidth.toDouble(), exportHeight.toDouble()),
    );
    canvas.scale(exportScale, exportScale);
    const rect = Rect.fromLTWH(0, 0, baseWidth, baseHeight);

    final artworkImage =
        request.preloadedArtworkImage ?? await SnapshotArtworkTools.loadArtworkImage(request.artworkUrl);
    final dominantArtworkColor = request.selectedColor ??
        await SnapshotArtworkTools.extractDominantColor(artworkImage);
    final shouldUseArtworkBackground = request.useArtworkBackground && artworkImage != null;

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
      final overlayColor = dominantArtworkColor == null
          ? theme.colorScheme.surface.withValues(alpha: 0.58)
          : Color.lerp(theme.colorScheme.surface, dominantArtworkColor, 0.30)!.withValues(alpha: 0.56);
      canvas.drawRect(rect, Paint()..color = overlayColor);
    } else {
      final gradientStartColor = dominantArtworkColor == null
          ? theme.colorScheme.surface
          : Color.lerp(theme.colorScheme.surface, dominantArtworkColor, 0.30)!;
      final gradientEndColor = dominantArtworkColor == null
          ? theme.colorScheme.surfaceContainerHighest
          : Color.lerp(theme.colorScheme.surfaceContainerHighest, dominantArtworkColor, 0.16)!;

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
            fontSize: (theme.textTheme.titleLarge?.fontSize ?? 22) + 2,
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
      fontSize: (theme.textTheme.headlineSmall?.fontSize ?? 24) + 15,
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.onSurface,
    );
    final artistStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) + 5,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.90),
    );
    final lyricsStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) + 8,
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

    final title = request.songTitle.trim().isEmpty ? 'Now Playing' : request.songTitle.trim();
    final artist = request.artistName.trim().isEmpty ? 'Unknown artist' : request.artistName.trim();

    drawText(
      text: title,
      style: titleStyle,
      top: 690,
      maxWidth: 820,
      maxLines: 2,
    );
    drawText(
      text: artist,
      style: artistStyle,
      top: 796,
      maxWidth: 820,
      maxLines: 1,
    );

    final lines = request.lyricsLines.isEmpty
        ? <String>[request.noLyricsFallback]
        : request.lyricsLines;

    var currentTop = 868.0;
    const maxBottom = 1212.0;
    final activeLineIndices = request.activeLineIndices.toSet();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final isActive =
          activeLineIndices.contains(lineIndex) || lineIndex == request.activeLineIndex;
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
        text: request.generatedWithBrand,
        style: theme.textTheme.labelLarge?.copyWith(
          fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) + 4,
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
}

class _ColorBucket {
  int _sumR = 0;
  int _sumG = 0;
  int _sumB = 0;
  int weight = 0;

  void accumulate({
    required int red,
    required int green,
    required int blue,
    required int weight,
  }) {
    _sumR += red * weight;
    _sumG += green * weight;
    _sumB += blue * weight;
    this.weight += weight;
  }

  Color toColor() {
    if (weight == 0) {
      return Colors.grey;
    }
    return Color.fromARGB(
      255,
      (_sumR / weight).round().clamp(0, 255),
      (_sumG / weight).round().clamp(0, 255),
      (_sumB / weight).round().clamp(0, 255),
    );
  }
}