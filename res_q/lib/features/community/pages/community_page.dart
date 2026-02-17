import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../common/services/frame_timing_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/utils/security_hash.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';

void _debugLog(Object? message) {
  if (kDebugMode) {
    debugPrint('$message');
  }
}

int _nonNegativeInt(dynamic value) {
  final int parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.toInt();
  } else {
    parsed = int.tryParse(value?.toString() ?? '') ?? 0;
  }
  return parsed < 0 ? 0 : parsed;
}

class _VoteStorageBackend {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _useApprovedUsersFallback = false;
  DocumentReference<Map<String, dynamic>>? _cachedApprovedUsersDocRef;

  bool get usingApprovedUsersFallback => _useApprovedUsersFallback;

  void _cacheResolvedDocId(Map<String, dynamic>? userData, String docId) {
    if (userData == null || docId.isEmpty) return;
    try {
      userData['docId'] = docId;
    } catch (_) {
      // Some user maps are read-only; cache stays in-memory via _cachedApprovedUsersDocRef.
    }
  }

  Iterable<String> _contactCandidates(
    String userPhone,
    Map<String, dynamic>? userData,
  ) sync* {
    final rawContact = (userData?['contactNumber'] ?? userData?['phoneNumber'])
        .toString()
        .trim();
    if (rawContact.isNotEmpty) {
      yield rawContact;
    }
    if (userPhone.isNotEmpty) {
      yield userPhone;
      if (!userPhone.startsWith('+')) {
        yield '+$userPhone';
      }
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveApprovedUsersDocRef({
    required String userPhone,
    required Map<String, dynamic>? userData,
  }) async {
    if (_cachedApprovedUsersDocRef != null) {
      return _cachedApprovedUsersDocRef;
    }

    final docId = (userData?['docId'] ?? userData?['id'] ?? '')
        .toString()
        .trim();
    if (docId.isNotEmpty) {
      _cachedApprovedUsersDocRef = _firestore
          .collection('approved_users')
          .doc(docId);
      return _cachedApprovedUsersDocRef;
    }

    final candidates = _contactCandidates(userPhone, userData).toList();

    for (final candidate in candidates) {
      final query = await _firestore
          .collection('approved_users')
          .where(
            'contactNumber_hash',
            isEqualTo: SecurityHash.sha256Hex(candidate),
          )
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        _cachedApprovedUsersDocRef = query.docs.first.reference;
        _cacheResolvedDocId(userData, query.docs.first.id);
        return _cachedApprovedUsersDocRef;
      }
    }

    for (final candidate in candidates) {
      final query = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: candidate)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        _cachedApprovedUsersDocRef = query.docs.first.reference;
        _cacheResolvedDocId(userData, query.docs.first.id);
        return _cachedApprovedUsersDocRef;
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> readVotePayload({
    required String userPhone,
    required Map<String, dynamic>? userData,
  }) async {
    if (!_useApprovedUsersFallback) {
      try {
        final snapshot = await _firestore
            .collection('userVotes')
            .doc(userPhone)
            .get();
        return snapshot.data();
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        _useApprovedUsersFallback = true;
      }
    }

    final approvedRef = await _resolveApprovedUsersDocRef(
      userPhone: userPhone,
      userData: userData,
    );
    if (approvedRef == null) {
      return null;
    }
    final approvedSnapshot = await approvedRef.get();
    return approvedSnapshot.data();
  }

  Future<void> writeVotePayload({
    required String userPhone,
    required Map<String, dynamic>? userData,
    required Map<String, dynamic> payload,
  }) async {
    if (!_useApprovedUsersFallback) {
      try {
        await _firestore
            .collection('userVotes')
            .doc(userPhone)
            .set(payload, SetOptions(merge: true));
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        _useApprovedUsersFallback = true;
      }
    }

    final approvedRef = await _resolveApprovedUsersDocRef(
      userPhone: userPhone,
      userData: userData,
    );
    if (approvedRef == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Unable to resolve approved_users vote fallback target.',
      );
    }
    await approvedRef.set(payload, SetOptions(merge: true));
  }
}

class CommunityPage extends StatefulWidget {
  final String? initialReportId;
  final VoidCallback? onInitialReportConsumed;

