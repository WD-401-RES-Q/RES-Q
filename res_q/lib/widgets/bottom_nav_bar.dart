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
      height: 80,
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
          items: [
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 0
                    ? "assets/icons/HOME-ICON-YELLOW.png"
                    : "assets/icons/HOME-ICON.png",
                width: 48,
                height: 48,
              ),
              label: "HOME",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 1
                    ? "assets/icons/COMMUNITY-ICON-YELLOW.png"
                    : "assets/icons/COMMUNITY-ICON.png",
                width: 48,
                height: 48,
              ),
              label: "COMMUNITY",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 2
                    ? "assets/icons/MAPS-ICON-YELLOW.png"
                    : "assets/icons/MAPS-ICON.png",
                width: 48,
                height: 48,
              ),
              label: "MAP",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 3
                    ? "assets/icons/NOTICATIONS-ICON-YELLOW.png"
                    : "assets/icons/NOTICATIONS-ICON.png",
                width: 48,
                height: 48,
              ),
              label: "NOTIFICATION",
            ),
            BottomNavigationBarItem(
              icon: Image.asset(
                widget.currentIndex == 4
                    ? "assets/icons/PROFILE-ICON-YELLOW.png"
                    : "assets/icons/PROFILE-ICON.png",
                width: 48,
                height: 48,
              ),
              label: "PROFILE",
            ),
          ],
        ),
      ),
    );
  }
}
