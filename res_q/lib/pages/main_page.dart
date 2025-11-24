import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'community_page.dart';
import 'map_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  List<Widget> get _pages => [
    _homeContent(),
    const CommunityPage(),
    const MapPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  static Widget _homeContent() {
    // return the main column content (no SafeArea/padding here)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        SizedBox(
          height: 100,
          child: Image.asset(
            "assets/images/logo.png",
            fit: BoxFit.contain,
            // errorBuilder is not available here (static), UI will still work if asset missing
          ),
        ),

        const SizedBox(height: 20),

        // Heading uses theme when rendered inside the Scaffold
        Builder(
          builder: (context) => Text(
            "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),

        const SizedBox(height: 30),

        // Grid placeholder; will be replaced at runtime by the state's _incidentCard calls
        const Expanded(child: SizedBox.shrink()),

        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.blue,
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
            selectedItemColor: Colors.red,
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
          padding: const EdgeInsets.all(16),
          child: _buildCurrentPage(context),
        ),
      ),
    );
  }

  Widget _buildCurrentPage(BuildContext context) {
    if (_currentIndex == 0) {
      // Build the full home content (logo, heading, grid, button)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          SizedBox(
            height: 100,
            child: Image.asset(
              "assets/images/logo.png",
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.image_not_supported,
                size: 64,
                color: Colors.blue,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),

          const SizedBox(height: 30),

          // 4 Squares
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _incidentCard(
                  context,
                  "EARTHQUAKE",
                  "assets/images/earthquake.png",
                ),
                _incidentCard(context, "FLOOD", "assets/images/flood.png"),
                _incidentCard(context, "FIRE", "assets/images/fire.png"),
                _incidentCard(context, "OTHER", "assets/images/other.png"),
              ],
            ),
          ),

          // Emergency Button
          SizedBox(
            width: 350,
            height: 140,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {},
              child: const Text(
                "EMERGENCY CALL",
                style: TextStyle(
                  fontSize: 26,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
        ],
      );
    }

    return _pages[_currentIndex];
  }

  Widget _incidentCard(BuildContext context, String title, String imgPath) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // intentionally empty; navigation will be added later
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 60,
                child: Image.asset(
                  imgPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image, size: 48, color: Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
