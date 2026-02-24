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
      final hasLocation = await _ensureLocationPermissionWithModal();
      if (!mounted || !hasLocation) return;
      await _navigateFromStartupAuthState();
    } finally {
      _isInitializing = false;
    }
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
        final isApprovedAccount =
            status.hasApprovedAccount &&
            !status.isPendingAccount &&
            !status.isBannedAccount;

        if (isApprovedAccount) {
          startupPhone = trustedPhone;
          allowDirectPin = true;
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

  Future<bool> _ensureLocationPermissionWithModal() async {
    while (mounted) {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      final hasPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (servicesEnabled && hasPermission) {
        return true;
      }

      if (!mounted) return false;
      final action = await showDialog<_LocationModalAction>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.56),
        builder: (context) => _LocationPermissionDialog(
          servicesEnabled: servicesEnabled,
          permission: permission,
        ),
      );

      if (!mounted) return false;

      if (action == _LocationModalAction.exitApp) {
        await _closeApplication();
        return false;
      }

      if (servicesEnabled && permission != LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      } else {
        // "Open Settings" should always route to app settings/permissions.
        await Geolocator.openAppSettings();
      }
    }

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

enum _LocationModalAction { enable, exitApp }

class _LocationPermissionDialog extends StatelessWidget {
  const _LocationPermissionDialog({
    required this.servicesEnabled,
    required this.permission,
  });

  final bool servicesEnabled;
  final LocationPermission permission;

  @override
  Widget build(BuildContext context) {
    final exitLabel = kIsWeb ? 'CLOSE TAB' : 'EXIT';
    final actionLabel =
        servicesEnabled && permission != LocationPermission.deniedForever
        ? 'ALLOW LOCATION'
        : 'OPEN SETTINGS';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.appOffWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.appOffYellow.withValues(alpha: 0.42),
            width: 1.4,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4A000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.appRed.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.appOffYellow.withValues(alpha: 0.8),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppTheme.appRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Location Permission Required',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.appBlack,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'RES-Q needs your location to submit reports and pin incidents accurately for responders.',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.appBlack,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_LocationModalAction.exitApp),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.appRed,
                        side: BorderSide(
                          color: AppTheme.appRed.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        exitLabel,
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_LocationModalAction.enable),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.appRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        actionLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
