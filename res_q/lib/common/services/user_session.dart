class ActiveReport {
  ActiveReport({required this.reportId, required this.reportData});

  final String reportId;
  final Map<String, dynamic> reportData;
}

class UserSession {
  static Map<String, dynamic>? currentUserData;
  static String? currentUsername;
  static String? _userId;
  static final List<ActiveReport> _activeReports = [];

  static void setUserData(Map<String, dynamic> data) {
    currentUserData = data;
    currentUsername = data['username'] as String?;
    // Try to get userId from various possible fields
    _userId = data['id'] as String? ??
              data['uid'] as String? ??
              data['userId'] as String? ??
              currentUsername;
  }

  static void setUserId(String? userId) {
    _userId = userId;
  }

  static String? getUserId() {
    return _userId ?? currentUsername;
  }

  static void clear() {
    currentUserData = null;
    currentUsername = null;
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
