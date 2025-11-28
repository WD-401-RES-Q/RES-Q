import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        SizedBox(
          height: 50,
          child: SvgPicture.asset(
            "assets/icons/RESQ-LOGO.svg",
            fit: BoxFit.contain,
            placeholderBuilder: (context) => const Icon(
              Icons.image,
              size: 64,
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Builder(
          builder: (context) => Text(
            "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 30),
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
          child: _buildCurrentPage(context),
        ),
      ),
    );
  }

  Widget _buildCurrentPage(BuildContext context) {
    if (_currentIndex == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          SizedBox(
            height: 25,
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

          const SizedBox(height: 8),

          Text(
            "SELECT THE TYPE OF INCIDENT YOU WANT TO REPORT",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 8),

          // Container wrapping all 4 cards
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 2,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              childAspectRatio: 1.5, // Make cards wider/flatter
              children: [
                _incidentCard(context, "EARTHQUAKE", "assets/images/earthquake.png"),
                _incidentCard(context, "FLOOD", "assets/images/flood.png"),
                _incidentCard(context, "FIRE", "assets/images/fire.png"),
                _incidentCard(context, "OTHER", "assets/images/other.png"),
              ],
            ),
          ),

          const SizedBox(height: 15),
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
              // Circular background with icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    imgPath,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 24,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),

              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 10,
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