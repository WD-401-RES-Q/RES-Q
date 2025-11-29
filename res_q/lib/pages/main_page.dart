import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'community_page.dart';
import 'map_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'emergency_call_screen.dart'; 


class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  List<Widget> get _pages => [
    const _HomePageContent(),
    const CommunityPage(),
    const MapPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
        color: Color(0xFF004FC6), // Changed to match the cards
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Color(0xFFD60000),
            unselectedItemColor: Colors.white,
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: "HOME"),
              BottomNavigationBarItem(
                icon: Icon(Icons.add_box),
                label: "COMMUNITY",
              ),
              BottomNavigationBarItem(icon: Icon(Icons.map), label: "MAP"),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications),
                label: "NOTIFICATION",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: "PROFILE",
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _pages[_currentIndex],
        ),
      ),
    );
  }
}

class _HomePageContent extends StatelessWidget {
  const _HomePageContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        SizedBox(
          height: 20,
          child: SvgPicture.asset(
            "assets/icons/RESQ-LOGO.svg",
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.image_not_supported,
              size: 64,
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 14,
              ),
        ),
        const SizedBox(height: 4),
        // Container wrapping all cards
        Container(
          width: 320,
          height: 360,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: GridView.count(
            crossAxisCount: 2, // 2 columns
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35, // Make cards taller to fit the container
            children: [
              _incidentCard(context, "EARTHQUAKE", "assets/icons/EARTHQUAKE-ICON.png"),
              _incidentCard(context, "FLOOD", "assets/icons/FLOOD-ICON.png"),
              _incidentCard(context, "FIRE", "assets/icons/FIRE-ICON.png"),
              _incidentCard(context, "MEDICAL", "assets/icons/AMBULANCE-ICON.png"), 
              _incidentCard(context, "VEHICULAR", "assets/icons/CRASH-ICON.png"), 
              _incidentCard(context, "ROAD OBSTRUCTION", "assets/icons/ROAD-ICON.png"),
            ],
          ),
        ),

        // const Spacer(), // This was preventing the container from expanding vertically

        // Emergency Button
        SizedBox(
          width: 240,
          height: 67,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD60000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              print("Emergency call button pressed");
              Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EmergencyCallScreen()),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "EMERGENCY CALL",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Image.asset(
                  'assets/icons/PHONE-ICON.png', // NOTE: Update with your icon pat
                  height: 40,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
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
        },
        child: Container(
          decoration: BoxDecoration(
            color: Color(0xFF004FC6), // Same blue as navbar
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
              // Icon without circular background
              Image.asset(
                imgPath,
                width: 70, // Increased icon size
                height: 70, // Increased icon size
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 32,
                  );
                },
              ),
              const SizedBox(height: 4),

              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}