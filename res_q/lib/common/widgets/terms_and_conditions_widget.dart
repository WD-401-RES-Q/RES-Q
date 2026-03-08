import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TermsAndConditionsWidget extends StatefulWidget {
  const TermsAndConditionsWidget({
    super.key,
    this.enabled = true,
    this.initiallyAgreed = false,
    this.onAgreementChanged,
    this.cardHeight = 220,
    this.title = 'TERMS AND CONDITIONS',
    this.checkboxLabel = 'I agree to the Terms and Conditions',
    this.lockedHintText = 'Scroll to the bottom to enable agreement.',
    this.tapHintText = 'Please scroll to read the full terms.',
    this.termsText = TermsAndConditionsContent.fullText,
  });

  final bool enabled;
  final bool initiallyAgreed;
  final ValueChanged<bool>? onAgreementChanged;
  final double cardHeight;
  final String title;
  final String checkboxLabel;
  final String lockedHintText;
  final String tapHintText;
  final String termsText;

  @override
  State<TermsAndConditionsWidget> createState() =>
      TermsAndConditionsWidgetState();
}

class TermsAndConditionsWidgetState extends State<TermsAndConditionsWidget> {
  final ScrollController _scrollController = ScrollController();
  bool _hasReachedBottom = false;
  bool _isAgreed = false;
  bool _showTapHint = false;

  bool get isAgreed => _isAgreed;
  bool get hasReachedBottom => _hasReachedBottom;

