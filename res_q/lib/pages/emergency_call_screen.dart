import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'main_page.dart';  


class EmergencyCallScreen extends StatelessWidget {
  const EmergencyCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Top icon - same size as main_page.dart
              SvgPicture.asset(
                'assets/icons/RESQ-LOGO.svg', // Replace with your logo path
                height: 30, // Adjust this to match your main_page icon size
              ),
              const SizedBox(height: 40),
              
              // Big PNG at the center
              Expanded(
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/CALLING-ICON.svg', // Replace with your PNG path
                    width: 300,
                    height: 300,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              
              // Text below the image
              const Text(
                'STAY CALM.\nCURRENTLY CONTACTING ACDRRMO...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.4,
                ),
              ),
              
              const SizedBox(height: 25),
              
              // End Call button
             SizedBox(
              width: 250,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => MainPage()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'END CALL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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