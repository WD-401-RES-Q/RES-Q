import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../../common/widgets/app_snackbar.dart';

import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../emergency/pages/emergency_call_screen.dart';
import '../../reports/pages/report_form_screen.dart';
import '../../map/pages/map_page.dart';
import '../../reports/pages/report_map_page.dart';
import '../../../common/services/user_session.dart';

class MainPage extends StatefulWidget {
  final int initialIndex;

  const MainPage({super.key, this.initialIndex = 0});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late int _currentIndex = widget.initialIndex;
  final Set<int> _loadedTabs = <int>{};
  final Map<int, Widget> _tabCache = <int, Widget>{};
  String? _cachedMapReportId;

  @override
  void initState() {
    super.initState();
    _loadedTabs.add(_currentIndex);
  }

  Widget _resolveMapPage() {
    final activeReport = UserSession.latestActiveReport;
    final currentReportId = activeReport?.reportId;

    if (_cachedMapReportId == currentReportId) {
      final cachedMapPage = _tabCache[2];
      if (cachedMapPage != null) {
        return cachedMapPage;
      }
    }

    final mapPage = activeReport != null
        ? ReportMapPage(
            key: ValueKey('report-map-${activeReport.reportId}'),
            reportId: activeReport.reportId,
            reportData: activeReport.reportData,
            showBottomNav: false,
          )
        : const MapPage();

    _cachedMapReportId = currentReportId;
    _tabCache[2] = mapPage;
    return mapPage;
  }

  Widget _pageForIndex(int index) {
    switch (index) {
      case 0:
        return _tabCache.putIfAbsent(0, () => const _HomePageContent());
      case 1:
        return _tabCache.putIfAbsent(1, () => const CommunityPage());
      case 2:
        return _resolveMapPage();
      case 3:
        return _tabCache.putIfAbsent(3, () => const NotificationsPage());
      case 4:
      default:
        return _tabCache.putIfAbsent(4, () => const ProfilePage());
    }
  }

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
      children: List.generate(5, (index) {
        if (!_loadedTabs.contains(index)) {
          return const SizedBox.shrink();
        }

        final isActive = index == _currentIndex;
        return Offstage(
          offstage: !isActive,
          child: TickerMode(enabled: isActive, child: _pageForIndex(index)),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8F3),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
      ),
      body: SafeArea(child: _buildLazyTabBody()),
    );
  }
}

