import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../common/services/user_session.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  // OFFICIAL COLORS
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appWhite = Color(0xFFF7F8F3);

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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

  Widget _buildAnnouncementsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
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
        final visibleDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isPlaceholder'] != true;
        }).toList();

        if (visibleDocs.isEmpty) {
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: visibleDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final data = visibleDocs[index].data() as Map<String, dynamic>;
            return _buildAnnouncementCard(data);
          },
        );
      },
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> data) {
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
    final dateText = DateFormat('MMM d, yyyy — h:mm a').format(date);
    final displayTitle = title.isNotEmpty ? title : 'Announcement';

    return Center(
      child: GestureDetector(
        onTap: () => _showAnnouncementDialog(context, data),
        child: Container(
          width: 343,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appBlack.withOpacity(0.12)),
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
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Container(
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.campaign,
                          size: 40,
                          color: appBlack.withOpacity(0.25),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            borderRadius: BorderRadius.circular(8),
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
  }

  Widget _buildNearbyIncidentsTab() {
    final userId = UserSession.getUserId();

    if (userId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off,
                size: 48, color: appBlack.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              'Login to receive nearby incident alerts',
              style: TextStyle(
                fontSize: 14,
                color: appBlack.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
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
          return Center(
            child: Text(
              'Failed to load notifications.',
              style: TextStyle(
                fontSize: 12,
                color: appBlack.withOpacity(0.7),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none,
                    size: 48, color: appBlack.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text(
                  'No nearby incidents reported yet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: appBlack.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You\'ll be notified when incidents\noccur within 5km of your location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: appBlack.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildIncidentNotificationCard(data, docs[index].id);
          },
        );
      },
    );
  }

  Widget _buildIncidentNotificationCard(
      Map<String, dynamic> data, String docId) {
    final title = (data['title'] as String?) ?? 'Incident Alert';
    final body = (data['body'] as String?) ?? '';
    final incidentType = (data['incidentType'] as String?) ?? 'Incident';
    final isRead = (data['read'] as bool?) ?? false;
    final ts = data['createdAt'];
    DateTime date = DateTime.now();
    if (ts is Timestamp) {
      date = ts.toDate();
    }
    final dateText = DateFormat('MMM d, h:mm a').format(date);

    IconData iconData;
    Color iconColor;
    switch (incidentType.toLowerCase()) {
      case 'fire':
        iconData = Icons.local_fire_department;
        iconColor = Colors.orange;
        break;
      case 'flood':
        iconData = Icons.water;
        iconColor = Colors.blue;
        break;
      case 'earthquake':
        iconData = Icons.vibration;
        iconColor = Colors.brown;
        break;
      case 'road accident':
      case 'vehicular accident':
        iconData = Icons.car_crash;
        iconColor = Colors.red;
        break;
      default:
        iconData = Icons.warning_amber;
        iconColor = appBlue;
    }

    return Center(
      child: Container(
        width: 343,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : appBlue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isRead ? appBlack.withOpacity(0.12) : appBlue.withOpacity(0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.w700,
                            color: appBlack,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: appBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: appBlack.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateText,
                    style: TextStyle(
                      fontSize: 11,
                      color: appBlack.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: appWhite,
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
                    TextSpan(text: 'N', style: TextStyle(color: appBlue)),
                    TextSpan(text: 'O', style: TextStyle(color: appRed)),
                    TextSpan(
                        text: 'TIFICATION', style: TextStyle(color: appBlue)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // TAB BAR
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: appBlack.withOpacity(0.12)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: appBlack,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: appBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorPadding: const EdgeInsets.all(4),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'RobotoCondensed',
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'RobotoCondensed',
                ),
                tabs: const [
                  Tab(text: 'Announcements'),
                  Tab(text: 'Nearby Incidents'),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // TAB CONTENT
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAnnouncementsTab(),
                  _buildNearbyIncidentsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
