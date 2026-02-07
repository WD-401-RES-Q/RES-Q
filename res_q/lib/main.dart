import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'features/home/pages/home_page.dart';
import 'features/loading/pages/loading_screen.dart';
// auth pages
import 'features/auth/pages/login_page.dart';
import 'features/auth/pages/registration_page.dart';
import 'features/auth/pages/otp_page.dart';
import 'features/auth/pages/pin_creation_page.dart';
import 'features/auth/pages/forgot_pin_page.dart';
// services
import 'common/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notification service for background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
        // Backwards-compatible route alias
        '/approved-pin-creation': (context) => const ForgotPinPage(),
        '/main': (context) => const MainPage(),
      },
    );
  }
}
