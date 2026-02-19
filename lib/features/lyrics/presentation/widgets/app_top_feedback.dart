import 'dart:async';

import 'package:flutter/material.dart';

class AppTopFeedback {
  static final ValueNotifier<bool> _isVisibleNotifier = ValueNotifier<bool>(false);
  static int _activeFeedbackId = 0;

  static ValueNotifier<bool> get visibility => _isVisibleNotifier;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1400),
    ValueChanged<bool>? onVisibilityChanged,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    messenger.hideCurrentSnackBar();
    messenger.hideCurrentMaterialBanner();

    final feedbackId = ++_activeFeedbackId;
    _isVisibleNotifier.value = true;
    onVisibilityChanged?.call(true);
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        backgroundColor: theme.colorScheme.inverseSurface,
        duration: duration,
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onInverseSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    controller.closed.whenComplete(() {
      if (feedbackId == _activeFeedbackId) {
        _isVisibleNotifier.value = false;
      }
      onVisibilityChanged?.call(false);
    });
  }
}
