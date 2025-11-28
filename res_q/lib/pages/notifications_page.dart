import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  // OFFICIAL COLORS
  static const appBlue = Color(0xFF004FC6);
  static const appRed = Color(0xFFD60000);
  static const appBlack = Color(0xFF212121);
  static const appWhite = Color(0xFFF7F8F3);

  // sample data
  List<Map<String, String>> _sampleNotifications() => [
    {
      'image': 'assets/images/NOTIF-1.png',
      'date': 'OCT 12 2025',
      'desc':
          'As we celebrate Fiestang La Naval, may our city be filled with joy, unity, and gratitude. Let us honor the traditions and culture that shape Angeles city and...',
    },
    {
      'image': 'assets/images/NOTIF-2.png',
      'date': 'NOV 23 2025',
      'desc': 'Flood advisory issued for low-lying areas.',
    },
    {
      'image': 'assets/images/NOTIF-3.png',
      'date': 'NOV 20 2025',
      'desc': 'Fire contained — avoid the industrial park.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final items = _sampleNotifications();

    return Container(
      color: appWhite, // background using official off-white
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ───────── TITLE ─────────
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                  ),
                  children: const [
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

            // ───────── LIST ─────────
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final it = items[index];

                  return Center(
                    child: Container(
                      width: 343,
                      height: 303,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: appBlack.withOpacity(0.2)),
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
                          // top image
                          SizedBox(
                            width: double.infinity,
                            height: 160,
                            child: Image.asset(it['image']!, fit: BoxFit.cover),
                          ),

                          const SizedBox(height: 12),

                          // date
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                            ),
                            child: Text(
                              it['date']!,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: appBlack,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // description
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                            ),
                            child: Text(
                              it['desc']!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: appBlack.withOpacity(0.9),
                              ),
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
