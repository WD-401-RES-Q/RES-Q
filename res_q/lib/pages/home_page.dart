import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/bottom_nav_bar.dart';

import 'community_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'emergency_call_screen.dart';
import 'report_form_screen.dart';
import 'semi-admin/admin-map_page.dart';

class MainPage extends StatefulWidget {
  final int initialIndex;

  const MainPage({super.key, this.initialIndex = 0});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late int _currentIndex = widget.initialIndex;

  List<Widget> get _pages => [
    const _HomePageContent(),
    const CommunityPage(),
    //const MapPage(),
    const AdminMapPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8F3),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
      body: SafeArea(child: _pages[_currentIndex]),
    );
  }
}

class _HomePageContent extends StatelessWidget {
  const _HomePageContent();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = (screenWidth - 32).clamp(300.0, 380.0);
    final cardAspectRatio = 1.0; // Square cards

    return Column(
      children: [
        // Logo at the very top
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 0),
          child: SizedBox(
            height: 40,
            child: SvgPicture.asset(
              "assets/icons/RESQ-LOGO.svg",
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.image_not_supported,
                size: 30,
                color: Colors.blue,
              ),
            ),
          ),
        ),

        // Everything else centered
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Instruction Text
                  Text(
                    "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Incident Cards Grid
                  Container(
                    width: gridWidth,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: cardAspectRatio,
                      children: [
                        _incidentCard(
                          context,
                          "EARTHQUAKE",
                          "assets/icons/FINAL-EARTHQUAKE-ICON.png",
                        ),
                        _incidentCard(
                          context,
                          "FLOOD",
                          "assets/icons/FINAL-FLOOD-ICON.png",
                        ),
                        _incidentCard(
                          context,
                          "FIRE",
                          "assets/icons/FINAL-FIRE-ICON.png",
                        ),
                        _incidentCard(
                          context,
                          "VEHICULAR",
                          "assets/icons/FINAL-CRASH-ICON.png",
                        ),
                        _incidentCard(
                          context,
                          "ROAD OBSTRUCTION",
                          "assets/icons/FINAL-ROAD-ICON.png",
                        ),
                        _incidentCard(
                          context,
                          "OTHERS",
                          "assets/icons/FINAL-OTHERS-ICON.png",
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Emergency Call Button
                  SizedBox(
                    width: (screenWidth * 0.75).clamp(260.0, 320.0),
                    height: 100,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFAC1B22),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        print("Emergency call button pressed");
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EmergencyCallScreen(),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "EMERGENCY CALL",
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Image.asset(
                            'assets/icons/PHONE-ICON.png',
                            height: 60,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.phone,
                                  color: Colors.white,
                                  size: 60,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _incidentCard(BuildContext context, String title, String imgPath) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          print("$title card tapped");
          // Navigate to report form screen with incident type
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportFormScreen(incidentType: title),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFAC1B22),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Image.asset(
                imgPath,
                width: 100,
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 40,
                  );
                },
              ),
              const SizedBox(height: 8),

              // Label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
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
