import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../ui/app_theme.dart';
import '../services/user_session.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _smsAlerts = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;

  @override
  bool get wantKeepAlive => true;
  static const String _ratingStarAsset = 'assets/icons/rating-star.png';
  static const String _ratingEmptyCircleAsset = 'assets/icons/rating-empty-circle.png';

  String _getModalContent(String title) {
    if (title == 'Terms of Service') {
      return 'A core functionality of the RESQ Service is the ability to report incidents with precise geolocation data to facilitate effective response. By using the Service, you expressly consent to the collection, processing, and storage of your personal information, including but not limited to your name, contact details, and precise real-time geographic location data from your device\'s GPS, Wi-Fi, and cellular networks.\n\nThis data is collected to generate accurate reports, provide contextual information to responders, and improve service functionality. You can manage location permissions through your device settings, though disabling geolocation services will severely limit or completely disable the reporting features of the app.\n\nYou understand and agree that the Service is provided on an "as-is" and "as-available" basis. While we strive for reliability, RESQ, its developers, and its affiliates make no warranties, express or implied, regarding the timeliness, accuracy, or completeness of any report or response. We are not liable for any direct or indirect damages arising from your use of or inability to use the Service, including but not limited to reliance on reported information, unauthorized access to your data, or system failures. The Service is a reporting tool and does not constitute an emergency response service; in the event of an immediate life-threatening situation, you must directly contact official emergency services through appropriate channels.';
    } else if (title == 'Privacy Policy') {
      return 'At RESQ, we are committed to protecting your personal information. This policy outlines how we collect, use, and safeguard the data you provide when using our incident reporting application.\n\nBy registering for and using the RESQ service, you expressly consent to the collection and processing of your personal details, such as your name, email address, and contact information, for the purpose of creating and managing your account. Crucially, to enable the core reporting functionality, the app will request access to your device\'s precise geolocation data; this information is collected solely to tag and validate incident reports, provide critical context to authorized recipients, and improve our service\'s accuracy.\n\nWe implement industry standard technical and organizational measures to protect your data from unauthorized access, alteration, or disclosure. Your information will not be sold to third party marketers; however, it may be shared with verified emergency responders or relevant authorities in connection with your submitted reports, or as required by law. You retain the right to access, correct, or request the deletion of your personal data through your account settings or by contacting us directly.';
    } else if (title == 'Source Licenses') {
      return 'The RESQ application incorporates and relies upon various third-party open-source software libraries and components to enable its functionality. These components are used in accordance with their respective licenses, such as the MIT License, Apache License 2.0, or other similar open-source agreements, which may grant specific rights and impose certain conditions regarding use and distribution.\n\nThe copyrights and intellectual property for these external components remain solely with their original authors and licensors. A complete list of these dependencies, along with their applicable license terms, is available upon request.\n\nIt is important to note that these third-party licenses govern only their specific components and are separate from the proprietary license governing your use of the RESQ application itself, which remains the exclusive intellectual property of RESQ\'s developers.';
    }
    return '';
  }

  void _showModal(BuildContext context, IconData icon, String title) {
    final content = _getModalContent(title);
    int feedbackRating = 4;
    String? selectedProblemType;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFFF7F8F3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon at top
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFAC1B22),
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: const Color(0xFFAC1B22),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFAC1B22),
                        letterSpacing: 0.5,
                        fontFamily: 'RobotoCondensed',
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Content area
                    Expanded(
                      child: _buildModalContent(
                        title,
                        content,
                        feedbackRating,
                        selectedProblemType,
                        (rating) => setDialogState(() => feedbackRating = rating),
                        (value) => setDialogState(() => selectedProblemType = value),
                        setDialogState,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Return button
                    SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC806),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'RETURN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            letterSpacing: 1,
                            fontFamily: 'RobotoCondensed',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _captureProfilePhoto() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (!mounted) return;
      if (photo != null) {
        await Future.delayed(const Duration(milliseconds: 200));
        await _cropProfilePhoto(photo);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to capture profile photo: $e');
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (!mounted) return;
      if (photo != null) {
        await Future.delayed(const Duration(milliseconds: 200));
        await _cropProfilePhoto(photo);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to pick profile photo: $e');
    }
  }

  Future<void> _cropProfilePhoto(XFile photo) async {
    try {
      final uiSettings = <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Crop',
          toolbarColor: const Color(0xFFAC1B22),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFAC1B22),
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop',
          aspectRatioLockEnabled: true,
        ),
        if (kIsWeb)
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
          ),
      ];

      final cropped = await ImageCropper().cropImage(
        sourcePath: photo.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 90,
        uiSettings: uiSettings,
      );

      if (!mounted || cropped == null) return;

      if (kIsWeb) {
        final bytes = await cropped.readAsBytes();
        if (!mounted) return;
        setState(() {
          _profilePhotoBytes = bytes;
          _profilePhoto = XFile(cropped.path);
        });
      } else {
        setState(() => _profilePhoto = XFile(cropped.path));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to crop profile photo: $e');
    }
  }

  void _showProfilePhotoOptions() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF7F8F3),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PROFILE PICTURE',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFAC1B22),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _captureProfilePhoto();
                  },
                  style: AppTheme.pillOutlineButtonStyle,
                  child: const Text(
                    'CAPTURE NOW',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _pickProfilePhoto();
                  },
                  style: AppTheme.pillOutlineButtonStyle,
                  child: const Text(
                    'CHOOSE FROM GALLERY',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalContent(
    String title,
    String content,
    int feedbackRating,
    String? selectedProblemType,
    ValueChanged<int> onRatingChanged,
    ValueChanged<String?> onProblemTypeChanged,
    StateSetter setDialogState,
  ) {
    switch (title) {
      case 'Personal Information':
        return _buildPersonalInfoContent();
      case 'Account Security':
        return _buildAccountSecurityContent();
      case 'Notifications':
        return _buildNotificationsContent(setDialogState);
      case 'Help Center':
        return _buildHelpCenterContent();
      case 'Report a Problem':
        return _buildReportProblemContent(
          selectedProblemType,
          onProblemTypeChanged,
        );
      case 'Write a feedback':
        return _buildFeedbackContent(
          feedbackRating,
          onRatingChanged,
        );
      default:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: content.isNotEmpty
              ? SingleChildScrollView(
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.8,
                      color: Colors.black87,
                      fontFamily: 'Roboto',
                    ),
                    textAlign: TextAlign.left,
                  ),
                )
              : const SizedBox.shrink(),
        );
    }
  }

  Widget _buildPersonalInfoContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Full Name', 'John Doe'),
          const SizedBox(height: 16),
          _buildTextField('Email Address', 'johndoe@email.com'),
          const SizedBox(height: 16),
          _buildTextField('Phone Number', '+63 912 345 6789'),
          const SizedBox(height: 16),
          _buildTextField('Address', '123 Main Street, City'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Save personal info
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'SAVE CHANGES',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSecurityContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Current Password', '••••••••', isPassword: true),
          const SizedBox(height: 16),
          _buildTextField('New Password', '', isPassword: true),
          const SizedBox(height: 16),
          _buildTextField('Confirm New Password', '', isPassword: true),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Change password
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'UPDATE PASSWORD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                // TODO: Enable 2FA
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFAC1B22), width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ENABLE TWO-FACTOR AUTH',
                style: TextStyle(
                  color: Color(0xFFAC1B22),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsContent(StateSetter setDialogState) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildNotificationToggle(
            'Push Notifications',
            'Receive alerts for new incidents',
            _pushNotifications,
            (value) => _updateNotificationSetting(
              setDialogState,
              () => _pushNotifications = value,
            ),
          ),
          const SizedBox(height: 12),
          _buildNotificationToggle(
            'Email Notifications',
            'Get updates via email',
            _emailNotifications,
            (value) => _updateNotificationSetting(
              setDialogState,
              () => _emailNotifications = value,
            ),
          ),
          const SizedBox(height: 12),
          _buildNotificationToggle(
            'SMS Alerts',
            'Receive critical alerts via SMS',
            _smsAlerts,
            (value) => _updateNotificationSetting(
              setDialogState,
              () => _smsAlerts = value,
            ),
          ),
          const SizedBox(height: 12),
          _buildNotificationToggle(
            'Sound',
            'Play notification sounds',
            _soundEnabled,
            (value) => _updateNotificationSetting(
              setDialogState,
              () => _soundEnabled = value,
            ),
          ),
          const SizedBox(height: 12),
          _buildNotificationToggle(
            'Vibration',
            'Vibrate on notifications',
            _vibrationEnabled,
            (value) => _updateNotificationSetting(
              setDialogState,
              () => _vibrationEnabled = value,
            ),
          ),
        ],
      ),
    );
  }

  void _updateNotificationSetting(
    StateSetter setDialogState,
    VoidCallback updateValue,
  ) {
    updateValue();
    if (mounted) {
      setState(() {});
    }
    setDialogState(() {});
  }

  Widget _buildNotificationToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFAC1B22),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCenterContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHelpItem(Icons.question_answer, 'FAQ', 'Frequently asked questions'),
          _buildHelpItem(Icons.book, 'User Guide', 'Learn how to use RESQ'),
          _buildHelpItem(Icons.contact_support, 'Contact Support', 'Get in touch with our team'),
          _buildHelpItem(Icons.video_library, 'Video Tutorials', 'Watch helpful guides'),
          _buildHelpItem(Icons.forum, 'Community Forum', 'Connect with other users'),
        ],
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String subtitle) {
    return InkWell(
      onTap: () {
        // TODO: Navigate to help section
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFAC1B22).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFFAC1B22), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildReportProblemContent(
    String? selectedProblemType,
    ValueChanged<String?> onProblemTypeChanged,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Problem Type',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          _buildDropdownField(
            'Select a problem type',
            selectedProblemType,
            onProblemTypeChanged,
          ),
          const SizedBox(height: 16),
          Text(
            'Description',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Describe the problem you\'re experiencing...',
              hintStyle: TextStyle(fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFAC1B22), width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                // TODO: Attach screenshot
              },
              icon: const Icon(Icons.attach_file),
              label: const Text('ATTACH SCREENSHOT'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFAC1B22),
                side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Submit problem report
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'SUBMIT REPORT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackContent(
    int feedbackRating,
    ValueChanged<int> onRatingChanged,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rate Your Experience',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final isSelected = index < feedbackRating;
              return GestureDetector(
                onTap: () => onRatingChanged(index + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildRatingIcon(isSelected),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Text(
            'Your Feedback',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Share your thoughts about RESQ...',
              hintStyle: TextStyle(fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFAC1B22), width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Submit feedback
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'SUBMIT FEEDBACK',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String hint, {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          obscureText: isPassword,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Color(0xFFAC1B22), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    String hint,
    String? selectedProblemType,
    ValueChanged<String?> onProblemTypeChanged,
  ) {
    final accentColor = const Color(0xFFAC1B22);
    final borderColor = const Color(0xFFFFC806);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6D8), Color(0xFFFFFDF4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: borderColor, width: 1.4),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selectedProblemType,
          hint: Text(
            hint,
            style: GoogleFonts.robotoCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: accentColor),
          dropdownColor: const Color(0xFFFFF9E8),
          style: GoogleFonts.robotoCondensed(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF3A2A2A),
            letterSpacing: 0.2,
          ),
          items: [
            'App Crashes',
            'Feature Not Working',
            'Login Issues',
            'Other',
          ].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                style: GoogleFonts.robotoCondensed(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3A2A2A),
                ),
              ),
            );
          }).toList(),
          onChanged: onProblemTypeChanged,
        ),
      ),
    );
  }

  Widget _buildRatingIcon(bool isSelected) {
    final assetPath = isSelected ? _ratingStarAsset : _ratingEmptyCircleAsset;
    return SizedBox(
      width: 36,
      height: 36,
      child: Image.asset(assetPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileName =
        (UserSession.currentUserData?['fullName'] ??
                UserSession.currentUserData?['username'] ??
                '')
            .toString()
            .trim();
    final profileInitial =
        profileName.isNotEmpty ? profileName[0].toUpperCase() : '?';
    final hasProfilePhoto = _profilePhotoBytes != null || _profilePhoto != null;
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
                    const SizedBox(width: 48),
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
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: const Color(0xFFAC1B22),
                    backgroundImage: _profilePhotoBytes != null
                        ? MemoryImage(_profilePhotoBytes!)
                        : (_profilePhoto != null
                            ? FileImage(File(_profilePhoto!.path))
                            : null),
                    child: hasProfilePhoto
                        ? null
                        : Text(
                            profileInitial,
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: _showProfilePhotoOptions,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(0xFFAC1B22),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
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
                        _ProfileItem(
                          icon: Icons.person_outline,
                          label: 'Personal Information',
                          onTap: () => _showModal(
                            context,
                            Icons.person_outline,
                            'Personal Information',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.shield_outlined,
                          label: 'Account Security',
                          onTap: () => _showModal(
                            context,
                            Icons.shield_outlined,
                            'Account Security',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.notifications_none,
                          label: 'Notifications',
                          onTap: () => _showModal(
                            context,
                            Icons.notifications_none,
                            'Notifications',
                          ),
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
                        _ProfileItem(
                          icon: Icons.support_agent_outlined,
                          label: 'Help Center',
                          onTap: () => _showModal(
                            context,
                            Icons.support_agent_outlined,
                            'Help Center',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.phone_in_talk_outlined,
                          label: 'Report a Problem',
                          onTap: () => _showModal(
                            context,
                            Icons.phone_in_talk_outlined,
                            'Report a Problem',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.rate_review_outlined,
                          label: 'Write a feedback',
                          onTap: () => _showModal(
                            context,
                            Icons.rate_review_outlined,
                            'Write a feedback',
                          ),
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
                        _ProfileItem(
                          icon: Icons.description_outlined,
                          label: 'Terms of Service',
                          onTap: () => _showModal(
                            context,
                            Icons.description_outlined,
                            'Terms of Service',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy Policy',
                          onTap: () => _showModal(
                            context,
                            Icons.privacy_tip_outlined,
                            'Privacy Policy',
                          ),
                        ),
                        _ProfileItem(
                          icon: Icons.article_outlined,
                          label: 'Source Licenses',
                          onTap: () => _showModal(
                            context,
                            Icons.article_outlined,
                            'Source Licenses',
                          ),
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
  final VoidCallback onTap;

  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'RobotoCondensed',
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
