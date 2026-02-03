/// Utility functions for phone number handling
class PhoneUtils {
  /// Sanitize a phone number by removing all non-digit characters
  ///
  /// Examples:
  /// - "+63-912-345-6789" → "639123456789"
  /// - "(123) 456-7890" → "1234567890"
  static String sanitize(String? phoneNumber) {
    if (phoneNumber == null) return '';
    return phoneNumber.replaceAll(RegExp(r'\D'), '');
  }

  /// Check if a string contains only digits (valid phone number format)
  static bool isValidFormat(String phoneNumber) {
    return RegExp(r'^[0-9]+$').hasMatch(phoneNumber);
  }
}
