import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/services/app_asset_precache_service.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/shell_navigation_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/utils/security_hash.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/mandatory_permission_gate.dart';
import '../../auth/pages/login_page.dart';

import '../../community/pages/community_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../profile/pages/profile_page.dart';
import '../../emergency/pages/emergency_call_screen.dart';
import '../../reports/pages/report_form_screen.dart';
import '../../map/pages/map_page.dart';
import '../../reports/pages/report_map_page.dart';

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
  static const int _tabCount = 5;
  static const Duration _tabTransitionDuration = Duration(milliseconds: 220);
  late int _currentIndex;
  late final Set<int> _loadedTabs;
  String? _currentCommunityReportId;
  final Map<int, int> _tabReloadTokens = <int, int>{};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _approvedUserStatusSubscription;
  bool _enforcingBanLogout = false;

  int _reloadTokenFor(int tabIndex) => _tabReloadTokens[tabIndex] ?? 0;

  void _markTabForReset(int tabIndex) {
    _tabReloadTokens[tabIndex] = _reloadTokenFor(tabIndex) + 1;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _tabCount - 1);
    _loadedTabs = {_currentIndex};
    _currentCommunityReportId = widget.initialCommunityReportId;
    MainShellNavigationService.commands.addListener(_handleShellNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializePostLoginServices());
      unawaited(_startApprovedUserBanWatcher());
    });
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCommunityReportId != oldWidget.initialCommunityReportId) {
      _currentCommunityReportId = widget.initialCommunityReportId;
      _loadedTabs.add(1);
    }
  }

  @override
  void dispose() {
    _approvedUserStatusSubscription?.cancel();
    MainShellNavigationService.commands.removeListener(_handleShellNavigation);
    super.dispose();
  }

  Future<void> _initializePostLoginServices() async {
    unawaited(AppAssetPrecacheService.warmUpPostLoginAssets(context));

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

  bool _isBannedStatus(dynamic rawStatus) {
    return rawStatus is String && rawStatus.trim().toUpperCase() == 'BANNED';
  }

  bool _isPermanentBan(Map<String, dynamic> data, bool isBanned) {
    if (!isBanned) {
      return false;
    }
    if (data['isPermanent'] == true) {
      return true;
    }
    final banType = (data['banType'] ?? '').toString().trim().toLowerCase();
    if (banType == 'permanent') {
      return true;
    }
    return data['bannedUntil'] == null;
  }

  DateTime? _parseBanUntil(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map<String, dynamic>) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        final nanos = nanoseconds is int
            ? nanoseconds
            : (nanoseconds is num ? nanoseconds.toInt() : 0);
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000) + (nanos ~/ 1000000),
        );
      }
    }
    return null;
  }

  List<String> _parseBanReasons(dynamic rawReasons) {
    if (rawReasons is! List) return const <String>[];
    return rawReasons
        .map((reason) => reason.toString().trim())
        .where((reason) => reason.isNotEmpty)
        .toList(growable: false);
  }

  String _formatBanUntil(DateTime? bannedUntil) {
    if (bannedUntil == null) {
      return '';
    }
    final month = bannedUntil.month.toString().padLeft(2, '0');
    final day = bannedUntil.day.toString().padLeft(2, '0');
    final year = bannedUntil.year.toString();
    final hour24 = bannedUntil.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = bannedUntil.minute.toString().padLeft(2, '0');
    final meridiem = hour24 >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year $hour12:$minute $meridiem';
  }

  Future<DocumentReference<Map<String, dynamic>>?>
  _resolveApprovedUserDocRef() async {
    final currentUser = UserSession.currentUserData;
    if (currentUser == null) {
      return null;
    }

    final docId = (currentUser['docId'] ?? '').toString().trim();
    if (docId.isNotEmpty) {
      return _firestore.collection('approved_users').doc(docId);
    }

    final contactNumber =
        (currentUser['contactNumber'] ?? currentUser['phoneNumber'])
            .toString()
            .trim();
    if (contactNumber.isEmpty) {
      return null;
    }

    QuerySnapshot<Map<String, dynamic>> query = await _firestore
        .collection('approved_users')
        .where(
          'contactNumber_hash',
          isEqualTo: SecurityHash.sha256Hex(contactNumber),
        )
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      query = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: contactNumber)
          .limit(1)
          .get();
    }
    if (query.docs.isEmpty) {
      return null;
    }

    currentUser['docId'] = query.docs.first.id;
    return query.docs.first.reference;
  }

  Future<void> _startApprovedUserBanWatcher() async {
    try {
      final docRef = await _resolveApprovedUserDocRef();
      if (docRef == null || !mounted) {
        return;
      }

      _approvedUserStatusSubscription?.cancel();
      _approvedUserStatusSubscription = docRef.snapshots().listen(
        (snapshot) {
          if (!mounted) return;

          if (!snapshot.exists) {
            unawaited(
              _enforceBanLogout(
                isPermanentBan: true,
                banReasons: const <String>[],
                bannedUntil: null,
              ),
            );
            return;
          }

          final userData = snapshot.data() ?? <String, dynamic>{};
          final isBanned = _isBannedStatus(userData['accountStatus']);
          if (!isBanned) {
            return;
          }
          unawaited(
            _enforceBanLogout(
              isPermanentBan: _isPermanentBan(userData, isBanned),
              banReasons: _parseBanReasons(userData['banReasons']),
              bannedUntil: _parseBanUntil(userData['bannedUntil']),
            ),
          );
        },
        onError: (Object error) {
          debugPrint('Approved user ban watcher error: $error');
        },
      );
    } catch (error) {
      debugPrint('Failed to start approved user ban watcher: $error');
    }
  }

  Future<void> _showBanEnforcementDialog({
    required bool isPermanentBan,
    required List<String> banReasons,
    DateTime? bannedUntil,
  }) async {
    if (!mounted) return;

    final reasonText = banReasons.isEmpty ? '' : banReasons.join(', ');
    final formattedUntil = _formatBanUntil(bannedUntil);
    final title = isPermanentBan
        ? 'ACCOUNT PERMANENTLY BANNED'
        : 'ACCOUNT TEMPORARILY BANNED';
    final subtitle = isPermanentBan
        ? 'Your account has been permanently banned by an administrator.'
        : 'Your account has been temporarily banned by an administrator.';
    final untilText = isPermanentBan || formattedUntil.isEmpty
        ? ''
        : 'Ban ends on: $formattedUntil';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFAC1B22).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFAC1B22), width: 2),
                ),
                child: const Icon(
                  Icons.block,
                  color: Color(0xFFAC1B22),
                  size: 44,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFAC1B22),
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF212121),
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              if (untilText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  untilText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (reasonText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Reason(s): $reasonText',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF212121),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAC1B22),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enforceBanLogout({
    required bool isPermanentBan,
    required List<String> banReasons,
    DateTime? bannedUntil,
  }) async {
    if (_enforcingBanLogout || !mounted) {
      return;
    }
    _enforcingBanLogout = true;

    try {
      await _showBanEnforcementDialog(
        isPermanentBan: isPermanentBan,
        banReasons: banReasons,
        bannedUntil: bannedUntil,
      );
      NotificationService().dispose();
      UserSession.clear();
      await RegistrationPrefs.setApprovedLoginCompleted(false);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (error) {
      debugPrint('Failed to enforce banned-account logout: $error');
      _enforcingBanLogout = false;
    }
  }

  void _handleShellNavigation() {
    final command = MainShellNavigationService.commands.value;
    if (command == null || !mounted) return;

    final nextIndex = command.tabIndex.clamp(0, _tabCount - 1);
    final communityReportId = command.communityReportId?.trim();

    setState(() {
      _markTabForReset(nextIndex);
      _currentIndex = nextIndex;
      _loadedTabs.add(nextIndex);
      if (communityReportId != null && communityReportId.isNotEmpty) {
        _currentCommunityReportId = communityReportId;
        _loadedTabs.add(1);
        _markTabForReset(1);
      }
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _markTabForReset(index);
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  Widget _getCachedTabPage(int index) {
    final reloadToken = _reloadTokenFor(index);
    switch (index) {
      case 0:
        return _HomePageContent(key: ValueKey('home-tab-$reloadToken'));
      case 1:
        final normalizedReportId = _currentCommunityReportId?.trim();
        final token = normalizedReportId == null || normalizedReportId.isEmpty
            ? 'none'
            : normalizedReportId;
        return CommunityPage(
          key: ValueKey('community-tab-$token-$reloadToken'),
          initialReportId: token == 'none' ? null : token,
        );
      case 2:
        final activeReport = UserSession.latestActiveReport;
        if (activeReport != null) {
          return ReportMapPage(
            key: ValueKey('report-map-${activeReport.reportId}-$reloadToken'),
            reportId: activeReport.reportId,
            reportData: activeReport.reportData,
            showBottomNav: false,
          );
        }
        return MapPage(key: ValueKey('map-tab-$reloadToken'));
      case 3:
        return NotificationsPage(
          key: ValueKey('notifications-tab-$reloadToken'),
        );
      case 4:
        return ProfilePage(key: ValueKey('profile-tab-$reloadToken'));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAnimatedTabBody() {
    return Stack(
      fit: StackFit.expand,
      children: List<Widget>.generate(_tabCount, (index) {
        if (!_loadedTabs.contains(index)) {
          return const SizedBox.shrink();
        }

        final isActive = index == _currentIndex;
        return Positioned.fill(
          child: ExcludeSemantics(
            excluding: !isActive,
            child: IgnorePointer(
              ignoring: !isActive,
              child: AnimatedOpacity(
                opacity: isActive ? 1 : 0,
                duration: _tabTransitionDuration,
                curve: isActive ? Curves.easeOutCubic : Curves.easeInCubic,
                child: TickerMode(
                  enabled: isActive,
                  child: _getCachedTabPage(index),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MandatoryPermissionGate(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8F3),
        bottomNavigationBar: BottomNavBar(
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
        ),
        body: SafeArea(bottom: false, child: _buildAnimatedTabBody()),
      ),
    );
  }
}

class _HomePageContent extends StatefulWidget {
  const _HomePageContent({super.key});

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
          const ResqLogoHeader(
            padding: EdgeInsets.only(top: 12),
            sideSlotWidth: 0,
            bottomSpacing: 4,
            trailing: SizedBox.shrink(),
          ),

          // Main content area - takes remaining space
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const Text(
                  "SELECT THE TYPE OF INCIDENT\nYOU WANT TO REPORT.",
                  textAlign: TextAlign.center,
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
          animate: false,
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
    bool animate = true,
  }) {
    Widget buildBorder(double angle, Widget innerChild) {
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
          child: innerChild,
        ),
      );
    }

    if (!animate) {
      return RepaintBoundary(child: buildBorder(0, child));
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _borderController,
        child: child,
        builder: (context, animatedChild) {
          final angle = _borderController.value * 2 * math.pi;
          return buildBorder(angle, animatedChild ?? child);
        },
      ),
    );
  }
}
