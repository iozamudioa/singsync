import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.theme,
    required this.songTitle,
    required this.artistName,
    required this.isDarkMode,
    required this.onToggleTheme,
    this.onHeaderTap,
  });

  final ThemeData theme;
  final String songTitle;
  final String artistName;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback? onHeaderTap;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Future<PackageInfo> _packageInfoFuture;
  double _lastTextWidth = 0;
  static const double _marqueeEndGap = 12;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncMarquee({required bool enabled, required double textWidth}) {
    if (!enabled || textWidth <= 0) {
      _lastTextWidth = 0;
      _controller.stop();
      _controller.value = 0;
      return;
    }

    final changed = (_lastTextWidth - textWidth).abs() >= 1;

    if (!changed) {
      if (!_controller.isAnimating) {
        _startLoopAnimation();
      }
      return;
    }

    _lastTextWidth = textWidth;
    _startLoopAnimation();
  }

  void _startLoopAnimation() {
    final distance = _lastTextWidth + _marqueeEndGap;
    final durationMs = (distance * 40).clamp(7000, 22000).round();
    _controller.duration = Duration(milliseconds: durationMs);
    _controller
      ..stop()
      ..reset()
      ..repeat();
  }

  void _showInfoModal() {
    const githubUrl = 'https://github.com/iozamudioa';

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColoredBox(color: Colors.black.withOpacity(0.28)),
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.68),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.10)),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: FutureBuilder<PackageInfo>(
                        future: _packageInfoFuture,
                        builder: (context, snapshot) {
                          final version = snapshot.data?.version ?? '1.1.0';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Center(
                                child: Text(
                                  'SingSync',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    'assets/app_icon/singsync.png',
                                    width: 86,
                                    height: 86,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text('Developer by: iozamudioa'),
                              const SizedBox(height: 6),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('Github: '),
                                  InkWell(
                                    onTap: () {
                                      launchUrl(
                                        Uri.parse(githubUrl),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                    child: Text(
                                      githubUrl,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Version: $version'),
                              const SizedBox(height: 6),
                              Text(
                                'Powered by: LRCLIB',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cerrar'),
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

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final style = widget.theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final fullHeaderText = '${widget.songTitle.trim()} - ${widget.artistName.trim()}';

    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onHeaderTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final painter = TextPainter(
                      text: TextSpan(text: fullHeaderText, style: style),
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    )..layout();

                    final needsMarquee = painter.width > constraints.maxWidth;
                    final scrollDistance = painter.width + _marqueeEndGap;
                    _syncMarquee(enabled: needsMarquee, textWidth: painter.width);

                    if (!needsMarquee) {
                      return Text(
                        fullHeaderText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: isLandscape ? TextAlign.center : TextAlign.start,
                        style: style,
                      );
                    }

                    return ClipRect(
                      child: SizedBox(
                        height: (style?.fontSize ?? 22) * 1.3,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final offsetX = -scrollDistance * _controller.value;
                            return Transform.translate(
                              offset: Offset(offsetX, 0),
                              child: child,
                            );
                          },
                          child: Align(
                            alignment: isLandscape ? Alignment.center : Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  fullHeaderText,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: style,
                                ),
                                const SizedBox(width: _marqueeEndGap),
                                Text(
                                  fullHeaderText,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: style,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          onPressed: _showInfoModal,
          icon: const Icon(Icons.info_outline_rounded),
          tooltip: 'Información',
        ),
        IconButton(
          onPressed: widget.onToggleTheme,
          icon: Icon(
            widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
          tooltip: widget.isDarkMode ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
        ),
      ],
    );
  }
}
