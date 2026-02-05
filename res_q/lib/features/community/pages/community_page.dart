import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../../../common/services/user_session.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with WidgetsBindingObserver {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFAC1B22);
  static const appGreen = Color(0xFF00A458); // True green
  static const appYellow = Color(0xFFFFC806); // Yellow for under review
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const commentBlue = Color(0xFF2563EB);
  static const statusGreen = Color(0xFF00A458); // Approved
  static const statusYellow = Color(0xFFFFC806); // Under Review
  static const statusRed = Color(0xFFAC1B22); // Flagged

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';
  String _selectedTimeFilter = 'All Time';
  bool _showFilterSheet = false;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _announcements = [];
  Map<String, String> _userVotes = {}; // reportId -> 'green' or 'red'
  bool _checkedLegacyVotes = false;
  bool _votesLoaded = false; // Track if votes have been loaded
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _announcementsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedFilter = _normalizeFilter(_selectedFilter);
    _subscribeToReports();
    _subscribeToAnnouncements();
    // Delay loading votes to ensure UserSession is initialized after login
    _initializeVotes();
    _ensureCommentsCollectionExists();
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
      debugPrint('⚠️ No user data available');
      return null;
    }

    // Try different possible field names for phone number
    // Note: Firestore uses 'contactNumber' as the primary field
    String? phone =
        userData['contactNumber']?.toString() ??
        userData['phoneNumber']?.toString() ??
        userData['phone']?.toString() ??
        userData['mobileNumber']?.toString();

    if (phone != null) {
      // Remove all non-numeric characters
      phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    }

    debugPrint('📱 Found logged-in user phone: $phone');
    return phone;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportsSubscription?.cancel();
    _announcementsSubscription?.cancel();
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
            debugPrint('❌ Failed to load announcements: $e');
          },
        );
  }

  Future<void> _loadUserVotes() async {
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) {
      debugPrint('⚠️ No phone number available for loading votes');
      return;
    }

    try {
      debugPrint('📥 Loading votes for phone: $userPhone');

      // Load votes from userVotes collection using phone number as document ID
      final doc = await FirebaseFirestore.instance
          .collection('userVotes')
          .doc(userPhone)
          .get();

      if (mounted) {
        if (doc.exists) {
          final data = doc.data() ?? {};
          final loadedVotes = Map<String, String>.from(data['votes'] ?? {});
          debugPrint('✅ Loaded ${loadedVotes.length} votes from Firestore');
          debugPrint('📋 Votes: $loadedVotes');
          setState(() {
            _userVotes = loadedVotes;
            _votesLoaded = true;
          });
        } else {
          debugPrint('ℹ️ No votes document found for phone: $userPhone');
          setState(() {
            _userVotes = {};
            _votesLoaded = true;
          });
        }
        // Update reports with user votes
        _applyUserVotesToReports();
      }
    } catch (e) {
      debugPrint('❌ Failed to load user votes: $e');
      if (mounted) {
        setState(() {
          _votesLoaded = true;
        });
      }
    }
  }

  void _applyUserVotesToReports() {
    if (_reports.isEmpty) return;

    setState(() {
      for (int i = 0; i < _reports.length; i++) {
        final reportId = _reports[i]['id'] as String?;
        if (reportId != null) {
          // Apply vote from _userVotes, default to 'none' if not found
          _reports[i]['userVote'] = _userVotes[reportId] ?? 'none';
        }
      }
    });
    debugPrint(
      '🔄 Applied ${_userVotes.length} user votes to ${_reports.length} reports',
    );
  }

  Future<void> _saveUserVote(String reportId, String vote) async {
    final userPhone = _getLoggedInUserPhone();
    if (userPhone == null || userPhone.isEmpty) {
      debugPrint('⚠️ Cannot save vote: No phone number found');
      return;
    }

    try {
      // Update local cache
      if (vote == 'none') {
        _userVotes.remove(reportId);
      } else {
        _userVotes[reportId] = vote;
      }

      debugPrint('🔐 Attempting to save vote to Firestore...');
      debugPrint('   Phone: $userPhone');
      debugPrint('   Report ID: $reportId');
      debugPrint('   Vote: $vote');
      debugPrint('   Total votes in map: ${_userVotes.length}');

      // Save to userVotes collection with phone number as document ID
      // Structure: userVotes/{phoneNumber}/votes/{reportId: voteType}
      await FirebaseFirestore.instance
          .collection('userVotes')
          .doc(userPhone)
          .set({'votes': _userVotes});

      debugPrint('💾 ✅ Successfully saved vote "$vote" for report $reportId');

      // Also save individual vote record for better tracking
      // Structure: voteRecords/{auto-id} with reportId, phone, voteType, timestamp
      await _saveVoteRecord(reportId, vote, userPhone);
    } catch (e) {
      debugPrint('❌ Failed to save user vote: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      // Re-add to local cache if removal failed
      if (vote != 'none') {
        _userVotes[reportId] = vote;
      }
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
      debugPrint('📝 Vote record saved to voteRecords collection');
    } catch (e) {
      debugPrint('⚠️ Could not save vote record: $e');
      // Don't fail the main operation if this fails
    }
  }

  Future<void> _migrateLegacyVotesIfNeeded(String userId) async {
    if (_checkedLegacyVotes) return;
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
    } catch (e) {
      debugPrint('❌ Failed to migrate legacy votes: $e');
    }
  }

  /// Ensure the comments collection exists by creating a marker document if needed
  Future<void> _ensureCommentsCollectionExists() async {
    try {
      // Check if collection exists by trying to get a single document
      final snapshot = await FirebaseFirestore.instance
          .collection('comments')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        // Collection is empty or doesn't exist, create a marker document
        debugPrint('📝 Creating comments collection with marker document...');
        await FirebaseFirestore.instance
            .collection('comments')
            .doc('_marker')
            .set({
              'initialized': true,
              'createdAt': Timestamp.now(),
              'note': 'Marker document for collection initialization',
            });
        debugPrint('✅ Comments collection initialized');
      } else {
        debugPrint('✅ Comments collection already exists');
      }
    } catch (e) {
      debugPrint('⚠️ Could not initialize comments collection: $e');
    }
  }

  void _subscribeToReports() {
    _reportsSubscription?.cancel();
    _reportsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('reportedAt', descending: true)
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
            setState(() {
              _reports = reports;
            });
            debugPrint('✅ Loaded ${reports.length} reports from Firestore');
          },
          onError: (e) {
            debugPrint('❌ Failed to load reports: $e');
          },
        );
  }

  Map<String, dynamic> _mapReportFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
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
      'greenFlags': data['greenFlags'] ?? 0,
      'redFlags': data['redFlags'] ?? 0,
      'status': data['status'] ?? 'Pending',
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

  List<Map<String, dynamic>> _getVisibleReports() {
    final filtered = _reports.where((report) {
      final status = (report['status'] as String? ?? '').toLowerCase();
      final category = (report['title'] as String? ?? '').toLowerCase();
      final resolvedAt = report['resolvedAt'] as DateTime?;
      final reportedAt = report['reportedAt'] as DateTime?;

      if ((status == 'resolved' || status == 'incident resolved') &&
          resolvedAt != null) {
        final elapsed = DateTime.now().difference(resolvedAt);
        if (elapsed >= const Duration(hours: 1)) {
          return false;
        }
      }

      bool matchesFilter;
      switch (_selectedFilter) {
        case 'Approved':
          matchesFilter =
              status == 'approved' ||
              status == 'resolved' ||
              status == 'incident resolved';
          break;
        case 'Under Review':
          matchesFilter = status == 'pending' || status == 'under review';
          break;
        case 'Flagged':
          matchesFilter = status == 'flagged';
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

  // ───────────────── DIALOG HELPERS ─────────────────

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

  // ───────────────── MEDIA BUILDER ─────────────────

  Widget _buildMediaWidget(Map<String, dynamic> report) {
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
    final mediaType = (report['mediaType'] as String? ?? 'photo').toLowerCase();

    // Debug: log what we're trying to load
    debugPrint('🖼️ Media load -> type: ' + mediaType + ', url: ' + mediaUrl);

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
      debugPrint('🔗 Converted storage path to download URL: $downloadUrl');
    }

    // Firebase Storage URLs are network images
    return _NetworkImageLoader(url: downloadUrl);
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

  // ───────────────── IMAGE ZOOM DIALOG ─────────────────

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
    final sourceIndex = _reports.indexWhere(
      (item) => item['id'] == report['id'],
    );
    final int reportIndex = sourceIndex == -1 ? 0 : sourceIndex;
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
                              child: _buildMediaWidget(report),
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
                                        Icons.flag,
                                        size: 18,
                                        color: greenIconColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${report['greenFlags']}',
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
                                        '${report['redFlags']}',
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

  // ───────────────── FLAG LOGIC (WITH DIALOG) ─────────────────

  Future<void> _onGreenFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];
    final reportId = report['id']?.toString() ?? '';

    // Already green → quick unverify
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

      setState(() {
        if (report['greenFlags'] > 0) report['greenFlags']--;
        report['userVote'] = 'none';
      });
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
        'Other...',
      ],
    );

    if (!confirmed) return;

    // Update _userVotes immediately so Firestore listener uses correct value
    _userVotes[reportId] = 'green';

    setState(() {
      if (vote == 'red' && report['redFlags'] > 0) {
        report['redFlags']--;
      }
      report['greenFlags']++;
      report['userVote'] = 'green';
    });
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

    // Already red → quick unflag
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

      setState(() {
        if (report['redFlags'] > 0) report['redFlags']--;
        report['userVote'] = 'none';
      });
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
        'False/Misleading Information',
        'Inappropriate Content',
        'Flagged/Lack of Evidence',
        'Spam/Irrelevant Content',
        'Other...',
      ],
    );

    if (!confirmed) return;

    // Update _userVotes immediately so Firestore listener uses correct value
    _userVotes[reportId] = 'red';

    setState(() {
      if (vote == 'green' && report['greenFlags'] > 0) {
        report['greenFlags']--;
      }
      report['redFlags']++;
      report['userVote'] = 'red';
    });
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
    final updates = <String, dynamic>{};
    if (greenDelta != 0) {
      updates['greenFlags'] = FieldValue.increment(greenDelta);
    }
    if (redDelta != 0) {
      updates['redFlags'] = FieldValue.increment(redDelta);
    }
    if (updates.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update(updates);
    } catch (e) {
      debugPrint('⚠️ Failed to update report flags: $e');
    }
  }

  // ───────────────── COMMENTS BOTTOM SHEET ─────────────────

  void _openComments(int index) {
    final report = _reports[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsBottomSheet(
        report: report,
        onCommentAdded: () {
          setState(() {
            final currentCount = report['comments'] as int? ?? 0;
            report['comments'] = currentCount + 1;
          });
        },
      ),
    );
  }

  // ───────────────── TIME FORMATTER ─────────────────

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

  // ───────────────── FILTER & ANNOUNCEMENT HELPERS ─────────────────

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
                        setState(() {});
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
                            setState(() {});
                          },
                          selectedColor: appBlue,
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
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
                            setState(() {});
                          },
                          selectedColor: appBlue,
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
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
                            setState(() {});
                          },
                          selectedColor: appBlue,
                          labelStyle: TextStyle(
                            fontFamily: 'RobotoCondensed',
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((announcement['imageUrl'] as String?)?.isNotEmpty ==
                          true)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            announcement['imageUrl'],
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
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
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    final visibleReports = _getVisibleReports();

    return Container(
      color: appOffWhite,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE
            Center(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Roboto',
                  ),
                  children: const [
                    TextSpan(
                      text: 'C',
                      style: TextStyle(color: appBlue),
                    ),
                    TextSpan(
                      text: 'O',
                      style: TextStyle(color: const Color(0xFFFFC806)),
                    ),
                    TextSpan(
                      text: 'MMUNITY',
                      style: TextStyle(color: appBlue),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ANNOUNCEMENTS SECTION (horizontal scroll)
            if (_announcements.isNotEmpty) ...[
              Text(
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
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final announcement = _announcements[index];
                    return GestureDetector(
                      onTap: () => _showAnnouncementDetail(announcement),
                      child: Container(
                        width: 200,
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
                              child: Text(
                                announcement['content'] ?? '',
                                style: TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
              child: ListView.separated(
                itemCount: visibleReports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final report = visibleReports[index];
                  final statusLower = (report['status'] as String? ?? '')
                      .toLowerCase();
                  final sourceIndex = _reports.indexWhere(
                    (item) => item['id'] == report['id'],
                  );
                  final int reportIndex = sourceIndex == -1
                      ? index
                      : sourceIndex;
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
                  final mediaUrl = (report['image'] as String? ?? '').trim();

                  return GestureDetector(
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
                                                fontWeight: FontWeight.w700,
                                                color: appBlack,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // Status badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusLower == 'resolved' ||
                                                      statusLower ==
                                                          'incident resolved'
                                                  ? const Color(0xFF4CAF50)
                                                  : statusLower == 'approved'
                                                  ? statusGreen
                                                  : statusLower == 'flagged'
                                                  ? statusRed
                                                  : statusYellow,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              statusLower == 'resolved' ||
                                                      statusLower ==
                                                          'incident resolved'
                                                  ? 'RESOLVED'
                                                  : report['status']
                                                        .toString()
                                                        .toUpperCase(),
                                              style: const TextStyle(
                                                fontFamily: 'RobotoCondensed',
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
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
                                              fontFamily: 'RobotoCondensed',
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          // Only show location if it's provided
                                          if ((report['location'] ??
                                                  'Not provided') !=
                                              'Not provided') ...[
                                            Text(
                                              ' • ',
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
                                                  fontFamily: 'RobotoCondensed',
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                                overflow: TextOverflow.ellipsis,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                              child: _buildMediaWidget(report),
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
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // GREEN FLAG (Verify)
                                Expanded(
                                  child: InkWell(
                                    onTap: () =>
                                        _onGreenFlagPressed(reportIndex),
                                    borderRadius: BorderRadius.circular(8),
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
                                            'Verify ${report['greenFlags']}',
                                            style: TextStyle(
                                              fontFamily: 'RobotoCondensed',
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
                                    onTap: () => _onRedFlagPressed(reportIndex),
                                    borderRadius: BorderRadius.circular(8),
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
                                            'Report ${report['redFlags']}',
                                            style: TextStyle(
                                              fontFamily: 'RobotoCondensed',
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
                                    onTap: () => _openComments(reportIndex),
                                    borderRadius: BorderRadius.circular(8),
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
                                              fontFamily: 'RobotoCondensed',
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

// ═══════════════════════════════════════════════════════════════════════════
// COMMENTS BOTTOM SHEET (Draggable)
// ═══════════════════════════════════════════════════════════════════════════

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

  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
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
              'greenFlags': data['greenFlags'] ?? 0,
              'redFlags': data['redFlags'] ?? 0,
              'userVote': 'none',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load comments: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) return;

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
        'text': _commentController.text.trim(),
        'author': userName,
        'type': 'user',
        'timestamp': Timestamp.now(),
        'greenFlags': 0,
        'redFlags': 0,
        'reportId': reportId,
        'reportTitle': reportTitle,
        'reportCategory': reportTitle,
        'reportStatus': reportStatus,
        'reportDate': reportDate,
        'reportTime': reportTime,
        'reportedBy': reportedBy,
      };

      final savedDocRef = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(newComment);

      // Also save to root comments collection
      try {
        await FirebaseFirestore.instance
            .collection('comments')
            .doc(savedDocRef.id)
            .set(newComment);
      } catch (_) {}

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to post comment: $e');
    }
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
                        '${widget.report['title']} • ${widget.report['status']}',
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
                          final timestamp = comment['timestamp'] as DateTime;
                          final timeAgo = _formatTimeAgo(timestamp);

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
                      onTap: _postComment,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: appBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
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

// ═══════════════════════════════════════════════════════════════════════════
// COMMENTS PAGE (Full Screen) - Legacy, kept for reference
// ═══════════════════════════════════════════════════════════════════════════

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
  static const appYellow = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const commentBlue = Color(0xFF2563EB);

  final TextEditingController _commentController = TextEditingController();
  String _commentFilter = 'All Comments';
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final reportId = widget.report['id']?.toString() ?? '';

      debugPrint(
        '📥 Loading comments from nested collection for reportId: $reportId',
      );

      // Load from nested comments collection
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .orderBy('timestamp', descending: true)
          .get();

      debugPrint(
        '✅ Loaded ${snapshot.docs.length} comments from nested collection',
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
              'greenFlags': data['greenFlags'] ?? 0,
              'redFlags': data['redFlags'] ?? 0,
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

      debugPrint('✅ Loaded ${comments.length} comments from Firestore');
    } catch (e) {
      debugPrint('❌ Failed to load comments: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      debugPrint('=== POSTING COMMENT ===');
      debugPrint('Report data: ${widget.report}');

      // Safely extract report data
      final reportId = widget.report['id']?.toString() ?? '';
      final reportTitle = widget.report['title']?.toString() ?? '';
      final reportStatusRaw = widget.report['status']?.toString() ?? '';
      final reportStatus = reportStatusRaw;
      final statusLower = reportStatusRaw.toLowerCase();
      final isResolved =
          statusLower == 'resolved' || statusLower == 'incident resolved';
      final reportDate = widget.report['date']?.toString() ?? '';
      final reportTime = widget.report['time']?.toString() ?? '';
      final reportedBy = widget.report['name']?.toString() ?? '';

      if (reportId.isEmpty) {
        debugPrint('❌ ERROR: reportId is empty! Cannot post comment.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Report ID is missing'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      debugPrint('📝 Posting comment with report credentials:');
      debugPrint('  - reportId: $reportId');
      debugPrint('  - reportTitle: $reportTitle');
      debugPrint('  - reportStatus: $reportStatus');
      debugPrint('  - reportedBy: $reportedBy');

      // Get the current user's name from UserSession
      final userName =
          UserSession.currentUserData?['fullName'] as String? ?? 'Anonymous';

      final newComment = {
        'text': _commentController.text.trim(),
        'author': userName,
        'type': 'user',
        'timestamp': Timestamp.now(),
        'greenFlags': 0,
        'redFlags': 0,
        // Report credentials
        'reportId': reportId,
        'reportTitle': reportTitle,
        'reportCategory': reportTitle,
        'reportStatus': reportStatus,
        'reportDate': reportDate,
        'reportTime': reportTime,
        'reportedBy': reportedBy,
      };

      debugPrint('📤 Comment data structure: $newComment');
      debugPrint('🔐 Saving to nested comments collection...');

      // Save to nested comments collection (for display in UI)
      final savedDocRef = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(newComment);

      debugPrint(
        '✅ Comment saved to nested collection with ID: ${savedDocRef.id}',
      );

      // Also save to root-level comments collection (for easy admin access)
      debugPrint('🔐 Also saving to root comments collection...');
      try {
        await FirebaseFirestore.instance
            .collection('comments')
            .doc(savedDocRef.id)
            .set(newComment);
        debugPrint('✅ Comment also saved to root collection');
      } catch (rootError) {
        debugPrint('⚠️ Warning: Could not save to root collection: $rootError');
        // Don't fail if root collection save fails
      }

      // Try to update report document with new comment count
      // If this fails due to permissions, it won't block the comment from being saved
      try {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({'comments': FieldValue.increment(1)});
        debugPrint('✅ Report comment count incremented');
        if (mounted) {
          setState(() {
            final currentCount = widget.report['comments'] as int? ?? 0;
            widget.report['comments'] = currentCount + 1;
          });
        }
      } catch (updateError) {
        debugPrint('⚠️ Warning: Could not update comment count: $updateError');
        // Don't fail the entire operation if count update fails
      }

      _commentController.clear();

      // Reload comments
      await _loadComments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to post comment: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      debugPrint('Error type: ${e.runtimeType}');
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
    }
  }

  Future<void> _onCommentGreenFlag(int commentIndex) async {
    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String;

    try {
      int newGreenCount = comment['greenFlags'] as int;
      int newRedCount = comment['redFlags'] as int;
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
      debugPrint('❌ Failed to update comment vote: $e');
    }
  }

  Future<void> _onCommentRedFlag(int commentIndex) async {
    final comment = _comments[commentIndex];
    final vote = comment['userVote'] as String;

    try {
      int newGreenCount = comment['greenFlags'] as int;
      int newRedCount = comment['redFlags'] as int;
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
      debugPrint('❌ Failed to update comment vote: $e');
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
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
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _commentFilter,
                      dropdownColor: Colors.white,
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
                                          Icons.flag,
                                          size: 18,
                                          color: greenColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${comment['greenFlags']}',
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
                                          '${comment['redFlags']}',
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
                  onPressed: _postComment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
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

// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
// IMAGE ZOOM DIALOG
// ═══════════════════════════════════════════════════════════════════════════

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
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return const SizedBox(
                      height: 260,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 260,
                      child: Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    );
                  },
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

// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
// FIREBASE STORAGE IMAGE LOADER
// ═══════════════════════════════════════════════════════════════════════════
/// Loads images directly from Firebase Storage using the download URL
/// Uses Image.memory for better control and error handling

class _NetworkImageLoader extends StatefulWidget {
  final String url;

  const _NetworkImageLoader({required this.url});

  @override
  State<_NetworkImageLoader> createState() => _NetworkImageLoaderState();
}

class _NetworkImageLoaderState extends State<_NetworkImageLoader> {
  int _retryCount = 0;
  static const int _maxRetries = 2;

  @override
  void initState() {
    super.initState();
    debugPrint('🖼️ [NetworkImageLoader] Init - URL: ${widget.url}');
  }

  void _retry() {
    if (_retryCount < _maxRetries) {
      setState(() => _retryCount++);
      debugPrint('🔄 Retry attempt ${_retryCount + 1}/$_maxRetries');
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('${widget.url}_retry$_retryCount');

    return Image.network(
      widget.url,
      key: key,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          debugPrint('✅ Image loaded successfully');
          return child;
        }
        final percent = loadingProgress.expectedTotalBytes != null
            ? (loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!) *
                  100
            : 0;
        debugPrint('⏳ Loading... ${percent.toStringAsFixed(0)}%');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                value: percent > 0 ? percent / 100 : null,
              ),
              const SizedBox(height: 8),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        String errorString = 'Unknown error';
        try {
          errorString = error?.toString() ?? 'Unknown error';
        } catch (e) {
          errorString = 'Error object inaccessible: $e';
        }

        debugPrint(
          '❌ [ImageLoader] Load failed:\n'
          '   URL: ${widget.url}\n'
          '   Error: $errorString\n'
          '   Type: ${error?.runtimeType ?? 'unknown'}',
        );

        String diagnosis = 'Failed to load image';

        if (errorString.contains('statusCode: 0')) {
          diagnosis = '📡 No Internet\n(Check connection or emulator network)';
        } else if (errorString.contains('401') ||
            errorString.contains('403') ||
            errorString.contains('Permission') ||
            errorString.contains('denied')) {
          diagnosis = '🔒 Access Denied\n(Check Storage Rules)';
        } else if (errorString.contains('404') ||
            errorString.contains('not found')) {
          diagnosis = '❌ File Not Found';
        } else if (errorString.contains('timeout') ||
            errorString.contains('Time out')) {
          diagnosis = '⏱️ Network Timeout';
        } else if (errorString.contains('Network') ||
            errorString.contains('Connection') ||
            errorString.contains('SocketException')) {
          diagnosis = '🌐 Network Error\n(Check internet connection)';
        } else if (errorString.contains('Certificate') ||
            errorString.contains('SSL')) {
          diagnosis = '🔐 SSL Error';
        }

        return Container(
          color: Colors.grey[300],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    diagnosis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                if (_retryCount < _maxRetries) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
