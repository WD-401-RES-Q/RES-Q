import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'common/navigation/app_page_transitions.dart';
import 'common/navigation/performance_route_observer.dart';
import 'features/home/pages/home_page.dart';
import 'features/loading/pages/loading_screen.dart';
// auth pages
import 'features/auth/pages/login_page.dart';
import 'features/auth/pages/registration_page.dart';
import 'features/auth/pages/otp_page.dart';
import 'features/auth/pages/pin_creation_page.dart';
import 'features/auth/pages/forgot_pin_page.dart';
import 'features/auth/pages/login_success_page.dart';
import 'features/auth/pages/account_submitted_page.dart';
// services
import 'common/services/frame_timing_service.dart';
import 'common/services/notification_service.dart';
import 'common/services/registration_prefs.dart';
import 'common/services/trusted_device_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notification service for background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (!kReleaseMode) {
    FrameTimingService.instance.start();
  }

  if (!kDebugMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
    runZonedGuarded(
      () => runApp(const MyApp()),
      (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {},
      ),
    );
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {

  static const bool _showPerformanceOverlay = bool.fromEnvironment(
    'RESQ_SHOW_PERF_OVERLAY',
    defaultValue: false,
  );
  static final PerformanceRouteObserver _performanceRouteObserver =
      PerformanceRouteObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(RegistrationPrefs.saveLastActivityNow());
      unawaited(TrustedDeviceService.instance.touchTrustedActivity());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: _showPerformanceOverlay && !kReleaseMode,
      checkerboardRasterCacheImages: _showPerformanceOverlay && !kReleaseMode,
      checkerboardOffscreenLayers: _showPerformanceOverlay && !kReleaseMode,
      navigatorObservers: !kReleaseMode
          ? <NavigatorObserver>[_performanceRouteObserver]
          : const <NavigatorObserver>[],
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: AppPageTransitionsBuilder(),
            TargetPlatform.iOS: AppPageTransitionsBuilder(),
            TargetPlatform.macOS: AppPageTransitionsBuilder(),
            TargetPlatform.windows: AppPageTransitionsBuilder(),
            TargetPlatform.linux: AppPageTransitionsBuilder(),
          },
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 48.0, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
          displaySmall: TextStyle(fontSize: 32.0, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
          ),
          headlineSmall: TextStyle(fontSize: 20.0, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600),
        ),
      ),
      home: const LoadingScreen(), // <-- SHOW LOADING SCREEN FIRST
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegistrationPage(),
        '/otp': (context) => const OTPPage(),
        '/pin-creation': (context) => const PINCreationPage(),
        '/forgot-pin': (context) => const ForgotPinPage(),
        '/login-success': (context) => const LoginSuccessPage(),
        '/account-submitted': (context) => const AccountSubmittedPage(),
        // Backwards-compatible route alias
        '/approved-pin-creation': (context) => const ForgotPinPage(),
        '/main': (context) => const MainPage(),
      },
    );
  }
}
