import 'dart:async';

import 'package:flutter/material.dart';
import 'semi_admin_map_page.dart';
import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../../common/services/app_asset_precache_service.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/shell_navigation_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../../common/widgets/mandatory_permission_gate.dart';

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

    return MandatoryPermissionGate(
      child: Scaffold(
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
                    child: AnimatedOpacity(
                      opacity: isActive ? 1 : 0,
                      duration: _tabTransitionDuration,
                      curve: isActive
                          ? Curves.easeOutCubic
                          : Curves.easeInCubic,
                      child: TickerMode(enabled: isActive, child: pages[index]),
                    ),
                  ),
                ),
              );
            }),
          ),
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
  final Map<int, int> _tabReloadTokens = <int, int>{};
  String? _currentMapReportId;

  int _reloadTokenFor(int tabIndex) => _tabReloadTokens[tabIndex] ?? 0;

  void _markTabForReset(int tabIndex) {
    _tabReloadTokens[tabIndex] = _reloadTokenFor(tabIndex) + 1;
  }

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

  String? _resolveNotificationUserId() {
    try {
      final userId = UserSession.getUserId();
      if (userId.isNotEmpty) {
        return userId;
      }
    } catch (_) {
      // Fall back to session document id for semi-admin profiles
      // that do not yet have a normalized phone field.
    }

    final sessionData = UserSession.currentUserData;
    final fallbackId =
        (sessionData?['id'] ?? sessionData?['docId'])?.toString().trim() ?? '';
    return fallbackId.isEmpty ? null : fallbackId;
  }

  Future<void> _initializePostLoginServices() async {
    unawaited(AppAssetPrecacheService.warmUpPostLoginAssets(context));

    final userId = _resolveNotificationUserId();

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
    final reportId = command.reportId?.trim();
    setState(() {
      _markTabForReset(nextIndex);
      _currentIndex = nextIndex;
      _loadedTabs.add(nextIndex);
      if (reportId != null && reportId.isNotEmpty) {
        _currentMapReportId = reportId;
        _loadedTabs.add(0);
        _markTabForReset(0);
      } else if (nextIndex == 0) {
        _currentMapReportId = null;
      }
    });
  }

  List<Widget> _buildLazyPages() {
    return List<Widget>.generate(4, (index) {
      if (!_loadedTabs.contains(index)) {
        return const SizedBox.shrink();
      }
      final reloadToken = _reloadTokenFor(index);

      switch (index) {
        case 0:
          final reportToken =
              (_currentMapReportId == null || _currentMapReportId!.isEmpty)
              ? 'none'
              : _currentMapReportId!;
          return KeyedSubtree(
            key: ValueKey('semi-map-tab-$reportToken-$reloadToken'),
            child: AdminMapPage(
              initialReportId: reportToken == 'none' ? null : reportToken,
            ),
          );
        case 1:
          return KeyedSubtree(
            key: ValueKey('semi-community-tab-$reloadToken'),
            child: const CommunityPage(),
          );
        case 2:
          return KeyedSubtree(
            key: ValueKey('semi-notifications-tab-$reloadToken'),
            child: const NotificationsPage(),
          );
        case 3:
          return KeyedSubtree(
            key: ValueKey('semi-profile-tab-$reloadToken'),
            child: const ProfilePage(),
          );
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
        setState(() {
          if (index == 0) {
            _currentMapReportId = null;
          }
          _markTabForReset(index);
          _currentIndex = index;
          _loadedTabs.add(index);
        });
      },
    );
  }
}
