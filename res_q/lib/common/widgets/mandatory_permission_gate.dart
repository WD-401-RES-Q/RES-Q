import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';

class MandatoryPermissionGate extends StatefulWidget {
  const MandatoryPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<MandatoryPermissionGate> createState() =>
      _MandatoryPermissionGateState();
}

class _MandatoryPermissionGateState extends State<MandatoryPermissionGate>
    with WidgetsBindingObserver {
  StreamSubscription<ServiceStatus>? _locationServiceSubscription;
  bool _isCheckingRequirement = false;
  bool _isDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      try {
        _locationServiceSubscription = Geolocator.getServiceStatusStream()
            .listen(
              (status) {
                if (status == ServiceStatus.disabled) {
                  unawaited(_ensureLocationRequirement());
                }
              },
              onError: (Object error) {
                debugPrint('Location status stream unavailable: $error');
              },
            );
      } catch (error) {
        debugPrint('Location status stream unsupported: $error');
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ensureLocationRequirement());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationServiceSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureLocationRequirement());
    }
  }

  Future<void> _ensureLocationRequirement() async {
    if (_isCheckingRequirement || !mounted) return;
    _isCheckingRequirement = true;
    try {
      final requiresPrompt = await _isLocationRequirementMissing();
      if (!requiresPrompt) return;
      await _showLocationRecoveryDialogLoop();
    } finally {
      _isCheckingRequirement = false;
    }
  }

  Future<bool> _isLocationRequirementMissing() async {
    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final locationPermission = await Geolocator.checkPermission();
    final locationGranted =
        locationPermission == LocationPermission.whileInUse ||
        locationPermission == LocationPermission.always;

    return !locationServiceEnabled || !locationGranted;
  }

  Future<void> _showLocationRecoveryDialogLoop() async {
    if (_isDialogVisible || !mounted) return;

    _isDialogVisible = true;
    try {
      while (mounted) {
        final servicesEnabled = await Geolocator.isLocationServiceEnabled();
        final permission = await Geolocator.checkPermission();
        final hasPermission =
            permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always;

        if (servicesEnabled && hasPermission) {
          break;
        }

        if (!mounted) break;
        final action = await showDialog<_LocationRecoveryAction>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          barrierColor: Colors.black.withValues(alpha: 0.56),
          builder: (context) => _LocationRecoveryDialog(
            servicesEnabled: servicesEnabled,
            permission: permission,
          ),
        );

        if (!mounted) break;
        if (action != _LocationRecoveryAction.enable) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }

        if (servicesEnabled && permission != LocationPermission.deniedForever) {
          await Geolocator.requestPermission();
        } else {
          // "Open Settings" should always route to app settings/permissions.
          if (kIsWeb) {
            await Geolocator.requestPermission();
          } else {
            await Geolocator.openAppSettings();
          }
        }
      }
    } finally {
      _isDialogVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _LocationRecoveryAction { enable }

class _LocationRecoveryDialog extends StatelessWidget {
  const _LocationRecoveryDialog({
    required this.servicesEnabled,
    required this.permission,
  });

  final bool servicesEnabled;
  final LocationPermission permission;

  @override
  Widget build(BuildContext context) {
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
                      'Location Turned Off',
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
                'RES-Q requires location to stay enabled while you are using the app.',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.appBlack,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_LocationRecoveryAction.enable),
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
}
