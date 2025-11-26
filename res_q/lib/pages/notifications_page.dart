import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  // sample data — replace with real notifications later
  List<Map<String, String>> _sampleNotifications() => [
    {
      'image': 'assets/images/NOTIF-1.png',
      'date': 'OCT 12 2025',
      'desc':
          'As we celebrate Fiestang La Naval, may our city be filled with joy, unity, and gratitude. Let us honor the traditions and culture that shape Angeles city and...',
    },
    {
      'image': 'assets/images/NOTIF-2.png',
      'date': '2025-11-23',
      'desc': 'Flood advisory issued for low-lying areas.',
    },
    {
      'image': 'assets/images/NOTIF-3.png',
      'date': '2025-11-20',
      'desc': 'Fire contained — avoid the industrial park.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final items = _sampleNotifications();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: 'N',
                    style: TextStyle(color: Colors.blue),
                  ),
                  TextSpan(
                    text: 'O',
                    style: TextStyle(color: Colors.red),
                  ),
                  TextSpan(
                    text: 'TIFICATION',
                    style: TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Notifications list
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final it = items[index];
              return Center(
                child: Container(
                  width: 343,
                  height: 303,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // full-width image at top
                      SizedBox(
                        width: double.infinity,
                        height: 160,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          child: Image.asset(
                            it['image']!,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const DecoratedBox(
                              decoration: BoxDecoration(color: Colors.grey),
                              child: Center(child: Icon(Icons.image, size: 48)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          it['date']!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          it['desc']!,
                          style: GoogleFonts.poppins(fontSize: 10),
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
    );
  }
}
