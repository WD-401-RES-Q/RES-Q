import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../common/services/shell_navigation_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/widgets/auth_widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // OFFICIAL COLORS
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appWhite = Color(0xFFF7F8F3);
  static const _badgeAnnouncementTextStyle = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: appBlack,
    fontFamily: 'RobotoCondensed',
    letterSpacing: 0.5,
  );
  static const _badgeIncidentTextStyle = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    fontFamily: 'RobotoCondensed',
    letterSpacing: 0.5,
  );
  static const _feedTitleNewTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: appBlack,
    height: 1.3,
  );
  static const _feedTitleReadTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: appBlack,
    height: 1.3,
  );
  static const _dialogBadgeAnnouncementTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: appBlack,
    fontFamily: 'RobotoCondensed',
  );
  static const _dialogBadgeIncidentTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    fontFamily: 'RobotoCondensed',
  );
  final ValueNotifier<Set<String>> _optimisticallyReadIdsNotifier =
      ValueNotifier<Set<String>>(<String>{});

  @override
  void dispose() {
    _optimisticallyReadIdsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: appWhite,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResqLogoHeader(
              padding: const EdgeInsets.only(top: 12),
              sideSlotWidth: 0,
              titleSpacing: 12,
              bottomSpacing: 6,
            ),

            // Unified notification feed
            Expanded(child: _buildUnifiedNotificationFeed()),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedNotificationFeed() {
    final isResponder = _isResponderUser();
    final reportFetchLimit = isResponder ? 150 : 30;
    final announcementsStream = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
    final reportsStream = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('reportedAt', descending: true)
        .limit(reportFetchLimit)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: announcementsStream,
      builder: (context, announcementsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: reportsStream,
          builder: (context, reportsSnapshot) {
            final announcementsWaiting =
                announcementsSnapshot.connectionState ==
                ConnectionState.waiting;
            final reportsWaiting =
                reportsSnapshot.connectionState == ConnectionState.waiting;
            if (announcementsWaiting &&
                reportsWaiting &&
                announcementsSnapshot.data == null &&
                reportsSnapshot.data == null) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(appBlue),
                ),
              );
            }

            if (announcementsSnapshot.hasError || reportsSnapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: appBlack.withOpacity(0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load notifications.',
                      style: TextStyle(
                        fontSize: 14,
                        color: appBlack.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              );
            }

            final notifications = _combineNotifications(
              announcementsSnapshot.data,
              reportsSnapshot.data,
            );

            if (notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: appBlack.withOpacity(0.25),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: appBlack.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You\'ll see announcements and\nincident alerts here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: appBlack.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              );
            }

            return ValueListenableBuilder<Set<String>>(
              valueListenable: _optimisticallyReadIdsNotifier,
              builder: (context, optimisticallyReadIds, _) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: appBlack.withValues(alpha: 0.08),
                  ),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return _buildNotificationCard(
                      notification,
                      optimisticallyReadIds,
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_NotificationItem> _combineNotifications(
    QuerySnapshot<Map<String, dynamic>>? announcementsSnapshot,
    QuerySnapshot<Map<String, dynamic>>? reportsSnapshot,
  ) {
    final isResponder = _isResponderUser();
    final announcements = (announcementsSnapshot?.docs ?? const [])
        .where((doc) {
          final data = doc.data();
          return data['isPlaceholder'] != true;
        })
        .map((doc) => _NotificationItem.fromAnnouncement(doc))
        .toList();

    final reports = (reportsSnapshot?.docs ?? const [])
        .where((doc) {
          final data = doc.data();
          if (data['location'] == null) {
            return false;
          }
          if (!isResponder) {
            return true;
          }
          return _isReportAssignedToCurrentResponder(data);
        })
        .map(
          (doc) => _NotificationItem.fromReport(doc, forResponder: isResponder),
        )
        .toList();

    final combined = [...announcements, ...reports];
    combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return combined;
  }

  Widget _buildNotificationCard(
    _NotificationItem notification,
    Set<String> optimisticallyReadIds,
  ) {
    final isAnnouncement = notification.type == _NotificationType.announcement;
    final isNew =
        notification.isNew && !optimisticallyReadIds.contains(notification.id);
    final timeAgo = _getTimeAgo(notification.timestamp);

    return GestureDetector(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isNew ? appBlue.withOpacity(0.04) : Colors.white,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon/Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isAnnouncement
                    ? appRed.withOpacity(0.15)
                    : _getIncidentColor(
                        notification.incidentType,
                      ).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAnnouncement
                    ? Icons.campaign
                    : _getIncidentIcon(notification.incidentType),
                color: isAnnouncement
                    ? const Color(0xFFB8860B)
                    : _getIncidentColor(notification.incidentType),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title with badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isAnnouncement ? appRed : appBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAnnouncement
                              ? 'ANNOUNCEMENT'
                              : notification.incidentType?.toUpperCase() ??
                                    'INCIDENT',
                          style: isAnnouncement
                              ? _badgeAnnouncementTextStyle
                              : _badgeIncidentTextStyle,
                        ),
                      ),
                      const Spacer(),
                      if (isNew)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: appBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Main text
                  Text(
                    notification.title,
                    style: isNew
                        ? _feedTitleNewTextStyle
                        : _feedTitleReadTextStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.subtitle != null &&
                      notification.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notification.subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: appBlack.withOpacity(0.6),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Time and location
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: appBlack.withOpacity(0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: appBlack.withOpacity(0.5),
                        ),
                      ),
                      if (!isAnnouncement && notification.location != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: appBlack.withOpacity(0.4),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            notification.location!,
                            style: TextStyle(
                              fontSize: 12,
                              color: appBlack.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Thumbnail for announcements with images
            if (isAnnouncement &&
                notification.imageUrl != null &&
                notification.imageUrl!.isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: notification.imageUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  memCacheWidth: 180,
                  memCacheHeight: 180,
                  maxWidthDiskCache: 180,
                  maxHeightDiskCache: 180,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _markNotificationAsReadOptimistically(_NotificationItem notification) {
    if (!notification.isNew) return;
    final current = _optimisticallyReadIdsNotifier.value;
    if (current.contains(notification.id)) return;
    if (!mounted) return;
    _optimisticallyReadIdsNotifier.value = <String>{
      ...current,
      notification.id,
    };
  }

  Future<void> _markNotificationAsRead(_NotificationItem notification) async {
    try {
      if (notification.type == _NotificationType.announcement) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(notification.id)
            .update({'isNew': false});
      } else {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(notification.id)
            .update({'isNew': false});
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _handleNotificationTap(_NotificationItem notification) async {
    _markNotificationAsReadOptimistically(notification);
    unawaited(_markNotificationAsRead(notification));
    if (!mounted) return;

    if (notification.type == _NotificationType.incident) {
      _openIncidentReport(notification);
      return;
    }

    _showNotificationDetail(notification);
  }

  void _openIncidentReport(_NotificationItem notification) {
    if (_isResponderUser()) {
      ResponderShellNavigationService.openTab(0, reportId: notification.id);
      return;
    }
    MainShellNavigationService.openTab(1, communityReportId: notification.id);
  }

  bool _isResponderUser() {
    final role = (UserSession.currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'semi-admin' || role == 'semi_admin' || role == 'responder';
  }

  String _normalizePhoneValue(Object? raw) {
    return (raw?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
  }

  bool _isReportAssignedToCurrentResponder(Map<String, dynamic> data) {
    final userData = UserSession.currentUserData;
    final responderDocId = (userData?['id'] ?? '').toString().trim();
    final responderPhone = _normalizePhoneValue(
      userData?['contactNumber'] ?? userData?['phoneNumber'],
    );
    final responderName = (userData?['fullName'] ?? userData?['username'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final assignedId = (data['responderId'] as String? ?? '').trim();
    final assignedIdPhone = _normalizePhoneValue(assignedId);
    final assignedContactPhone = _normalizePhoneValue(
      data['responderContactNumber'] ?? data['responderPhone'],
    );
    final assignedName = (data['responderName'] as String? ?? '')
        .trim()
        .toLowerCase();

    final matchesPhone =
        responderPhone.isNotEmpty &&
        (assignedIdPhone == responderPhone ||
            assignedContactPhone == responderPhone);
    final matchesDocId =
        responderDocId.isNotEmpty && assignedId == responderDocId;
    final matchesName =
        responderName.isNotEmpty &&
        assignedName.isNotEmpty &&
        assignedName == responderName;

    return matchesPhone || matchesDocId || matchesName;
  }

  void _showNotificationDetail(_NotificationItem notification) {
    final isAnnouncement = notification.type == _NotificationType.announcement;

    // Mark as read when opened
    _markNotificationAsReadOptimistically(notification);
    unawaited(_markNotificationAsRead(notification));

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: appWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isAnnouncement ? appRed : appBlue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isAnnouncement
                              ? 'ANNOUNCEMENT'
                              : notification.incidentType?.toUpperCase() ??
                                    'INCIDENT',
                          style: isAnnouncement
                              ? _dialogBadgeAnnouncementTextStyle
                              : _dialogBadgeIncidentTextStyle,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Image for announcements
                  if (isAnnouncement &&
                      notification.imageUrl != null &&
                      notification.imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: notification.imageUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        memCacheHeight: 360,
                        maxHeightDiskCache: 360,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  if (isAnnouncement &&
                      notification.imageUrl != null &&
                      notification.imageUrl!.isNotEmpty)
                    const SizedBox(height: 16),

                  // Title
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: appBlack,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Date
                  Text(
                    DateFormat(
                      'MMM d, yyyy — h:mm a',
                    ).format(notification.timestamp),
                    style: TextStyle(
                      fontSize: 13,
                      color: appBlack.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Content
                  if (notification.subtitle != null &&
                      notification.subtitle!.isNotEmpty)
                    Text(
                      notification.subtitle!,
                      style: TextStyle(
                        fontSize: 14,
                        color: appBlack.withOpacity(0.8),
                        height: 1.5,
                      ),
                    ),

                  // Location for incidents
                  if (!isAnnouncement && notification.location != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: appBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: appBlue.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: appBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              notification.location!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Reporter info for incidents
                  if (!isAnnouncement && notification.reporter != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: appBlack.withOpacity(0.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Reported by ${notification.reporter}',
                          style: TextStyle(
                            fontSize: 13,
                            color: appBlack.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Status for incidents
                  if (!isAnnouncement && notification.status != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          notification.status!,
                        ).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getStatusColor(notification.status!),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(notification.status!),
                            size: 16,
                            color: _getStatusColor(notification.status!),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status: ${_normalizeStatusLabel(notification.status!)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(notification.status!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins ${mins == 1 ? 'min' : 'mins'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }

  IconData _getIncidentIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire':
        return Icons.local_fire_department;
      case 'flood':
        return Icons.water;
      case 'earthquake':
        return Icons.waves;
      case 'vehicular':
      case 'road accident':
        return Icons.car_crash;
      default:
        return Icons.report_problem;
    }
  }

  Color _getIncidentColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire':
        return const Color(0xFFEF4444);
      case 'flood':
        return const Color(0xFF3B82F6);
      case 'earthquake':
        return const Color(0xFF8B5CF6);
      case 'vehicular':
      case 'road accident':
        return const Color(0xFFF97316);
      case 'road obstruction':
        return const Color(0xFFF59E0B);
      default:
        return appBlue;
    }
  }

  Color _getStatusColor(String status) {
    switch (_normalizeStatusKey(status)) {
      case 'pending':
        return const Color(0xFF3B82F6);
      case 'responding':
        return const Color(0xFFF59E0B);
      case 'on scene':
      case 'on-scene':
        return const Color(0xFF8B5CF6);
      case 'resolved':
      case 'incident resolved':
        return const Color(0xFF22C55E);
      case 'flagged':
      case 'unverified':
      case 'admin flagged':
        return const Color(0xFFEF4444);
      default:
        return appBlue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (_normalizeStatusKey(status)) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'responding':
        return Icons.directions_run;
      case 'on scene':
      case 'on-scene':
        return Icons.location_on;
      case 'resolved':
      case 'incident resolved':
        return Icons.check_circle;
      case 'flagged':
      case 'unverified':
      case 'admin flagged':
        return Icons.flag;
      default:
        return Icons.info_outline;
    }
  }

  String _normalizeStatusKey(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeStatusLabel(String status) {
    final normalized = _normalizeStatusKey(status);
    if (normalized == 'flagged' ||
        normalized == 'unverified' ||
        normalized == 'admin flagged') {
      return 'FLAGGED';
    }
    if (normalized == 'incident resolved') {
      return 'RESOLVED';
    }
    return status.trim().toUpperCase().replaceAll('_', ' ');
  }
}

enum _NotificationType { announcement, incident }

class _NotificationItem {
  final String id;
  final _NotificationType type;
  final String title;
  final String? subtitle;
  final DateTime timestamp;
  final String? imageUrl;
  final String? incidentType;
  final String? location;
  final String? reporter;
  final String? status;
  final bool isNew;

  _NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    required this.timestamp,
    this.imageUrl,
    this.incidentType,
    this.location,
    this.reporter,
    this.status,
    this.isNew = false,
  });

  factory _NotificationItem.fromAnnouncement(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final ts = data['createdAt'];
    DateTime timestamp = DateTime.now();
    if (ts is Timestamp) {
      timestamp = ts.toDate();
    }

    // Check if explicitly marked as new, otherwise use time-based logic (24 hours)
    bool isNew;
    if (data['isNew'] != null) {
      isNew = data['isNew'] as bool;
    } else {
      isNew = DateTime.now().difference(timestamp).inHours < 24;
    }

    return _NotificationItem(
      id: doc.id,
      type: _NotificationType.announcement,
      title: data['title'] as String? ?? 'Announcement',
      subtitle: data['content'] as String?,
      timestamp: timestamp,
      imageUrl: data['imageUrl'] as String?,
      isNew: isNew,
    );
  }

  factory _NotificationItem.fromReport(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool forResponder = false,
  }) {
    final data = doc.data()!;
    final reportedAtRaw = data['reportedAt'];
    final assignedAtRaw =
        data['responderAssignedAt'] ??
        data['deployedAt'] ??
        data['respondingAt'] ??
        reportedAtRaw;
    final timestamp = _parseTimestamp(
      forResponder ? assignedAtRaw : reportedAtRaw,
    );

    final incidentType = data['incidentType'] as String? ?? 'Incident';
    final reporter = data['name'] as String?;
    final barangay = data['barangay'] as String?;
    final status =
        (data['responderStatus'] as String?) ?? (data['status'] as String?);
    final deployedBy = (data['deployedBy'] as String? ?? '').trim();
    final title = forResponder
        ? '$incidentType assigned to you'
        : '$incidentType incident reported';
    final subtitle = forResponder
        ? (deployedBy.isNotEmpty
              ? 'Deployed by $deployedBy'
              : 'Tap to open assigned incident')
        : null;

    // Check if explicitly marked as new, otherwise use time-based logic.
    bool isNew;
    if (data['isNew'] != null) {
      isNew = data['isNew'] as bool;
    } else {
      final freshnessHours = forResponder ? 12 : 6;
      isNew = DateTime.now().difference(timestamp).inHours < freshnessHours;
    }

    return _NotificationItem(
      id: doc.id,
      type: _NotificationType.incident,
      title: title,
      subtitle: subtitle,
      timestamp: timestamp,
      incidentType: incidentType,
      location: barangay ?? 'Location not specified',
      reporter: reporter,
      status: status,
      isNew: isNew,
    );
  }

  static DateTime _parseTimestamp(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return DateTime.now();
  }
}
