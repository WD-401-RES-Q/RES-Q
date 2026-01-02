import 'package:flutter/material.dart';
import 'admin-map_page.dart';
import '../community_page.dart';
import '../notifications_page.dart';
import '../profile_page.dart';

class SemiAdminMainPage extends StatefulWidget {
  const SemiAdminMainPage({super.key});

  @override
  State<SemiAdminMainPage> createState() => _SemiAdminMainPageState();
}

class _SemiAdminMainPageState extends State<SemiAdminMainPage> {
  static const appOffWhite = Color(0xFFF7F8F3);

  int _currentIndex = 0;

  final List<Widget> _pages = [
    const AdminMapPage(),
    const CommunityPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
      bottomNavigationBar: Container(
        height: 70,
        decoration: const BoxDecoration(
          color: Color(0xFFAC1B22),
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
            selectedItemColor: const Color(0xFFFFC806),
            unselectedItemColor: Colors.white,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            items: [
              BottomNavigationBarItem(
                icon: Image.asset(
                  _currentIndex == 0
                      ? "assets/icons/NAV-MAPS-ICON-YELLOW.png"
                      : "assets/icons/NAV-MAPS-ICON-WHITE.png",
                  width: 40,
                  height: 40,
                ),
                label: "MAP",
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  _currentIndex == 1
                      ? "assets/icons/NAV-COMMUNITY-ICON-YELLOW.png"
                      : "assets/icons/NAV-COMMUNITY-ICON-WHITE.png",
                  width: 40,
                  height: 40,
                ),
                label: "COMMUNITY",
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  _currentIndex == 2
                      ? "assets/icons/NAV-NOTIFICATIONS-ICON-YELLOW.png"
                      : "assets/icons/NAV-NOTIFICATIONS-ICON-WHITE.png",
                  width: 40,
                  height: 40,
                ),
                label: "NOTIFICATION",
              ),
              BottomNavigationBarItem(
                icon: Image.asset(
                  _currentIndex == 3
                      ? "assets/icons/NAV-PROFILE-ICON-YELLOW.png"
                      : "assets/icons/NAV-PROFILE-ICON-WHITE.png",
                  width: 40,
                  height: 40,
                ),
                label: "PROFILE",
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(child: _pages[_currentIndex]),
    );
  }
}
