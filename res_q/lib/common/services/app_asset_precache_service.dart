import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppAssetPrecacheService {
  AppAssetPrecacheService._();

  static bool _didWarmUp = false;
  static Future<void>? _warmUpInFlight;

  static const List<String> _svgAssets = <String>[
    // Logos
    'assets/icons/logo/RES-Q_LOGO.svg',
    'assets/icons/logo/RES-Q_LOGO-WHITE.svg',

    // Bottom navigation
    'assets/icons/navbar/NAV-HOME-ICON.svg',
    'assets/icons/navbar/NAV-HOME-ICON-YELLOW.svg',
    'assets/icons/navbar/NAV-COMMUNITY-ICON.svg',
    'assets/icons/navbar/NAV-COMMUNITY-ICON-YELLOW.svg',
    'assets/icons/navbar/NAV-MAPS-ICON.svg',
    'assets/icons/navbar/NAV-MAPS-ICON-YELLOW.svg',
    'assets/icons/navbar/NAV-NOTIFICATIONS-ICON.svg',
    'assets/icons/navbar/NAV-NOTIFICATIONS-ICON-YELLOW.svg',
    'assets/icons/navbar/NAV-PROFILE-ICON.svg',
    'assets/icons/navbar/NAV-PROFILE-ICON-YELLOW.svg',

    // Main action icons
    'assets/icons/buttons/FINAL-EARTHQUAKE-ICON.svg',
    'assets/icons/buttons/FINAL-FLOOD-ICON.svg',
    'assets/icons/buttons/FINAL-FIRE-ICON.svg',
    'assets/icons/buttons/FINAL-CRASH-ICON.svg',
    'assets/icons/buttons/FINAL-OTHERS-ICON.svg',
  ];

  static const List<String> _rasterAssets = <String>[
    'assets/icons/logo/RES-Q_APP_LOGO.png',
    'assets/icons/buttons/FINAL-EARTHQUAKE-ICON.png',
    'assets/icons/buttons/FINAL-FLOOD-ICON.png',
    'assets/icons/buttons/FINAL-FIRE-ICON.png',
    'assets/icons/buttons/FINAL-CRASH-ICON.png',
    'assets/icons/buttons/FINAL-OTHERS-ICON.png',
  ];

  static Future<void> warmUpPostLoginAssets(BuildContext context) {
    if (_didWarmUp) {
      return Future<void>.value();
    }
    final inFlight = _warmUpInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    _warmUpInFlight = _warm(context);
    return _warmUpInFlight!;
  }

  static Future<void> _warm(BuildContext context) async {
    final futures = <Future<void>>[
      for (final assetPath in _rasterAssets)
        _safeWarm(
          () => precacheImage(AssetImage(assetPath), context),
          assetPath,
        ),
      for (final assetPath in _svgAssets)
        _safeWarm(
          () => SvgAssetLoader(assetPath).loadBytes(context),
          assetPath,
        ),
    ];

    await Future.wait(futures);
    _didWarmUp = true;
    _warmUpInFlight = null;
  }

  static Future<void> _safeWarm(
    Future<Object?> Function() loader,
    String assetPath,
  ) async {
    try {
      await loader();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Asset precache skipped for $assetPath: $error');
      }
    }
  }
}
