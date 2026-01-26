import 'package:flutter/material.dart';
import 'admin-map_page.dart';
import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../common/widgets/bottom_nav_bar.dart';

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
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        itemConfigs: const [
          BottomNavItemConfig(
            label: "MAP",
            activeIconPath: "assets/icons/MAPS-ICON-YELLOW.png",
            inactiveIconPath: "assets/icons/MAPS-ICON.png",
            iconWidth: 40,
            iconHeight: 40,
          ),
          BottomNavItemConfig(
            label: "COMMUNITY",
            activeIconPath: "assets/icons/COMMUNITY-ICON-YELLOW.png",
            inactiveIconPath: "assets/icons/COMMUNITY-ICON.png",
            iconWidth: 40,
            iconHeight: 40,
          ),
          BottomNavItemConfig(
            label: "NOTIFICATION",
            activeIconPath: "assets/icons/NOTICATIONS-ICON-YELLOW.png",
            inactiveIconPath: "assets/icons/NOTICATIONS-ICON.png",
            iconWidth: 40,
            iconHeight: 40,
          ),
          BottomNavItemConfig(
            label: "PROFILE",
            activeIconPath: "assets/icons/PROFILE-ICON-YELLOW.png",
            inactiveIconPath: "assets/icons/PROFILE-ICON.png",
            iconWidth: 40,
            iconHeight: 40,
          ),
        ],
      ),
      body: SafeArea(child: _pages[_currentIndex]),
    );
  }
}
