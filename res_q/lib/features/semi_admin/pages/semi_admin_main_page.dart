import 'dart:async';

import 'package:flutter/material.dart';
import 'semi_admin_map_page.dart';
import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/shell_navigation_service.dart';
import '../../../common/services/user_session.dart';
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
  static const Duration _tabTransitionDuration = Duration(milliseconds: 220);

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
        child: Stack(
          fit: StackFit.expand,
          children: List<Widget>.generate(pages.length, (index) {
            final isActive = index == safeIndex;
            return Positioned.fill(
              child: ExcludeSemantics(
                excluding: !isActive,
                child: IgnorePointer(
                  ignoring: !isActive,
                  child: TickerMode(
                    enabled: isActive,
                    child: AnimatedOpacity(
                      opacity: isActive ? 1 : 0,
                      duration: _tabTransitionDuration,
                      curve: isActive
                          ? Curves.easeOutCubic
                          : Curves.easeInCubic,
                      child: pages[index],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
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
  final Set<int> _loadedTabs = {0};

  @override
  void initState() {
    super.initState();
    SemiAdminShellNavigationService.commands.addListener(
      _handleShellNavigation,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializePostLoginServices());
    });
  }

  @override
  void dispose() {
    SemiAdminShellNavigationService.commands.removeListener(
      _handleShellNavigation,
    );
    super.dispose();
  }

  Future<void> _initializePostLoginServices() async {
    String? userId;
    try {
      userId = UserSession.getUserId();
    } catch (_) {
      userId = null;
    }

    if (userId == null || userId.isEmpty) {
      debugPrint('Skipping notification init: missing post-login user ID');
      return;
    }

    try {
      await NotificationService().initialize(userId: userId);
    } catch (e) {
      debugPrint('Notification init failed post-login: $e');
    }
  }

  void _handleShellNavigation() {
    final command = SemiAdminShellNavigationService.commands.value;
    if (command == null || !mounted) return;
    final nextIndex = command.tabIndex.clamp(0, 3);
    setState(() {
      _currentIndex = nextIndex;
      _loadedTabs.add(nextIndex);
    });
  }

  List<Widget> _buildLazyPages() {
    return List<Widget>.generate(4, (index) {
      if (!_loadedTabs.contains(index)) {
        return const SizedBox.shrink();
      }

      switch (index) {
        case 0:
          return const AdminMapPage();
        case 1:
          return const CommunityPage();
        case 2:
          return const NotificationsPage();
        case 3:
          return const ProfilePage();
        default:
          return const SizedBox.shrink();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SemiAdminMainPage(
      currentIndex: _currentIndex,
      pages: _buildLazyPages(),
      onTap: (index) {
        if (index == _currentIndex) return;
        setState(() {
          _currentIndex = index;
          _loadedTabs.add(index);
        });
      },
    );
  }
}
