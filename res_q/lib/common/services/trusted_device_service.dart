import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TrustedDeviceService {
  TrustedDeviceService._();

  static final TrustedDeviceService instance = TrustedDeviceService._();

  static const String _trustedPhoneKey = 'trusted_device_phone';
  static const String _trustedAtKey = 'trusted_device_last_activity_at';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _normalizeToE164(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('9')) {
      return '+63$digits';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+63${digits.substring(1)}';
    }
    if (digits.length == 12 && digits.startsWith('63')) {
      return '+$digits';
    }
    if (value.trim().startsWith('+')) {
      return '+${digits.isNotEmpty ? digits : value.trim().substring(1)}';
    }
    return value.trim();
  }

  Future<void> markTrusted(String phone) async {
    final normalizedPhone = _normalizeToE164(phone);
    if (normalizedPhone.isEmpty) return;

    try {
      await _storage.write(key: _trustedPhoneKey, value: normalizedPhone);
      await touchTrustedActivity();
    } catch (e) {
      debugPrint('TrustedDeviceService markTrusted failed: $e');
    }
  }

  Future<void> touchTrustedActivity() async {
    try {
      await _storage.write(
        key: _trustedAtKey,
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('TrustedDeviceService touchTrustedActivity failed: $e');
    }
  }

  Future<String?> getTrustedPhone() async {
    try {
      final value = await _storage.read(key: _trustedPhoneKey);
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return _normalizeToE164(value);
    } catch (e) {
      debugPrint('TrustedDeviceService getTrustedPhone failed: $e');
      return null;
    }
  }

  Future<bool> isTrustedPhone(String phone) async {
    final normalizedPhone = _normalizeToE164(phone);
    final trustedPhone = await getTrustedPhone();
    return trustedPhone != null && trustedPhone == normalizedPhone;
  }

  Future<DateTime?> getLastTrustedActivity() async {
    try {
      final value = await _storage.read(key: _trustedAtKey);
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    } catch (e) {
      debugPrint('TrustedDeviceService getLastTrustedActivity failed: $e');
      return null;
    }
  }

  Future<void> clearTrustedDevice() async {
    try {
      await _storage.delete(key: _trustedPhoneKey);
      await _storage.delete(key: _trustedAtKey);
    } catch (e) {
      debugPrint('TrustedDeviceService clearTrustedDevice failed: $e');
    }
  }
}
