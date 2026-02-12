import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

class BottomNavItemConfig {
  final String label;
  final String activeIconPath;
  final String inactiveIconPath;
  final double iconWidth;
  final double iconHeight;

  const BottomNavItemConfig({
    required this.label,
    required this.activeIconPath,
    required this.inactiveIconPath,
    this.iconWidth = 28,
    this.iconHeight = 28,
  });
}

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavItemConfig>? itemConfigs;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.itemConfigs,
  });

  @override
  Widget build(BuildContext context) {
    final configs = itemConfigs ?? _defaultItems;

    return ColoredBox(
      color: AppColors.appRed,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: SizedBox(
            height: 54,
            child: BottomNavigationBar(
              backgroundColor: AppColors.appRed,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.appYellow,
              unselectedItemColor: Colors.white,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              selectedFontSize: 7,
              unselectedFontSize: 7,
              selectedLabelStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
              iconSize: 25,
              currentIndex: currentIndex,
              enableFeedback: false,
              onTap: onTap,
              items: List.generate(configs.length, (index) {
                final config = configs[index];
                return BottomNavigationBarItem(
                  icon: _buildNavIcon(
                    config.inactiveIconPath,
                    config.iconWidth,
                    config.iconHeight,
                  ),
                  activeIcon: _buildNavIcon(
                    config.activeIconPath,
                    config.iconWidth,
                    config.iconHeight,
                  ),
                  label: config.label,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon(String assetPath, double width, double height) {
    if (assetPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
      );
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }

  static const String _navIconSvgPath = "assets/icons/navbar";

  List<BottomNavItemConfig> get _defaultItems => const [
    BottomNavItemConfig(
      label: "HOME",
      activeIconPath: "$_navIconSvgPath/NAV-HOME-ICON-YELLOW.svg",
      inactiveIconPath: "$_navIconSvgPath/NAV-HOME-ICON.svg",
    ),
    BottomNavItemConfig(
      label: "COMMUNITY",
      activeIconPath: "$_navIconSvgPath/NAV-COMMUNITY-ICON-YELLOW.svg",
      inactiveIconPath: "$_navIconSvgPath/NAV-COMMUNITY-ICON.svg",
    ),
    BottomNavItemConfig(
      label: "MAP",
      activeIconPath: "$_navIconSvgPath/NAV-MAPS-ICON-YELLOW.svg",
      inactiveIconPath: "$_navIconSvgPath/NAV-MAPS-ICON.svg",
    ),
    BottomNavItemConfig(
      label: "NOTIFICATION",
      activeIconPath: "$_navIconSvgPath/NAV-NOTIFICATIONS-ICON-YELLOW.svg",
      inactiveIconPath: "$_navIconSvgPath/NAV-NOTIFICATIONS-ICON.svg",
    ),
    BottomNavItemConfig(
      label: "PROFILE",
      activeIconPath: "$_navIconSvgPath/NAV-PROFILE-ICON-YELLOW.svg",
      inactiveIconPath: "$_navIconSvgPath/NAV-PROFILE-ICON.svg",
    ),
  ];
}
