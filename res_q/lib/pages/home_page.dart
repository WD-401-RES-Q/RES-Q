import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../ui/widgets/bottom_nav_bar.dart';

import 'community_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'emergency_call_screen.dart';
import 'report_form_screen.dart';
import 'map_page.dart';
import 'report_map_page.dart';
import '../services/user_session.dart';

class MainPage extends StatefulWidget {
  final int initialIndex;

  const MainPage({super.key, this.initialIndex = 0});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late int _currentIndex = widget.initialIndex;

  @override
  void initState() {
    super.initState();
  }

  Widget _buildMapPage() {
    final activeReport = UserSession.latestActiveReport;

    if (activeReport != null) {
      return ReportMapPage(
        key: ValueKey('report-map-${activeReport.reportId}'),
        reportId: activeReport.reportId,
        reportData: activeReport.reportData,
        showBottomNav: false,
      );
    }

    return const MapPage();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _HomePageContent(),
      const CommunityPage(),
      _buildMapPage(),
      const NotificationsPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      backgroundColor: Color(0xFFF7F8F3),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: pages),
      ),
    );
  }
}

class _HomePageContent extends StatefulWidget {
  const _HomePageContent();

  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<_HomePageContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderController;

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = (screenWidth - 32).clamp(300.0, 380.0);

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
                    "SELECT THE TYPE OF INCIDENT\nYOU WANT TO REPORT",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'RobotoCondensed',
                    ),
                  ),

                  const SizedBox(height: 9),

                  // Incident Cards Grid
                  Container(
                    width: gridWidth,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8F3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = (constraints.maxWidth - 16) / 2;
                        final itemHeight = itemWidth / 1.05;
                        return Column(
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: itemWidth,
                                  height: itemHeight,
                                  child: _incidentCard(
                                    context,
                                    "EARTHQUAKE",
                                    "assets/icons/FINAL-EARTHQUAKE-ICON.png",
                                    fontSize: 19.0,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: itemWidth,
                                  height: itemHeight,
                                  child: _incidentCard(
                                    context,
                                    "FLOOD",
                                    "assets/icons/FINAL-FLOOD-ICON.png",
                                    fontSize: 22.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                SizedBox(
                                  width: itemWidth,
                                  height: itemHeight,
                                  child: _incidentCard(
                                    context,
                                    "FIRE",
                                    "assets/icons/FINAL-FIRE-ICON.png",
                                    fontSize: 22.0,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: itemWidth,
                                  height: itemHeight,
                                  child: _incidentCard(
                                    context,
                                    "VEHICULAR",
                                    "assets/icons/FINAL-CRASH-ICON.png",
                                    fontSize: 20.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: itemWidth,
                                  height: itemHeight,
                                  child: _incidentCard(
                                    context,
                                    "OTHERS",
                                    "assets/icons/FINAL-OTHERS-ICON.png",
                                    fontSize: 20.0,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 0.5),

                  // Circular Emergency Call Button
                  GestureDetector(
                    onTap: () {
                      print("Emergency call button pressed");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EmergencyCallScreen(),
                        ),
                      );
                    },
                    child: _buildAnimatedBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderWidth: 9,
                      isCircle: true,
                      child: const SizedBox(
                        width: 130,
                        height: 130,
                        child: Center(
                          child: Icon(
                            Icons.phone,
                            size: 70,
                            color: Colors.white,
                          ),
                        ),
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

  Widget _incidentCard(
    BuildContext context,
    String title,
    String imgPath, {
    double fontSize = 13.5,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          print("$title card tapped");
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportFormScreen(incidentType: title),
            ),
          );
        },
        child: _buildAnimatedBorder(
          borderRadius: BorderRadius.circular(40),
          borderWidth: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Image.asset(
                imgPath,
                width: 110,
                height: 110,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 35,
                  );
                },
              ),
              const SizedBox(height: 6),

              // Label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'RobotoCondensed',
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

  Widget _buildAnimatedBorder({
    required BorderRadius borderRadius,
    required double borderWidth,
    required Widget child,
    bool isCircle = false,
  }) {
    return AnimatedBuilder(
      animation: _borderController,
      builder: (context, _) {
        final angle = _borderController.value * 2 * math.pi;
        return Container(
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : borderRadius,
            gradient: SweepGradient(
              colors: const [
                Color(0xFFFFC806),
                Color(0xFFFFE27A),
                Color(0xFFFFC806),
              ],
              transform: GradientRotation(angle),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(borderWidth),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFAC1B22),
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle ? null : borderRadius,
            ),
            child: child,
          ),
        );
      },
    );
  }

}
