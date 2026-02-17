import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.theme,
    required this.lyrics,
    this.playbackPositionMs,
    required this.songTitle,
    required this.artistName,
    required this.onTap,
    required this.showActionButtons,
    this.onAssociateToSong,
    this.onCopyFeedbackVisibleChanged,
    this.onScrollDirectionChanged,
    this.onTimedLineTap,
  });

  final ThemeData theme;
  final String lyrics;
  final int? playbackPositionMs;
  final String songTitle;
  final String artistName;
  final VoidCallback onTap;
  final bool showActionButtons;
  final Future<bool> Function()? onAssociateToSong;
  final ValueChanged<bool>? onCopyFeedbackVisibleChanged;
  final ValueChanged<ScrollDirection>? onScrollDirectionChanged;
  final ValueChanged<int>? onTimedLineTap;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  late final ScrollController _scrollController;
  List<_TimedLyricLine> _timedLines = const [];
  int _currentTimedLineIndex = -1;
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  bool? _lastIsLandscape;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
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
    _scrollController.dispose();
    super.dispose();
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

    _showFeedback(context, 'Letra copiada');
  }

  Future<void> _shareLyrics() async {
    final text = _buildShareableLyrics().trim();
    if (text.isEmpty) {
      return;
    }
    await Share.share(text);
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
      associated ? 'Letra asociada a la canción' : 'No se pudo asociar la letra',
    );
  }

  void _showFeedback(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    widget.onCopyFeedbackVisibleChanged?.call(true);
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        content: Text(message, textAlign: TextAlign.center),
      ),
    );
    controller.closed.whenComplete(() {
      widget.onCopyFeedbackVisibleChanged?.call(false);
    });
  }

  String _buildShareableLyrics() {
    final lyricsText = _toPlainLyrics(widget.lyrics);
    if (lyricsText.isEmpty) {
      return '';
    }

    final title = widget.songTitle.trim();
    final artist = widget.artistName.trim();
    final hasHeader =
        title.isNotEmpty &&
        artist.isNotEmpty &&
        title.toLowerCase() != 'now playing' &&
        artist.toLowerCase() != 'artista desconocido';

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
      final key = _lineKeys[index];
      final context = key?.currentContext;
      if (context == null) {
        return;
      }

      Scrollable.ensureVisible(
        context,
        alignment: 0.38,
        duration: const Duration(milliseconds: 320),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
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
                                                : widget.theme.colorScheme.onSurface.withOpacity(0.74),
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
                      onPressed: () => _copyLyrics(context),
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy_all_rounded),
                    ),
                    IconButton(
                      onPressed: _shareLyrics,
                      tooltip: 'Compartir',
                      icon: const Icon(Icons.share_rounded),
                    ),
                    if (widget.onAssociateToSong != null)
                      IconButton(
                        onPressed: () => _associateLyrics(context),
                        tooltip: 'Asociar a canción',
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
