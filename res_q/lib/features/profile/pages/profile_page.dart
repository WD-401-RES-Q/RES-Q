import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../common/services/user_session.dart';
import '../../auth/pages/login_page.dart';

// ============================================================================
// TODO: Replace with your actual email address for feedback/reports
// This email will receive all user feedback and problem reports
// ============================================================================
const String kFeedbackEmail = 'YOUR_EMAIL_HERE@example.com';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  bool _pushNotifications = true;
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

    // Prevent swipe to dismiss for Personal Information modal
    final bool canDismiss = title != 'Personal Information';

    showDialog(
      context: context,
      barrierDismissible: canDismiss,
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close button at top right
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                    ),

                    // Icon at top
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFAC1B22),
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 35,
                        color: const Color(0xFFAC1B22),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Title
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFAC1B22),
                        letterSpacing: 0.5,
                        fontFamily: 'RobotoCondensed',
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFF7F8F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFAC1B22),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.logout,
                    size: 34,
                    color: Color(0xFFAC1B22),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'LOG OUT?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFAC1B22),
                    letterSpacing: 0.6,
                    fontFamily: 'RobotoCondensed',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Are you sure you want to log out of your account?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[700],
                    fontFamily: 'RobotoCondensed',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFAC1B22)),
                          foregroundColor: const Color(0xFFAC1B22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontFamily: 'RobotoCondensed',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          UserSession.clear();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                            (_) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFAC1B22),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: const Text(
                          'LOG OUT',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontFamily: 'RobotoCondensed',
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
  }

  Future<bool> _requestCameraPermission() async {
    if (kIsWeb) return true;

    final status = await Permission.camera.status;
    if (status.isGranted) return true;

    if (status.isDenied) {
      final result = await Permission.camera.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      if (mounted) {
        _showPermissionDeniedDialog('Camera');
      }
      return false;
    }

    return false;
  }

  Future<bool> _requestGalleryPermission() async {
    if (kIsWeb) return true;

    // For Android 13+ use photos permission, for older use storage
    Permission permission;
    if (Platform.isAndroid) {
      permission = Permission.photos;
      final status = await permission.status;
      if (status.isGranted) return true;

      // Try photos first, fallback to storage for older Android
      if (status.isDenied) {
        var result = await permission.request();
        if (result.isGranted) return true;

        // Fallback to storage permission for older Android versions
        permission = Permission.storage;
        result = await permission.request();
        return result.isGranted;
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog('Photo Library');
        }
        return false;
      }
    } else {
      permission = Permission.photos;
      final status = await permission.status;
      if (status.isGranted) return true;

      if (status.isDenied) {
        final result = await permission.request();
        return result.isGranted;
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog('Photo Library');
        }
        return false;
      }
    }

    return false;
  }

  void _showPermissionDeniedDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$permissionName Access Required',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFFAC1B22),
          ),
        ),
        content: Text(
          'Please enable $permissionName access in your device settings to use this feature.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
            ),
            child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _captureProfilePhoto() async {
    try {
      // Request camera permission first
      final hasPermission = await _requestCameraPermission();
      if (!hasPermission) {
        debugPrint('Camera permission denied');
        return;
      }

      if (!mounted) return;

      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
        preferredCameraDevice: CameraDevice.front,
      );

      if (!mounted) return;

      if (photo != null) {
        // Small delay to ensure camera UI is fully dismissed
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        await _cropProfilePhoto(photo);
      }
    } catch (e) {
      debugPrint('Failed to capture profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to capture photo. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      // Request gallery permission first
      final hasPermission = await _requestGalleryPermission();
      if (!hasPermission) {
        debugPrint('Gallery permission denied');
        return;
      }

      if (!mounted) return;

      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (!mounted) return;

      if (photo != null) {
        // Small delay to ensure gallery UI is fully dismissed
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        await _cropProfilePhoto(photo);
      }
    } catch (e) {
      debugPrint('Failed to pick profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to select photo. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cropProfilePhoto(XFile photo) async {
    try {
      final uiSettings = <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Picture',
          toolbarColor: const Color(0xFFAC1B22),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFAC1B22),
          lockAspectRatio: true,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.square,
        ),
        IOSUiSettings(
          title: 'Crop Profile Picture',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated!'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to crop profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to crop photo. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showProfilePhotoOptions() {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF7F8F3),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button at top right
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(dialogContext),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF666666),
                    ),
                  ),
                ),
              ),
              // Camera icon
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFAC1B22),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 35,
                  color: Color(0xFFAC1B22),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PROFILE PICTURE',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFAC1B22),
                ),
              ),
              const SizedBox(height: 24),
              // Inline buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _captureProfilePhoto();
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFAC1B22), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text(
                          'CAPTURE',
                          style: TextStyle(
                            color: Color(0xFFAC1B22),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _pickProfilePhoto();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFAC1B22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'GALLERY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
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
    final userData = UserSession.currentUserData ?? {};
    final fullNameCtl = TextEditingController(
      text: userData['fullName']?.toString() ?? '',
    );
    final emailCtl = TextEditingController(
      text: userData['email']?.toString() ?? '',
    );
    final addressCtl = TextEditingController(
      text: userData['address']?.toString() ?? '',
    );
    final phoneNumber = userData['contactNumber']?.toString() ?? '';
    // Try multiple possible document ID fields
    final docId = userData['username']?.toString() ??
        userData['uid']?.toString() ??
        userData['id']?.toString() ??
        UserSession.getUserId() ??
        '';
    bool isEditing = false;
    bool isSaving = false;
    String? errorMessage;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full Name Field
              _buildEditableField(
                label: 'Full Name',
                controller: fullNameCtl,
                isEditing: isEditing,
                enabled: isEditing,
              ),
              const SizedBox(height: 16),

              // Email Field
              _buildEditableField(
                label: 'Email Address',
                controller: emailCtl,
                isEditing: isEditing,
                enabled: isEditing,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // Phone Number (Read-only)
              _buildReadOnlyField(
                label: 'Phone Number',
                value: _formatPhoneNumber(phoneNumber),
                hint: 'Phone number cannot be changed',
              ),
              const SizedBox(height: 16),

              // Address Field
              _buildEditableField(
                label: 'Home Address',
                controller: addressCtl,
                isEditing: isEditing,
                enabled: isEditing,
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Inline buttons row
              Row(
                children: [
                  if (isEditing) ...[
                    // Cancel button
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () {
                            // Reset to original values
                            fullNameCtl.text = userData['fullName']?.toString() ?? '';
                            emailCtl.text = userData['email']?.toString() ?? '';
                            addressCtl.text = userData['address']?.toString() ?? '';
                            setModalState(() {
                              isEditing = false;
                              errorMessage = null;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFAC1B22), width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'CANCEL',
                            style: TextStyle(
                              color: Color(0xFFAC1B22),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Edit / Save Button
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!isEditing) {
                                  setModalState(() => isEditing = true);
                                } else {
                                  // Validate and save
                                  final newFullName = fullNameCtl.text.trim();
                                  final newEmail = emailCtl.text.trim();
                                  final newAddress = addressCtl.text.trim();

                                  if (newFullName.isEmpty) {
                                    setModalState(
                                      () => errorMessage = 'Full name is required',
                                    );
                                    return;
                                  }

                                  if (newEmail.isNotEmpty &&
                                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                          .hasMatch(newEmail)) {
                                    setModalState(
                                      () => errorMessage = 'Invalid email address',
                                    );
                                    return;
                                  }

                                  // Check if we have a valid document ID
                                  if (docId.isEmpty) {
                                    setModalState(() {
                                      errorMessage = 'User session error. Please log out and log in again.';
                                    });
                                    return;
                                  }

                                  setModalState(() {
                                    isSaving = true;
                                    errorMessage = null;
                                  });

                                  // Capture messenger before async gap
                                  final messenger = ScaffoldMessenger.of(context);

                                  try {
                                    // Use set with merge to handle both create and update
                                    await FirebaseFirestore.instance
                                        .collection('approved_users')
                                        .doc(docId)
                                        .set({
                                      'fullName': newFullName,
                                      'email': newEmail.isEmpty ? null : newEmail,
                                      'address': newAddress,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    // Update local session
                                    UserSession.currentUserData?['fullName'] =
                                        newFullName;
                                    UserSession.currentUserData?['email'] = newEmail;
                                    UserSession.currentUserData?['address'] =
                                        newAddress;

                                    setModalState(() {
                                      isEditing = false;
                                      isSaving = false;
                                    });

                                    if (mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Profile updated successfully!'),
                                          backgroundColor: Color(0xFF22C55E),
                                        ),
                                      );
                                      // Refresh the main page
                                      setState(() {});
                                    }
                                  } on FirebaseException catch (e) {
                                    debugPrint('Firebase error updating profile: ${e.code} - ${e.message}');
                                    setModalState(() {
                                      isSaving = false;
                                      if (e.code == 'permission-denied') {
                                        errorMessage = 'Permission denied. Please check your account.';
                                      } else if (e.code == 'unavailable') {
                                        errorMessage = 'Network error. Please check your connection.';
                                      } else {
                                        errorMessage = 'Failed to save: ${e.message}';
                                      }
                                    });
                                  } catch (e) {
                                    debugPrint('Failed to update profile: $e');
                                    setModalState(() {
                                      isSaving = false;
                                      errorMessage =
                                          'Failed to save changes. Please try again.';
                                    });
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isEditing ? const Color(0xFF22C55E) : const Color(0xFFAC1B22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isEditing ? 'SAVE' : 'EDIT INFORMATION',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatPhoneNumber(String phone) {
    if (phone.isEmpty) return '';
    // Handle +63XXXXXXXXXX format
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.length == 10) {
      return '+63 ${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    }
    return phone;
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required bool isEditing,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
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
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 14,
            color: enabled ? Colors.black87 : Colors.grey[600],
          ),
          decoration: InputDecoration(
            filled: !enabled,
            fillColor: enabled ? null : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isEditing ? const Color(0xFFAC1B22) : Colors.grey[300]!,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFAC1B22), width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    String? hint,
  }) {
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.isNotEmpty ? value : 'Not provided',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSecurityContent() {
    final currentPasswordCtl = TextEditingController();
    final newPasswordCtl = TextEditingController();
    final confirmPasswordCtl = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    String? successMessage;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    final userData = UserSession.currentUserData ?? {};
    final storedPassword = userData['password']?.toString() ?? '';
    final username = userData['username']?.toString() ?? '';

    return StatefulBuilder(
      builder: (context, setModalState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Password
              _buildPasswordField(
                label: 'Current Password',
                controller: currentPasswordCtl,
                obscureText: obscureCurrent,
                onToggleVisibility: () {
                  setModalState(() => obscureCurrent = !obscureCurrent);
                },
              ),
              const SizedBox(height: 16),

              // New Password
              _buildPasswordField(
                label: 'New Password',
                controller: newPasswordCtl,
                obscureText: obscureNew,
                onToggleVisibility: () {
                  setModalState(() => obscureNew = !obscureNew);
                },
              ),
              const SizedBox(height: 8),

              // Password requirements hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password Requirements:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• At least 8 characters\n'
                      '• At least one uppercase letter (A-Z)\n'
                      '• At least one number (0-9)\n'
                      '• At least one special character (!@#\$%^&*)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[700],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Confirm New Password
              _buildPasswordField(
                label: 'Confirm New Password',
                controller: confirmPasswordCtl,
                obscureText: obscureConfirm,
                onToggleVisibility: () {
                  setModalState(() => obscureConfirm = !obscureConfirm);
                },
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (successMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.green[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          successMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Update Password Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final currentPassword = currentPasswordCtl.text;
                          final newPassword = newPasswordCtl.text;
                          final confirmPassword = confirmPasswordCtl.text;

                          setModalState(() {
                            errorMessage = null;
                            successMessage = null;
                          });

                          // Validate current password
                          if (currentPassword.isEmpty) {
                            setModalState(() =>
                                errorMessage = 'Please enter your current password');
                            return;
                          }

                          if (currentPassword != storedPassword) {
                            setModalState(() =>
                                errorMessage = 'Current password is incorrect');
                            return;
                          }

                          // Validate new password
                          final passwordValidation =
                              _validatePassword(newPassword);
                          if (passwordValidation != null) {
                            setModalState(() => errorMessage = passwordValidation);
                            return;
                          }

                          // Check passwords match
                          if (newPassword != confirmPassword) {
                            setModalState(
                                () => errorMessage = 'New passwords do not match');
                            return;
                          }

                          // Check new password is different from current
                          if (newPassword == currentPassword) {
                            setModalState(() => errorMessage =
                                'New password must be different from current password');
                            return;
                          }

                          setModalState(() => isLoading = true);

                          try {
                            // Update password in Firestore
                            await FirebaseFirestore.instance
                                .collection('approved_users')
                                .doc(username)
                                .update({'password': newPassword});

                            // Update local session
                            UserSession.currentUserData?['password'] = newPassword;

                            // Clear fields
                            currentPasswordCtl.clear();
                            newPasswordCtl.clear();
                            confirmPasswordCtl.clear();

                            setModalState(() {
                              isLoading = false;
                              successMessage = 'Password updated successfully!';
                            });
                          } catch (e) {
                            debugPrint('Failed to update password: $e');
                            setModalState(() {
                              isLoading = false;
                              errorMessage =
                                  'Failed to update password. Please try again.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAC1B22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'UPDATE PASSWORD',
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
      },
    );
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain at least one special character (!@#\$%^&*)';
    }
    return null;
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
  }) {
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
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: const TextStyle(fontSize: 13),
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
              borderSide: const BorderSide(color: Color(0xFFAC1B22), width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Colors.grey[600],
                size: 20,
              ),
              onPressed: onToggleVisibility,
            ),
          ),
        ),
      ],
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
          _buildHelpItem(
            Icons.book,
            'User Guide',
            'Learn how to use RESQ',
            onTap: () {
              // User guide content - can be expanded later
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User Guide coming soon!'),
                  backgroundColor: Color(0xFFAC1B22),
                ),
              );
            },
          ),
          _buildHelpItem(
            Icons.contact_support,
            'Contact Support',
            'Get in touch with our team',
            onTap: () async {
              final Uri emailUri = Uri(
                scheme: 'mailto',
                path: kFeedbackEmail,
                query: 'subject=RESQ Support Request',
              );
              try {
                if (await canLaunchUrl(emailUri)) {
                  await launchUrl(emailUri);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open email app'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Failed to open email: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
                color: const Color(0xFFAC1B22).withValues(alpha: 0.1),
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
                    style: const TextStyle(
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
    final descriptionCtl = TextEditingController();
    bool isSubmitting = false;
    String? errorMessage;

    return StatefulBuilder(
      builder: (context, setModalState) {
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
                controller: descriptionCtl,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Describe the problem you\'re experiencing...',
                  hintStyle: const TextStyle(fontSize: 13),
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
                    borderSide: const BorderSide(color: Color(0xFFAC1B22), width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final problemType = selectedProblemType;
                          final description = descriptionCtl.text.trim();

                          if (problemType == null) {
                            setModalState(() =>
                                errorMessage = 'Please select a problem type');
                            return;
                          }

                          if (description.isEmpty) {
                            setModalState(() =>
                                errorMessage = 'Please describe the problem');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          final userData = UserSession.currentUserData ?? {};
                          final username =
                              userData['username']?.toString() ?? 'Unknown';
                          final email = userData['email']?.toString() ?? '';

                          final Uri emailUri = Uri(
                            scheme: 'mailto',
                            path: kFeedbackEmail,
                            query: Uri.encodeFull(
                              'subject=RESQ Problem Report: $problemType&'
                              'body=Problem Type: $problemType\n\n'
                              'Description:\n$description\n\n'
                              '---\n'
                              'Reported by: $username\n'
                              'User email: $email',
                            ),
                          );

                          try {
                            if (await canLaunchUrl(emailUri)) {
                              await launchUrl(emailUri);
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Email app opened. Please send your report.'),
                                    backgroundColor: Color(0xFF22C55E),
                                  ),
                                );
                              }
                            } else {
                              setModalState(() {
                                isSubmitting = false;
                                errorMessage = 'Could not open email app';
                              });
                            }
                          } catch (e) {
                            debugPrint('Failed to open email: $e');
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage = 'Failed to open email app';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAC1B22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
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
      },
    );
  }

  Widget _buildFeedbackContent(
    int feedbackRating,
    ValueChanged<int> onRatingChanged,
  ) {
    final feedbackCtl = TextEditingController();
    bool isSubmitting = false;
    String? errorMessage;

    return StatefulBuilder(
      builder: (context, setModalState) {
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
                controller: feedbackCtl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Share your thoughts about RESQ...',
                  hintStyle: const TextStyle(fontSize: 13),
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
                    borderSide: const BorderSide(color: Color(0xFFAC1B22), width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final feedback = feedbackCtl.text.trim();

                          if (feedback.isEmpty) {
                            setModalState(() =>
                                errorMessage = 'Please write your feedback');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          final userData = UserSession.currentUserData ?? {};
                          final username =
                              userData['username']?.toString() ?? 'Unknown';
                          final email = userData['email']?.toString() ?? '';

                          final ratingStars = '★' * feedbackRating +
                              '☆' * (5 - feedbackRating);

                          final Uri emailUri = Uri(
                            scheme: 'mailto',
                            path: kFeedbackEmail,
                            query: Uri.encodeFull(
                              'subject=RESQ App Feedback&'
                              'body=Rating: $ratingStars ($feedbackRating/5)\n\n'
                              'Feedback:\n$feedback\n\n'
                              '---\n'
                              'From: $username\n'
                              'User email: $email',
                            ),
                          );

                          try {
                            if (await canLaunchUrl(emailUri)) {
                              await launchUrl(emailUri);
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Email app opened. Thank you for your feedback!'),
                                    backgroundColor: Color(0xFF22C55E),
                                  ),
                                );
                              }
                            } else {
                              setModalState(() {
                                isSubmitting = false;
                                errorMessage = 'Could not open email app';
                              });
                            }
                          } catch (e) {
                            debugPrint('Failed to open email: $e');
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage = 'Failed to open email app';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAC1B22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
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
      },
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
              letterSpacing: 0.2,
              fontFamily: 'RobotoCondensed',
            ),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: accentColor),
          dropdownColor: const Color(0xFFFFF9E8),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A2A2A),
            letterSpacing: 0.2,
            fontFamily: 'RobotoCondensed',
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A2A2A),
                  fontFamily: 'RobotoCondensed',
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

                        const SizedBox(height: 20),

                        // Logout
                        Text(
                          'Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProfileItem(
                          icon: Icons.logout,
                          label: 'Log out',
                          onTap: _showLogoutConfirm,
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
