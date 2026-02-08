import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../common/services/user_session.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: appWhite,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Roboto',
                  ),
                  children: [
                    TextSpan(
                      text: 'N',
                      style: TextStyle(color: appBlue),
                    ),
                    TextSpan(
                      text: 'O',
                      style: TextStyle(color: appRed),
                    ),
                    TextSpan(
                      text: 'TIFICATION',
                      style: TextStyle(color: appBlue),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Unified notification feed
            Expanded(child: _buildUnifiedNotificationFeed()),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedNotificationFeed() {
    return StreamBuilder<List<_NotificationItem>>(
      stream: _getCombinedNotificationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(appBlue),
            ),
          );
        }

        if (snapshot.hasError) {
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

        final notifications = snapshot.data ?? [];

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

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return _buildNotificationCard(notification);
          },
        );
      },
    );
  }

  Stream<List<_NotificationItem>> _getCombinedNotificationsStream() {
    final controller = StreamController<List<_NotificationItem>>();
    final isResponder = _isResponderSession();
    final responderDocId = _getResponderDocId();
    final reportOwnerId = _getCurrentUserReportOwnerId();

    List<_NotificationItem> announcements = [];
    List<_NotificationItem> reports = [];

    void emitCombined() {
      if (controller.isClosed) return;
      final combined = [...announcements, ...reports]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      controller.add(combined);
    }

    final announcementsSub = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
          announcements = snapshot.docs
              .where((doc) {
                final data = doc.data();
                return data['isPlaceholder'] != true;
              })
              .map((doc) => _NotificationItem.fromAnnouncement(doc))
              .toList();
          emitCombined();
        }, onError: controller.addError);

    Query<Map<String, dynamic>> reportsQuery;
    if (isResponder && responderDocId != null && responderDocId.isNotEmpty) {
      reportsQuery = FirebaseFirestore.instance
          .collection('reports')
          .where('responderId', isEqualTo: responderDocId)
          .limit(40);
    } else if (isResponder) {
      reportsQuery = FirebaseFirestore.instance
          .collection('reports')
          .where('responderId', isEqualTo: '__none__')
          .limit(1);
    } else {
      if (reportOwnerId != null && reportOwnerId.isNotEmpty) {
        reportsQuery = FirebaseFirestore.instance
            .collection('reports')
            .where('userId', isEqualTo: reportOwnerId)
            .limit(40);
      } else {
        reportsQuery = FirebaseFirestore.instance
            .collection('reports')
            .orderBy('reportedAt', descending: true)
            .limit(30);
      }
    }

    final reportsSub = reportsQuery.snapshots().listen((snapshot) {
      reports = snapshot.docs
          .where((doc) {
            final data = doc.data();
            if (isResponder) {
              return (data['responderId'] as String?)?.trim().isNotEmpty ==
                  true;
            }
            if (reportOwnerId != null && reportOwnerId.isNotEmpty) {
              return true;
            }
            return data['location'] != null ||
                data['incidentLocation'] != null ||
                data['reporterLocation'] != null;
          })
          .map(
            (doc) => _NotificationItem.fromReport(
              doc,
              deploymentNotification: isResponder,
            ),
          )
          .toList();
      emitCombined();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await announcementsSub.cancel();
      await reportsSub.cancel();
    };

    return controller.stream;
  }

  bool _isResponderSession() {
    final role = (UserSession.currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'semi-admin' || role == 'semi_admin' || role == 'responder';
  }

  String? _getResponderDocId() {
    final userData = UserSession.currentUserData;
    final rawId =
        (userData?['id'] ?? userData?['contactNumber'])?.toString().trim() ??
        '';
    if (rawId.isEmpty) return null;
    return rawId;
  }

  String? _getCurrentUserReportOwnerId() {
    final userData = UserSession.currentUserData;
    final raw =
        (userData?['userId'] ??
                userData?['contactNumber'] ??
                userData?['phoneNumber'] ??
                userData?['id'])
            ?.toString() ??
        '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits;
  }

  Widget _buildNotificationCard(_NotificationItem notification) {
    final isAnnouncement = notification.type == _NotificationType.announcement;
    final timeAgo = _getTimeAgo(notification.timestamp);

    return GestureDetector(
      onTap: () => _showNotificationDetail(notification),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: notification.isNew ? appBlue.withOpacity(0.04) : Colors.white,
          border: Border(
            bottom: BorderSide(color: appBlack.withOpacity(0.08), width: 1),
          ),
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
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isAnnouncement ? appBlack : Colors.white,
                            fontFamily: 'RobotoCondensed',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (notification.isNew)
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: notification.isNew
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: appBlack,
                      height: 1.3,
                    ),
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
                child: Image.network(
                  notification.imageUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  void _showNotificationDetail(_NotificationItem notification) {
    final isAnnouncement = notification.type == _NotificationType.announcement;

    // Mark as read when opened
    _markNotificationAsRead(notification);

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
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isAnnouncement ? appBlack : Colors.white,
                            fontFamily: 'RobotoCondensed',
                          ),
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
                      child: Image.network(
                        notification.imageUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                          Icon(Icons.location_on, color: appBlue, size: 20),
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
                            'Status: ${notification.status!.toUpperCase()}',
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
    switch (status.toLowerCase()) {
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
        return const Color(0xFFEF4444);
      default:
        return appBlue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
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
        return Icons.flag;
      default:
        return Icons.info_outline;
    }
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
    bool deploymentNotification = false,
  }) {
    final data = doc.data()!;
    final incidentType = data['incidentType'] as String? ?? 'Incident';
    final reporter = data['name'] as String?;
    final details = data['details'] as String?;
    final barangay = data['barangay'] as String?;
    final status =
        data['responderStatus'] as String? ?? data['status'] as String?;
    final statusLower = (status ?? '').trim().toLowerCase();
    final responderNameRaw = (data['responderName'] as String? ?? '').trim();
    final safeResponderName = responderNameRaw.isEmpty
        ? 'Responder'
        : responderNameRaw;
    final latestComment = _extractLatestResponderComment(
      data['responderComments'],
    );
    final latestCommentText = (latestComment?['text'] as String? ?? '').trim();
    final latestCommentAt = latestComment?['timestamp'] as DateTime?;

    Object? ts;
    String title;
    String? subtitle;

    if (deploymentNotification) {
      ts =
          data['responderAssignedAt'] ??
          data['deployedAt'] ??
          data['respondingAt'] ??
          data['reportedAt'];
      title = 'You were deployed to a $incidentType incident';
      subtitle = details?.trim().isNotEmpty == true
          ? details
          : 'Open map to view assigned report details.';
    } else {
      final hasAssignment =
          (data['responderId'] as String? ?? '').trim().isNotEmpty ||
          (responderNameRaw.isNotEmpty &&
              responderNameRaw.toLowerCase() != 'unknown' &&
              responderNameRaw.toLowerCase() != 'responder') ||
          data['responderAssignedAt'] != null ||
          data['deployedAt'] != null;

      if (statusLower == 'responding') {
        ts =
            data['respondingAt'] ??
            data['responderStatusUpdatedAt'] ??
            data['responderAssignedAt'] ??
            data['deployedAt'] ??
            data['reportedAt'];
        title = '$safeResponderName is responding to your report';
        subtitle = latestCommentText.isNotEmpty
            ? latestCommentText
            : 'Responder is on the way to your location.';
      } else if (hasAssignment) {
        ts =
            data['responderAssignedAt'] ??
            data['deployedAt'] ??
            data['reportedAt'];
        title = '$safeResponderName was deployed to your report';
        subtitle = latestCommentText.isNotEmpty
            ? latestCommentText
            : 'Status stays pending until responder taps responding.';
      } else {
        ts = data['reportedAt'];
        title = '$incidentType incident reported';
        subtitle = details;
      }

      if (latestCommentAt != null &&
          latestCommentAt.isAfter(_parseTimestamp(ts))) {
        ts = latestCommentAt;
      }
    }

    final timestamp = _parseTimestamp(ts);

    // Check if explicitly marked as new, otherwise use time-based logic.
    bool isNew;
    if (data['isNew'] != null) {
      isNew = data['isNew'] as bool;
    } else {
      final thresholdHours = deploymentNotification ? 12 : 24;
      isNew = DateTime.now().difference(timestamp).inHours < thresholdHours;
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
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Map<String, Object?>? _extractLatestResponderComment(
    Object? rawComments,
  ) {
    if (rawComments is! List) {
      return null;
    }

    Map<String, Object?>? latest;
    for (final entry in rawComments) {
      if (entry is! Map) continue;
      final comment = Map<String, dynamic>.from(entry);
      final text = (comment['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;

      final type = (comment['type'] as String?)?.toLowerCase();
      final role = (comment['role'] as String?)?.toLowerCase();
      final isResponderComment =
          type == 'admin' ||
          role == 'responder' ||
          (type != 'user' && type != null);
      if (!isResponderComment) continue;

      final commentTimestamp = _parseTimestamp(comment['timestamp']);
      if (latest == null ||
          commentTimestamp.isAfter(latest['timestamp'] as DateTime)) {
        latest = {'text': text, 'timestamp': commentTimestamp};
      }
    }
    return latest;
  }
}
