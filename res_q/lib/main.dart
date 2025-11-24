import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/main_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Use Quicksand as the default font for body text
        textTheme: GoogleFonts.quicksandTextTheme().copyWith(
          // Use Poppins for headings (h1/h2/h3 equivalents)
          displayLarge: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 48.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          displayMedium: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 40.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          displaySmall: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 32.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          headlineMedium: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          headlineSmall: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          titleLarge: GoogleFonts.poppins(
            textStyle: const TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      home: MainPage(),
    );
  }
}
