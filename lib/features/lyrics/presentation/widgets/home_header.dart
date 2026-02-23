import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_localizations.dart';

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.theme,
    required this.songTitle,
    required this.artistName,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.useArtworkBackground,
    required this.onUseArtworkBackgroundChanged,
    this.onHeaderTap,
    this.isCurrentFavorite = false,
    this.onToggleFavorite,
    this.onOpenFavorites,
    this.onInfoActionReady,
    this.isSleepTimerActive = false,
    this.sleepTimerTooltip,
    this.onSleepTimerTap,
  });

  final ThemeData theme;
  final String songTitle;
  final String artistName;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final bool useArtworkBackground;
  final ValueChanged<bool> onUseArtworkBackgroundChanged;
  final VoidCallback? onHeaderTap;
  final bool isCurrentFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOpenFavorites;
  final ValueChanged<VoidCallback>? onInfoActionReady;
  final bool isSleepTimerActive;
  final String? sleepTimerTooltip;
  final VoidCallback? onSleepTimerTap;

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
    widget.onInfoActionReady?.call(_showInfoModal);
  }

  @override
  void didUpdateWidget(covariant HomeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onInfoActionReady != widget.onInfoActionReady) {
      widget.onInfoActionReady?.call(_showInfoModal);
    }
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
    const privacyPolicyUrl = 'https://github.com/iozamudioa/singsync/blob/main/docs/privacy-policy.md';
    var useArtworkBackground = widget.useArtworkBackground;
    var isDarkMode = widget.isDarkMode;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) {
        final dialogTheme = Theme.of(context);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
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
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dialogTheme.colorScheme.surface.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: dialogTheme.colorScheme.onSurface.withValues(alpha: 0.10),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: StatefulBuilder(
                        builder: (context, modalSetState) {
                          final seedColor = widget.theme.colorScheme.primary;
                          final modalColorScheme = ColorScheme.fromSeed(
                            seedColor: seedColor,
                            brightness: isDarkMode ? Brightness.dark : Brightness.light,
                          );
                          final theme = Theme.of(context).copyWith(
                            colorScheme: modalColorScheme,
                          );
                          final l10n = AppLocalizations.of(context);
                          return FutureBuilder<PackageInfo>(
                            future: _packageInfoFuture,
                            builder: (context, snapshot) {
                              final version = snapshot.data?.version ?? '1.1.0';
                              return Theme(
                                data: theme,
                                child: DefaultTextStyle.merge(
                                  style: TextStyle(color: theme.colorScheme.onSurface),
                                  child: IconTheme.merge(
                                    data: IconThemeData(color: theme.colorScheme.onSurface),
                                    child: Column(
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
                                          child: SizedBox(
                                            width: 94,
                                            height: 94,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                Container(
                                                  width: 94,
                                                  height: 94,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: RadialGradient(
                                                      colors: [
                                                        theme.colorScheme.onSurface.withValues(alpha: 0.26),
                                                        theme.colorScheme.onSurface.withValues(alpha: 0.62),
                                                      ],
                                                      stops: const [0.12, 1],
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 74,
                                                  height: 74,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 50,
                                                  height: 50,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: theme.colorScheme.surface,
                                                      width: 1.8,
                                                    ),
                                                  ),
                                                  child: ClipOval(
                                                    child: Image.asset(
                                                      'assets/app_icon/singsync.png',
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(l10n.developerBy),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text('${l10n.githubLabel} '),
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
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text('${l10n.privacyPolicyLabel} '),
                                            InkWell(
                                              onTap: () {
                                                launchUrl(
                                                  Uri.parse(privacyPolicyUrl),
                                                  mode: LaunchMode.externalApplication,
                                                );
                                              },
                                              child: Text(
                                                privacyPolicyUrl,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: theme.colorScheme.primary,
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(l10n.versionLabel(version)),
                                        const SizedBox(height: 6),
                                        Text(
                                          l10n.poweredByLrclib,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      l10n.useArtworkBackground,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: theme.colorScheme.onSurface,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      l10n.useSolidBackgroundDescription,
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Switch.adaptive(
                                                value: useArtworkBackground,
                                                onChanged: (value) {
                                                  modalSetState(() {
                                                    useArtworkBackground = value;
                                                  });
                                                  widget.onUseArtworkBackgroundChanged(value);
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  isDarkMode ? l10n.switchToLightMode : l10n.switchToDarkMode,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  modalSetState(() {
                                                    isDarkMode = !isDarkMode;
                                                  });
                                                  widget.onToggleTheme();
                                                },
                                                icon: Icon(
                                                  isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                                ),
                                                tooltip: isDarkMode
                                                    ? l10n.switchToLightMode
                                                    : l10n.switchToDarkMode,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: Text(l10n.close),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
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
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        IconButton(
          onPressed: widget.onToggleFavorite,
          icon: Icon(
            widget.isCurrentFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
          tooltip: widget.isCurrentFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
        ),
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
          if (widget.isSleepTimerActive)
            IconButton(
              onPressed: widget.onSleepTimerTap,
              icon: const Icon(Icons.snooze_rounded),
              tooltip: widget.sleepTimerTooltip ?? AppLocalizations.of(context).sleepTimerActiveTitle,
            ),
      ],
    );
  }
}
