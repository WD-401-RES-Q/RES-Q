import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class GlobalPermissionGate extends StatefulWidget {
  const GlobalPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalPermissionGate> createState() => _GlobalPermissionGateState();
}

class _GlobalPermissionGateState extends State<GlobalPermissionGate>
    with WidgetsBindingObserver {
  bool _notificationPromptRequested = false;
  bool _isCheckingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runStartupPermissionChecks());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureLocationEnabledGlobally());
    }
  }

  Future<void> _runStartupPermissionChecks() async {
    await _requestNotificationPermissionOnce();
    await _ensureLocationEnabledGlobally();
  }

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notificationPromptRequested) return;
    _notificationPromptRequested = true;
    try {
      await NotificationService().requestPermissions();
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  Future<void> _ensureLocationEnabledGlobally() async {
    if (_isCheckingLocation || !mounted) return;
    _isCheckingLocation = true;

    try {
      while (mounted) {
        final servicesEnabled = await Geolocator.isLocationServiceEnabled();
        final permission = await Geolocator.checkPermission();
        final hasPermission =
            permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;

        if (servicesEnabled && hasPermission) {
          return;
        }

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.56),
          useRootNavigator: true,
          builder: (dialogContext) {
            return _GlobalLocationPermissionDialog(
              servicesEnabled: servicesEnabled,
              permission: permission,
              onContinue: () {
                Navigator.of(dialogContext).pop();
              },
            );
          },
        );

        if (!mounted) return;
        await _routeToLocationAction(
          servicesEnabled: servicesEnabled,
          permission: permission,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _isCheckingLocation = false;
    }
  }

  Future<void> _routeToLocationAction({
    required bool servicesEnabled,
    required LocationPermission permission,
  }) async {
    if (!servicesEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
      return;
    }

    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _GlobalLocationPermissionDialog extends StatelessWidget {
  const _GlobalLocationPermissionDialog({
    required this.servicesEnabled,
    required this.permission,
    required this.onContinue,
  });

  final bool servicesEnabled;
  final LocationPermission permission;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final actionLabel = _resolveActionLabel();
    final helperText = _resolveHelperText();

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
                      'Location Required',
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
                'RES-Q needs device location access before you can continue using the app.',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.appBlack,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                helperText,
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 14,
                  color: AppTheme.appBlack,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
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
                    style: const TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveActionLabel() {
    if (!servicesEnabled) {
      return 'OPEN LOCATION SETTINGS';
    }
    if (permission == LocationPermission.denied) {
      return 'ALLOW LOCATION';
    }
    return 'OPEN APP SETTINGS';
  }

  String _resolveHelperText() {
    if (!servicesEnabled) {
      return 'Turn on Location services on your device to proceed.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location permission is blocked. Enable it in device app settings to continue.';
    }
    return 'Grant location permission to continue.';
  }
}
