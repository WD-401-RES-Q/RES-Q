import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting registration data locally
class RegistrationPrefs {
  static const String _phoneKey = 'registration_phone_number';
  static const String _approvedLoginKey = 'approved_login_completed';

  /// Normalize phone value to local 10-digit format (9XXXXXXXXX).
  static String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 12 && digits.startsWith('63')) {
      return digits.substring(2);
    }

    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }

    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }

    return digits;
  }

  /// Save phone number locally for convenience (prefill login/registration).
  static Future<void> savePhoneNumber(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return;
    await prefs.setString(_phoneKey, normalized);
  }

  /// Get saved phone number (without +63 prefix)
  static Future<String?> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_phoneKey);
    if (saved == null || saved.isEmpty) return null;

    final normalized = _normalizePhone(saved);
    if (normalized.isNotEmpty && normalized != saved) {
      // Migrate legacy values (e.g. +63XXXXXXXXXX) to 10-digit local format.
      await prefs.setString(_phoneKey, normalized);
    }
    return normalized.isEmpty ? null : normalized;
  }

  /// Clear saved phone number (e.g., when switching accounts on this device).
  static Future<void> clearPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }

  /// Mark whether this device has completed an approved account login.
  /// Used to switch Login UI between editable phone input and compact saved phone.
  static Future<void> setApprovedLoginCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    if (completed) {
      await prefs.setBool(_approvedLoginKey, true);
      return;
    }
    await prefs.remove(_approvedLoginKey);
  }

  /// Returns true when the user previously logged in with an approved account.
  static Future<bool> isApprovedLoginCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_approvedLoginKey) ?? false;
  }
}
