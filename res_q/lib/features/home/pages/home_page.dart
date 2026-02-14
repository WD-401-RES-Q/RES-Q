import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';

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
  final String? initialCommunityReportId;

  const MainPage({
    super.key,
    this.initialIndex = 0,
    this.initialCommunityReportId,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late int _currentIndex = widget.initialIndex;

  @override
  void initState() {
    super.initState();
  }

  Widget _buildMapPage() {
    final activeReport = UserSession.latestActiveReport;

    if (activeReport != null) {
      return ReportMapPage(
        key: ValueKey('report-map-${activeReport.reportId}'),
        reportId: activeReport.reportId,
        reportData: activeReport.reportData,
        showBottomNav: false,
      );
    }

    return const MapPage();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _HomePageContent(),
      CommunityPage(initialReportId: widget.initialCommunityReportId),
      _buildMapPage(),
      const NotificationsPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      backgroundColor: Color(0xFFF7F8F3),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _currentIndex, children: pages),
      ),
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
  static const Color _appRed = Color(0xFFAC1B22);
  static const Color _appOffWhite = Color(0xFFF7F8F3);

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
  void dispose() {
    _borderController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _openEmergencyCall() {
    print("Emergency call button pressed");
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EmergencyCallScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final availableHeight = screenHeight - 200;
    final gridHeight = availableHeight * 0.65;
    final gridWidth = (screenWidth - 32).clamp(280.0, 380.0);
    final emergencyButtonSize = (screenHeight * 0.12).clamp(80.0, 120.0);
    final emergencyIconSize = emergencyButtonSize * 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ResqLogoHeader(
            padding: const EdgeInsets.only(top: 12),
            sideSlotWidth: 0,
            bottomSpacing: 4,
            trailing: const SizedBox.shrink(),
          ),

          // Main content area - takes remaining space
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  "SELECT THE TYPE OF INCIDENT\nYOU WANT TO REPORT.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                        final iconSize = (cardHeight * 0.42).clamp(34.0, 64.0);
                        final labelFont = (cardHeight * 0.135).clamp(
                          10.0,
                          14.0,
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
                                    "assets/icons/buttons/FINAL-EARTHQUAKE-ICON.svg",
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
                                    "assets/icons/buttons/FINAL-FLOOD-ICON.svg",
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
                                    "assets/icons/buttons/FINAL-FIRE-ICON.svg",
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
                                    "assets/icons/buttons/FINAL-CRASH-ICON.svg",
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
                                    "assets/icons/buttons/FINAL-OTHERS-ICON.svg",
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
                const SizedBox(height: 2),
                const Text(
                  'Press and Hold to Call',
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
        ],
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
        onTap: () => _handleIncidentTap(context, title),
        child: _buildAnimatedBorder(
          borderRadius: BorderRadius.circular(40),
          borderWidth: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildAssetIcon(
                        imgPath,
                        width: iconSize,
                        height: iconSize,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
      ),
    );
  }

  Future<void> _handleIncidentTap(BuildContext context, String title) async {
    String incidentType = title;

    if (title.toUpperCase() == 'OTHERS') {
      final customType = await _showOtherReportTypeModal(context);
      if (!mounted || customType == null) return;
      incidentType = customType;
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportFormScreen(incidentType: incidentType),
      ),
    );
  }

  Future<String?> _showOtherReportTypeModal(BuildContext context) async {
    final controller = TextEditingController();
    String? validationError;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: _appOffWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _appRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.edit_note,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'OTHER REPORT ',
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _appRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'What incident are you reporting?',
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      style: const TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'e.g. Landslide, Fallen Tree, etc.',
                        hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.45),
                          fontFamily: 'RobotoCondensed',
                        ),
                        errorText: validationError,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _appRed.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: _appRed.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(color: _appRed, width: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _appRed.withValues(alpha: 0.45),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w700,
                                color: _appRed,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final customType = controller.text.trim();
                              if (customType.isEmpty) {
                                setDialogState(() {
                                  validationError =
                                      'Please enter the report type';
                                });
                                return;
                              }
                              Navigator.pop(dialogContext, customType);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _appRed,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'CONTINUE',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Widget _buildAssetIcon(
    String assetPath, {
    required double width,
    required double height,
  }) {
    final resolvedPath = _resolveIconAssetPath(assetPath);

    if (resolvedPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        resolvedPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            SizedBox(width: width, height: height, child: _missingIcon()),
      );
    }

    return Image.asset(
      resolvedPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _missingIcon();
      },
    );
  }

  String _resolveIconAssetPath(String assetPath) {
    final lower = assetPath.toLowerCase();
    if (lower.endsWith('.svg') &&
        (lower.contains('/icons/buttons/') ||
            lower.contains('/icons/locations/'))) {
      return assetPath.substring(0, assetPath.length - 4) + '.png';
    }
    return assetPath;
  }

  Widget _missingIcon() {
    return const Icon(
      Icons.warning_amber_rounded,
      color: Colors.white,
      size: 30,
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
}
