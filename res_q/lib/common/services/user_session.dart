/// UserSession manages the current user's session data.
///
/// MIGRATION NOTE (2026-02-03):
/// - Changed primary identifier from username to phone number
/// - getUserId() now returns sanitized phone number (digits only)
/// - Phone number extracted from 'contactNumber' or 'phoneNumber' fields
/// - ⚠️ IMPORTANT: All users MUST have a phone number for voting and reporting
///
/// Example userId values:
/// - "639123456789" (phone number, REQUIRED)
///
/// Note: Users without phone numbers cannot vote or submit reports due to
/// Firestore security rules requiring phone number verification.
///
/// Legacy data may still reference 'username' field - update as needed.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../utils/phone_utils.dart';

class ActiveReport {
  ActiveReport({required this.reportId, required this.reportData});

  final String reportId;
  final Map<String, dynamic> reportData;
}

class UserSession {
  static Map<String, dynamic>? currentUserData;
  static String? _userId;
  static final List<ActiveReport> _activeReports = [];

  static void setUserData(Map<String, dynamic> data) {
    currentUserData = data;
    // Extract phone number from user data and use it as the primary identifier
    // This makes it easier to track users in Firestore
    // Note: Firestore uses 'contactNumber' as the primary field
    final phoneNumber = _extractPhoneNumber(data);
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      _userId = phoneNumber;
      debugPrint('📱 UserSession: Set userId from phone number: $_userId');
    } else {
      _userId = null;
      debugPrint('⚠️ UserSession: No phone number found in user data');
    }
  }

  /// Extract and sanitize phone number from user data
  static String? _extractPhoneNumber([Map<String, dynamic>? data]) {
    final userData = data ?? currentUserData;
    if (userData == null) return null;

    final phoneNumber = PhoneUtils.sanitize(
      userData['contactNumber'] ?? userData['phoneNumber'],
    );
    return phoneNumber.isNotEmpty ? phoneNumber : null;
  }

  static void setUserId(String? userId) {
    _userId = userId;
    debugPrint('🆔 UserSession: Manually set userId to: $_userId');
  }

  /// Get the current user's ID (phone number).
  /// Throws an exception if no phone number is available.
  /// Note: This should never happen in production since registration requires phone numbers.
  static String getUserId() {
    final phoneNumber = _extractPhoneNumber();
    if (phoneNumber == null || phoneNumber.isEmpty) {
      // CRITICAL: This indicates a data inconsistency
      final userId = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('🚨 CRITICAL: User $userId logged in without phone number!');

      // Log to Crashlytics for monitoring
      FirebaseCrashlytics.instance.recordError(
        Exception('User logged in without phone number'),
        StackTrace.current,
        reason: 'User ID: $userId, UserData: ${currentUserData?.toString()}',
        fatal: false,
      );

      throw Exception(
        'Your account is missing a phone number. Please contact support or log out and register again.',
      );
    }
    return phoneNumber;
  }

  static void clear() {
    currentUserData = null;
    _userId = null;
    _activeReports.clear();
  }

  static List<ActiveReport> get activeReports =>
      List<ActiveReport>.unmodifiable(_activeReports);

  static int get activeReportCount => _activeReports.length;

  static ActiveReport? get latestActiveReport =>
      _activeReports.isNotEmpty ? _activeReports.last : null;

  static void addActiveReport({
    required String reportId,
    required Map<String, dynamic> reportData,
  }) {
    _activeReports.removeWhere((report) => report.reportId == reportId);
    _activeReports.add(
      ActiveReport(reportId: reportId, reportData: reportData),
    );
  }

  static void removeActiveReport(String reportId) {
    _activeReports.removeWhere((report) => report.reportId == reportId);
  }
}
