import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  // Brand colors
  static const appBlue = Color(0xFF004FC6);
  static const appRed = Color(0xFFD60000);
  static const appGreen = Color(0xFF00A458);
  static const appYellow = Color(0xFFF5F520);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';

  // Reports with mutable engagement fields
  final List<Map<String, dynamic>> _reports = [
    {
      'image': 'assets/images/COMMUNITY-IMAGE-1.png',
      'date': 'NOV 24. 2025',
      'time': '9:12 AM',
      'title': 'Pothole forming',
      'desc': 'Large pothole forming near 5th Avenue.',
      'greenFlags': 3,
      'redFlags': 0,
      'status': 'Verified',
      'comments': 5,
      'userVote': 'none', // 'none' | 'green' | 'red'
    },
    {
      'image': 'assets/images/COMMUNITY-IMAGE-2.png',
      'date': 'NOV 23. 2025',
      'time': '6:40 PM',
      'title': 'Minor Flooding',
      'desc': 'Minor flooding along Riverside Drive.',
      'greenFlags': 0,
      'redFlags': 0,
      'status': 'Under Review',
      'comments': 8,
      'userVote': 'none',
    },
    {
      'image': 'assets/images/COMMUNITY-IMAGE-3.png',
      'date': 'NOV 22. 2025',
      'time': '2:05 PM',
      'title': 'Small Fire',
      'desc': 'Small fire reported behind the warehouse.',
      'greenFlags': 0,
      'redFlags': 4,
      'status': 'Flagged',
      'comments': 2,
      'userVote': 'none',
    },
  ];

  static const List<String> _categories = [
    'All',
    'Roads',
    'Earthquake',
    'Flood',
    'Fire',
    'Other',
  ];

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
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Comments (${_reports[index]['comments']})',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Write a comment...',
                  hintStyle: GoogleFonts.poppins(fontSize: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      setState(() {
                        _reports[index]['comments']++;
                      });
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Post',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
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
                          value: 'Recent',
                          child: Text('Recent'),
                        ),
                        DropdownMenuItem(
                          value: 'Popular',
                          child: Text('Popular'),
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
                    color: appRed,
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
                itemCount: _reports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final report = _reports[index];
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
                                      color: report['status'] == 'Verified'
                                          ? appGreen
                                          : report['status'] == 'Flagged'
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
                                      color: report['status'] == 'Verified'
                                          ? appGreen
                                          : report['status'] == 'Flagged'
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
                                onTap: () => _onGreenFlagPressed(index),
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
                                onTap: () => _onRedFlagPressed(index),
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
                                onTap: () => _openComments(index),
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
