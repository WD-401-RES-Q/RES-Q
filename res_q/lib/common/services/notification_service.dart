import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _reportsSubscription;
  Position? _lastKnownPosition;
  String? _currentUserId;
  bool _isInitialized = false;

  // Notification channel for Android
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'resq_notifications',
    'RES-Q Notifications',
    description: 'Notifications for nearby incidents and announcements',
    importance: Importance.high,
    playSound: true,
  );

  static const AndroidNotificationChannel _alertChannel =
      AndroidNotificationChannel(
        'resq_emergency_alerts',
        'RES-Q Emergency Alerts',
        description: 'Critical responder deployment notifications',
        importance: Importance.max,
        playSound: true,
      );

  // Default vicinity radius in meters (5km)
  static const double defaultVicinityRadius = 5000;

  /// Initialize the notification service
  Future<void> initialize({
    String? userId,
    bool requestPermissionsAtInit = false,
  }) async {
    if (_isInitialized) {
      if (userId != null) {
        setUserId(userId);
      }
      return;
    }

    _currentUserId = userId;

    if (requestPermissionsAtInit) {
      await _requestPermissions();
    }

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Set up FCM handlers
    _setupFCMHandlers();

    // Subscribe to FCM topics for announcements and incident reports.
    await Future.wait([
      _messaging.subscribeToTopic('announcements'),
      _messaging.subscribeToTopic('reports'),
    ]);
    debugPrint('Subscribed to FCM topics: announcements, reports');

    // Get and save FCM token
    await _saveFCMToken();

    // Start listening for nearby reports
    await _startNearbyReportsListener();

    _isInitialized = true;
  }

  /// Request notification permissions explicitly (e.g., during splash).
  Future<void> requestPermissions() async {
    await _requestPermissions();
  }

  /// Request notification permissions
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

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel for Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_alertChannel);
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle navigation based on payload if needed
  }

  /// Set up FCM message handlers
  void _setupFCMHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.notification?.title}');
      _showLocalNotification(message);
      _saveNotificationToFirestore(message);
    });

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        'App opened from notification: ${message.notification?.title}',
      );
    });

    // Set background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Save FCM token to Firestore for the user
  Future<void> _saveFCMToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && _currentUserId != null) {
        final tokenDocIds = _buildTokenDocIds(_currentUserId!);
        for (final docId in tokenDocIds) {
          await _firestore.collection('user_tokens').doc(docId).set({
            'fcmToken': token,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        debugPrint('FCM token saved: ${token.substring(0, 20)}...');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        if (_currentUserId != null) {
          final tokenDocIds = _buildTokenDocIds(_currentUserId!);
          for (final docId in tokenDocIds) {
            await _firestore.collection('user_tokens').doc(docId).set({
              'fcmToken': newToken,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      });
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Show a local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final payloadType = (message.data['type'] ?? '').toString().trim();
    final isResponderAssignment = payloadType == 'responder_assignment';

    final androidDetails = AndroidNotificationDetails(
      isResponderAssignment ? 'resq_emergency_alerts' : 'resq_notifications',
      isResponderAssignment ? 'RES-Q Emergency Alerts' : 'RES-Q Notifications',
      channelDescription: isResponderAssignment
          ? 'Critical responder deployment notifications'
          : 'Notifications for nearby incidents and announcements',
      importance: isResponderAssignment ? Importance.max : Importance.high,
      priority: isResponderAssignment ? Priority.max : Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: isResponderAssignment ? const Color(0xFFAC1B22) : null,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: payloadType.isEmpty ? 'general' : payloadType,
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

  /// Update user's location
  Future<void> _updateUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _lastKnownPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
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

  Set<String> _buildTokenDocIds(String rawUserId) {
    final ids = <String>{};
    final trimmed = rawUserId.trim();
    if (trimmed.isEmpty) {
      return ids;
    }

    ids.add(trimmed);
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) {
      return ids;
    }

    ids.add(digits);
    if (digits.startsWith('63')) {
      ids.add('+$digits');
      final local = digits.substring(2);
      if (local.length == 10) {
        ids.add(local);
        ids.add('0$local');
      }
      return ids;
    }

    if (digits.length == 11 && digits.startsWith('0')) {
      final local = digits.substring(1);
      if (local.length == 10) {
        ids.add(local);
        ids.add('63$local');
        ids.add('+63$local');
      }
      return ids;
    }

    if (digits.length == 10 && digits.startsWith('9')) {
      ids.add('0$digits');
      ids.add('63$digits');
      ids.add('+63$digits');
    }

    return ids;
  }

  /// Update current user ID (call after login)
  void setUserId(String? userId) {
    _currentUserId = userId;
    if (userId != null) {
      _saveFCMToken();
    }
  }

  /// Dispose resources
  void dispose() {
    _reportsSubscription?.cancel();
  }
}
