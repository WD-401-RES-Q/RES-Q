import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/phone_lookup_service.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/theme/app_theme.dart';
import '../../auth/pages/login_page.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  bool _isInitializing = false;
  bool _webExitRequested = false;
  static const Duration _otpBypassWindow = Duration(days: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializeApp());
    });
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await _requestNotificationPermission();
      final hasLocation = await _ensureLocationPermission();
      if (!mounted || !hasLocation) return;
      await _navigateFromStartupAuthState();
    } finally {
      _isInitializing = false;
    }
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      return value.toDate() as DateTime?;
    } catch (_) {}
    if (value is Map<String, dynamic>) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanos = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        final parsedNanos = nanos is int
            ? nanos
            : (nanos is num ? nanos.toInt() : 0);
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000) + (parsedNanos ~/ 1000000),
        );
      }
    }
    return null;
  }

  Future<bool> _canBypassOtpOnStartup({
    required String phone,
    dynamic firestoreLastLogin,
  }) async {
    final trustedForPhone = await TrustedDeviceService.instance.isTrustedPhone(
      phone,
    );
    if (!trustedForPhone) return false;

    final trustedActivity = await TrustedDeviceService.instance
        .getLastTrustedActivity();
    final firestoreActivity = _parseTimestamp(firestoreLastLogin);
    final latestActivity = (() {
      if (trustedActivity == null) return firestoreActivity;
      if (firestoreActivity == null) return trustedActivity;
      return firestoreActivity.isAfter(trustedActivity)
          ? firestoreActivity
          : trustedActivity;
    })();

    if (latestActivity == null) return false;
    return DateTime.now().difference(latestActivity) <= _otpBypassWindow;
  }

  Future<void> _navigateFromStartupAuthState() async {
    final trustedPhone = await TrustedDeviceService.instance.getTrustedPhone();

    String? startupPhone;
    bool allowDirectPin = false;

    if (trustedPhone != null && trustedPhone.isNotEmpty) {
      try {
        final status = await PhoneLookupService.instance.lookupAccountStatus(
          trustedPhone,
          useCache: false,
        );
        if (!status.isPendingAccount && !status.isBannedAccount) {
          dynamic firestoreLastLogin;
          var hasEligibleAccount = false;

          if (status.hasResponderAccount) {
            final responderDoc = await PhoneLookupService.instance
                .getFirstResponderDoc(trustedPhone);
            final responderData = responderDoc?.data();
            final hasPinCreated =
                responderData != null && responderData['hasPinCreated'] == true;
            if (hasPinCreated) {
              hasEligibleAccount = true;
              firestoreLastLogin =
                  responderData['lastLoginTimestamp'] ??
                  responderData['lastLoginAt'];
            }
          }

          if (!hasEligibleAccount && status.hasApprovedAccount) {
            final approvedDoc = await PhoneLookupService.instance
                .getFirstApprovedUserDoc(trustedPhone);
            if (approvedDoc != null) {
              hasEligibleAccount = true;
              firestoreLastLogin = approvedDoc.data()['lastLoginTimestamp'];
            }
          }

          if (hasEligibleAccount) {
            startupPhone = trustedPhone;
            allowDirectPin = await _canBypassOtpOnStartup(
              phone: trustedPhone,
              firestoreLastLogin: firestoreLastLogin,
            );
          }
        }
      } catch (e) {
        debugPrint('Startup phone status lookup failed: $e');
      }
    }

    if (!mounted) return;

    final args = <String, dynamic>{};
    if (startupPhone != null) {
      args['trustedPhone'] = startupPhone;
    }
    if (allowDirectPin) {
      args['directPin'] = true;
    }

    if (args.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginPage(),
        settings: RouteSettings(arguments: args),
      ),
    );
  }

  Future<void> _closeApplication() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _webExitRequested = true;
      });
      return;
    }

    try {
      await SystemNavigator.pop();
    } catch (e) {
      debugPrint('SystemNavigator.pop failed: $e');
    }

    // Fallback: retry once through platform channel for emulators/debug shells.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
    } catch (e) {
      debugPrint('Platform pop fallback failed: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await NotificationService().requestPermissions();
    } catch (e) {
      debugPrint('Notification permission request failed on loading: $e');
    }
  }

  Future<bool> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();

    // Already granted — proceed even if location services are currently off.
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return true;
    }

    // Permanently denied — must go to app settings; can't show native dialog.
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      if (!mounted) return false;
      permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        await _closeApplication();
        return false;
      }
      return true;
    }

    // First request — triggers the native OS dialog ("While Using the App",
    // "Only This Time", "Deny").
    permission = await Geolocator.requestPermission();
    if (!mounted) return false;

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return true;
    }

    // User denied on the native dialog — exit the app.
    await _closeApplication();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_webExitRequested) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8F3),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/logo/RES-Q_LOGO.svg',
                  height: 96,
                ),
                const SizedBox(height: 16),
                const Text(
                  'You can now close this browser tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.appBlack,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Browser security does not allow apps to force-close web tabs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 15,
                    color: AppTheme.appBlack,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F3),
      body: const Center(child: _LoadingContent()),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset('assets/icons/logo/RES-Q_LOGO.svg', height: 100),
        const SizedBox(height: 20),
        const Text(
          "EVERY SECOND COUNTS",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.3,
            color: Colors.black,
            fontFamily: 'RobotoCondensed',
          ),
        ),
        const SizedBox(height: 35),
        const SizedBox(
          height: 100,
          width: 100,
          child: CircularProgressIndicator(
            strokeWidth: 12,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC806)),
          ),
        ),
      ],
    );
  }
}
