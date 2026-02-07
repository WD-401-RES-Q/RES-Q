import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppSnackBarType { info, success, warning, error }

class AppSnackBar {
  static OverlayEntry? _activeOverlay;

  static void show(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 2),
    bool useRootOverlay = false,
  }) {
    if (useRootOverlay) {
      _showInOverlay(context, message, type: type, duration: duration);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(build(message, type: type, duration: duration));
  }

  static SnackBar build(
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    final backgroundColor = _backgroundFor(type);
    final foregroundColor = type == AppSnackBarType.warning
        ? AppColors.appBlack
        : Colors.white;
    final icon = _iconFor(type, foregroundColor);

    return SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      elevation: 6,
      duration: duration,
      backgroundColor: backgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      content: Row(
        children: [
          icon,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showInOverlay(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(build(message, type: type, duration: duration));
      return;
    }

    _activeOverlay?.remove();
    _activeOverlay = null;

    final backgroundColor = _backgroundFor(type);
    final foregroundColor = type == AppSnackBarType.warning
        ? AppColors.appBlack
        : Colors.white;
    final icon = _iconFor(type, foregroundColor);

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(
          minimum: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: foregroundColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _activeOverlay = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_activeOverlay == entry) {
        entry.remove();
        _activeOverlay = null;
      }
    });
  }

  static Color _backgroundFor(AppSnackBarType type) {
    switch (type) {
      case AppSnackBarType.success:
        return AppColors.appGreen;
      case AppSnackBarType.warning:
        return AppColors.appOffYellow;
      case AppSnackBarType.error:
        return AppColors.appRed;
      case AppSnackBarType.info:
      default:
        return AppColors.appBlack;
    }
  }

  static Widget _iconFor(AppSnackBarType type, Color color) {
    IconData icon;
    switch (type) {
      case AppSnackBarType.success:
        icon = Icons.check_circle_outline;
        break;
      case AppSnackBarType.warning:
        icon = Icons.warning_amber_rounded;
        break;
      case AppSnackBarType.error:
        icon = Icons.error_outline;
        break;
      case AppSnackBarType.info:
      default:
        icon = Icons.info_outline;
        break;
    }
    return Icon(icon, color: color, size: 20);
  }
}
