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

  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    if (_initialized) {
      await _handleInitialMessage();
      return;
    }

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

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        return;
      }
      await _firestore.collection('user_tokens').doc(userId).set({
        'tokens': FieldValue.arrayRemove([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to clear FCM token: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      debugPrint('Failed to request FCM permissions: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
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
        >();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.requestNotificationsPermission();
  }

  void _setupForegroundAndTapHandlers() {
    FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleMessageTap(message);
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
      'resq_dispatch_updates',
      'RES-Q Dispatch Updates',
      channelDescription:
          'Deployment, responder status, and responder comments',
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
      payload: reportId != null ? 'report:$reportId' : null,
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    if (_lastHandledMessageId != null &&
        _lastHandledMessageId == message.messageId) {
      return;
    }
    _lastHandledMessageId = message.messageId;
    final reportId = _extractReportIdFromData(message.data);
    if (reportId == null || reportId.isEmpty) {
      return;
    }
    _openReportMap(reportId);
  }

  String? _extractReportIdFromData(Map<String, dynamic> data) {
    final keys = ['reportId', 'report_id', 'id'];
    for (final key in keys) {
      final raw = data[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }
    return null;
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
    } catch (e) {
      debugPrint('Failed to open report map from notification: $e');
    }
  }
}
