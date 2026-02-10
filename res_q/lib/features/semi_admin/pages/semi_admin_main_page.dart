import 'package:flutter/material.dart';
import 'semi_admin_map_page.dart';
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
  final Set<int> _loadedTabs = <int>{0};
  static const List<Widget> _pages = <Widget>[
    AdminMapPage(),
    CommunityPage(),
    NotificationsPage(),
    ProfilePage(),
  ];

  void _onTabSelected(int index) {
    if (_currentIndex == index && _loadedTabs.contains(index)) {
      return;
    }

    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  Widget _buildLazyTabBody() {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(_pages.length, (index) {
        if (!_loadedTabs.contains(index)) {
          return const SizedBox.shrink();
        }

        final isActive = index == _currentIndex;
        return Offstage(
          offstage: !isActive,
          child: TickerMode(enabled: isActive, child: _pages[index]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
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
      body: SafeArea(child: _buildLazyTabBody()),
    );
  }
}
