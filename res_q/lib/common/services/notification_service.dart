import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/reports/pages/report_map_page.dart';

/// Background message handler - must be top-level and entry-point.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background FCM message received: ${message.messageId}');
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _reportsSubscription;
  Position? _lastKnownPosition;
  String? _currentUserId;
  bool _isInitialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'resq_dispatch_updates',
    'RES-Q Dispatch Updates',
    description: 'Deployment, responder status, and responder comments',
    importance: Importance.high,
  );

  GlobalKey<NavigatorState>? _navigatorKey;
  String? _currentUserId;
  String? _currentRole;
  bool _initialized = false;
  String? _lastHandledMessageId;

  /// Initialize the notification service
  Future<void> initialize({String? userId}) async {
    if (_isInitialized) {
      if (userId != null) {
        setUserId(userId);
      }
      return;
    }

    _currentUserId = userId;

    await _requestPermissions();
    await _initializeLocalNotifications();
    _setupForegroundAndTapHandlers();
    await _handleInitialMessage();
    _initialized = true;
  }

  Future<void> setUserId(String? userId, {String? role}) async {
    _currentUserId = userId?.trim().isNotEmpty == true ? userId!.trim() : null;
    _currentRole = role?.trim();
    if (_currentUserId == null) {
      return;
    }
    await _saveCurrentToken();
    _messaging.onTokenRefresh.listen((_) {
      _saveCurrentToken();
    });
  }

  Future<void> clearCurrentUserToken() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Start listening for nearby reports
    await _startNearbyReportsListener();

    _isInitialized = true;
  }

  Future<void> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint(
      'Notification permission status: ${settings.authorizationStatus}',
    );
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(
      init,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload ?? '';
        if (payload.startsWith('report:')) {
          final reportId = payload.substring('report:'.length).trim();
          if (reportId.isNotEmpty) {
            _openReportMap(reportId);
          }
        }
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle navigation based on payload if needed
  }

  void _setupForegroundAndTapHandlers() {
    FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        'App opened from notification: ${message.notification?.title}',
      );
    });
  }

  Future<void> _handleInitialMessage() async {
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _handleMessageTap(initial);
      }
    } catch (e) {
      debugPrint('Failed to handle initial FCM message: $e');
    }
  }

  Future<void> _saveCurrentToken() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      final platform = defaultTargetPlatform.name;
      await _firestore.collection('user_tokens').doc(userId).set({
        'userId': userId,
        'role': _currentRole,
        'platform': platform,
        'fcmToken': token,
        'lastToken': token,
        'tokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'resq_notifications',
      'RES-Q Notifications',
      channelDescription:
          'Notifications for nearby incidents and announcements',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFAC1B22),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final reportId = _extractReportIdFromData(message.data);
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      notification.title,
      notification.body,
      details,
      payload: message.data['type'] ?? 'general',
    );
  }

  /// Show notification for nearby incident
  Future<void> showNearbyIncidentNotification({
    required String title,
    required String body,
    required String reportId,
    required String incidentType,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'resq_notifications',
      'RES-Q Notifications',
      channelDescription:
          'Notifications for nearby incidents and announcements',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFAC1B22),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      reportId.hashCode,
      title,
      body,
      details,
      payload: 'incident:$reportId',
    );

    // Save to user's notifications collection
    await _saveIncidentNotification(
      title: title,
      body: body,
      reportId: reportId,
      incidentType: incidentType,
    );
  }

  /// Save notification to Firestore for in-app display
  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    if (_currentUserId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('notifications')
          .add({
            'title': message.notification?.title ?? '',
            'body': message.notification?.body ?? '',
            'type': message.data['type'] ?? 'announcement',
            'data': message.data,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error saving notification to Firestore: $e');
    }
  }

  /// Save incident notification to Firestore
  Future<void> _saveIncidentNotification({
    required String title,
    required String body,
    required String reportId,
    required String incidentType,
  }) async {
    if (_currentUserId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('notifications')
          .add({
            'title': title,
            'body': body,
            'type': 'nearby_incident',
            'reportId': reportId,
            'incidentType': incidentType,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error saving incident notification: $e');
    }
    _openReportMap(reportId);
  }

  /// Start listening for nearby reports
  Future<void> _startNearbyReportsListener() async {
    // Get user's current location
    await _updateUserLocation();

    // Load notified reports to avoid duplicates
    final prefs = await SharedPreferences.getInstance();
    final notifiedReports = prefs.getStringList('notified_reports') ?? [];

    // Listen to new reports
    _reportsSubscription = _firestore
        .collection('reports')
        .where('status', isEqualTo: 'PENDING')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) async {
          if (_lastKnownPosition == null) return;

          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final doc = change.doc;
              final data = doc.data();
              if (data == null) continue;

              // Skip if already notified
              if (notifiedReports.contains(doc.id)) continue;

              // Check if report is within vicinity
              final reportLat = data['latitude'] as double?;
              final reportLng = data['longitude'] as double?;

              if (reportLat != null && reportLng != null) {
                final distance = _calculateDistance(
                  _lastKnownPosition!.latitude,
                  _lastKnownPosition!.longitude,
                  reportLat,
                  reportLng,
                );

                // If within 5km, show notification
                if (distance <= defaultVicinityRadius) {
                  final incidentType =
                      data['incidentType'] as String? ?? 'Incident';
                  final description = data['description'] as String? ?? '';
                  final distanceKm = (distance / 1000).toStringAsFixed(1);

                  await showNearbyIncidentNotification(
                    title: '$incidentType Reported Nearby',
                    body: '${distanceKm}km away: $description',
                    reportId: doc.id,
                    incidentType: incidentType,
                  );

                  // Mark as notified
                  notifiedReports.add(doc.id);
                  await prefs.setStringList(
                    'notified_reports',
                    notifiedReports,
                  );
                }
              }
            }
          }
        });
  }

  Future<void> _openReportMap(String reportId) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    try {
      final snapshot = await _firestore
          .collection('reports')
          .doc(reportId)
          .get();
      final data = snapshot.data();
      if (data == null) return;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => ReportMapPage(
            reportId: reportId,
            reportData: Map<String, dynamic>.from(data),
            showBottomNav: false,
          ),
        ),
      );
      debugPrint(
        'User location updated: ${_lastKnownPosition?.latitude}, ${_lastKnownPosition?.longitude}',
      );
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Update current user ID (call after login)
  void setUserId(String? userId) {
    _currentUserId = userId;
    if (userId != null) {
      _saveFCMToken();
    }
  }
}