class _HomePageContent extends StatefulWidget {
  const _HomePageContent();

  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<_HomePageContent>
    with TickerProviderStateMixin {
  late final AnimationController _borderController;
  late final AnimationController _holdController;
  bool _didPrecacheAssets = false;

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _holdController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (!mounted) return;
            _holdController.reset();
            _openEmergencyCall();
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheAssets) return;
    _didPrecacheAssets = true;
    _precacheHomeAssets();
  }

  @override
  void dispose() {
    _borderController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _openEmergencyCall() {
    debugPrint('Emergency call button pressed');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EmergencyCallScreen()),
    );
  }

  Future<void> _precacheHomeAssets() async {
    final futures = <Future<void>>[
      precacheImage(
        const AssetImage('assets/icons/FINAL-EARTHQUAKE-ICON.png'),
        context,
      ),
      precacheImage(
        const AssetImage('assets/icons/FINAL-FLOOD-ICON.png'),
        context,
      ),
      precacheImage(
        const AssetImage('assets/icons/FINAL-FIRE-ICON.png'),
        context,
      ),
      precacheImage(
        const AssetImage('assets/icons/FINAL-CRASH-ICON.png'),
        context,
      ),
      precacheImage(
        const AssetImage('assets/icons/FINAL-OTHERS-ICON.png'),
        context,
      ),
    ];

    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final emergencyButtonSize = (shortestSide * 0.24).clamp(80.0, 120.0);
    final emergencyIconSize = emergencyButtonSize * 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gridWidth = math.min(constraints.maxWidth, 380.0);
          final gridHeight = (constraints.maxHeight * 0.52)
              .clamp(250.0, 430.0)
              .toDouble();

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: SizedBox(
                      height: 36,
                      child: SvgPicture.asset(
                        "assets/icons/RES-Q_LOGO.svg",
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.image_not_supported,
                              size: 30,
                              color: Colors.blue,
                            ),
                      ),
                    ),
                  ),
                  const Text(
                    "SELECT THE TYPE OF INCIDENT\nYOU WANT TO REPORT.",
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'RobotoCondensed',
                    ),
                  ),
                  SizedBox(
                    width: gridWidth,
                    height: gridHeight,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8F3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const spacing = 12.0;
                          final maxCardWidth =
                              (constraints.maxWidth - spacing) / 2;
                          final maxCardHeightByWidth = maxCardWidth / 1.05;
                          final maxCardHeightByHeight =
                              (constraints.maxHeight - spacing * 2) / 3;
                          final cardHeight = math.min(
                            maxCardHeightByWidth,
                            maxCardHeightByHeight,
                          );
                          final cardWidth = cardHeight * 1.05;
                          final iconSize = (cardHeight * 0.55).clamp(
                            50.0,
                            90.0,
                          );
                          final labelFont = (cardHeight * 0.16).clamp(
                            11.0,
                            16.0,
                          );

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _incidentCard(
                                      context,
                                      "EARTHQUAKE",
                                      "assets/icons/FINAL-EARTHQUAKE-ICON.png",
                                      fontSize: labelFont,
                                      iconSize: iconSize,
                                    ),
                                  ),
                                  const SizedBox(width: spacing),
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _incidentCard(
                                      context,
                                      "FLOOD",
                                      "assets/icons/FINAL-FLOOD-ICON.png",
                                      fontSize: labelFont,
                                      iconSize: iconSize,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: spacing),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _incidentCard(
                                      context,
                                      "FIRE",
                                      "assets/icons/FINAL-FIRE-ICON.png",
                                      fontSize: labelFont,
                                      iconSize: iconSize,
                                    ),
                                  ),
                                  const SizedBox(width: spacing),
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _incidentCard(
                                      context,
                                      "ROAD CRASH",
                                      "assets/icons/FINAL-CRASH-ICON.png",
                                      fontSize: labelFont,
                                      iconSize: iconSize,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: spacing),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _incidentCard(
                                      context,
                                      "OTHERS",
                                      "assets/icons/FINAL-OTHERS-ICON.png",
                                      fontSize: labelFont,
                                      iconSize: iconSize,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  GestureDetector(
                    onLongPressStart: (_) {
                      if (_holdController.isAnimating) return;
                      _holdController.forward(from: 0);
                    },
                    onLongPressEnd: (_) {
                      if (_holdController.isAnimating ||
                          _holdController.value > 0) {
                        _holdController.stop();
                        _holdController.reset();
                      }
                    },
                    onLongPressCancel: () {
                      if (_holdController.isAnimating ||
                          _holdController.value > 0) {
                        _holdController.stop();
                        _holdController.reset();
                      }
                    },
                    onTap: () {
                      AppSnackBar.show(
                        context,
                        'Press and hold to place a call',
                        type: AppSnackBarType.info,
                      );
                    },
                    child: _buildAnimatedBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderWidth: 7,
                      isCircle: true,
                      child: SizedBox(
                        width: emergencyButtonSize,
                        height: emergencyButtonSize,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _holdController,
                            builder: (context, _) {
                              final progress = _holdController.value == 0
                                  ? 0.18
                                  : _holdController.value;
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: emergencyButtonSize * 0.7,
                                    height: emergencyButtonSize * 0.7,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: (emergencyButtonSize * 0.06)
                                          .clamp(4.0, 6.0),
                                      backgroundColor: Colors.white.withOpacity(
                                        0.15,
                                      ),
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFFFFC806),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.phone,
                                    size: emergencyIconSize,
                                    color: Colors.white,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Press and Hold to Call',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _incidentCard(
    BuildContext context,
    String title,
    String imgPath, {
    double fontSize = 13.5,
    double iconSize = 90,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          debugPrint('$title card tapped');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportFormScreen(incidentType: title),
            ),
          );
        },
        child: _buildStaticBorder(
          borderRadius: BorderRadius.circular(40),
          borderWidth: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Image.asset(
                imgPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 35,
                  );
                },
              ),
              const SizedBox(height: 6),

              // Label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'RobotoCondensed',
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBorder({
    required BorderRadius borderRadius,
    required double borderWidth,
    required Widget child,
    bool isCircle = false,
  }) {
    return AnimatedBuilder(
      animation: _borderController,
      builder: (context, _) {
        final angle = _borderController.value * 2 * math.pi;
        return Container(
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : borderRadius,
            gradient: SweepGradient(
              colors: const [
                Color(0xFFFFC806),
                Color(0xFFFFE27A),
                Color(0xFFFFC806),
              ],
              transform: GradientRotation(angle),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(borderWidth),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFAC1B22),
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle ? null : borderRadius,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildStaticBorder({
    required BorderRadius borderRadius,
    required double borderWidth,
    required Widget child,
    bool isCircle = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC806), Color(0xFFFFE27A), Color(0xFFFFC806)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(borderWidth),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFAC1B22),
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : borderRadius,
        ),
        child: child,
      ),
    );
  }
}
