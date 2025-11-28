import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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
                        color: const Color(0xFF0052CC),
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
                            style: GoogleFonts.poppins(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                            ),
                            children: const [
                              TextSpan(
                                text: 'PR',
                                style: TextStyle(color: Color(0xFF0052CC)),
                              ),
                              TextSpan(
                                text: 'O',
                                style: TextStyle(color: Color(0xFFE53935)),
                              ),
                              TextSpan(
                                text: 'FILE',
                                style: TextStyle(color: Color(0xFF0052CC)),
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

                    // ✨ UPDATED FLOATING SHADOW ✨
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
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _ProfileItem(
                          icon: Icons.person_outline,
                          label: 'Personal Information',
                        ),
                        const _ProfileItem(
                          icon: Icons.shield_outlined,
                          label: 'Account Security',
                        ),
                        const _ProfileItem(
                          icon: Icons.credit_card_outlined,
                          label: 'Payments',
                        ),
                        const _ProfileItem(
                          icon: Icons.notifications_none,
                          label: 'Notifications',
                        ),

                        const SizedBox(height: 20),

                        // Support
                        Text(
                          'Support',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _ProfileItem(
                          icon: Icons.support_agent_outlined,
                          label: 'Help Center',
                        ),
                        const _ProfileItem(
                          icon: Icons.phone_in_talk_outlined,
                          label: 'Report a Problem',
                        ),
                        const _ProfileItem(
                          icon: Icons.rate_review_outlined,
                          label: 'Write a feedback',
                        ),

                        const SizedBox(height: 20),

                        // Legal
                        Text(
                          'Legal',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _ProfileItem(
                          icon: Icons.description_outlined,
                          label: 'Terms of Service',
                        ),
                        const _ProfileItem(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy Policy',
                        ),
                        const _ProfileItem(
                          icon: Icons.article_outlined,
                          label: 'Source Licenses',
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
