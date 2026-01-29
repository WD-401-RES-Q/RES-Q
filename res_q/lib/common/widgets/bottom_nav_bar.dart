import 'package:flutter/material.dart';
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
    this.iconWidth = 40,
    this.iconHeight = 40,
  });
}

class BottomNavBar extends StatefulWidget {
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
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  Widget build(BuildContext context) {
    final configs = widget.itemConfigs ?? _defaultItems;

    return Container(
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        color: AppColors.appBlue,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: ClipRect(
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.appYellow,
            unselectedItemColor: Colors.white,
            selectedFontSize: 8,
            unselectedFontSize: 8,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            currentIndex: widget.currentIndex,
            onTap: widget.onTap,
            items: List.generate(configs.length, (index) {
              final config = configs[index];
              final isActive = widget.currentIndex == index;
              return BottomNavigationBarItem(
                icon: Image.asset(
                  isActive ? config.activeIconPath : config.inactiveIconPath,
                  width: config.iconWidth,
                  height: config.iconHeight,
                ),
                label: config.label,
              );
            }),
          ),
        ),
      ),
    );
  }

  List<BottomNavItemConfig> get _defaultItems => const [
    BottomNavItemConfig(
      label: "HOME",
      activeIconPath: "assets/icons/HOME-ICON-YELLOW.png",
      inactiveIconPath: "assets/icons/HOME-ICON.png",
    ),
    BottomNavItemConfig(
      label: "COMMUNITY",
      activeIconPath: "assets/icons/COMMUNITY-ICON-YELLOW.png",
      inactiveIconPath: "assets/icons/COMMUNITY-ICON.png",
    ),
    BottomNavItemConfig(
      label: "MAP",
      activeIconPath: "assets/icons/MAPS-ICON-YELLOW.png",
      inactiveIconPath: "assets/icons/MAPS-ICON.png",
    ),
    BottomNavItemConfig(
      label: "NOTIFICATION",
      activeIconPath: "assets/icons/NOTICATIONS-ICON-YELLOW.png",
      inactiveIconPath: "assets/icons/NOTICATIONS-ICON.png",
    ),
    BottomNavItemConfig(
      label: "PROFILE",
      activeIconPath: "assets/icons/PROFILE-ICON-YELLOW.png",
      inactiveIconPath: "assets/icons/PROFILE-ICON.png",
    ),
  ];
}
