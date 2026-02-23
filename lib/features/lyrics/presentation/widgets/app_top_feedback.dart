import 'dart:async';

import 'package:flutter/material.dart';

class AppTopFeedback {
  static final ValueNotifier<bool> _isVisibleNotifier = ValueNotifier<bool>(false);
  static int _activeFeedbackId = 0;
  static OverlayEntry? _overlayEntry;
  static Timer? _hideTimer;
  static const double _bottomNavClearance = 82;

  static ValueNotifier<bool> get visibility => _isVisibleNotifier;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1400),
    ValueChanged<bool>? onVisibilityChanged,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    _hideTimer?.cancel();
    _overlayEntry?.remove();

    final feedbackId = ++_activeFeedbackId;
    _isVisibleNotifier.value = true;
    onVisibilityChanged?.call(true);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: 16,
          right: 16,
          bottom: 16 + bottomInset + _bottomNavClearance,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);

    _hideTimer = Timer(duration, () {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (feedbackId == _activeFeedbackId) {
        _isVisibleNotifier.value = false;
      }
      onVisibilityChanged?.call(false);
    });
  }
}
