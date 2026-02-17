import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/security_hash.dart';

class PhoneLookupResult {
  const PhoneLookupResult({
    required this.hasSemiAdminAccount,
    required this.hasApprovedAccount,
    required this.isPendingAccount,
    this.isBannedAccount = false,
    this.isPermanentBan = false,
    this.bannedUntil,
    this.banReasons = const <String>[],
  });

  final bool hasSemiAdminAccount;
  final bool hasApprovedAccount;
  final bool isPendingAccount;
  final bool isBannedAccount;
  final bool isPermanentBan;
  final DateTime? bannedUntil;
  final List<String> banReasons;

  bool get hasAnyAccount => hasSemiAdminAccount || hasApprovedAccount;
  bool get hasRegistrationConflict => hasApprovedAccount || isPendingAccount;
  bool get isTemporaryBan => isBannedAccount && !isPermanentBan;
}

class _PhoneLookupCacheEntry {
  const _PhoneLookupCacheEntry({required this.result, required this.checkedAt});

  final PhoneLookupResult result;
  final DateTime checkedAt;
}

class PhoneLookupService {
  PhoneLookupService._();

  static final PhoneLookupService instance = PhoneLookupService._();

  static const Duration _cacheTtl = Duration(seconds: 12);
  static const Duration _defaultDebounceDelay = Duration(milliseconds: 300);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, _PhoneLookupCacheEntry> _statusCache = {};
  final Map<String, Future<PhoneLookupResult>> _inFlightLookups = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, Completer<PhoneLookupResult?>> _debounceCompleters = {};
  final Map<String, int> _debounceTokens = {};

  bool _isBannedStatus(dynamic accountStatus) {
    return accountStatus is String &&
        accountStatus.trim().toUpperCase() == 'BANNED';
  }

  bool _isPermanentBan(Map<String, dynamic> data, bool isBanned) {
    if (!isBanned) {
      return false;
    }
    if (data['isPermanent'] == true) {
      return true;
    }
    final banType = (data['banType'] ?? '').toString().trim().toLowerCase();
    if (banType == 'permanent') {
      return true;
    }
    return data['bannedUntil'] == null;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is Map<String, dynamic>) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        final nanos = nanoseconds is int
            ? nanoseconds
            : (nanoseconds is num ? nanoseconds.toInt() : 0);
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000) + (nanos ~/ 1000000),
        );
      }
    }
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _queryCollectionByPhone({
    required String collection,
    required String phone,
  }) async {
    final phoneHash = SecurityHash.sha256Hex(phone);
    final hashedQuery = await _firestore
        .collection(collection)
        .where('contactNumber_hash', isEqualTo: phoneHash)
        .limit(1)
        .get();
    if (hashedQuery.docs.isNotEmpty) {
      return hashedQuery;
    }
    return _firestore
        .collection(collection)
        .where('contactNumber', isEqualTo: phone)
        .limit(1)
        .get();
  }

  PhoneLookupResult? readCachedAccountStatus(String phone) {
    final cached = _statusCache[phone];
    if (cached == null) return null;
    final cacheAge = DateTime.now().difference(cached.checkedAt);
    if (cacheAge > _cacheTtl) {
      _statusCache.remove(phone);
      return null;
    }
    return cached.result;
  }

  Future<PhoneLookupResult> lookupAccountStatus(
    String phone, {
    bool useCache = true,
  }) async {
    if (useCache) {
      final cached = readCachedAccountStatus(phone);
      if (cached != null) {
        return cached;
      }
    }

    final inFlight = _inFlightLookups[phone];
    if (inFlight != null) {
      return inFlight;
    }

    final lookupFuture = _lookupAccountStatusUncached(phone);
    _inFlightLookups[phone] = lookupFuture;

    try {
      final result = await lookupFuture;
      _statusCache[phone] = _PhoneLookupCacheEntry(
        result: result,
        checkedAt: DateTime.now(),
      );
      return result;
    } finally {
      _inFlightLookups.remove(phone);
    }
  }

  Future<PhoneLookupResult> _lookupAccountStatusUncached(String phone) async {
    final queries = await Future.wait([
      _queryCollectionByPhone(collection: 'semi_admins', phone: phone),
      _queryCollectionByPhone(collection: 'approved_users', phone: phone),
      _queryCollectionByPhone(collection: 'pending_users', phone: phone),
    ]);

    final approvedQuery = queries[1];
    Map<String, dynamic> approvedData = const <String, dynamic>{};
    if (approvedQuery.docs.isNotEmpty) {
      approvedData = approvedQuery.docs.first.data();
    }
    final isBanned = _isBannedStatus(approvedData['accountStatus']);
    final isPermanentBan = _isPermanentBan(approvedData, isBanned);
    final banReasons = (approvedData['banReasons'] as List<dynamic>? ?? [])
        .map((reason) => reason.toString().trim())
        .where((reason) => reason.isNotEmpty)
        .toList(growable: false);

    return PhoneLookupResult(
      hasSemiAdminAccount: queries[0].docs.isNotEmpty,
      hasApprovedAccount: approvedQuery.docs.isNotEmpty,
      isPendingAccount: queries[2].docs.isNotEmpty,
      isBannedAccount: isBanned,
      isPermanentBan: isPermanentBan,
      bannedUntil: _toDateTime(approvedData['bannedUntil']),
      banReasons: banReasons,
    );
  }

  Future<bool> hasRegistrationConflict(
    String phone, {
    bool useCache = true,
  }) async {
    final status = await lookupAccountStatus(phone, useCache: useCache);
    return status.hasRegistrationConflict;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> getFirstApprovedUserDoc(
    String phone,
  ) async {
    final approvedQuery = await _queryCollectionByPhone(
      collection: 'approved_users',
      phone: phone,
    );
    if (approvedQuery.docs.isEmpty) {
      return null;
    }
    return approvedQuery.docs.first;
  }

  Future<PhoneLookupResult?> debouncedLookupAccountStatus({
    required String scopeKey,
    required String phone,
    Duration delay = _defaultDebounceDelay,
    bool useCache = true,
  }) {
    _debounceTimers.remove(scopeKey)?.cancel();

    final previousCompleter = _debounceCompleters.remove(scopeKey);
    if (previousCompleter != null && !previousCompleter.isCompleted) {
      previousCompleter.complete(null);
    }

    final token = (_debounceTokens[scopeKey] ?? 0) + 1;
    _debounceTokens[scopeKey] = token;

    final completer = Completer<PhoneLookupResult?>();
    _debounceCompleters[scopeKey] = completer;

    _debounceTimers[scopeKey] = Timer(delay, () async {
      try {
        final result = await lookupAccountStatus(phone, useCache: useCache);
        if (_debounceTokens[scopeKey] != token) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (_debounceTokens[scopeKey] != token) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        _debounceTimers.remove(scopeKey);
        _debounceCompleters.remove(scopeKey);
      }
    });

    return completer.future;
  }

  void cancelDebounce(String scopeKey) {
    _debounceTokens[scopeKey] = (_debounceTokens[scopeKey] ?? 0) + 1;
    _debounceTimers.remove(scopeKey)?.cancel();
    final completer = _debounceCompleters.remove(scopeKey);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }
}
