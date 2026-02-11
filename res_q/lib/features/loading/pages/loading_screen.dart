import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import '../../auth/pages/login_page.dart';
import '../../../common/services/location_service.dart';
import '../../../common/services/notification_service.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _promptEnableLocationServiceIfNeeded();
    await LocationService.requestLocationPermission();

    // Initialize notifications (permission + FCM handlers).
    try {
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }

    // Wait 3 seconds then navigate
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      final shouldOpenSettings = await _showEnableLocationDialog();
      if (!shouldOpenSettings) {
        return;
      }

      await Geolocator.openLocationSettings();
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<bool> _showEnableLocationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Location Required',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: const Text(
          'Location is currently turned off. Please turn on location services so RES-Q can verify reports accurately.',
          style: TextStyle(
            fontFamily: 'RobotoCondensed',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8F3),
      body: Center(child: _LoadingContent()),
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
