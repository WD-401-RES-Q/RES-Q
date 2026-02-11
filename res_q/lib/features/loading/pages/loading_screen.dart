import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  void _initializeApp() async {
    // Request location permission
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    });
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
