import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  // OFFICIAL COLORS
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appWhite = Color(0xFFF7F8F3);

  void _showImageZoom(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
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
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 260,
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
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
      },
    );
  }

  void _showAnnouncementDialog(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final title = (data['title'] as String?) ?? '';
    final content = (data['content'] as String?) ?? '';
    final imageUrl = (data['imageUrl'] as String?) ?? '';
    final ts = data['createdAt'];
    DateTime date = DateTime.now();
    if (ts is Timestamp) {
      date = ts.toDate();
    } else if (ts is DateTime) {
      date = ts;
    }
    final dateText = DateFormat('MMM d yyyy').format(date);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          backgroundColor: appWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: FractionallySizedBox(
            widthFactor: 0.95,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  if (imageUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showImageZoom(context, imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.error_outline,
                                  color: appBlack,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  if (imageUrl.isNotEmpty) const SizedBox(height: 12),
                  Text(
                    title.isNotEmpty ? title : 'Announcement',
                    style: const TextStyle(
                      fontSize: 16,
                      color: appBlack,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateText.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: appBlack.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (content.isNotEmpty)
                    Text(
                      content,
                      style: const TextStyle(
                        fontSize: 13,
                        color: appBlack,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w600,
                          color: appBlue,
                        ),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: appWhite, // background using official off-white
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Roboto',
                  ),
                  children: [
                    TextSpan(
                      text: 'N',
                      style: TextStyle(color: appBlue),
                    ),
                    TextSpan(
                      text: 'O',
                      style: TextStyle(color: appRed),
                    ),
                    TextSpan(
                      text: 'TIFICATION',
                      style: TextStyle(color: appBlue),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('announcements')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(appBlue),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint(
                      'NotificationsPage error: ${snapshot.error}',
                    );
                    return Center(
                      child: Text(
                        'Failed to load announcements.',
                        style: TextStyle(
                          fontSize: 12,
                          color: appBlack.withOpacity(0.7),
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  debugPrint(
                    'NotificationsPage announcements fetched: ${docs.length}',
                  );
                  final visibleDocs =
                      docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['isPlaceholder'] != true;
                      }).toList();
                  debugPrint(
                    'NotificationsPage visible announcements: ${visibleDocs.length}',
                  );
                  if (visibleDocs.isEmpty) {
                    debugPrint('Announcements collection initialized: ${docs.isNotEmpty}');
                    return Center(
                      child: Text(
                        'No announcements yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: appBlack.withOpacity(0.7),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: visibleDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final data =
                          visibleDocs[index].data() as Map<String, dynamic>;
                      final title = (data['title'] as String?) ?? '';
                      final content = (data['content'] as String?) ?? '';
                      final imageUrl = (data['imageUrl'] as String?) ?? '';
                      final ts = data['createdAt'];
                      DateTime date = DateTime.now();
                      if (ts is Timestamp) {
                        date = ts.toDate();
                      } else if (ts is DateTime) {
                        date = ts;
                      }
                      final dateText =
                          DateFormat('MMM d, yyyy — h:mm a').format(date);
                      final displayTitle =
                          title.isNotEmpty ? title : 'Announcement';

                      return Center(
                        child: GestureDetector(
                          onTap: () => _showAnnouncementDialog(context, data),
                          child: Container(
                            width: 343,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: appBlack.withOpacity(0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 18,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 150,
                                  child: imageUrl.isNotEmpty
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: Colors.white,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.image_outlined,
                                            size: 40,
                                            color: appBlack.withOpacity(0.25),
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: appRed,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Important',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: appBlack,
                                                fontFamily: 'RobotoCondensed',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              displayTitle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: appBlack,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        dateText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: appBlack.withOpacity(0.7),
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      if (content.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          content,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: appBlack.withOpacity(0.75),
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
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
