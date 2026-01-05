import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  static const appRed = Color(0xFFFFC806);
  static const appGreen = Color(0xFF00A458);
  static const appYellow = Color(0xFFF5F520);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReportsFromFirestore();
    _ensureCommentsCollectionExists(); // Initialize comments collection
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

  Future<void> _loadReportsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('reportedAt', descending: true)
          .get();

      final reports = snapshot.docs.map((doc) {
        final data = doc.data();
        final reportedAt = (data['reportedAt'] as Timestamp).toDate();
        final dateFormat = DateFormat('MMM dd. yyyy');
        final timeFormat = DateFormat('h:mm a');

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
          'comments': data['comments'] ?? 0,
          'commentsList': <Map<String, dynamic>>[],
          'userVote': 'none',
          'name': data['name'] ?? 'Unknown',
          'mediaType': data['mediaType'] ?? 'photo',
        };
      }).toList();

      setState(() {
        _reports = reports;
      });

      debugPrint('✅ Loaded ${reports.length} reports from Firestore');
    } catch (e) {
      debugPrint('❌ Failed to load reports: $e');
      setState(() {});
    }
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
                borderRadius: BorderRadius.circular(16),
              ),
              child: StatefulBuilder(
                builder: (context, setStateDialog) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // HEADER WITH BACK BUTTON
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: headerColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            // back button (blue, like profile)
                            Container(
                              decoration: BoxDecoration(
                                //color: appBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Center(
                                child: Text(
                                  headerText,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 40), // balance right side
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Reasons
                            ...List.generate(reasons.length, (i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4.0,
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
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: appBlack,
                                            width: 1.4,
                                          ),
                                          color: selected[i]
                                              ? headerColor.withOpacity(0.15)
                                              : Colors.white,
                                        ),
                                        child: selected[i]
                                            ? Icon(
                                                Icons.check,
                                                size: 18,
                                                color: headerColor,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          reasons[i],
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: appBlack,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            const SizedBox(height: 16),

                            Text(
                              'Additional Comments',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: commentController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF0F0F0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.transparent,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),
                            ),

                            if (errorText != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                errorText!,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: appRed,
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: 110,
                                height: 36,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: headerColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
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
                                  child: Text(
                                    'SUBMIT',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
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

  // ───────────────── FLAG LOGIC (WITH DIALOG) ─────────────────

  Future<void> _onGreenFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];

    // Already green → quick unverify
    if (vote == 'green') {
      setState(() {
        if (report['greenFlags'] > 0) report['greenFlags']--;
        report['userVote'] = 'none';
      });
      return;
    }

    // Show VERIFY modal
    final bool confirmed = await _showReasonDialog(
      headerColor: appGreen,
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
  }

  Future<void> _onRedFlagPressed(int index) async {
    final report = _reports[index];
    final String vote = report['userVote'];

    // Already red → quick unflag
    if (vote == 'red') {
      setState(() {
        if (report['redFlags'] > 0) report['redFlags']--;
        report['userVote'] = 'none';
      });
      return;
    }

    // Show REPORT modal
    final bool confirmed = await _showReasonDialog(
      headerColor: appRed,
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
                  style: GoogleFonts.poppins(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                  ),
                  children: const [
                    TextSpan(
                      text: 'C',
                      style: TextStyle(color: appBlue),
                    ),
                    TextSpan(
                      text: 'O',
                      style: TextStyle(color: appRed),
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

            // FILTER ROW
            Row(
              children: [
                Text(
                  'Filter by:',
                  style: GoogleFonts.poppins(fontSize: 12, color: appBlack),
                ),
                const SizedBox(width: 6),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedFilter,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.poppins(fontSize: 12, color: appBlack),
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

                const SizedBox(width: 24),

                Text(
                  'Category:',
                  style: GoogleFonts.poppins(fontSize: 12, color: appBlack),
                ),
                const SizedBox(width: 6),

                Container(
                  height: 40,
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
                      style: GoogleFonts.poppins(fontSize: 12, color: appBlack),
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

            const SizedBox(height: 16),

            Text(
              'LATEST REPORTS',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: appBlack,
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
                          child: Image.asset(
                            report['image'],
                            fit: BoxFit.cover,
                          ),
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
                                          statusLower == 'approved' ||
                                              statusLower == 'verified'
                                          ? appGreen
                                          : statusLower == 'flagged' ||
                                                statusLower == 'unverified'
                                          ? appRed
                                          : appYellow,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    report['status'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          statusLower == 'approved' ||
                                              statusLower == 'verified'
                                          ? appGreen
                                          : statusLower == 'flagged' ||
                                                statusLower == 'unverified'
                                          ? appRed
                                          : appYellow,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'DATE: ${report['date']}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: appBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'TIME: ${report['time']}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
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
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
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
                            style: GoogleFonts.poppins(
                              fontSize: 14,
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
                                        ? appGreen.withOpacity(0.12)
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: greenSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
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
                                        ? appRed.withOpacity(0.12)
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: redSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
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
  static const appRed = Color(0xFFFFC806);
  static const appGreen = Color(0xFF00A458);
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

      final comments = snapshot.docs.map((doc) {
        final data = doc.data();
        final timestamp = (data['timestamp'] as Timestamp).toDate();

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
      }).toList();

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
      final reportStatus = widget.report['status']?.toString() ?? '';
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
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
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
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: appBlack,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status: ${widget.report['status']}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      'By: ${widget.report['name']}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
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
                  style: GoogleFonts.poppins(fontSize: 13, color: appBlack),
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
                      style: GoogleFonts.poppins(fontSize: 12, color: appBlack),
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
                      style: GoogleFonts.poppins(
                        fontSize: 14,
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
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: appBlack,
                                        ),
                                      ),
                                      Text(
                                        timeAgo,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
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
                              style: GoogleFonts.poppins(
                                fontSize: 13,
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
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: greenSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
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
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: redSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
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
                    decoration: InputDecoration(
                      hintText: 'Write a comment...',
                      hintStyle: GoogleFonts.poppins(fontSize: 13),
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
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
