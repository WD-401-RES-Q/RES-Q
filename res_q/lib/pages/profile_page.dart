import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Track which sections are expanded
  Set<String> expandedSections = {};

  void toggleSection(String section) {
    setState(() {
      if (expandedSections.contains(section)) {
        expandedSections.remove(section);
      } else {
        expandedSections.add(section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            children: [
              // ───────── TOP BAR ─────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFAC1B22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 45,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Roboto',
                            ),
                            children: const [
                              TextSpan(
                                text: 'PR',
                                style: TextStyle(color: Color(0xFFAC1B22)),
                              ),
                              TextSpan(
                                text: 'O',
                                style: TextStyle(color: Color(0xFFFFC806)),
                              ),
                              TextSpan(
                                text: 'FILE',
                                style: TextStyle(color: Color(0xFFAC1B22)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 48),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ───────── PROFILE AVATAR ─────────
              const CircleAvatar(
                radius: 55,
                backgroundColor: Color(0xFFDCC6FF),
              ),

              const SizedBox(height: 24),

              // ───────── FLOATING PROFILE CARD ─────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18.0,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Settings Section
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProfileItemWithDropdown(
                          icon: Icons.person_outline,
                          label: 'Personal Information',
                          isExpanded: expandedSections.contains('personal_info'),
                          onTap: () => toggleSection('personal_info'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.shield_outlined,
                          label: 'Account Security',
                          isExpanded: expandedSections.contains('account_security'),
                          onTap: () => toggleSection('account_security'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.credit_card_outlined,
                          label: 'Payments',
                          isExpanded: expandedSections.contains('payments'),
                          onTap: () => toggleSection('payments'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.notifications_none,
                          label: 'Notifications',
                          isExpanded: expandedSections.contains('notifications'),
                          onTap: () => toggleSection('notifications'),
                        ),

                        const SizedBox(height: 20),

                        // Support
                        Text(
                          'Support',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProfileItemWithDropdown(
                          icon: Icons.support_agent_outlined,
                          label: 'Help Center',
                          isExpanded: expandedSections.contains('help_center'),
                          onTap: () => toggleSection('help_center'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.phone_in_talk_outlined,
                          label: 'Report a Problem',
                          isExpanded: expandedSections.contains('report_problem'),
                          onTap: () => toggleSection('report_problem'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.rate_review_outlined,
                          label: 'Write a feedback',
                          isExpanded: expandedSections.contains('feedback'),
                          onTap: () => toggleSection('feedback'),
                        ),

                        const SizedBox(height: 20),

                        // Legal
                        Text(
                          'Legal',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProfileItemWithDropdown(
                          icon: Icons.description_outlined,
                          label: 'Terms of Service',
                          isExpanded: expandedSections.contains('terms'),
                          onTap: () => toggleSection('terms'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy Policy',
                          isExpanded: expandedSections.contains('privacy'),
                          onTap: () => toggleSection('privacy'),
                        ),
                        _ProfileItemWithDropdown(
                          icon: Icons.article_outlined,
                          label: 'Source Licenses',
                          isExpanded: expandedSections.contains('licenses'),
                          onTap: () => toggleSection('licenses'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────── PROFILE ITEM WITH DROPDOWN ─────────
class _ProfileItemWithDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ProfileItemWithDropdown({
    required this.icon,
    required this.label,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.black87),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Colors.black38,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    'To be added',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ───────── REUSABLE LIST ITEM ─────────
class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.black87),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}