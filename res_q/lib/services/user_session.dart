class UserSession {
  static Map<String, dynamic>? currentUserData;
  static String? currentUsername;
  static String? activeReportId;
  static Map<String, dynamic>? activeReportData;

  static void setUserData(Map<String, dynamic> data) {
    currentUserData = data;
    currentUsername = data['username'] as String?;
  }

  static void clear() {
    currentUserData = null;
    currentUsername = null;
    activeReportId = null;
    activeReportData = null;
  }

  static void setActiveReport({
    required String reportId,
    required Map<String, dynamic> reportData,
  }) {
    activeReportId = reportId;
    activeReportData = reportData;
  }

  static void clearActiveReport() {
    activeReportId = null;
    activeReportData = null;
  }
}