  const CommunityPage({
    super.key,
    this.initialReportId,
    this.onInitialReportConsumed,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with WidgetsBindingObserver {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFAC1B22);
  static const appGreen = Color(0xFF00A458); // True green
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const commentBlue = Color(0xFF2563EB);
  static const statusGreen = Color(0xFF00A458); // Approved
  static const statusYellow = Color(0xFFFFC806); // Under Review
  static const statusRed = Color(0xFFAC1B22); // Flagged
  static const int _reportFeedLimit = 150;

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';
  String _selectedTimeFilter = 'All Time';
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _announcements = [];
  Map<String, String> _userVotes = {}; // reportId -> 'green' or 'red'
  bool _checkedLegacyVotes = false;
  bool _canSyncVotesWithFirestore = true;
  bool _hasLoggedVotesPermissionIssue = false;
  String? _pendingInitialReportId;
  bool _initialReportDialogOpened = false;
  bool _isResolvingInitialReport = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _announcementsSubscription;
  Map<String, int> _reportIndexById = const {};
  final ValueNotifier<List<Map<String, dynamic>>> _visibleReportsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  final _VoteStorageBackend _voteStorageBackend = _VoteStorageBackend();

  @override
  void initState() {
    super.initState();
    FrameTimingService.instance.setCurrentScreen('CommunityPage');
    WidgetsBinding.instance.addObserver(this);
    _pendingInitialReportId = _normalizeInitialReportId(widget.initialReportId);
    _selectedFilter = _normalizeFilter(_selectedFilter);
    _recomputeDerivedReportState();
    _subscribeToReports();
    _subscribeToAnnouncements();
    // Delay loading votes to ensure UserSession is initialized after login
    _initializeVotes();
  }

  @override
  void didUpdateWidget(covariant CommunityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReportId != oldWidget.initialReportId) {
      _pendingInitialReportId = _normalizeInitialReportId(
        widget.initialReportId,
      );
      _initialReportDialogOpened = false;
      _tryOpenPendingInitialReport();
    }
  }

  Future<void> _initializeVotes() async {
    // Wait a moment for UserSession to be fully initialized after login
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadUserVotes();
  }

  /// Get the logged-in user's phone number directly from currentUserData
  String? _getLoggedInUserPhone() {
    final userData = UserSession.currentUserData;
    if (userData == null) {
      try {
        final fallbackUserId = UserSession.getUserId();
        if (fallbackUserId.isNotEmpty) {
          return fallbackUserId.replaceAll(RegExp(r'[^0-9]'), '');
        }
      } catch (_) {}
      _debugLog('No user data available');
      return null;
    }

    // Try different possible field names for phone number.
    String? phone =
        userData['contactNumber']?.toString() ??
        userData['phoneNumber']?.toString() ??
        userData['phone']?.toString() ??
        userData['mobileNumber']?.toString();

    if (phone != null) {
      phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    }

    if (phone != null && phone.isNotEmpty) {
      _debugLog('Found logged-in user phone: $phone');
      return phone;
    }

    try {
      final fallbackUserId = UserSession.getUserId();
      if (fallbackUserId.isNotEmpty) {
        final normalized = fallbackUserId.replaceAll(RegExp(r'[^0-9]'), '');
        if (normalized.isNotEmpty) {
          _debugLog('Using fallback session userId for votes: $normalized');
          return normalized;
        }
      }
    } catch (_) {}

    _debugLog('No phone number found for vote sync');
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportsSubscription?.cancel();
    _announcementsSubscription?.cancel();
    _visibleReportsNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload user votes when app resumes (comes back to foreground)
    if (state == AppLifecycleState.resumed) {
      _loadUserVotes();
    }
  }

  /// Called when the page becomes visible again (e.g., navigating back)
  void reloadVotesIfNeeded() {
    _loadUserVotes();
  }

  void _subscribeToAnnouncements() {
    _announcementsSubscription = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _announcements = snapshot.docs.map((doc) {
                final data = doc.data();
                return {
                  'id': doc.id,
                  'title': data['title'] ?? '',
                  'content': data['content'] ?? '',
                  'imageUrl': data['imageUrl'] ?? '',
                  'createdAt': data['createdAt'],
                };
              }).toList();
            });
          },
          onError: (e) {
            _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to load announcements: $e');
          },
        );
  }

  Future<void> _loadUserVotes() async {
    if (!_canSyncVotesWithFirestore) {
      return;
    }
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) {
      _debugLog('No phone number available for loading votes');
      return;
    }
    try {
      _debugLog('Loading votes for phone: $userPhone');
      await _migrateLegacyVotesIfNeeded(userPhone);
      final data = await _voteStorageBackend.readVotePayload(
        userPhone: userPhone,
        userData: UserSession.currentUserData,
      );
      final rawVotes = data?['votes'];
      final loadedVotes = rawVotes is Map
          ? rawVotes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : <String, String>{};
      if (mounted) {
        _debugLog('Loaded ${loadedVotes.length} votes from Firestore');
        _debugLog('Votes: $loadedVotes');
        _userVotes = loadedVotes;
        // Update reports with user votes
        _applyUserVotesToReports();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!_hasLoggedVotesPermissionIssue) {
          _hasLoggedVotesPermissionIssue = true;
          _debugLog(
            'Vote sync disabled: missing Firestore permission for vote storage.',
          );
        }
        _canSyncVotesWithFirestore = false;
        if (mounted) {
          _userVotes = {};
          _applyUserVotesToReports();
        }
        return;
      }
      _debugLog('Failed to load user votes: $e');
    } catch (e) {
      _debugLog('Failed to load user votes: $e');
    }
  }

  void _applyUserVotesToReports() {
    if (_reports.isEmpty) return;
    for (int i = 0; i < _reports.length; i++) {
      final reportId = _reports[i]['id'] as String?;
      if (reportId != null) {
        // Apply vote from _userVotes, default to 'none' if not found
        _reports[i]['userVote'] = _userVotes[reportId] ?? 'none';
      }
    }
    _recomputeDerivedReportState();
    _debugLog(
      'Applied ${_userVotes.length} user votes to ${_reports.length} reports',
    );
  }

  Future<void> _saveUserVote(String reportId, String vote) async {
    if (!_canSyncVotesWithFirestore) {
      return;
    }
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) {
      _debugLog('Cannot save vote: no phone number found');
      return;
    }
    final previousVote = _userVotes[reportId];
    try {
      // Update local cache
      if (vote == 'none') {
        _userVotes.remove(reportId);
      } else {
        _userVotes[reportId] = vote;
      }
      await _voteStorageBackend.writeVotePayload(
        userPhone: userPhone,
        userData: UserSession.currentUserData,
        payload: {'votes': _userVotes},
      );
      // Also save individual vote record for better tracking
      await _saveVoteRecord(reportId, vote, userPhone);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!_hasLoggedVotesPermissionIssue) {
          _hasLoggedVotesPermissionIssue = true;
          _debugLog(
            'Vote sync disabled: missing Firestore permission for vote storage.',
          );
        }
        _canSyncVotesWithFirestore = false;
      } else {
        _debugLog('Failed to save user vote: $e');
      }
      if (previousVote == null || previousVote == 'none') {
        _userVotes.remove(reportId);
      } else {
        _userVotes[reportId] = previousVote;
      }
      _applyUserVotesToReports();
    } catch (e) {
      _debugLog('Failed to save user vote: $e');
      if (previousVote == null || previousVote == 'none') {
        _userVotes.remove(reportId);
      } else {
        _userVotes[reportId] = previousVote;
      }
      _applyUserVotesToReports();
    }
  }

  /// Save individual vote record for easier tracking in Firestore
  Future<void> _saveVoteRecord(
    String reportId,
    String vote,
    String userPhone,
  ) async {
    try {
      // Find the report for better tracking
      final report = _reports.firstWhere(
        (r) => r['id'] == reportId,
        orElse: () => <String, dynamic>{},
      );
      final reportTitle = report['title']?.toString() ?? 'Unknown';
      // Use custom reportId if available, otherwise use Firestore doc ID
      final customReportId = report['reportId']?.toString() ?? reportId;

      // Save to voteRecords collection
      await FirebaseFirestore.instance.collection('voteRecords').add({
        'reportDocId': reportId, // Firestore document ID
        'reportId': customReportId, // Custom report ID (RPT-YYYYMMDD-XXXXXX)
        'reportTitle': reportTitle,
        'userPhone': userPhone,
        'voteType':
            vote, // 'green' (verify) or 'red' (report) or 'none' (removed)
        'timestamp': FieldValue.serverTimestamp(),
      });
      _debugLog(
        'ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â Vote record saved to voteRecords collection',
      );
    } catch (e) {
      _debugLog('ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Could not save vote record: $e');
      // Don't fail the main operation if this fails
    }
  }

  Future<void> _migrateLegacyVotesIfNeeded(String userId) async {
    if (_checkedLegacyVotes ||
        !_canSyncVotesWithFirestore ||
        _voteStorageBackend.usingApprovedUsersFallback) {
      return;
    }
    _checkedLegacyVotes = true;
    final legacyUsername = UserSession.currentUserData?['username']
        ?.toString()
        .trim();
    if (legacyUsername == null ||
        legacyUsername.isEmpty ||
        legacyUsername == userId) {
      return;
    }
    try {
      final legacyDoc = await FirebaseFirestore.instance
          .collection('userVotes')
          .doc(legacyUsername)
          .get();
      if (!legacyDoc.exists) return;
      final legacyData = legacyDoc.data() ?? {};
      final legacyVotes = Map<String, String>.from(legacyData['votes'] ?? {});
      if (legacyVotes.isEmpty) return;
      _userVotes.addAll(legacyVotes);
      await FirebaseFirestore.instance.collection('userVotes').doc(userId).set({
        'votes': _userVotes,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!_hasLoggedVotesPermissionIssue) {
          _hasLoggedVotesPermissionIssue = true;
          _debugLog(
            'Vote migration skipped: missing Firestore permission for userVotes.',
          );
        }
        // Keep vote sync enabled so fallback storage can still work.
        return;
      }
      _debugLog('Failed to migrate legacy votes: $e');
    } catch (e) {
      _debugLog('Failed to migrate legacy votes: $e');
    }
  }

  void _subscribeToReports() {
    _reportsSubscription?.cancel();
    _reportsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('reportedAt', descending: true)
        .limit(_reportFeedLimit)
        .snapshots()
        .listen(
          (snapshot) {
            final previousVotes = {
              for (final report in _reports)
                report['id']?.toString() ?? '': report['userVote'],
            };
            final reports = snapshot.docs.map(_mapReportFromDoc).toList();
            for (final report in reports) {
              final reportId = report['id']?.toString() ?? '';
              report['userVote'] =
                  _userVotes[reportId] ?? previousVotes[reportId] ?? 'none';
            }
            if (!mounted) return;
            _reports = reports;
            _recomputeDerivedReportState();
            _tryOpenPendingInitialReport();
            _debugLog(
              'ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Loaded ${reports.length} reports from Firestore',
            );
          },
          onError: (e) {
            _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to load reports: $e');
          },
        );
  }

  String? _normalizeInitialReportId(String? reportId) {
    final normalized = (reportId ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _tryOpenPendingInitialReport() {
    if (!mounted ||
        _initialReportDialogOpened ||
        _pendingInitialReportId == null) {
      return;
    }

    final targetId = _pendingInitialReportId!;
    final reportIndex = _reportIndexById[targetId] ?? -1;
    if (reportIndex < 0) {
      if (_isResolvingInitialReport) {
        return;
      }
      _isResolvingInitialReport = true;
      unawaited(_openPendingInitialReportById(targetId));
      return;
    }

    final report = Map<String, dynamic>.from(_reports[reportIndex]);
    _initialReportDialogOpened = true;
    _pendingInitialReportId = null;
    widget.onInitialReportConsumed?.call();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showReportDetailsDialog(report);
    });
  }

  Future<void> _openPendingInitialReportById(String reportId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .get();
      if (!mounted) {
        return;
      }
      final data = doc.data();
      if (!doc.exists || data == null) {
        _pendingInitialReportId = null;
        _initialReportDialogOpened = false;
        widget.onInitialReportConsumed?.call();
        return;
      }

      final report = _mapReportFromDoc(doc);
      _initialReportDialogOpened = true;
      _pendingInitialReportId = null;
      widget.onInitialReportConsumed?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showReportDetailsDialog(report);
      });
    } catch (error) {
      _debugLog('Failed to open initial report by ID: $error');
      _pendingInitialReportId = null;
      _initialReportDialogOpened = false;
      widget.onInitialReportConsumed?.call();
    } finally {
      _isResolvingInitialReport = false;
    }
  }

  Map<String, dynamic> _mapReportFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final reportedAtRaw = data['reportedAt'];
    final reportedAt = reportedAtRaw is Timestamp
        ? reportedAtRaw.toDate()
        : DateTime.now();
    final dateFormat = DateFormat('MMM dd. yyyy');
    final timeFormat = DateFormat('h:mm a');
    final resolvedAtRaw = data['resolvedAt'];
    DateTime? resolvedAt;
    if (resolvedAtRaw is Timestamp) {
      resolvedAt = resolvedAtRaw.toDate();
    } else if (resolvedAtRaw is DateTime) {
      resolvedAt = resolvedAtRaw;
    }
    final locationText =
        (data['locationName'] ?? data['address'] ?? data['barangay'] ?? '')
            .toString()
            .trim();

    return {
      'id': doc.id,
      'reportId':
          data['reportId'] ?? doc.id, // Custom report ID or fallback to doc ID
      'image': data['mediaUrl'] ?? '',
      'date': dateFormat.format(reportedAt).toUpperCase(),
      'time': timeFormat.format(reportedAt).toUpperCase(),
      'reportedAt': reportedAt,
      'location': locationText.isNotEmpty ? locationText : 'Not provided',
      'title': data['incidentType'] ?? 'Unknown',
      'desc': data['details'] ?? 'No description provided.',
      'greenFlags': _nonNegativeInt(data['greenFlags']),
      'redFlags': _nonNegativeInt(data['redFlags']),
      'status': _normalizeStatusLabel((data['status'] ?? 'Pending').toString()),
      'resolvedAt': resolvedAt,
      'comments': data['comments'] ?? 0,
      'commentsList': <Map<String, dynamic>>[],
      'userVote': 'none',
      'name': data['name'] ?? 'Unknown',
      'mediaType': data['mediaType'] ?? 'photo',
    };
  }

  static const List<String> _categories = [
    'All',
    'Earthquake',
    'Flood',
    'Fire',
    'Vehicular',
    'Others',
  ];

  static const List<String> _timeFilters = [
    'All Time',
    'Today',
    'This Week',
    'This Month',
    'This Year',
  ];

  bool _matchesTimeFilter(DateTime reportedAt) {
    final now = DateTime.now();
    switch (_selectedTimeFilter) {
      case 'Today':
        return reportedAt.year == now.year &&
            reportedAt.month == now.month &&
            reportedAt.day == now.day;
      case 'This Week':
        final weekAgo = now.subtract(const Duration(days: 7));
        return reportedAt.isAfter(weekAgo);
      case 'This Month':
        return reportedAt.year == now.year && reportedAt.month == now.month;
      case 'This Year':
        return reportedAt.year == now.year;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _computeVisibleReports() {
    final filtered = _reports.where((report) {
      final statusRaw = report['status']?.toString() ?? '';
      final status = _normalizeStatusKey(statusRaw);
      final category = (report['title'] as String? ?? '').toLowerCase();
      final resolvedAt = report['resolvedAt'] as DateTime?;
      final reportedAt = report['reportedAt'] as DateTime?;

      if (_isResolvedStatus(statusRaw) && resolvedAt != null) {
        final elapsed = DateTime.now().difference(resolvedAt);
        if (elapsed >= const Duration(hours: 1)) {
          return false;
        }
      }

      bool matchesFilter;
      switch (_selectedFilter) {
        case 'Approved':
          matchesFilter =
              _isApprovedStatus(statusRaw) || _isResolvedStatus(statusRaw);
          break;
        case 'Under Review':
          matchesFilter = status == 'pending' || status == 'under review';
          break;
        case 'Flagged':
          matchesFilter = _isFlaggedStatus(statusRaw);
          break;
        default:
          matchesFilter = true;
      }

      final matchesCategory =
          _selectedCategory == 'All' ||
          category == _selectedCategory.toLowerCase();

      final matchesTime = reportedAt == null || _matchesTimeFilter(reportedAt);

      return matchesFilter && matchesCategory && matchesTime;
    }).toList();

    // Sort by most recent first
    filtered.sort((a, b) {
      final aTime = a['reportedAt'] as DateTime? ?? DateTime(1970);
      final bTime = b['reportedAt'] as DateTime? ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return filtered;
  }

  void _recomputeDerivedReportState() {
    _reportIndexById = {
      for (int i = 0; i < _reports.length; i++)
        if ((_reports[i]['id']?.toString() ?? '').isNotEmpty)
          _reports[i]['id'].toString(): i,
    };
    _visibleReportsNotifier.value = List<Map<String, dynamic>>.unmodifiable(
      _computeVisibleReports(),
    );
  }

  String _normalizeFilter(String value) {
    switch (value) {
      case 'Verified':
        return 'Approved';
      case 'Unverified':
        return 'Flagged';
      case 'Approved':
      case 'Under Review':
      case 'Flagged':
      case 'All':
        return value;
      default:
        return 'All';
    }
  }

  String _normalizeStatusKey(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isResolvedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'resolved' || normalized == 'incident resolved';
  }

  bool _isApprovedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'approved' || normalized == 'verified';
  }

  bool _isFlaggedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'flagged' ||
        normalized == 'unverified' ||
        normalized == 'admin flagged';
  }

  String _normalizeStatusLabel(String status) {
    final normalized = _normalizeStatusKey(status);

    if (_isResolvedStatus(status)) {
      return 'RESOLVED';
    }
    if (_isApprovedStatus(status)) {
      return 'APPROVED';
    }
    if (normalized == 'under review') {
      return 'UNDER REVIEW';
    }
    if (normalized == 'pending') {
      return 'PENDING';
    }
    if (_isFlaggedStatus(status)) {
      return 'FLAGGED';
    }

    return status.trim().toUpperCase().replaceAll('_', ' ');
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ DIALOG HELPERS ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  // Add this method to replace the existing _showReasonDialog in community_page.dart

  Future<bool> _showReasonDialog({
    required Color headerColor,
    required String headerText,
    required String question,
    required List<String> reasons,
  }) async {
    final TextEditingController commentController = TextEditingController();
    final List<bool> selected = List<bool>.filled(reasons.length, false);
    String? errorText;

    final result =
        await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 32,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  minWidth: 300,
                  maxHeight: MediaQuery.of(context).size.height * 0.72,
                ),
                child: StatefulBuilder(
                  builder: (context, setStateDialog) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // HEADER (Yellow/Green background with white text)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: headerColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Close button (X) on top right
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              // Header text
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  headerText,
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // BODY (White background)
                        Flexible(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(20),
                                bottomRight: Radius.circular(20),
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Question
                                  Text(
                                    question,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: 'RobotoCondensed',
                                      fontSize: 22,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Reasons (Checkboxes)
                                  ...List.generate(reasons.length, (i) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          setStateDialog(() {
                                            selected[i] = !selected[i];
                                          });
                                        },
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.black,
                                                  width: 2,
                                                ),
                                                color: selected[i]
                                                    ? headerColor.withOpacity(
                                                        0.1,
                                                      )
                                                    : Colors.white,
                                              ),
                                              child: selected[i]
                                                  ? Icon(
                                                      Icons.check,
                                                      size: 28,
                                                      color: headerColor,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                reasons[i],
                                                style: const TextStyle(
                                                  fontFamily: 'RobotoCondensed',
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w400,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),

                                  const SizedBox(height: 24),

                                  // Additional Comments Label
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Additional Comments',
                                      style: const TextStyle(
                                        fontFamily: 'RobotoCondensed',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Text Field
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8E8E8),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: TextField(
                                      controller: commentController,
                                      maxLines: 4,
                                      style: const TextStyle(
                                        fontFamily: 'RobotoCondensed',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black,
                                      ),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.all(16),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),

                                  if (errorText != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      errorText!,
                                      style: const TextStyle(
                                        fontFamily: 'RobotoCondensed',
                                        fontSize: 14,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 24),

                                  // Submit Button
                                  Container(
                                    width: 200,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: headerColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: () {
                                        final hasReason = selected.contains(
                                          true,
                                        );
                                        final hasComment = commentController
                                            .text
                                            .trim()
                                            .isNotEmpty;

                                        if (!hasReason && !hasComment) {
                                          setStateDialog(() {
                                            errorText =
                                                'Please select a reason or add a comment.';
                                          });
                                          return;
                                        }

                                        Navigator.of(dialogContext).pop(true);
                                      },
                                      child: const Text(
                                        'SUBMIT',
                                        style: TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ) ??
        false;

    return result;
  }

  Future<bool> _showUndoConfirmDialog({
    required String title,
    required String message,
    required Color headerColor,
  }) async {
    final result =
        await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: headerColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.undo, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(dialogContext).pop(false),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: BorderSide(color: headerColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    color: headerColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: headerColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'YES, UNDO',
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;

    return result;
  }

  /// Dialog to confirm changing vote from one type to another
  Future<bool> _showChangeVoteDialog({
    required String fromVote,
    required String toVote,
  }) async {
    final fromLabel = fromVote == 'verify' ? 'VERIFIED' : 'REPORTED';
    final toLabel = toVote == 'verify' ? 'VERIFY' : 'REPORT';
    final headerColor = toVote == 'verify' ? statusGreen : appBlue;

    final result =
        await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: headerColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'CHANGE VOTE',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(dialogContext).pop(false),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          'You have already $fromLabel this report. Do you want to change your vote to $toLabel instead?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  side: BorderSide(color: headerColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    color: headerColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: headerColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'YES, CHANGE',
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;

    return result;
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ MEDIA BUILDER ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  Widget _buildMediaWidget(
    Map<String, dynamic> report, {
    double targetHeight = 200,
  }) {
    final mediaUrl = (report['image'] as String? ?? '').trim();
    final mediaType = (report['mediaType'] as String? ?? 'photo').toLowerCase();

    // Debug: log what we're trying to load
    _debugLog(
      'ÃƒÂ°Ã…Â¸Ã¢â‚¬â€œÃ‚Â¼ÃƒÂ¯Ã‚Â¸Ã‚Â Media load -> type: ' +
          mediaType +
          ', url: ' +
          mediaUrl,
    );

    // Handle empty URL
    if (mediaUrl.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(child: Icon(Icons.image_not_supported, size: 48)),
      );
    }

    // Convert Firebase Storage path to download URL if needed
    String downloadUrl = mediaUrl;
    if (!mediaUrl.startsWith('https')) {
      // This is a storage path, convert to download URL
      final bucket = 'res-q-93ca6.firebasestorage.app';
      downloadUrl =
          'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(mediaUrl)}?alt=media';
      _debugLog(
        'ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬â€ Converted storage path to download URL: $downloadUrl',
      );
    }

    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    final mediaWidth = MediaQuery.of(context).size.width - 32;
    final cacheWidth = (mediaWidth * dpr).round();
    final cacheHeight = (targetHeight * dpr).round();

    // Firebase Storage URLs are network images
    return _NetworkImageLoader(
      url: downloadUrl,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  String _resolveMediaUrl(String mediaUrl) {
    if (mediaUrl.isEmpty) {
      return mediaUrl;
    }
    if (mediaUrl.startsWith('https')) {
      return mediaUrl;
    }
    final bucket = 'res-q-93ca6.firebasestorage.app';
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(mediaUrl)}?alt=media';
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ IMAGE ZOOM DIALOG ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  void _showImageZoom(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => _ImageZoomDialog(imageUrl: imageUrl),
    );
  }

  void _showReportDetailsDialog(Map<String, dynamic> report) {
    final statusLower = (report['status'] as String? ?? '').toLowerCase();
    final isResolved =
        statusLower == 'resolved' || statusLower == 'incident resolved';
    final mediaUrl = (report['image'] as String? ?? '').trim();
    final resolvedBy =
        (report['resolvedBy'] ??
                report['resolvedByName'] ??
                report['resolved_by'] ??
                '')
            .toString()
            .trim();
    final approvedBy =
        (report['approvedBy'] ??
                report['approvedByName'] ??
                report['approved_by'] ??
                '')
            .toString()
            .trim();
    final reportId = report['id']?.toString() ?? '';
    final int reportIndex = _reportIndexById[reportId] ?? 0;
    final vote = report['userVote'] as String? ?? 'none';
    final bool greenSelected = vote == 'green';
    final bool redSelected = vote == 'red';
    final Color greenIconColor = greenSelected
        ? appGreen
        : appGreen.withOpacity(0.6);
    final Color redIconColor = redSelected ? appRed : appRed.withOpacity(0.6);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              minWidth: 300,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mediaUrl.isNotEmpty)
                        GestureDetector(
                          onTap: () =>
                              _showImageZoom(_resolveMediaUrl(mediaUrl)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: _buildMediaWidget(
                                report,
                                targetHeight: 180,
                              ),
                            ),
                          ),
                        ),
                      if (mediaUrl.isNotEmpty) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              report['title'] ?? 'Report',
                              style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: appBlack,
                              ),
                            ),
                          ),
                          if (isResolved)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'RESOLVED',
                                style: TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'STATUS: ${report['status']}',
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          color: appBlack,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DATE: ${report['date']}',
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 12,
                              color: appBlack.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'TIME: ${report['time']}',
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 12,
                              color: appBlack.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Reported by: ${report['name'] ?? 'Unknown'}',
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          color: appBlack.withOpacity(0.8),
                        ),
                      ),
                      if (resolvedBy.isNotEmpty) const SizedBox(height: 6),
                      if (resolvedBy.isNotEmpty)
                        Text(
                          'Resolved by: $resolvedBy',
                          style: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 12,
                            color: appBlack.withOpacity(0.8),
                          ),
                        ),
                      if (approvedBy.isNotEmpty) const SizedBox(height: 6),
                      if (approvedBy.isNotEmpty)
                        Text(
                          'Approved by: $approvedBy',
                          style: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 12,
                            color: appBlack.withOpacity(0.8),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                onTap: () => _onGreenFlagPressed(reportIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 18,
                                        color: greenIconColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_nonNegativeInt(report['greenFlags'])}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _onRedFlagPressed(reportIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flag,
                                        size: 18,
                                        color: redIconColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_nonNegativeInt(report['redFlags'])}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _openComments(reportIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.comment,
                                        size: 18,
                                        color: commentBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${report['comments']}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 12,
                                          color: appBlack,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              side: const BorderSide(
                                color: appBlue,
                                width: 1.5,
                              ),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'CLOSE',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w600,
                                color: appBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ FLAG LOGIC (WITH DIALOG) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  Future<void> _onGreenFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];
    final reportId = report['id']?.toString() ?? '';
    int greenCount = _nonNegativeInt(report['greenFlags']);
    int redCount = _nonNegativeInt(report['redFlags']);

    // Already green ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ quick unverify
    if (vote == 'green') {
      final shouldUndo = await _showUndoConfirmDialog(
        title: 'UNDO VERIFY',
        message:
            'You already verified this report. Do you want to undo your verification?',
        headerColor: statusGreen,
      );
      if (!shouldUndo) return;

      // Update _userVotes immediately so Firestore listener uses correct value
      _userVotes.remove(reportId);

      greenCount = _nonNegativeInt(greenCount - 1);
      report['greenFlags'] = greenCount;
      report['userVote'] = 'none';
      _recomputeDerivedReportState();
      await _updateReportFlags(reportId, greenDelta: -1);
      await _saveUserVote(reportId, 'none');
      return;
    }

    // If user already reported (red), ask if they want to change their vote
    if (vote == 'red') {
      final shouldChange = await _showChangeVoteDialog(
        fromVote: 'report',
        toVote: 'verify',
      );
      if (!shouldChange) return;
    }

    // Show VERIFY modal
    final bool confirmed = await _showReasonDialog(
      headerColor: statusGreen,
      headerText: 'VERIFY REPORT',
      question: 'Why are you verifying this report?',
      reasons: const [
        'Witnessed the event',
        'Heard from neighbors',
        'Consistent with other reports',
      ],
    );

    if (!confirmed) return;

    // Update _userVotes immediately so Firestore listener uses correct value
    _userVotes[reportId] = 'green';

    if (vote == 'red') {
      redCount = _nonNegativeInt(redCount - 1);
    }
    greenCount = _nonNegativeInt(greenCount + 1);
    report['greenFlags'] = greenCount;
    report['redFlags'] = redCount;
    report['userVote'] = 'green';
    _recomputeDerivedReportState();
    await _updateReportFlags(
      reportId,
      greenDelta: 1,
      redDelta: vote == 'red' ? -1 : 0,
    );
    await _saveUserVote(reportId, 'green');
  }

  Future<void> _onRedFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];
    final reportId = report['id']?.toString() ?? '';
    int greenCount = _nonNegativeInt(report['greenFlags']);
    int redCount = _nonNegativeInt(report['redFlags']);

    // Already red ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ quick unflag
    if (vote == 'red') {
      final shouldUndo = await _showUndoConfirmDialog(
        title: 'UNDO REPORT',
        message:
            'You already reported this incident. Do you want to undo your report?',
        headerColor: appBlue,
      );
      if (!shouldUndo) return;

      // Update _userVotes immediately so Firestore listener uses correct value
      _userVotes.remove(reportId);

      redCount = _nonNegativeInt(redCount - 1);
      report['redFlags'] = redCount;
      report['userVote'] = 'none';
      _recomputeDerivedReportState();
      await _updateReportFlags(reportId, redDelta: -1);
      await _saveUserVote(reportId, 'none');
      return;
    }

    // If user already verified (green), ask if they want to change their vote
    if (vote == 'green') {
      final shouldChange = await _showChangeVoteDialog(
        fromVote: 'verify',
        toVote: 'report',
      );
      if (!shouldChange) return;
    }

    // Show REPORT modal
    final bool confirmed = await _showReasonDialog(
      headerColor: appBlue,
      headerText: 'REPORT INCIDENT',
      question: 'Why are you flagging this report?',
      reasons: const [
        'Inappropriate Content',
        'Flagged/Lack of Evidence',
        'Spam/Irrelevant Content',
      ],
    );

    if (!confirmed) return;

    // Update _userVotes immediately so Firestore listener uses correct value
    _userVotes[reportId] = 'red';

    if (vote == 'green') {
      greenCount = _nonNegativeInt(greenCount - 1);
    }
    redCount = _nonNegativeInt(redCount + 1);
    report['greenFlags'] = greenCount;
    report['redFlags'] = redCount;
    report['userVote'] = 'red';
    _recomputeDerivedReportState();
    await _updateReportFlags(
      reportId,
      greenDelta: vote == 'green' ? -1 : 0,
      redDelta: 1,
    );
    await _saveUserVote(reportId, 'red');
  }

  Future<void> _updateReportFlags(
    String reportId, {
    int greenDelta = 0,
    int redDelta = 0,
  }) async {
    if (reportId.isEmpty) return;
    if (greenDelta == 0 && redDelta == 0) return;
    try {
      final reportRef = FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(reportRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() ?? <String, dynamic>{};
        final currentGreen = _nonNegativeInt(data['greenFlags']);
        final currentRed = _nonNegativeInt(data['redFlags']);
        final updates = <String, dynamic>{};
        if (greenDelta != 0) {
          updates['greenFlags'] = _nonNegativeInt(currentGreen + greenDelta);
        }
        if (redDelta != 0) {
          updates['redFlags'] = _nonNegativeInt(currentRed + redDelta);
        }
        if (updates.isNotEmpty) {
          transaction.update(reportRef, updates);
        }
      });
    } catch (e) {
      _debugLog('Failed to update report flags: $e');
    }
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ COMMENTS BOTTOM SHEET ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  void _openComments(int index) {
    final report = _reports[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsBottomSheet(
        report: report,
        onCommentAdded: () {
          final currentCount = report['comments'] as int? ?? 0;
          report['comments'] = currentCount + 1;
          _recomputeDerivedReportState();
        },
      ),
    );
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ TIME FORMATTER ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd').format(timestamp);
    }
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ FILTER & ANNOUNCEMENT HELPERS ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedFilter != 'All') count++;
    if (_selectedCategory != 'All') count++;
    if (_selectedTimeFilter != 'All Time') count++;
    return count;
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'FILTER REPORTS',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setStateSheet(() {
                          _selectedFilter = 'All';
                          _selectedCategory = 'All';
                          _selectedTimeFilter = 'All Time';
                        });
                        setState(() {
                          _recomputeDerivedReportState();
                        });
                      },
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          color: appBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Status Filter
                const Text(
                  'STATUS',
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: appBlack,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['All', 'Approved', 'Under Review', 'Flagged']
                      .map(
                        (status) => ChoiceChip(
                          label: Text(status),
                          selected: _selectedFilter == status,
                          onSelected: (selected) {
                            setStateSheet(() => _selectedFilter = status);
                            setState(() {
                              _recomputeDerivedReportState();
                            });
                          },
                          showCheckmark: false,
                          backgroundColor: appOffWhite,
                          selectedColor: appBlue,
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: _selectedFilter == status
                                ? appBlue
                                : appBlue.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontWeight: FontWeight.w600,
                            color: _selectedFilter == status
                                ? Colors.white
                                : appBlack,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),

                // Category Filter
                const Text(
                  'CATEGORY',
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: appBlack,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .map(
                        (category) => ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          onSelected: (selected) {
                            setStateSheet(() => _selectedCategory = category);
                            setState(() {
                              _recomputeDerivedReportState();
                            });
                          },
                          showCheckmark: false,
                          backgroundColor: appOffWhite,
                          selectedColor: appBlue,
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: _selectedCategory == category
                                ? appBlue
                                : appBlue.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontWeight: FontWeight.w600,
                            color: _selectedCategory == category
                                ? Colors.white
                                : appBlack,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),

                // Time Filter
                const Text(
                  'TIME',
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: appBlack,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _timeFilters
                      .map(
                        (time) => ChoiceChip(
                          label: Text(time),
                          selected: _selectedTimeFilter == time,
                          onSelected: (selected) {
                            setStateSheet(() => _selectedTimeFilter = time);
                            setState(() {
                              _recomputeDerivedReportState();
                            });
                          },
                          showCheckmark: false,
                          backgroundColor: appOffWhite,
                          selectedColor: appBlue,
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: _selectedTimeFilter == time
                                ? appBlue
                                : appBlue.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontWeight: FontWeight.w600,
                            color: _selectedTimeFilter == time
                                ? Colors.white
                                : appBlack,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),

                // Apply Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'APPLY FILTERS',
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAnnouncementDetail(Map<String, dynamic> announcement) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        backgroundColor: appOffWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            minWidth: 300,
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: appBlue,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        announcement['title'] ?? 'Announcement',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: Container(
                  color: appOffWhite,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((announcement['imageUrl'] as String?)?.isNotEmpty ==
                            true)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: announcement['imageUrl'],
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              memCacheHeight: 300,
                              maxHeightDiskCache: 300,
                              errorWidget: (context, url, error) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        if ((announcement['imageUrl'] as String?)?.isNotEmpty ==
                            true)
                          const SizedBox(height: 12),
                        Text(
                          announcement['content'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 14,
                            color: appBlack,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ UI ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

  @override
  Widget build(BuildContext context) {
    return Container(
      color: appOffWhite,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResqLogoHeader(
              padding: const EdgeInsets.only(top: 12),
              sideSlotWidth: 0,
              bottomSpacing: 6,
            ),

            // ANNOUNCEMENTS SECTION (horizontal scroll)
            if (_announcements.isNotEmpty) ...[
              const Text(
                'ANNOUNCEMENTS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: appBlack,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 112,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: const <PointerDeviceKind>{
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.unknown,
                    },
                    scrollbars: false,
                  ),
                  child: ListView.separated(
                    primary: false,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: _announcements.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final announcement = _announcements[index];
                      final imageUrl =
                          (announcement['imageUrl'] as String? ?? '').trim();
                      final hasImage = imageUrl.isNotEmpty;
                      return GestureDetector(
                        onTap: () => _showAnnouncementDetail(announcement),
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [appBlue, appBlue.withOpacity(0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: appBlue.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.campaign,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      announcement['title'] ?? 'Announcement',
                                      style: const TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        announcement['content'] ?? '',
                                        style: TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 11,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                        maxLines: hasImage ? 3 : 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (hasImage) ...[
                                      const SizedBox(width: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 56,
                                          height: 56,
                                          child: CachedNetworkImage(
                                            imageUrl: imageUrl,
                                            fit: BoxFit.cover,
                                            fadeInDuration: const Duration(
                                              milliseconds: 120,
                                            ),
                                            memCacheWidth: 220,
                                            memCacheHeight: 220,
                                            placeholder: (context, url) =>
                                                Container(
                                                  color: Colors.white24,
                                                  alignment: Alignment.center,
                                                  child: const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 1.8,
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                ),
                                            errorWidget:
                                                (
                                                  context,
                                                  url,
                                                  error,
                                                ) => Container(
                                                  color: Colors.white24,
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                    Icons.broken_image_outlined,
                                                    size: 18,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (hasImage) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to preview',
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    fontSize: 9.5,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // LATEST REPORTS HEADER WITH FILTER BUTTON
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LATEST REPORTS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: appBlack,
                    fontFamily: 'Roboto',
                  ),
                ),
                GestureDetector(
                  onTap: _showFilterBottomSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: appBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_list,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getActiveFilterCount() > 0
                              ? 'Filters (${_getActiveFilterCount()})'
                              : 'Filter',
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // REPORT LIST
            Expanded(
              child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                valueListenable: _visibleReportsNotifier,
                builder: (context, visibleReports, _) {
                  final reportIndexById = _reportIndexById;
                  return ListView.separated(
                    itemCount: visibleReports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final report = visibleReports[index];
                      final reportId = report['id']?.toString() ?? '';
                      final statusRaw = report['status']?.toString() ?? '';
                      final isResolved = _isResolvedStatus(statusRaw);
                      final isApproved = _isApprovedStatus(statusRaw);
                      final isFlagged = _isFlaggedStatus(statusRaw);
                      final reportIndex = reportIndexById[reportId] ?? index;
                      final vote = report['userVote'] as String;
                      final bool greenSelected = vote == 'green';
                      final bool redSelected = vote == 'red';

                      final Color greenIconColor = greenSelected
                          ? appGreen
                          : appGreen.withOpacity(0.6);
                      final Color redIconColor = redSelected
                          ? appRed
                          : appRed.withOpacity(0.6);

                      // Get reporter info
                      final reporterName = report['name'] ?? 'Unknown';
                      final reporterInitial = reporterName.isNotEmpty
                          ? reporterName[0].toUpperCase()
                          : '?';
                      final reportedAt = report['reportedAt'] as DateTime?;
                      final timeAgo = reportedAt != null
                          ? _formatTimeAgo(reportedAt)
                          : report['date'];
                      final mediaUrl = (report['image'] as String? ?? '')
                          .trim();

                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () => _showReportDetailsDialog(report),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // PROFILE HEADER (Facebook-style)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Profile Avatar
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: appBlue,
                                        child: Text(
                                          reporterInitial,
                                          style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Name + Time + Status
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    reporterName,
                                                    style: const TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: appBlack,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                // Status badge
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isResolved
                                                        ? const Color(
                                                            0xFF4CAF50,
                                                          )
                                                        : isApproved
                                                        ? statusGreen
                                                        : isFlagged
                                                        ? statusRed
                                                        : statusYellow,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    _normalizeStatusLabel(
                                                      statusRaw,
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily:
                                                          'RobotoCondensed',
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Text(
                                                  timeAgo,
                                                  style: TextStyle(
                                                    fontFamily:
                                                        'RobotoCondensed',
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                // Only show location if it's provided
                                                if ((report['location'] ??
                                                        'Not provided') !=
                                                    'Not provided') ...[
                                                  Text(
                                                    ' \u2022 ',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Flexible(
                                                    child: Text(
                                                      report['location'] ?? '',
                                                      style: TextStyle(
                                                        fontFamily:
                                                            'RobotoCondensed',
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // INCIDENT TYPE + DESCRIPTION
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        report['title'],
                                        style: const TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: appBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        report['desc'],
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: appBlack,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // IMAGE (if exists)
                                if (mediaUrl.isNotEmpty)
                                  SizedBox(
                                    height: 200,
                                    width: double.infinity,
                                    child: _buildMediaWidget(
                                      report,
                                      targetHeight: 200,
                                    ),
                                  ),

                                // DIVIDER
                                Divider(height: 1, color: Colors.grey[300]),

                                // ACTION BAR (FLAGS + COMMENTS)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      // GREEN FLAG (Verify)
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              _onGreenFlagPressed(reportIndex),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.check_circle_outline,
                                                  size: 20,
                                                  color: greenIconColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Verify ${_nonNegativeInt(report['greenFlags'])}',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        'RobotoCondensed',
                                                    fontSize: 12,
                                                    fontWeight: greenSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    color: greenIconColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // RED FLAG (Report)
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              _onRedFlagPressed(reportIndex),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.flag_outlined,
                                                  size: 20,
                                                  color: redIconColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Report ${_nonNegativeInt(report['redFlags'])}',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        'RobotoCondensed',
                                                    fontSize: 12,
                                                    fontWeight: redSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    color: redIconColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // COMMENTS
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              _openComments(reportIndex),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.chat_bubble_outline,
                                                  size: 20,
                                                  color: commentBlue,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Comment ${report['comments']}',
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        'RobotoCondensed',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                    color: commentBlue,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
// COMMENTS BOTTOM SHEET (Draggable)
// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â

class _CommentsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> report;
  final VoidCallback? onCommentAdded;

  const _CommentsBottomSheet({required this.report, this.onCommentAdded});

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFAC1B22);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const commentBlue = Color(0xFF2563EB);
  static const int _maxReplyDepth = 4;

  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  final Map<String, List<Map<String, dynamic>>> _repliesByCommentId = {};
  final Set<String> _expandedReplyComments = <String>{};
  final Map<String, bool> _loadingReplies = {};
  final Map<String, bool> _postingReply = {};
  Map<String, String> _commentVotes = {};
  String? _replyingToCommentId;
  String? _replyingToReplyId;
  final Set<String> _expandedNestedReplies = <String>{};
  bool _loading = true;
  bool _isPostingComment = false;
  final _VoteStorageBackend _voteStorageBackend = _VoteStorageBackend();

  @override
  void initState() {
    super.initState();
    _loadCommentVotes();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final reportId = widget.report['id']?.toString() ?? '';
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .orderBy('timestamp', descending: true)
          .get();

      final comments = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final timestampRaw = data['timestamp'];
            if (timestampRaw == null) return null;
            final timestamp = (timestampRaw as Timestamp).toDate();
            final type = (data['type'] as String?)?.toLowerCase();
            if (type == 'admin') return null;

            return {
              'id': doc.id,
              'text': data['text'] ?? '',
              'author': data['author'] ?? 'Anonymous',
              'timestamp': timestamp,
              'greenFlags': _nonNegativeInt(data['greenFlags']),
              'redFlags': _nonNegativeInt(data['redFlags']),
              'replyCount': data['replyCount'] ?? 0,
              'userVote': _commentVotes[_commentVoteKey(doc.id)] ?? 'none',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (e) {
      _debugLog('âŒ Failed to load comments: $e');
      setState(() => _loading = false);
    }
  }

  String _commentVoteKey(String commentId) {
    final reportId = widget.report['id']?.toString() ?? '';
    return '$reportId:$commentId';
  }

  String _replyVoteKey(String commentId, String replyId) {
    final reportId = widget.report['id']?.toString() ?? '';
    return 'reply:$reportId:$commentId:$replyId';
  }

  String _replyThreadKey(String commentId, String replyId) {
    return '$commentId:$replyId';
  }

  String? _getLoggedInUserPhone() {
    final userData = UserSession.currentUserData;
    if (userData == null) return null;

    String? phone =
        userData['contactNumber']?.toString() ??
        userData['phoneNumber']?.toString() ??
        userData['phone']?.toString() ??
        userData['mobileNumber']?.toString();

    if (phone == null || phone.isEmpty) return null;
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _loadCommentVotes() async {
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) return;

    try {
      final data = await _voteStorageBackend.readVotePayload(
        userPhone: userPhone,
        userData: UserSession.currentUserData,
      );
      final rawVotes = data?['commentVotes'];
      final loadedVotes = rawVotes is Map
          ? rawVotes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : <String, String>{};

      if (!mounted) return;
      setState(() {
        _commentVotes = loadedVotes;
        for (final comment in _comments) {
          final id = comment['id']?.toString();
          if (id == null) continue;
          comment['userVote'] = _commentVotes[_commentVoteKey(id)] ?? 'none';
        }
        for (final entry in _repliesByCommentId.entries) {
          for (final reply in entry.value) {
            final replyId = reply['id']?.toString();
            if (replyId == null) continue;
            reply['userVote'] =
                _commentVotes[_replyVoteKey(entry.key, replyId)] ?? 'none';
          }
        }
      });
    } catch (e) {
      _debugLog('Failed to load comment votes: $e');
    }
  }

  Future<void> _saveCommentVote(String commentId, String vote) async {
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) return;

    final key = _commentVoteKey(commentId);
    if (vote == 'none') {
      _commentVotes.remove(key);
    } else {
      _commentVotes[key] = vote;
    }

    try {
      await _voteStorageBackend.writeVotePayload(
        userPhone: userPhone,
        userData: UserSession.currentUserData,
        payload: {'commentVotes': _commentVotes},
      );
    } catch (e) {
      _debugLog('Failed to save comment vote: $e');
    }
  }

  Future<void> _saveReplyVote(
    String commentId,
    String replyId,
    String vote,
  ) async {
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) return;

    final key = _replyVoteKey(commentId, replyId);
    if (vote == 'none') {
      _commentVotes.remove(key);
    } else {
      _commentVotes[key] = vote;
    }

    try {
      await _voteStorageBackend.writeVotePayload(
        userPhone: userPhone,
        userData: UserSession.currentUserData,
        payload: {'commentVotes': _commentVotes},
      );
    } catch (e) {
      _debugLog('Failed to save reply vote: $e');
    }
  }

  Future<void> _postComment() async {
    if (_isPostingComment) return;
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;
    if (commentText.length > 256) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Comment must be 256 characters or less.',
        type: AppSnackBarType.error,
      );
      return;
    }
    setState(() => _isPostingComment = true);

    try {
      final reportId = widget.report['id']?.toString() ?? '';
      final reportTitle = widget.report['title']?.toString() ?? '';
      final reportStatus = widget.report['status']?.toString() ?? '';
      final reportDate = widget.report['date']?.toString() ?? '';
      final reportTime = widget.report['time']?.toString() ?? '';
      final reportedBy = widget.report['name']?.toString() ?? '';

      if (reportId.isEmpty) return;

      final userName =
          UserSession.currentUserData?['fullName'] as String? ?? 'Anonymous';

      final newComment = {
        'text': commentText,
        'author': userName,
        'type': 'user',
        'timestamp': Timestamp.now(),
        'greenFlags': 0,
        'redFlags': 0,
        'replyCount': 0,
        'reportId': reportId,
        'reportTitle': reportTitle,
        'reportCategory': reportTitle,
        'reportStatus': reportStatus,
        'reportDate': reportDate,
        'reportTime': reportTime,
        'reportedBy': reportedBy,
      };

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(newComment);

      // Update report comment count
      try {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({'comments': FieldValue.increment(1)});
        widget.onCommentAdded?.call();
      } catch (_) {}

      _commentController.clear();
      await _loadComments();

      if (mounted) {
        AppSnackBar.show(
          context,
          'Comment posted',
          type: AppSnackBarType.success,
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      _debugLog('âŒ Failed to post comment: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          'Failed to post comment. Please try again.',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPostingComment = false);
      }
    }
  }

  Future<void> _onCommentVerify(int commentIndex) async {
    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String? ?? 'none';

    var newGreenCount = _nonNegativeInt(comment['greenFlags']);
    var newRedCount = _nonNegativeInt(comment['redFlags']);
    var newVote = vote;

    if (vote == 'green') {
      if (newGreenCount > 0) newGreenCount--;
      newVote = 'none';
    } else {
      if (vote == 'red' && newRedCount > 0) newRedCount--;
      newGreenCount++;
      newVote = 'green';
    }

    newGreenCount = _nonNegativeInt(newGreenCount);
    newRedCount = _nonNegativeInt(newRedCount);

    try {
      final commentId = comment['id'] as String;
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      if (!mounted) return;
      setState(() {
        comment['greenFlags'] = newGreenCount;
        comment['redFlags'] = newRedCount;
        comment['userVote'] = newVote;
      });
      await _saveCommentVote(commentId, newVote);
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to update comment vote.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _onCommentReport(int commentIndex) async {
    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String? ?? 'none';

    var newGreenCount = _nonNegativeInt(comment['greenFlags']);
    var newRedCount = _nonNegativeInt(comment['redFlags']);
    var newVote = vote;

    if (vote == 'red') {
      if (newRedCount > 0) newRedCount--;
      newVote = 'none';
    } else {
      if (vote == 'green' && newGreenCount > 0) newGreenCount--;
      newRedCount++;
      newVote = 'red';
    }

    newGreenCount = _nonNegativeInt(newGreenCount);
    newRedCount = _nonNegativeInt(newRedCount);

    try {
      final commentId = comment['id'] as String;
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      if (!mounted) return;
      setState(() {
        comment['greenFlags'] = newGreenCount;
        comment['redFlags'] = newRedCount;
        comment['userVote'] = newVote;
      });
      await _saveCommentVote(commentId, newVote);
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to update comment vote.',
        type: AppSnackBarType.error,
      );
    }
  }

  Map<String, dynamic>? _findReply(String commentId, String replyId) {
    final replies = _repliesByCommentId[commentId];
    if (replies == null) return null;

    for (final reply in replies) {
      if (reply['id']?.toString() == replyId) return reply;
    }
    return null;
  }

  List<Map<String, dynamic>> _repliesForParent(
    String commentId, {
    String? parentReplyId,
  }) {
    final replies =
        _repliesByCommentId[commentId] ?? const <Map<String, dynamic>>[];
    return replies.where((reply) {
      final parentId = reply['parentReplyId']?.toString();
      if (parentReplyId == null) {
        return parentId == null || parentId.isEmpty;
      }
      return parentId == parentReplyId;
    }).toList();
  }

  Future<void> _onReplyVerify(String commentId, String replyId) async {
    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    final reply = _findReply(commentId, replyId);
    if (reply == null) return;

    final vote = reply['userVote'] as String? ?? 'none';
    var newGreenCount = _nonNegativeInt(reply['greenFlags']);
    var newRedCount = _nonNegativeInt(reply['redFlags']);
    var newVote = vote;

    if (vote == 'green') {
      if (newGreenCount > 0) newGreenCount--;
      newVote = 'none';
    } else {
      if (vote == 'red' && newRedCount > 0) newRedCount--;
      newGreenCount++;
      newVote = 'green';
    }

    newGreenCount = _nonNegativeInt(newGreenCount);
    newRedCount = _nonNegativeInt(newRedCount);

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .doc(replyId)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      if (!mounted) return;
      setState(() {
        reply['greenFlags'] = newGreenCount;
        reply['redFlags'] = newRedCount;
        reply['userVote'] = newVote;
      });
      await _saveReplyVote(commentId, replyId, newVote);
    } catch (e) {
      _debugLog('âŒ Failed to update reply verify vote: $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to update reply vote.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _onReplyReport(String commentId, String replyId) async {
    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    final reply = _findReply(commentId, replyId);
    if (reply == null) return;

    final vote = reply['userVote'] as String? ?? 'none';
    var newGreenCount = _nonNegativeInt(reply['greenFlags']);
    var newRedCount = _nonNegativeInt(reply['redFlags']);
    var newVote = vote;

    if (vote == 'red') {
      if (newRedCount > 0) newRedCount--;
      newVote = 'none';
    } else {
      if (vote == 'green' && newGreenCount > 0) newGreenCount--;
      newRedCount++;
      newVote = 'red';
    }

    newGreenCount = _nonNegativeInt(newGreenCount);
    newRedCount = _nonNegativeInt(newRedCount);

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .doc(replyId)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      if (!mounted) return;
      setState(() {
        reply['greenFlags'] = newGreenCount;
        reply['redFlags'] = newRedCount;
        reply['userVote'] = newVote;
      });
      await _saveReplyVote(commentId, replyId, newVote);
    } catch (e) {
      _debugLog('âŒ Failed to update reply report vote: $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to update reply vote.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _loadReplies(String commentId) async {
    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    if (mounted) {
      setState(() => _loadingReplies[commentId] = true);
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .orderBy('timestamp')
          .get();

      final replies = snapshot.docs.map((doc) {
        final data = doc.data();
        final timestampRaw = data['timestamp'];
        final timestamp = timestampRaw is Timestamp
            ? timestampRaw.toDate()
            : DateTime.now();
        final parentReplyIdRaw = data['parentReplyId']?.toString();
        final parentReplyId =
            parentReplyIdRaw == null || parentReplyIdRaw.isEmpty
            ? null
            : parentReplyIdRaw;
        return {
          'id': doc.id,
          'text': data['text'] ?? '',
          'author': data['author'] ?? 'Anonymous',
          'timestamp': timestamp,
          'greenFlags': _nonNegativeInt(data['greenFlags']),
          'redFlags': _nonNegativeInt(data['redFlags']),
          'replyCount': data['replyCount'] ?? 0,
          'parentReplyId': parentReplyId,
          'userVote': _commentVotes[_replyVoteKey(commentId, doc.id)] ?? 'none',
        };
      }).toList();

      final actualReplyCount = replies.length;
      final commentIndex = _comments.indexWhere((c) => c['id'] == commentId);
      final storedReplyCount = commentIndex != -1
          ? (_comments[commentIndex]['replyCount'] as int? ?? 0)
          : null;

      if (!mounted) return;
      setState(() {
        _repliesByCommentId[commentId] = replies;
        if (commentIndex != -1) {
          _comments[commentIndex]['replyCount'] = actualReplyCount;
        }
      });

      if (storedReplyCount != null && storedReplyCount != actualReplyCount) {
        try {
          await FirebaseFirestore.instance
              .collection('reports')
              .doc(reportId)
              .collection('comments')
              .doc(commentId)
              .update({'replyCount': actualReplyCount});
        } catch (e) {
          _debugLog('âŒ Failed to sync replyCount for comment $commentId: $e');
        }
      }
    } catch (e) {
      _debugLog('âŒ Failed to load replies for comment $commentId: $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to load replies.',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingReplies[commentId] = false);
      }
    }
  }

  Future<void> _toggleReplies(String commentId) async {
    final isExpanded = _expandedReplyComments.contains(commentId);
    setState(() {
      if (isExpanded) {
        _expandedReplyComments.remove(commentId);
      } else {
        _expandedReplyComments.add(commentId);
      }
    });

    if (!isExpanded && !_repliesByCommentId.containsKey(commentId)) {
      await _loadReplies(commentId);
    }
  }

  Future<void> _startReply(String commentId, {String? replyId}) async {
    final changedTarget =
        _replyingToCommentId != commentId || _replyingToReplyId != replyId;
    if (changedTarget) {
      _replyController.clear();
    }

    setState(() {
      _replyingToCommentId = commentId;
      _replyingToReplyId = replyId;
      _expandedReplyComments.add(commentId);
      if (replyId != null) {
        _expandedNestedReplies.add(_replyThreadKey(commentId, replyId));
      }
    });

    if (!_repliesByCommentId.containsKey(commentId)) {
      await _loadReplies(commentId);
    }
  }

  Future<void> _postReply(String commentId, {String? parentReplyId}) async {
    if (_postingReply[commentId] == true) return;

    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) return;
    if (replyText.length > 256) {
      AppSnackBar.show(
        context,
        'Reply must be 256 characters or less.',
        type: AppSnackBarType.error,
      );
      return;
    }

    final reportId = widget.report['id']?.toString() ?? '';
    if (reportId.isEmpty) return;

    final targetParentReplyId = parentReplyId ?? _replyingToReplyId;
    setState(() => _postingReply[commentId] = true);

    try {
      final userName =
          UserSession.currentUserData?['fullName'] as String? ?? 'Anonymous';
      final reportTitle = widget.report['title']?.toString() ?? '';
      final reportStatus = widget.report['status']?.toString() ?? '';
      final reportDate = widget.report['date']?.toString() ?? '';
      final reportTime = widget.report['time']?.toString() ?? '';
      final reportedBy = widget.report['name']?.toString() ?? '';

      final newReply = {
        'text': replyText,
        'author': userName,
        'type': 'user_reply',
        'timestamp': Timestamp.now(),
        'greenFlags': 0,
        'redFlags': 0,
        'replyCount': 0,
        'parentCommentId': commentId,
        'parentReplyId': targetParentReplyId ?? '',
        'reportId': reportId,
        'reportTitle': reportTitle,
        'reportCategory': reportTitle,
        'reportStatus': reportStatus,
        'reportDate': reportDate,
        'reportTime': reportTime,
        'reportedBy': reportedBy,
      };

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .add(newReply);

      try {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .collection('comments')
            .doc(commentId)
            .update({'replyCount': FieldValue.increment(1)});
      } catch (_) {}

      if (targetParentReplyId != null && targetParentReplyId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('reports')
              .doc(reportId)
              .collection('comments')
              .doc(commentId)
              .collection('replies')
              .doc(targetParentReplyId)
              .update({'replyCount': FieldValue.increment(1)});
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        final targetIndex = _comments.indexWhere((c) => c['id'] == commentId);
        if (targetIndex != -1) {
          final current = _comments[targetIndex]['replyCount'] as int? ?? 0;
          _comments[targetIndex]['replyCount'] = current + 1;
        }
        if (targetParentReplyId != null && targetParentReplyId.isNotEmpty) {
          final parentReply = _findReply(commentId, targetParentReplyId);
          if (parentReply != null) {
            final current = parentReply['replyCount'] as int? ?? 0;
            parentReply['replyCount'] = current + 1;
            _expandedNestedReplies.add(
              _replyThreadKey(commentId, targetParentReplyId),
            );
          }
        }
        _replyController.clear();
        _replyingToCommentId = null;
        _replyingToReplyId = null;
      });

      await _loadReplies(commentId);

      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Reply posted',
        type: AppSnackBarType.success,
        duration: const Duration(seconds: 1),
      );
    } catch (e) {
      _debugLog('âŒ Failed to post reply for comment $commentId: $e');
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to post reply. Please try again.',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _postingReply[commentId] = false);
      }
    }
  }

  Widget _buildCommentAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? color : color.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: appBlack,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleNestedReplies(String commentId, String replyId) {
    final key = _replyThreadKey(commentId, replyId);
    setState(() {
      if (_expandedNestedReplies.contains(key)) {
        _expandedNestedReplies.remove(key);
      } else {
        _expandedNestedReplies.add(key);
      }
    });
  }

  Widget _buildReplyComposer({
    required String commentId,
    String? parentReplyId,
    String? replyingToAuthor,
  }) {
    final isPostingReply = _postingReply[commentId] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyingToAuthor != null) ...[
          Text(
            'Replying to $replyingToAuthor',
            style: TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                maxLines: null,
                inputFormatters: [LengthLimitingTextInputFormatter(256)],
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 13,
                  color: appBlack,
                ),
                decoration: InputDecoration(
                  hintText: 'Write a reply...',
                  hintStyle: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: isPostingReply
                  ? null
                  : () => _postReply(commentId, parentReplyId: parentReplyId),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isPostingReply ? appBlue.withOpacity(0.6) : appBlue,
                  shape: BoxShape.circle,
                ),
                child: isPostingReply
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildReplyTree(
    String commentId, {
    String? parentReplyId,
    int depth = 0,
  }) {
    if (depth >= _maxReplyDepth) {
      return const <Widget>[];
    }

    final replies = _repliesForParent(commentId, parentReplyId: parentReplyId);
    return replies
        .map(
          (reply) =>
              _buildReplyTile(commentId: commentId, reply: reply, depth: depth),
        )
        .toList();
  }

  Widget _buildReplyTile({
    required String commentId,
    required Map<String, dynamic> reply,
    int depth = 0,
  }) {
    final replyId = reply['id']?.toString() ?? '';
    final author = reply['author']?.toString() ?? 'Anonymous';
    final initial = author.isNotEmpty ? author[0].toUpperCase() : '?';
    final timestamp = reply['timestamp'] as DateTime? ?? DateTime.now();
    final vote = reply['userVote'] as String? ?? 'none';
    final verifySelected = vote == 'green';
    final reportSelected = vote == 'red';
    final nestedReplies = _repliesForParent(commentId, parentReplyId: replyId);
    final directChildCount = nestedReplies.length;
    final storedReplyCount = reply['replyCount'] as int? ?? 0;
    final replyCount = storedReplyCount > directChildCount
        ? storedReplyCount
        : directChildCount;
    final level = depth + 1;
    final canReplyHere = level < _maxReplyDepth;
    final canShowChildren = level < _maxReplyDepth;
    final isExpanded = _expandedNestedReplies.contains(
      _replyThreadKey(commentId, replyId),
    );
    final showReplyInput =
        _replyingToCommentId == commentId && _replyingToReplyId == replyId;
    final leftPadding = (10 + depth * 18)
        .toDouble()
        .clamp(10.0, 64.0)
        .toDouble();

    return Padding(
      padding: EdgeInsets.only(top: 8, left: leftPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: Colors.grey[350],
            child: Text(
              initial,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: appBlack,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reply['text']?.toString() ?? '',
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          color: appBlack,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTimeAgo(timestamp),
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildCommentAction(
                      icon: Icons.verified,
                      label: 'Verify ${_nonNegativeInt(reply['greenFlags'])}',
                      color: appGreen,
                      selected: verifySelected,
                      onTap: () => _onReplyVerify(commentId, replyId),
                    ),
                    _buildCommentAction(
                      icon: Icons.flag,
                      label: 'Report ${_nonNegativeInt(reply['redFlags'])}',
                      color: appRed,
                      selected: reportSelected,
                      onTap: () => _onReplyReport(commentId, replyId),
                    ),
                    _buildCommentAction(
                      icon: Icons.reply,
                      label: replyCount > 0 ? 'Reply ($replyCount)' : 'Reply',
                      color: canReplyHere ? commentBlue : Colors.grey,
                      selected: canReplyHere && showReplyInput,
                      onTap: () {
                        if (!canReplyHere) {
                          AppSnackBar.show(
                            context,
                            'Maximum reply depth ($_maxReplyDepth levels) reached.',
                            type: AppSnackBarType.error,
                          );
                          return;
                        }
                        _startReply(commentId, replyId: replyId);
                      },
                    ),
                    if (replyCount > 0)
                      _buildCommentAction(
                        icon: isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        label: isExpanded ? 'Hide replies' : 'View replies',
                        color: appBlack,
                        selected: isExpanded,
                        onTap: () => _toggleNestedReplies(commentId, replyId),
                      ),
                  ],
                ),
                if (showReplyInput && canReplyHere) ...[
                  const SizedBox(height: 8),
                  _buildReplyComposer(
                    commentId: commentId,
                    parentReplyId: replyId,
                    replyingToAuthor: author,
                  ),
                ],
                if (isExpanded &&
                    nestedReplies.isNotEmpty &&
                    canShowChildren) ...[
                  const SizedBox(height: 4),
                  Column(
                    children: _buildReplyTree(
                      commentId,
                      parentReplyId: replyId,
                      depth: depth + 1,
                    ),
                  ),
                ],
                if (isExpanded &&
                    nestedReplies.isNotEmpty &&
                    !canShowChildren) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Additional replies hidden (depth limit reached).',
                    style: TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return DateFormat('MMM dd').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Comments (${widget.report['comments'] ?? 0})',
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: appBlack),
                    ),
                  ],
                ),
              ),

              // Report info
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.grey[50],
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${widget.report['title']} \u2022 ${widget.report['status']}",
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Comments list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No comments yet',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to comment!',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          final author = comment['author'] as String;
                          final initial = author.isNotEmpty
                              ? author[0].toUpperCase()
                              : '?';
                          final commentId = comment['id'] as String;
                          final timestamp = comment['timestamp'] as DateTime;
                          final timeAgo = _formatTimeAgo(timestamp);
                          final vote = comment['userVote'] as String? ?? 'none';
                          final verifySelected = vote == 'green';
                          final reportSelected = vote == 'red';
                          final loadedReplyCount =
                              _repliesByCommentId[commentId]?.length;
                          final replyCount =
                              loadedReplyCount ??
                              (comment['replyCount'] as int? ?? 0);
                          final isExpanded = _expandedReplyComments.contains(
                            commentId,
                          );
                          final isLoadingReplies =
                              _loadingReplies[commentId] == true;
                          final topLevelReplies = _repliesForParent(commentId);
                          final showReplyInput =
                              _replyingToCommentId == commentId &&
                              _replyingToReplyId == null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: appBlue,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Comment bubble
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              author,
                                              style: const TextStyle(
                                                fontFamily: 'RobotoCondensed',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: appBlack,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              comment['text'],
                                              style: const TextStyle(
                                                fontFamily: 'RobotoCondensed',
                                                fontSize: 13,
                                                color: appBlack,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        timeAgo,
                                        style: TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          _buildCommentAction(
                                            icon: Icons.verified,
                                            label:
                                                'Verify ${_nonNegativeInt(comment['greenFlags'])}',
                                            color: appGreen,
                                            selected: verifySelected,
                                            onTap: () =>
                                                _onCommentVerify(index),
                                          ),
                                          _buildCommentAction(
                                            icon: Icons.flag,
                                            label:
                                                'Report ${_nonNegativeInt(comment['redFlags'])}',
                                            color: appRed,
                                            selected: reportSelected,
                                            onTap: () =>
                                                _onCommentReport(index),
                                          ),
                                          _buildCommentAction(
                                            icon: Icons.reply,
                                            label: replyCount > 0
                                                ? 'Reply ($replyCount)'
                                                : 'Reply',
                                            color: commentBlue,
                                            selected: showReplyInput,
                                            onTap: () => _startReply(commentId),
                                          ),
                                          if (replyCount > 0)
                                            _buildCommentAction(
                                              icon: isExpanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              label: isExpanded
                                                  ? 'Hide replies'
                                                  : 'View replies',
                                              color: appBlack,
                                              selected: isExpanded,
                                              onTap: () =>
                                                  _toggleReplies(commentId),
                                            ),
                                        ],
                                      ),
                                      if (isExpanded) ...[
                                        const SizedBox(height: 4),
                                        if (isLoadingReplies)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        else if (topLevelReplies.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 10,
                                              top: 6,
                                            ),
                                            child: Text(
                                              'No replies yet.',
                                              style: TextStyle(
                                                fontFamily: 'RobotoCondensed',
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          )
                                        else
                                          Column(
                                            children: _buildReplyTree(
                                              commentId,
                                            ),
                                          ),
                                      ],
                                      if (showReplyInput) ...[
                                        const SizedBox(height: 8),
                                        _buildReplyComposer(
                                          commentId: commentId,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Comment input
              Container(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: bottomPadding + 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        maxLines: null,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(256),
                        ],
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 14,
                          color: appBlack,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          hintStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _isPostingComment ? null : _postComment,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _isPostingComment
                              ? appBlue.withOpacity(0.6)
                              : appBlue,
                          shape: BoxShape.circle,
                        ),
                        child: _isPostingComment
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// COMMENTS PAGE (Full Screen) - Legacy, kept for reference
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _CommentsPage extends StatefulWidget {
  final Map<String, dynamic> report;

  const _CommentsPage({required this.report});

  @override
  State<_CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<_CommentsPage> {
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFAC1B22);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final TextEditingController _commentController = TextEditingController();
  String _commentFilter = 'All Comments';
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _isPostingComment = false;
  static const Duration _commentPostCooldown = Duration(seconds: 5);
  static const Duration _duplicateCommentWindow = Duration(seconds: 25);
  Timer? _commentCooldownTimer;
  DateTime? _commentCooldownUntil;
  int _commentCooldownSeconds = 0;
  String? _lastPostedCommentSignature;
  DateTime? _lastPostedCommentAt;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCooldownTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  bool get _isCommentSendLocked =>
      _isPostingComment || _commentCooldownSeconds > 0;

  void _startCommentCooldown([Duration duration = _commentPostCooldown]) {
    _commentCooldownTimer?.cancel();
    final cooldownUntil = DateTime.now().add(duration);
    if (mounted) {
      setState(() {
        _commentCooldownUntil = cooldownUntil;
        _commentCooldownSeconds = duration.inSeconds;
      });
    } else {
      _commentCooldownUntil = cooldownUntil;
      _commentCooldownSeconds = duration.inSeconds;
    }

    _commentCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final until = _commentCooldownUntil;
      if (until == null) {
        timer.cancel();
        return;
      }
      final remaining = until.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _commentCooldownSeconds = 0;
          _commentCooldownUntil = null;
        });
        return;
      }
      setState(() => _commentCooldownSeconds = remaining);
    });
  }

  bool _isDuplicateCommentBurst(String signature) {
    final lastSignature = _lastPostedCommentSignature;
    final lastPostedAt = _lastPostedCommentAt;
    if (lastSignature == null || lastPostedAt == null) {
      return false;
    }
    if (lastSignature != signature) {
      return false;
    }
    return DateTime.now().difference(lastPostedAt) < _duplicateCommentWindow;
  }

  Future<void> _loadComments() async {
    try {
      final reportId = widget.report['id']?.toString() ?? '';

      _debugLog(
        'ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¥ Loading comments from nested collection for reportId: $reportId',
      );

      // Load from nested comments collection
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .orderBy('timestamp', descending: true)
          .get();

      _debugLog(
        'ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Loaded ${snapshot.docs.length} comments from nested collection',
      );

      final comments = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final timestamp = (data['timestamp'] as Timestamp).toDate();
            final type = (data['type'] as String?)?.toLowerCase();
            if (type == 'admin') {
              return null;
            }

            return {
              'id': doc.id,
              'text': data['text'] ?? '',
              'author': data['author'] ?? 'Anonymous',
              'timestamp': timestamp,
              'greenFlags': _nonNegativeInt(data['greenFlags']),
              'redFlags': _nonNegativeInt(data['redFlags']),
              'userVote': 'none',
              // Report credentials
              'reportId': data['reportId'] ?? '',
              'reportTitle': data['reportTitle'] ?? '',
              'reportCategory': data['reportCategory'] ?? '',
              'reportStatus': data['reportStatus'] ?? '',
              'reportDate': data['reportDate'] ?? '',
              'reportTime': data['reportTime'] ?? '',
              'reportedBy': data['reportedBy'] ?? '',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _comments = comments;
        _loading = false;
      });

      _debugLog(
        'ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Loaded ${comments.length} comments from Firestore',
      );
    } catch (e) {
      _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to load comments: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _postComment() async {
    if (_isPostingComment) return;
    if (_commentCooldownSeconds > 0) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Please wait $_commentCooldownSeconds seconds before posting again.',
        type: AppSnackBarType.warning,
      );
      return;
    }
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;
    if (commentText.length > 256) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Comment must be 256 characters or less.',
        type: AppSnackBarType.error,
      );
      return;
    }
    setState(() => _isPostingComment = true);

    try {
      _debugLog('=== POSTING COMMENT ===');
      _debugLog('Report data: ${widget.report}');

      // Safely extract report data
      final reportId = widget.report['id']?.toString() ?? '';
      final reportTitle = widget.report['title']?.toString() ?? '';
      final reportStatusRaw = widget.report['status']?.toString() ?? '';
      final reportStatus = reportStatusRaw;
      final reportDate = widget.report['date']?.toString() ?? '';
      final reportTime = widget.report['time']?.toString() ?? '';
      final reportedBy = widget.report['name']?.toString() ?? '';

      if (reportId.isEmpty) {
        _debugLog(
          'ÃƒÂ¢Ã‚ÂÃ…â€™ ERROR: reportId is empty! Cannot post comment.',
        );
        if (mounted) {
          AppSnackBar.show(
            context,
            'Error: Report ID is missing',
            type: AppSnackBarType.error,
          );
        }
        return;
      }

      _debugLog('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â Posting comment with report credentials:');
      _debugLog('  - reportId: $reportId');
      _debugLog('  - reportTitle: $reportTitle');
      _debugLog('  - reportStatus: $reportStatus');
      _debugLog('  - reportedBy: $reportedBy');

      // Get the current user's name from UserSession
      final userName =
          UserSession.currentUserData?['fullName'] as String? ?? 'Anonymous';
      final commentSignature =
          '${reportId.trim().toLowerCase()}|${userName.trim().toLowerCase()}|${commentText.toLowerCase()}';
      if (_isDuplicateCommentBurst(commentSignature)) {
        if (!mounted) return;
        _startCommentCooldown(const Duration(seconds: 3));
        AppSnackBar.show(
          context,
          'Duplicate comment blocked. Please edit your comment.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      final newComment = {
        'text': commentText,
        'author': userName,
        'type': 'user',
        'timestamp': Timestamp.now(),
        'greenFlags': 0,
        'redFlags': 0,
        'replyCount': 0,
        // Report credentials
        'reportId': reportId,
        'reportTitle': reportTitle,
        'reportCategory': reportTitle,
        'reportStatus': reportStatus,
        'reportDate': reportDate,
        'reportTime': reportTime,
        'reportedBy': reportedBy,
      };

      _debugLog('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¤ Comment data structure: $newComment');
      _debugLog('ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â Saving to nested comments collection...');

      // Save to nested comments collection (for display in UI)
      final savedDocRef = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(newComment);

      _debugLog(
        'ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Comment saved to nested collection with ID: ${savedDocRef.id}',
      );

      // Try to update report document with new comment count
      // If this fails due to permissions, it won't block the comment from being saved
      try {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({'comments': FieldValue.increment(1)});
        _debugLog('ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Report comment count incremented');
        if (mounted) {
          setState(() {
            final currentCount = widget.report['comments'] as int? ?? 0;
            widget.report['comments'] = currentCount + 1;
          });
        }
      } catch (updateError) {
        _debugLog(
          'ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Warning: Could not update comment count: $updateError',
        );
        // Don't fail the entire operation if count update fails
      }

      _commentController.clear();
      _lastPostedCommentSignature = commentSignature;
      _lastPostedCommentAt = DateTime.now();
      _startCommentCooldown();

      // Reload comments
      await _loadComments();

      if (mounted) {
        AppSnackBar.show(
          context,
          'Comment posted successfully',
          type: AppSnackBarType.success,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to post comment: $e');
      _debugLog('Stack trace: ${StackTrace.current}');
      _debugLog('Error type: ${e.runtimeType}');
      _startCommentCooldown(const Duration(seconds: 2));
      if (mounted) {
        // Show detailed error in dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error Posting Comment'),
            content: Text(
              'Failed to save comment to Firestore:\n\n$e\n\nPlease check:\n1. Internet connection\n2. Firestore rules are deployed\n3. Firebase is initialized',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPostingComment = false);
      }
    }
  }

  Future<void> _onCommentGreenFlag(int commentIndex) async {
    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String;

    try {
      int newGreenCount = _nonNegativeInt(comment['greenFlags']);
      int newRedCount = _nonNegativeInt(comment['redFlags']);
      String newVote = vote;

      if (vote == 'green') {
        // Unvote
        newGreenCount = (newGreenCount > 0) ? newGreenCount - 1 : 0;
        newVote = 'none';
      } else {
        // Vote green
        if (vote == 'red' && newRedCount > 0) {
          newRedCount--;
        }
        newGreenCount++;
        newVote = 'green';
      }

      newGreenCount = _nonNegativeInt(newGreenCount);
      newRedCount = _nonNegativeInt(newRedCount);

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.report['id'] as String)
          .collection('comments')
          .doc(comment['id'] as String)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      setState(() {
        comment['greenFlags'] = newGreenCount;
        comment['redFlags'] = newRedCount;
        comment['userVote'] = newVote;
      });
    } catch (e) {
      _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to update comment vote: $e');
    }
  }

  Future<void> _onCommentRedFlag(int commentIndex) async {
    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String;

    try {
      int newGreenCount = _nonNegativeInt(comment['greenFlags']);
      int newRedCount = _nonNegativeInt(comment['redFlags']);
      String newVote = vote;

      if (vote == 'red') {
        // Unvote
        newRedCount = (newRedCount > 0) ? newRedCount - 1 : 0;
        newVote = 'none';
      } else {
        // Vote red
        if (vote == 'green' && newGreenCount > 0) {
          newGreenCount--;
        }
        newRedCount++;
        newVote = 'red';
      }

      newGreenCount = _nonNegativeInt(newGreenCount);
      newRedCount = _nonNegativeInt(newRedCount);

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.report['id'] as String)
          .collection('comments')
          .doc(comment['id'] as String)
          .update({'greenFlags': newGreenCount, 'redFlags': newRedCount});

      setState(() {
        comment['greenFlags'] = newGreenCount;
        comment['redFlags'] = newRedCount;
        comment['userVote'] = newVote;
      });
    } catch (e) {
      _debugLog('ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to update comment vote: $e');
    }
  }

  List<Map<String, dynamic>> _getFilteredComments() {
    switch (_commentFilter) {
      case 'Recent':
        final sorted = List<Map<String, dynamic>>.from(_comments);
        sorted.sort((a, b) {
          final aTime = a['timestamp'] as DateTime;
          final bTime = b['timestamp'] as DateTime;
          return bTime.compareTo(aTime);
        });
        return sorted;
      case 'Popular':
        final sorted = List<Map<String, dynamic>>.from(_comments);
        sorted.sort((a, b) {
          final aScore = (a['greenFlags'] as int) - (a['redFlags'] as int);
          final bScore = (b['greenFlags'] as int) - (b['redFlags'] as int);
          return bScore.compareTo(aScore);
        });
        return sorted;
      default:
        return _comments;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredComments = _getFilteredComments();

    return Scaffold(
      backgroundColor: appOffWhite,
      appBar: AppBar(
        backgroundColor: appBlue,
        elevation: 0,
        leading: ResqBackButton(
          style: ResqBackButtonStyle.ghost,
          iconColor: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Comments (${widget.report['comments']})',
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // REPORT DETAILS HEADER
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report: ${widget.report['title']}',
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: appBlack,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status: ${widget.report['status']}',
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      'By: ${widget.report['name']}',
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // FILTER BAR
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Filter:',
                  style: const TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: appBlack,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: appOffWhite,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: appBlue.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _commentFilter,
                      dropdownColor: Colors.white,
                      iconEnabledColor: appBlue,
                      focusColor: Colors.transparent,
                      style: const TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: appBlack,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'All Comments',
                          child: Text('All Comments'),
                        ),
                        DropdownMenuItem(
                          value: 'Recent',
                          child: Text('Recent'),
                        ),
                        DropdownMenuItem(
                          value: 'Popular',
                          child: Text('Popular'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _commentFilter = v ?? _commentFilter),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // COMMENTS LIST
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredComments.isEmpty
                ? Center(
                    child: Text(
                      'No comments yet.\nBe the first to comment!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredComments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final comment = filteredComments[index];
                      final vote = comment['userVote'] as String;
                      final greenSelected = vote == 'green';
                      final redSelected = vote == 'red';

                      final greenColor = greenSelected
                          ? appGreen
                          : appGreen.withOpacity(0.6);
                      final redColor = redSelected
                          ? appRed
                          : appRed.withOpacity(0.6);

                      final timestamp = comment['timestamp'] as DateTime;
                      final timeAgo = _formatTimeAgo(timestamp);

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: appBlack.withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // AUTHOR + TIME
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: appBlue,
                                  child: Text(
                                    comment['author'][0].toUpperCase(),
                                    style: const TextStyle(
                                      fontFamily: 'RobotoCondensed',
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        comment['author'],
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: appBlack,
                                        ),
                                      ),
                                      Text(
                                        timeAgo,
                                        style: TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // COMMENT TEXT
                            Text(
                              comment['text'],
                              style: const TextStyle(
                                inherit: false,
                                fontFamily: 'RobotoCondensed',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // FLAGS
                            Row(
                              children: [
                                // GREEN FLAG
                                InkWell(
                                  onTap: () => _onCommentGreenFlag(index),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: greenSelected
                                          ? appGreen.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                          color: greenColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_nonNegativeInt(comment['greenFlags'])}',
                                          style: const TextStyle(
                                            fontFamily: 'RobotoCondensed',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: appBlack,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 16),

                                // RED FLAG
                                InkWell(
                                  onTap: () => _onCommentRedFlag(index),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: redSelected
                                          ? appRed.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.flag,
                                          size: 18,
                                          color: redColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_nonNegativeInt(comment['redFlags'])}',
                                          style: const TextStyle(
                                            fontFamily: 'RobotoCondensed',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: appBlack,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // COMMENT INPUT
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    maxLines: null,
                    inputFormatters: [LengthLimitingTextInputFormatter(256)],
                    style: const TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: appBlack,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Write a comment...',
                      hintStyle: const TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isCommentSendLocked ? null : _postComment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCommentSendLocked
                        ? appBlue.withValues(alpha: 0.6)
                        : appBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: _isPostingComment
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : _commentCooldownSeconds > 0
                      ? Text(
                          '${_commentCooldownSeconds}s',
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Text(
                          'Post',
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd').format(timestamp);
    }
  }
}

// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
// IMAGE ZOOM DIALOG
// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â

class _ImageZoomDialog extends StatelessWidget {
  final String imageUrl;

  const _ImageZoomDialog({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(
                    height: 260,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const SizedBox(
                    height: 260,
                    child: Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
// FIREBASE STORAGE IMAGE LOADER
// ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
/// Loads images directly from Firebase Storage using the download URL
/// Uses Image.memory for better control and error handling

class _NetworkImageLoader extends StatelessWidget {
  final String url;
  final int? cacheWidth;
  final int? cacheHeight;

  const _NetworkImageLoader({
    required this.url,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      maxHeightDiskCache: cacheHeight,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.error_outline, size: 36, color: Colors.red),
        ),
      ),
    );
  }
}
