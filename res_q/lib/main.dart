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
import 'common/widgets/global_permission_gate.dart';
// auth pages
import 'features/auth/pages/login_page.dart';
import 'features/auth/pages/registration_page.dart';
import 'features/auth/pages/otp_page.dart';
import 'features/auth/pages/pin_creation_page.dart';
import 'features/auth/pages/forgot_pin_page.dart';
import 'features/auth/pages/change_phone_number_page.dart';
import 'features/auth/pages/login_verify_page.dart';
import 'features/auth/pages/login_register_page.dart';
import 'features/auth/pages/login_create_pin_page.dart';
import 'features/auth/pages/login_confirm_pin_page.dart';
import 'features/auth/pages/login_submitted_page.dart';
import 'features/auth/pages/login_pin_page.dart';
// services
import 'common/services/frame_timing_service.dart';
import 'common/services/notification_service.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const bool _showPerformanceOverlay = bool.fromEnvironment(
    'RESQ_SHOW_PERF_OVERLAY',
    defaultValue: false,
  );
  static final PerformanceRouteObserver _performanceRouteObserver =
      PerformanceRouteObserver();

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
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return GlobalPermissionGate(child: child);
      },
      home: const LoadingScreen(), // <-- SHOW LOADING SCREEN FIRST
      routes: {
        '/login': (context) => const LoginPage(),
        '/login/verify': (context) => const LoginVerifyPage(),
        '/login/register': (context) => const LoginRegisterPage(),
        '/login/create-pin': (context) => const LoginCreatePinPage(),
        '/login/confirm-pin': (context) => const LoginConfirmPinPage(),
        '/login/submitted': (context) => const LoginSubmittedPage(),
        '/login/pin': (context) => const LoginPinPage(),
        '/register': (context) => const RegistrationPage(),
        '/otp': (context) => const OTPPage(),
        '/pin-creation': (context) => const PINCreationPage(),
        '/forgot-pin': (context) => const ForgotPinPage(),
        '/change-phone-number': (context) => const ChangePhoneNumberPage(),
        // Backwards-compatible route alias
        '/approved-pin-creation': (context) => const ForgotPinPage(),
        '/main': (context) => const MainPage(),
      },
    );
  }
}
