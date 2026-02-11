import 'package:flutter/material.dart';
import 'semi_admin_map_page.dart';
import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../common/widgets/bottom_nav_bar.dart';

class SemiAdminMainPage extends StatelessWidget {
  const SemiAdminMainPage({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.pages = _defaultPages,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<Widget> pages;

  static const appOffWhite = Color(0xFFF7F8F3);
  static const _navIconSvgPath = "assets/icons/navbar";
  static const List<Widget> _defaultPages = [
    AdminMapPage(),
    CommunityPage(),
    NotificationsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final safeIndex = currentIndex.clamp(0, pages.length - 1);

    return Scaffold(
      backgroundColor: appOffWhite,
      bottomNavigationBar: BottomNavBar(
        currentIndex: safeIndex,
        onTap: onTap,
        itemConfigs: const [
          BottomNavItemConfig(
            label: "MAP",
            activeIconPath: "$_navIconSvgPath/NAV-MAPS-ICON-YELLOW.svg",
            inactiveIconPath: "$_navIconSvgPath/NAV-MAPS-ICON.svg",
          ),
          BottomNavItemConfig(
            label: "COMMUNITY",
            activeIconPath: "$_navIconSvgPath/NAV-COMMUNITY-ICON-YELLOW.svg",
            inactiveIconPath: "$_navIconSvgPath/NAV-COMMUNITY-ICON.svg",
          ),
          BottomNavItemConfig(
            label: "NOTIFICATION",
            activeIconPath:
                "$_navIconSvgPath/NAV-NOTIFICATIONS-ICON-YELLOW.svg",
            inactiveIconPath: "$_navIconSvgPath/NAV-NOTIFICATIONS-ICON.svg",
          ),
          BottomNavItemConfig(
            label: "PROFILE",
            activeIconPath: "$_navIconSvgPath/NAV-PROFILE-ICON-YELLOW.svg",
            inactiveIconPath: "$_navIconSvgPath/NAV-PROFILE-ICON.svg",
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: safeIndex, children: pages),
      ),
    );
  }
}

class SemiAdminMainScreen extends StatefulWidget {
  const SemiAdminMainScreen({super.key});

  @override
  State<SemiAdminMainScreen> createState() => _SemiAdminMainScreenState();
}

class _SemiAdminMainScreenState extends State<SemiAdminMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SemiAdminMainPage(
      currentIndex: _currentIndex,
      onTap: (index) {
        if (index == _currentIndex) return;
        setState(() => _currentIndex = index);
      },
    );
  }
}
