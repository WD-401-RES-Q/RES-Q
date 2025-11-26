import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  // selected values for the dropdowns (placeholders)
  String _selectedFilter = 'Verified';
  String _selectedCategory = 'All';

  List<Map<String, String>> _sampleReports() => [
    // sample data for reports (can also change the status like verified, under review and flagged)
    {
      'image': 'assets/images/COMMUNITY-IMAGE-1.png',
      'date': 'NOV 24. 2025',
      'time': '9:12 AM',
      'title': 'Pothole forming',
      'desc': 'Large pothole forming near 5th Avenue.',
      'greenFlags': '3',
      'redFlags': '0',
      'status': 'Verified',
      'comments': '5',
    },
    {
      'image': 'assets/images/COMMUNITY-IMAGE-2.png',
      'date': 'NOV 23. 2025',
      'time': '6:40 PM',
      'title': 'Minor Flooding',
      'desc': 'Minor flooding along Riverside Drive.',
      'greenFlags': '0',
      'redFlags': '0',
      'status': 'Under Review',
      'comments': '8',
    },
    {
      'image': 'assets/images/COMMUNITY-IMAGE-3.png',
      'date': 'NOV 22. 2025',
      'time': '2:05 PM',
      'title': 'Small Fire',
      'desc': 'Small fire reported behind the warehouse.',
      'greenFlags': '0',
      'redFlags': '4',
      'status': 'Flagged',
      'comments': '2',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final items = _sampleReports();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: 'C',
                    style: const TextStyle(color: Colors.blue),
                  ),
                  TextSpan(
                    text: 'O',
                    style: const TextStyle(color: Colors.red),
                  ),
                  TextSpan(
                    text: 'MMUNITY',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Filters:
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Filter by: '),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.poppins(color: Colors.black),
                    items: const [
                      DropdownMenuItem(
                        value: 'Verified',
                        child: Text('Verified'),
                      ),
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'Recent', child: Text('Recent')),
                      DropdownMenuItem(
                        value: 'Popular',
                        child: Text('Popular'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedFilter = v ?? _selectedFilter),
                  ),
                ),
              ),

              const SizedBox(width: 24),

              const Text('Category:'),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.poppins(color: Colors.black),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'Roads', child: Text('Roads')),
                      DropdownMenuItem(
                        value: 'Earthquake',
                        child: Text('Earthquake'),
                      ),
                      DropdownMenuItem(value: 'Flood', child: Text('Flood')),
                      DropdownMenuItem(value: 'Fire', child: Text('Fire')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
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
            ),
          ),

          const SizedBox(height: 8),

          // Reports list
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
                                child: Center(
                                  child: Icon(Icons.image, size: 48),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Builder(
                            builder: (context) {
                              // use explicit `date` and `time` fields from data
                              final dateLabel = 'DATE: ${it['date'] ?? ''}';
                              final timeLabel =
                                  it['time'] != null && it['time']!.isNotEmpty
                                  ? 'TIME: ${it['time']}'
                                  : '';

                              // status comes predetermined in the data; use it directly
                              final statusLabel =
                                  it['status'] ?? 'Under Review';
                              final statusColor =
                                  {
                                    'flagged': Colors.red,
                                    'verified': Colors.green,
                                    'under review': Colors.yellow,
                                  }[statusLabel.toLowerCase()] ??
                                  Colors.yellow;

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // left: small circle + status (per-card)
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        statusLabel,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: statusColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // right: DATE and TIME (exact requested format)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        dateLabel,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        timeLabel,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Title before description
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            it['title'] ?? '',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            it['desc']!,
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Flags and comments row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            children: [
                              // green flag + count
                              Row(
                                children: [
                                  Icon(
                                    Icons.flag,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    it['greenFlags'] ?? '0',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 18),
                              // red flag + count
                              Row(
                                children: [
                                  Icon(Icons.flag, size: 16, color: Colors.red),
                                  const SizedBox(width: 6),
                                  Text(
                                    it['redFlags'] ?? '0',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 18),
                              // comments + count
                              Row(
                                children: [
                                  Icon(
                                    Icons.comment,
                                    size: 16,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    it['comments'] ?? '0',
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                ],
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
    );
  }
}
