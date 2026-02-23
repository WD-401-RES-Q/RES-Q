import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/security_hash.dart';
import 'phone_lookup_service.dart';

enum PhoneCheckStatus { approved, pending, notFound }

class AuthLoginResult {
  const AuthLoginResult({
    required this.userId,
    required this.token,
    this.userData = const <String, dynamic>{},
  });

  final String userId;
  final String token;
  final Map<String, dynamic> userData;
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApiService {
  AuthApiService._();

  static final AuthApiService instance = AuthApiService._();

  static const String _tokenStorageKey = 'auth_token';
  static const String _baseUrl = String.fromEnvironment(
    'RESQ_AUTH_API_BASE_URL',
    defaultValue: '',
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhoneLookupService _phoneLookupService = PhoneLookupService.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final http.Client _client = http.Client();

  final Map<String, String> _verificationIds = <String, String>{};

  bool get _useRemoteApi => _baseUrl.trim().isNotEmpty;

  Uri _endpoint(String path) {
    final normalizedBase = _baseUrl.trim().replaceAll(RegExp(r'\/+$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, String> _jsonHeaders() => const <String, String>{
    'Content-Type': 'application/json',
  };

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('9')) return '+63$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+63${digits.substring(1)}';
    }
    if (digits.length == 12 && digits.startsWith('63')) return '+$digits';
    if (phone.trim().startsWith('+')) return '+${digits.trim()}';
    return phone.trim();
  }

  String _phoneHash(String phone) =>
      SecurityHash.sha256Hex(_normalizePhone(phone));

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final response = await _client
        .post(_endpoint(path), headers: _jsonHeaders(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> payload = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          (payload['message'] ?? payload['error'] ?? 'Request failed')
              .toString();
      throw AuthApiException(message);
    }

    return payload;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _queryCollectionByPhone({
    required String collection,
    required String phone,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final hashedQuery = await _firestore
        .collection(collection)
        .where('contactNumber_hash', isEqualTo: _phoneHash(normalizedPhone))
        .limit(1)
        .get();
    if (hashedQuery.docs.isNotEmpty) {
      return hashedQuery;
    }
    return _firestore
        .collection(collection)
        .where('contactNumber', isEqualTo: normalizedPhone)
        .limit(1)
        .get();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _firstDocByPhone({
    required String collection,
    required String phone,
  }) async {
    final query = await _queryCollectionByPhone(
      collection: collection,
      phone: phone,
    );
    if (query.docs.isEmpty) return null;
    return query.docs.first;
  }

  bool _isApproved(Map<String, dynamic> data) {
    final isApproved = data['isApproved'];
    if (isApproved is bool) return isApproved;
    final status = (data['accountStatus'] as String?)?.trim().toLowerCase();
    return status == 'approved';
  }

  bool _pinMatches(Map<String, dynamic> data, String pinHash) {
    final storedHash = (data['hashedPin'] ?? data['pin_hash'])?.toString();
    return storedHash != null && storedHash.isNotEmpty && storedHash == pinHash;
  }

  String _issueLocalToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: _tokenStorageKey, value: token);
  }

  Future<String?> readAuthToken() async {
    return _secureStorage.read(key: _tokenStorageKey);
  }

  Future<void> clearAuthToken() async {
    await _secureStorage.delete(key: _tokenStorageKey);
  }

  Future<PhoneCheckStatus> checkPhone({required String phone}) async {
    final normalizedPhone = _normalizePhone(phone);

    if (_useRemoteApi) {
      final payload = await _postJson(
        '/api/auth/check-phone',
        body: <String, dynamic>{'phone': normalizedPhone},
      );
      final status = (payload['status'] ?? '').toString().trim().toLowerCase();
      switch (status) {
        case 'approved':
          return PhoneCheckStatus.approved;
        case 'pending':
          return PhoneCheckStatus.pending;
        default:
          return PhoneCheckStatus.notFound;
      }
    }

    final lookup = await _phoneLookupService.lookupAccountStatus(
      normalizedPhone,
      useCache: false,
    );
    if (lookup.hasApprovedAccount) return PhoneCheckStatus.approved;
    if (lookup.isPendingAccount) return PhoneCheckStatus.pending;
    return PhoneCheckStatus.notFound;
  }

  Future<void> resendOtp({required String phone}) async {
    final normalizedPhone = _normalizePhone(phone);

    if (_useRemoteApi) {
      await _postJson(
        '/api/auth/resend-otp',
        body: <String, dynamic>{'phone': normalizedPhone},
      );
      return;
    }

    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
        } catch (_) {}
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(
            AuthApiException(e.message ?? 'Unable to send OTP.'),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationIds[normalizedPhone] = verificationId;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationIds[normalizedPhone] = verificationId;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future.timeout(const Duration(seconds: 70));
  }

  Future<void> verifyOtp({required String phone, required String otp}) async {
    final normalizedPhone = _normalizePhone(phone);

    if (_useRemoteApi) {
      final payload = await _postJson(
        '/api/auth/verify-otp',
        body: <String, dynamic>{'phone': normalizedPhone, 'otp': otp.trim()},
      );
      final verified = payload['verified'] == true;
      if (!verified) {
        throw const AuthApiException('Incorrect code');
      }
      return;
    }

    final verificationId = _verificationIds[normalizedPhone];
    if (verificationId == null || verificationId.isEmpty) {
      throw const AuthApiException(
        'Verification session expired. Resend code.',
      );
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp.trim(),
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('verifyOtp fallback failed: ${e.code} ${e.message}');
      }
      throw const AuthApiException('Incorrect code');
    }
  }

  Future<String> register({
    required String phone,
    required String name,
    String? email,
  }) async {
    final normalizedPhone = _normalizePhone(phone);

    if (_useRemoteApi) {
      final payload = await _postJson(
        '/api/auth/register',
        body: <String, dynamic>{
          'phone': normalizedPhone,
          'name': name.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );
      final userId = (payload['userId'] ?? '').toString().trim();
      if (userId.isEmpty) {
        throw const AuthApiException('Unable to create account.');
      }
      return userId;
    }

    final userId = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    await _firestore.collection('pending_users').doc(userId).set({
      'fullName': name.trim(),
      'email': email?.trim().isEmpty ?? true ? null : email?.trim(),
      'contactNumber': normalizedPhone,
      'phoneNumber': normalizedPhone,
      'contactNumber_hash': _phoneHash(normalizedPhone),
      'accountStatus': 'pending',
      'status': 'pending',
      'isApproved': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return userId;
  }

  Future<void> setPin({
    required String phone,
    required String pin,
    String? userId,
    String? name,
    String? email,
    bool resetPin = false,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final pinHash = SecurityHash.sha256Hex(pin);

    if (_useRemoteApi) {
      await _postJson(
        '/api/auth/set-pin',
        body: <String, dynamic>{
          'phone': normalizedPhone,
          'pin': pinHash,
          'pinHash': pinHash,
          'resetPin': resetPin,
          if (userId != null && userId.trim().isNotEmpty) 'userId': userId,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );
      return;
    }

    if (resetPin) {
      final approvedDoc = await _firstDocByPhone(
        collection: 'approved_users',
        phone: normalizedPhone,
      );
      if (approvedDoc == null) {
        throw const AuthApiException('Approved account not found.');
      }
      await _firestore.collection('approved_users').doc(approvedDoc.id).set({
        'pin': FieldValue.delete(),
        'hashedPin': pinHash,
        'pin_hash': pinHash,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final targetDocId = (userId ?? '').trim();
    if (targetDocId.isNotEmpty) {
      await _firestore.collection('pending_users').doc(targetDocId).set({
        'fullName': name?.trim(),
        'email': email?.trim().isEmpty ?? true ? null : email?.trim(),
        'contactNumber': normalizedPhone,
        'phoneNumber': normalizedPhone,
        'contactNumber_hash': _phoneHash(normalizedPhone),
        'pin': FieldValue.delete(),
        'hashedPin': pinHash,
        'pin_hash': pinHash,
        'accountStatus': 'pending',
        'status': 'pending',
        'isApproved': false,
        'pinCreatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final pendingDoc = await _firstDocByPhone(
      collection: 'pending_users',
      phone: normalizedPhone,
    );
    if (pendingDoc == null) {
      throw const AuthApiException('Pending account not found.');
    }
    await _firestore.collection('pending_users').doc(pendingDoc.id).set({
      'pin': FieldValue.delete(),
      'hashedPin': pinHash,
      'pin_hash': pinHash,
      'pinCreatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AuthLoginResult> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final pinHash = SecurityHash.sha256Hex(pin);

    if (_useRemoteApi) {
      final payload = await _postJson(
        '/api/auth/login-pin',
        body: <String, dynamic>{
          'phone': normalizedPhone,
          'pin': pinHash,
          'pinHash': pinHash,
        },
      );
      final token = (payload['token'] ?? '').toString().trim();
      if (token.isEmpty) {
        throw const AuthApiException('Invalid login response.');
      }
      final userId = (payload['userId'] ?? '').toString().trim();
      await saveAuthToken(token);
      return AuthLoginResult(
        userId: userId.isEmpty
            ? normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '')
            : userId,
        token: token,
        userData: payload,
      );
    }

    final approvedDoc = await _firstDocByPhone(
      collection: 'approved_users',
      phone: normalizedPhone,
    );
    if (approvedDoc == null) {
      throw const AuthApiException(
        'No approved account found for this number.',
      );
    }

    final data = approvedDoc.data();
    if (!_isApproved(data)) {
      throw const AuthApiException('Your account is pending admin approval.');
    }
    if (!_pinMatches(data, pinHash)) {
      throw const AuthApiException('Incorrect PIN');
    }

    await _firestore.collection('approved_users').doc(approvedDoc.id).set({
      'lastLoginTimestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final token = _issueLocalToken();
    await saveAuthToken(token);
    return AuthLoginResult(
      userId: approvedDoc.id,
      token: token,
      userData: <String, dynamic>{...data, 'docId': approvedDoc.id},
    );
  }
}
