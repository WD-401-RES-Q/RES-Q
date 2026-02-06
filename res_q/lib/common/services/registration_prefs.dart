import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting registration data locally
class RegistrationPrefs {
  static const String _phoneKey = 'registration_phone_number';

  /// Save phone number locally for convenience (prefill login/registration).
  static Future<void> savePhoneNumber(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, phone);
  }

  /// Get saved phone number (without +63 prefix)
  static Future<String?> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  /// Clear saved phone number (e.g., when switching accounts on this device).
  static Future<void> clearPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }
}
