import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
    final phoneNumber = (data['contactNumber'] ?? data['phoneNumber'])
        ?.toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      _userId = phoneNumber;
      debugPrint('📱 UserSession: Set userId from phone number: $_userId');
    } else {
      // Fallback to Firebase Auth uid if no phone number
      _userId = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('🔐 UserSession: Set userId from Firebase Auth: $_userId');
    }
  }

  static void setUserId(String? userId) {
    _userId = userId;
    debugPrint('🆔 UserSession: Manually set userId to: $_userId');
  }

  static String? getUserId() {
    // Return the stored userId (phone number), don't fall back to Firebase Auth
    return _userId;
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
