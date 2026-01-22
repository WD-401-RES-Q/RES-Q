import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../services/user_session.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFAC1B22);
  static const appGreen = Color(0xFF00A458); // True green
  static const appYellow = Color(0xFFFFC806); // Yellow for under review
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const statusGreen = Color(0xFF00A458); // Approved
  static const statusYellow = Color(0xFFFFC806); // Under Review
  static const statusRed = Color(0xFFAC1B22); // Flagged

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _reports = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _reportsSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToReports();
    _ensureCommentsCollectionExists(); // Initialize comments collection
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    super.dispose();
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
        .listen((snapshot) {
      final previousVotes = {
        for (final report in _reports)
          report['id']?.toString() ?? '': report['userVote'],
      };
      final reports = snapshot.docs.map(_mapReportFromDoc).toList();
      for (final report in reports) {
        final reportId = report['id']?.toString() ?? '';
        report['userVote'] = previousVotes[reportId] ?? 'none';
      }
      if (!mounted) return;
      setState(() {
        _reports = reports;
      });
      debugPrint('✅ Loaded ${reports.length} reports from Firestore');
    }, onError: (e) {
      debugPrint('❌ Failed to load reports: $e');
    });
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

    return {
      'id': doc.id,
      'image': data['mediaUrl'] ?? '',
      'date': dateFormat.format(reportedAt).toUpperCase(),
      'time': timeFormat.format(reportedAt).toUpperCase(),
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
    'Roads',
    'Earthquake',
    'Flood',
    'Fire',
    'Other',
  ];

  List<Map<String, dynamic>> _getVisibleReports() {
    return _reports.where((report) {
      final status = (report['status'] as String? ?? '').toLowerCase();
      final category = (report['title'] as String? ?? '').toLowerCase();
      final resolvedAt = report['resolvedAt'] as DateTime?;
      if ((status == 'resolved' || status == 'incident resolved') &&
          resolvedAt != null) {
        final elapsed = DateTime.now().difference(resolvedAt);
        if (elapsed >= const Duration(hours: 1)) {
          return false;
        }
      }

      bool matchesFilter;
      switch (_selectedFilter) {
        case 'Verified':
          matchesFilter = status == 'approved' || status == 'verified';
          break;
        case 'Under Review':
          matchesFilter = status == 'pending' || status == 'under review';
          break;
        case 'Unverified':
          matchesFilter = status == 'flagged' || status == 'unverified';
          break;
        default:
          matchesFilter = true;
      }

      final matchesCategory =
          _selectedCategory == 'All' ||
          category == _selectedCategory.toLowerCase();

      return matchesFilter && matchesCategory;
    }).toList();
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
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
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
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: headerColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Center(
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
                      ),

                      // BODY (White background)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
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
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.black,
                                            width: 2,
                                          ),
                                          color: selected[i]
                                              ? headerColor.withOpacity(0.1)
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
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  final hasReason = selected.contains(true);
                                  final hasComment = commentController.text
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
                    ],
                  );
                },
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

    // Firebase Storage URLs are network images - wrapped in GestureDetector for tap to zoom
    return GestureDetector(
      onTap: () => _showImageZoom(downloadUrl),
      child: _NetworkImageLoader(url: downloadUrl),
    );
  }

  // ───────────────── IMAGE ZOOM DIALOG ─────────────────

  void _showImageZoom(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => _ImageZoomDialog(imageUrl: imageUrl),
    );
  }

  // ───────────────── FLAG LOGIC (WITH DIALOG) ─────────────────

  Future<void> _onGreenFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];
    final reportId = report['id']?.toString() ?? '';

    // Already green → quick unverify
    if (vote == 'green') {
      setState(() {
        if (report['greenFlags'] > 0) report['greenFlags']--;
        report['userVote'] = 'none';
      });
      await _updateReportFlags(reportId, greenDelta: -1);
      return;
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
  }

  Future<void> _onRedFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];
    final reportId = report['id']?.toString() ?? '';

    // Already red → quick unflag
    if (vote == 'red') {
      setState(() {
        if (report['redFlags'] > 0) report['redFlags']--;
        report['userVote'] = 'none';
      });
      await _updateReportFlags(reportId, redDelta: -1);
      return;
    }

    // Show REPORT modal
    final bool confirmed = await _showReasonDialog(
      headerColor: appBlue,
      headerText: 'REPORT INCIDENT',
      question: 'Why are you flagging this report?',
      reasons: const [
        'False/Misleading Information',
        'Inappropriate Content',
        'Unverified/Lack of Evidence',
        'Spam/Irrelevant Content',
        'Other...',
      ],
    );

    if (!confirmed) return;

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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _CommentsPage(report: _reports[index]),
          ),
        )
        .then((_) => setState(() {}));
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

            // FILTERS
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'FILTER BY:  ',
                      style: TextStyle(
                        fontSize: 16,
                        color: appBlack,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 35,
                      width: 120,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedFilter,
                          dropdownColor: Colors.white,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: appBlack,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(
                              value: 'Verified',
                              child: Text('Verified'),
                            ),
                            DropdownMenuItem(
                              value: 'Under Review',
                              child: Text('Under Review'),
                            ),
                            DropdownMenuItem(
                              value: 'Unverified',
                              child: Text('Unverified'),
                            ),
                          ],
                          onChanged: (v) => setState(
                            () => _selectedFilter = v ?? _selectedFilter,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'CATEGORY:',
                      style: TextStyle(
                        fontSize: 16,
                        color: appBlack,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 35,
                      width: 120,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: appBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          dropdownColor: Colors.white,
                          iconEnabledColor: Colors.white,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: appBlack,
                          ),
                          items: _categories
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    style: const TextStyle(color: appBlack),
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) {
                            return _categories.map((value) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList();
                          },
                          onChanged: (v) => setState(
                            () => _selectedCategory = v ?? _selectedCategory,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            Text(
              'LATEST REPORTS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: appBlack,
                fontFamily: 'Roboto',
              ),
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

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: appBlack.withOpacity(0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // IMAGE
                        SizedBox(
                          height: 160,
                          width: double.infinity,
                          child: _buildMediaWidget(report),
                        ),

                        const SizedBox(height: 12),

                        // STATUS + DATE/TIME
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color:
                                          statusLower == 'resolved' ||
                                                  statusLower ==
                                                      'incident resolved'
                                          ? const Color(0xFF4CAF50)
                                          :
                                          statusLower == 'approved' ||
                                              statusLower == 'verified'
                                          ? statusGreen
                                          : statusLower == 'flagged' ||
                                                statusLower == 'unverified'
                                          ? statusRed
                                          : statusYellow,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    report['status'],
                                    style: TextStyle(
                                      fontFamily: 'RobotoCondensed',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color:
                                          statusLower == 'resolved' ||
                                                  statusLower ==
                                                      'incident resolved'
                                          ? const Color(0xFF4CAF50)
                                          :
                                          statusLower == 'approved' ||
                                              statusLower == 'verified'
                                          ? statusGreen
                                          : statusLower == 'flagged' ||
                                                statusLower == 'unverified'
                                          ? statusRed
                                          : statusYellow,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'DATE: ${report['date']}',
                                    style: const TextStyle(
                                      fontFamily: 'RobotoCondensed',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: appBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'TIME: ${report['time']}',
                                    style: const TextStyle(
                                      fontFamily: 'RobotoCondensed',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: appBlack,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // TITLE
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            report['title'],
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: appBlack,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // DESCRIPTION
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            report['desc'],
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: appBlack,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // FLAGS + COMMENTS
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              // GREEN FLAG + count
                              InkWell(
                                onTap: () => _onGreenFlagPressed(reportIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: greenSelected
                                        ? appGreen.withOpacity(1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flag,
                                        size: 22,
                                        color: greenIconColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${report['greenFlags']}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: appBlack,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 20),

                              // RED FLAG + count
                              InkWell(
                                onTap: () => _onRedFlagPressed(reportIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: redSelected
                                        ? appRed.withOpacity(1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flag,
                                        size: 22,
                                        color: redIconColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${report['redFlags']}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: appBlack,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 20),

                              // COMMENTS
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
                                        size: 22,
                                        color: appBlue,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${report['comments']}',
                                        style: const TextStyle(
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 13,
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
                        ),

                        const SizedBox(height: 8),
                      ],
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
// COMMENTS PAGE (Full Screen)
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
          UserSession.currentUserData?['fullName'] as String? ??
          UserSession.currentUserData?['username'] as String? ??
          'Anonymous';

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

class _ImageZoomDialog extends StatefulWidget {
  final String imageUrl;

  const _ImageZoomDialog({required this.imageUrl});

  @override
  State<_ImageZoomDialog> createState() => _ImageZoomDialogState();
}

class _ImageZoomDialogState extends State<_ImageZoomDialog> {
  double _scale = 1.0;
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black.withOpacity(0.9),
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onScaleStart: (details) {
          _baseScale = _scale;
        },
        onScaleUpdate: (details) {
          setState(() {
            _scale = (_baseScale * details.scale).clamp(1.0, 3.0);
          });
        },
        child: Stack(
          children: [
            // ZOOMED IMAGE
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.0,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  (loadingProgress.expectedTotalBytes ?? 1)
                            : null,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
            ),

            // CLOSE BUTTON
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ],
        ),
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