  @override
  void initState() {
    super.initState();
    _isAgreed = widget.initiallyAgreed;
    _hasReachedBottom = widget.initiallyAgreed;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unlockIfNotScrollable();
    });
  }

  @override
  void didUpdateWidget(covariant TermsAndConditionsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyAgreed != widget.initiallyAgreed &&
        widget.initiallyAgreed != _isAgreed) {
      setState(() {
        _isAgreed = widget.initiallyAgreed;
        if (_isAgreed) {
          _hasReachedBottom = true;
        }
      });
    }
    if (oldWidget.termsText != widget.termsText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _unlockIfNotScrollable();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _unlockIfNotScrollable() {
    if (!mounted || !_scrollController.hasClients || _hasReachedBottom) return;
    if (_scrollController.position.maxScrollExtent <= 0) {
      setState(() {
        _hasReachedBottom = true;
      });
    }
  }

  void _handleScroll() {
    if (_hasReachedBottom || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 20) {
      setState(() {
        _hasReachedBottom = true;
        _showTapHint = false;
      });
    }
  }

  void _toggleAgreement() {
    if (!widget.enabled) return;
    if (!_hasReachedBottom) {
      if (!_showTapHint) {
        setState(() {
          _showTapHint = true;
        });
      }
      return;
    }
    final nextValue = !_isAgreed;
    setState(() {
      _isAgreed = nextValue;
      _showTapHint = false;
    });
    widget.onAgreementChanged?.call(nextValue);
  }

  @override
  Widget build(BuildContext context) {
    final checkboxEnabled = widget.enabled && _hasReachedBottom;
    final mutedColor = AppTheme.appBlack.withValues(alpha: 0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: widget.cardHeight,
          decoration: BoxDecoration(
            color: AppTheme.appBrightWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.appBlack.withValues(alpha: 0.14),
            ),
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            radius: const Radius.circular(6),
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.termsText,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: AppTheme.appBlack.withValues(alpha: 0.86),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: checkboxEnabled ? 1.0 : 0.7,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.enabled ? _toggleAgreement : null,
            child: Row(
              children: [
                Checkbox(
                  value: _isAgreed,
                  onChanged: checkboxEnabled ? (_) => _toggleAgreement() : null,
                  checkColor: Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.appRed;
                    }
                    return AppTheme.appBrightWhite;
                  }),
                ),
                Expanded(
                  child: Text(
                    widget.checkboxLabel,
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w600,
                      color: checkboxEnabled ? AppTheme.appBlack : mutedColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_hasReachedBottom || _showTapHint)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              _showTapHint ? widget.tapHintText : widget.lockedHintText,
              style: TextStyle(
                fontSize: 10.5,
                color: _showTapHint
                    ? AppTheme.appRed
                    : AppTheme.appBlack.withValues(alpha: 0.55),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

class TermsAndConditionsContent {
  static const String fullText =
      '''TERMS AND CONDITIONS FOR RES-Q DISASTER RESPONSE APP

Last Updated: January 2026

IMPORTANT: Please read these terms carefully before using RES-Q. By clicking "I AGREE," you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.

1. ACCEPTANCE OF TERMS
By creating an account and using the RES-Q emergency and disaster response application, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our services.

2. SERVICE DESCRIPTION
RES-Q is a community-based disaster response and emergency assistance application designed to:
- Connect users with emergency services and local responders during disasters
- Facilitate real-time disaster reporting (floods, earthquakes, fires, accidents, etc.)
- Enable location sharing during emergencies for rescue operations
- Provide community assistance and coordination during calamities
- Deliver emergency alerts and notifications

3. USER REGISTRATION AND VERIFICATION
3.1 You must provide accurate, current, and complete information during registration including a valid government-issued ID.
3.2 You are responsible for maintaining the confidentiality of your account credentials and PIN.
3.3 You must be at least 13 years old to use this service.
3.4 Phone number verification via OTP is required for account activation.
3.5 Your account is subject to approval by administrators to ensure community safety.

4. EMERGENCY AND DISASTER SERVICES
4.1 RES-Q is a SUPPLEMENTARY TOOL and should NOT replace official emergency services (911, local emergency hotlines, NDRRMC, LGU disaster offices).
4.2 In life-threatening situations, ALWAYS contact official emergency services FIRST.
4.3 We strive for accuracy but cannot guarantee response times, service availability, or emergency responder actions during disasters.
4.4 Network outages during disasters may affect app functionality.

5. DISASTER REPORTING RESPONSIBILITIES
5.1 You agree to report disasters and emergencies accurately and truthfully.
5.2 FALSE DISASTER REPORTS may result in immediate account termination and potential legal action under applicable laws.
5.3 You are responsible for the accuracy of your location and the information you report.
5.4 Do not report incidents that have already been resolved or are being handled by authorities.

6. LOCATION SERVICES DURING EMERGENCIES
6.1 The app requires location access to function properly during emergencies.
6.2 Your REAL-TIME LOCATION will be automatically shared with:
    - Emergency responders when you report or are involved in an emergency
    - Local disaster response teams
    - Your designated emergency contacts
    - Responders managing disaster response
6.3 Location data during active emergencies may be retained for rescue coordination and post-incident analysis.
6.4 You may disable location sharing in non-emergency situations through app settings.

7. EMERGENCY CONTACT AUTO-NOTIFICATION
7.1 By agreeing to these terms, you consent to RES-Q automatically notifying your emergency contacts when:
    - You report a disaster or emergency
    - You mark yourself as "in danger" or "needs assistance"
    - You are unresponsive during an active emergency in your area
    - Authorities request welfare checks
7.2 Your emergency contacts will receive your location and status updates.

8. DATA COLLECTION AND PRIVACY DURING DISASTERS
8.1 We collect and store personal information including:
    - Name, contact details, address, and date of birth
    - Government ID photos for verification
    - Location data (especially during emergencies)
    - Disaster reports and photos you submit
    - Emergency contacts
8.2 During active disasters, your data may be shared with:
    - Local Government Units (LGUs)
    - Barangay officials
    - Philippine National Police (PNP)
    - Bureau of Fire Protection (BFP)
    - Medical responders
    - National Disaster Risk Reduction and Management Council (NDRRMC)
8.3 We use industry-standard security measures to protect your information.

9. COMMUNITY CONDUCT
9.1 You must respect other users and community members at all times.
9.2 Prohibited actions include:
    - Filing false or malicious disaster reports
    - Harassment of other users or responders
    - Sharing misleading information about disasters
    - Interfering with rescue operations
    - Spam or irrelevant content
9.3 We reserve the right to remove content and terminate accounts that violate these terms.

10. SMS AND PUSH NOTIFICATIONS
10.1 You consent to receive SMS messages and push notifications for:
    - Emergency alerts in your area
    - Disaster warnings (typhoons, earthquakes, floods, etc.)
    - Account security notifications
    - Status updates on your reports
    - Evacuation notices
10.2 Critical emergency alerts cannot be disabled for your safety.

11. LIABILITY DISCLAIMER
11.1 RES-Q is provided "as is" without warranties of any kind.
11.2 We are NOT liable for:
    - Delays, failures, or inaccuracies in emergency response
    - Actions or inactions of emergency responders or other users
    - Network failures during disasters
    - Damage or injury resulting from use of the app
11.3 Use of the app is at your own risk.

12. INTELLECTUAL PROPERTY
12.1 All app content, features, and functionality are owned by RES-Q.
12.2 Disaster reports and photos you submit may be used for emergency coordination, public safety announcements, and improving disaster response.

13. ACCOUNT TERMINATION
13.1 We reserve the right to suspend or terminate accounts for violations of these terms.
13.2 You may request account deletion through app settings.
13.3 Termination does not relieve you of obligations incurred before termination.
13.4 Emergency data may be retained for legal and public safety purposes.

14. MODIFICATIONS TO TERMS
14.1 We may update these Terms and Conditions at any time.
14.2 Continued use of the app after changes constitutes acceptance of new terms.
14.3 Material changes will be notified through the app.

15. INDEMNIFICATION
You agree to indemnify and hold harmless RES-Q, its developers, affiliates, and partner agencies from any claims, damages, or expenses arising from your use of the service or violation of these terms.

16. GOVERNING LAW
These terms are governed by the laws of the Republic of the Philippines including the Data Privacy Act of 2012 (RA 10173) and the Philippine Disaster Risk Reduction and Management Act (RA 10121). Any disputes shall be resolved in the appropriate courts of the jurisdiction.

17. CONTACT INFORMATION
For questions about these Terms and Conditions:
Email: support@resq-app.com

By clicking "I AGREE," you acknowledge that:
- You have read and understood these Terms and Conditions
- You consent to location sharing during emergencies
- You consent to automatic notification of your emergency contacts
- You consent to receiving emergency alerts and disaster warnings
- You understand your responsibilities in accurate disaster reporting''';
}
