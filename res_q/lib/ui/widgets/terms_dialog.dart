import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import 'auth_widgets.dart';

class TermsAndConditionsDialog {
  static Future<bool> show(BuildContext context) async {
    final ScrollController scrollController = ScrollController();
    bool canAgree = false;
    bool agreed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            scrollController.addListener(() {
              if (scrollController.position.pixels >=
                  scrollController.position.maxScrollExtent - 20) {
                if (!canAgree) {
                  setDialogState(() {
                    canAgree = true;
                  });
                }
              }
            });

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                  maxWidth: 500,
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const ResqLogo(),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: AppTheme.appBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TERMS AND CONDITIONS',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Text(
                            _getTermsAndConditionsText(),
                            style: GoogleFonts.quicksand(
                              fontSize: 13,
                              height: 1.6,
                              color: AppTheme.appBlack,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!canAgree)
                      Text(
                        'Scroll to the bottom to continue',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.appBlue),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                'CLOSE',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.appBlue,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: canAgree
                                  ? () {
                                      agreed = true;
                                      Navigator.pop(context);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.appBlue,
                                disabledBackgroundColor: Colors.grey[300],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                'I AGREE',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: canAgree ? Colors.white : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    scrollController.dispose();
    return agreed;
  }

  static String _getTermsAndConditionsText() {
    return '''TERMS AND CONDITIONS FOR RES-Q APP

Last Updated: December 14, 2025

1. ACCEPTANCE OF TERMS
By creating an account and using the RES-Q emergency response application, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our services.

2. SERVICE DESCRIPTION
RES-Q is an emergency response application designed to connect users with emergency services, responders, and community support during critical situations. Our services include but are not limited to emergency alerts, location sharing, and community assistance features.

3. USER REGISTRATION
3.1 You must provide accurate, current, and complete information during registration.
3.2 You are responsible for maintaining the confidentiality of your account credentials.
3.3 You must be at least 13 years old to use this service.
3.4 Phone number verification is required for account activation.

4. EMERGENCY SERVICES
4.1 RES-Q is a supplementary tool and should not replace official emergency services (911, local emergency numbers).
4.2 In life-threatening situations, always contact official emergency services first.
4.3 We strive for accuracy but cannot guarantee response times or service availability.

5. USER RESPONSIBILITIES
5.1 You agree not to misuse the emergency alert system.
5.2 False emergency reports may result in account termination and legal action.
5.3 You are responsible for the accuracy of your location and contact information.
5.4 You must respect other users and community members.

6. PRIVACY AND DATA COLLECTION
6.1 We collect and store personal information including name, contact details, location data, and emergency contacts.
6.2 Your data may be shared with emergency responders when you activate emergency services.
6.3 We use industry-standard security measures to protect your information.
6.4 For full details, please review our Privacy Policy.

7. LOCATION SERVICES
7.1 The app requires location access to function properly.
7.2 Your location may be shared with emergency responders and authorized contacts during emergencies.
7.3 You can control location sharing settings in your device and app preferences.

8. CONTENT AND CONDUCT
8.1 You are responsible for any content you post or share through the app.
8.2 Prohibited content includes: harassment, threats, illegal activities, spam, or misleading information.
8.3 We reserve the right to remove content and terminate accounts that violate these terms.

9. LIABILITY DISCLAIMER
9.1 RES-Q is provided "as is" without warranties of any kind.
9.2 We are not liable for delays, failures, or inaccuracies in emergency response.
9.3 We are not responsible for actions or inactions of emergency responders or other users.
9.4 Use of the app is at your own risk.

10. INTELLECTUAL PROPERTY
10.1 All app content, features, and functionality are owned by RES-Q.
10.2 You may not copy, modify, distribute, or reverse engineer any part of the application.

11. ACCOUNT TERMINATION
11.1 We reserve the right to suspend or terminate accounts for violations of these terms.
11.2 You may delete your account at any time through app settings.
11.3 Termination does not relieve you of obligations incurred before termination.

12. MODIFICATIONS TO TERMS
12.1 We may update these Terms and Conditions at any time.
12.2 Continued use of the app after changes constitutes acceptance of new terms.
12.3 Material changes will be notified through the app or email.

13. INDEMNIFICATION
You agree to indemnify and hold harmless RES-Q, its developers, and affiliates from any claims, damages, or expenses arising from your use of the service or violation of these terms.

14. GOVERNING LAW
These terms are governed by the laws of the Philippines. Any disputes shall be resolved in the appropriate courts of the jurisdiction.

15. CONTACT INFORMATION
For questions about these Terms and Conditions, please contact:
Email: support@resq-app.com
Address: [Your Address]

16. EMERGENCY CONTACT CONSENT
By agreeing to these terms, you consent to RES-Q contacting your emergency contacts in situations where you have activated emergency services or are unresponsive.

17. SMS AND NOTIFICATIONS
You consent to receive SMS messages and push notifications related to emergency alerts, account security, and important service updates.

By clicking "I AGREE," you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.''';
  }
}
