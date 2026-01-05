class UserSession {
  static Map<String, dynamic>? currentUserData;
  static String? currentUsername;

  static void setUserData(Map<String, dynamic> data) {
    currentUserData = data;
    currentUsername = data['username'] as String?;
  }

  static void clear() {
    currentUserData = null;
    currentUsername = null;
  }
}
