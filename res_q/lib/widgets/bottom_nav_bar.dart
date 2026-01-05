import 'package:flutter/material.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
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
          currentIndex: widget.currentIndex,
          onTap: widget.onTap,
          items: [
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 0
                    ? "assets/icons/NAV-HOMEPAGE-ICON-YELLOW.png"
                    : "assets/icons/NAV-HOMEPAGE-ICON-WHITE.png",
                width: 40,
                height: 40,
              ),
              label: "HOME",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 1
                    ? "assets/icons/NAV-COMMUNITY-ICON-YELLOW.png"
                    : "assets/icons/NAV-COMMUNITY-ICON-WHITE.png",
                width: 40,
                height: 40,
              ),
              label: "COMMUNITY",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 2
                    ? "assets/icons/NAV-MAPS-ICON-YELLOW.png"
                    : "assets/icons/NAV-MAPS-ICON-WHITE.png",
                width: 40,
                height: 40,
              ),
              label: "MAP",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 3
                    ? "assets/icons/NAV-NOTIFICATIONS-ICON-YELLOW.png"
                    : "assets/icons/NAV-NOTIFICATIONS-ICON-WHITE.png",
                width: 40,
                height: 40,
              ),
              label: "NOTIFICATION",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 4
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
    );
  }
}
