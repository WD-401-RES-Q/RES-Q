import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import '../../../common/services/user_session.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../auth/pages/login_page.dart';

// Support inbox for feedback and user queries.
const String kFeedbackEmail = 'resq42649@gmail.com';
const String kEmailJsServiceId = 'service_yoyvzs4';
const String kEmailJsTemplateId = 'template_yekv4k9';
const String kEmailJsPublicKey = 'JLaponS_oi9inmIDR';
const String kEmailJsEndpoint = 'https://api.emailjs.com/api/v1.0/email/send';

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
  static const Duration _notificationPersistDebounceDelay = Duration(
    milliseconds: 400,
  );
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  String? _profilePhotoUrl; // URL from Firebase Storage
  bool _isUploadingPhoto = false;
  static const String _profilePhotoCachePrefix = 'profile_photo_url_';
  Timer? _notificationPersistDebounce;
  Future<List<dynamic>>? _accountSecurityFuture;
  bool? _cachedBiometricsAvailable;
  bool? _cachedBiometricsEnabled;

  bool _hasConfiguredSupportEmail() {
    final trimmed = kFeedbackEmail.trim();
    return trimmed.isNotEmpty &&
        trimmed.contains('@') &&
        !trimmed.contains('YOUR_EMAIL_HERE');
  }

  bool _hasConfiguredEmailJs() {
    return kEmailJsServiceId.trim().isNotEmpty &&
        kEmailJsTemplateId.trim().isNotEmpty &&
        kEmailJsPublicKey.trim().isNotEmpty &&
        !kEmailJsServiceId.contains('YOUR_') &&
        !kEmailJsTemplateId.contains('YOUR_') &&
        !kEmailJsPublicKey.contains('YOUR_');
  }

  Future<bool> _sendSupportEmail({
    required String subject,
    required String message,
    required String senderName,
    required String senderEmail,
  }) async {
    if (!_hasConfiguredSupportEmail() || !_hasConfiguredEmailJs()) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(kEmailJsEndpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': kEmailJsServiceId,
          'template_id': kEmailJsTemplateId,
          'user_id': kEmailJsPublicKey,
          'template_params': {
            'to_email': kFeedbackEmail,
            'to_name': 'RES-Q Support',
            'subject': subject,
            'message': message,
            'from_name': senderName,
            'reply_to': senderEmail,
          },
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }

      debugPrint(
        'EmailJS send failed [${response.statusCode}]: ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('EmailJS send error: $e');
      return false;
    }
  }

  void _showSupportEmailNotConfiguredMessage() {
    if (!mounted) return;
    AppSnackBar.show(
      context,
      'Support email is not configured yet. Please contact your admin.',
      type: AppSnackBarType.warning,
      useRootOverlay: true,
    );
  }

  @override
  void initState() {
    super.initState();
    _accountSecurityFuture = _loadAccountSecurityState(forceRefresh: true);
    _initializeProfilePhoto();
    _initializeNotificationSettings();
  }

  @override
  void dispose() {
    final pendingPersist = _notificationPersistDebounce;
    if (pendingPersist?.isActive == true) {
      _notificationPersistDebounce?.cancel();
      unawaited(_persistNotificationSettings());
    } else {
      _notificationPersistDebounce?.cancel();
    }
    super.dispose();
  }

  Future<void> _initializeProfilePhoto() async {
    await _loadSavedProfilePhoto();
    await _refreshProfilePhotoFromFirestore();
  }

  /// Load the saved profile photo URL from UserSession/local cache.
  Future<void> _loadSavedProfilePhoto() async {
    final savedUrl = UserSession.currentUserData?['profilePhotoUrl']
        ?.toString()
        .trim();
    if (savedUrl != null && savedUrl.isNotEmpty && mounted) {
      setState(() {
        _profilePhotoUrl = savedUrl;
      });
      return;
    }

    final cacheKey = _profilePhotoCacheKey();
    if (cacheKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString(cacheKey);
      if (!mounted || cachedUrl == null || cachedUrl.isEmpty) return;
      setState(() {
        _profilePhotoUrl = cachedUrl;
      });
      UserSession.currentUserData?['profilePhotoUrl'] = cachedUrl;
    } catch (e) {
      debugPrint('Failed to load cached profile photo URL: $e');
    }
  }

  String? _profilePhotoCacheKey() {
    final userData = UserSession.currentUserData;
    final contact = (userData?['contactNumber'] ?? userData?['phoneNumber'])
        ?.toString()
        .trim();
    final docId = (userData?['docId'] ?? userData?['id'])?.toString().trim();
    final rawKey = (contact != null && contact.isNotEmpty) ? contact : docId;
    if (rawKey == null || rawKey.isEmpty) return null;
    final normalized = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (normalized.isEmpty) return null;
    return '$_profilePhotoCachePrefix$normalized';
  }

  Future<void> _saveProfilePhotoUrlToCache(String url) async {
    final cacheKey = _profilePhotoCacheKey();
    if (cacheKey == null || url.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, url);
    } catch (e) {
      debugPrint('Failed to cache profile photo URL: $e');
    }
  }

  bool _isResponderRole() {
    final role = (UserSession.currentUserData?['role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'semi-admin' || role == 'semi_admin' || role == 'responder';
  }

  String _currentContactNumber() {
    return (UserSession.currentUserData?['contactNumber'] ??
                UserSession.currentUserData?['phoneNumber'])
            ?.toString()
            .trim() ??
        '';
  }

  String _currentUserDocId() {
    return (UserSession.currentUserData?['docId'] ??
                UserSession.currentUserData?['id'])
            ?.toString()
            .trim() ??
        '';
  }

  Future<bool> _ensureFirebaseAuthSession() async {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  String? _notificationPrefsLocalKeyBase() {
    final raw = _currentContactNumber().isNotEmpty
        ? _currentContactNumber()
        : _currentUserDocId();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (normalized.isEmpty) return null;
    return 'notif_prefs_$normalized';
  }

  String? _notificationPrefsDocId() {
    final contactNumber = _currentContactNumber();
    if (contactNumber.isNotEmpty) {
      final cleanPhone = contactNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      if (cleanPhone.isNotEmpty) return cleanPhone;
    }
    final docId = _currentUserDocId();
    if (docId.isNotEmpty) return docId;
    return null;
  }

  Future<void> _initializeNotificationSettings() async {
    final localKeyBase = _notificationPrefsLocalKeyBase();
    if (localKeyBase != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localPush = prefs.getBool('${localKeyBase}_push');
        final localSound = prefs.getBool('${localKeyBase}_sound');
        final localVibration = prefs.getBool('${localKeyBase}_vibration');
        if (mounted) {
          setState(() {
            _pushNotifications = localPush ?? _pushNotifications;
            _soundEnabled = localSound ?? _soundEnabled;
            _vibrationEnabled = localVibration ?? _vibrationEnabled;
          });
        } else {
          _pushNotifications = localPush ?? _pushNotifications;
          _soundEnabled = localSound ?? _soundEnabled;
          _vibrationEnabled = localVibration ?? _vibrationEnabled;
        }
      } catch (e) {
        debugPrint('Failed to load local notification settings: $e');
      }
    }

    final docId = _notificationPrefsDocId();
    if (docId == null) return;
    try {
      if (!await _ensureFirebaseAuthSession()) return;
      final doc = await FirebaseFirestore.instance
          .collection('userPreferences')
          .doc(docId)
          .get();
      final data = doc.data();
      if (data == null) return;
      final remotePush = data['pushNotifications'] as bool?;
      final remoteSound = data['soundEnabled'] as bool?;
      final remoteVibration = data['vibrationEnabled'] as bool?;

      if (mounted) {
        setState(() {
          _pushNotifications = remotePush ?? _pushNotifications;
          _soundEnabled = remoteSound ?? _soundEnabled;
          _vibrationEnabled = remoteVibration ?? _vibrationEnabled;
        });
      } else {
        _pushNotifications = remotePush ?? _pushNotifications;
        _soundEnabled = remoteSound ?? _soundEnabled;
        _vibrationEnabled = remoteVibration ?? _vibrationEnabled;
      }
      await _persistNotificationSettings();
    } catch (e) {
      debugPrint('Failed to load remote notification settings: $e');
    }
  }

  Future<void> _persistNotificationSettings() async {
    final localKeyBase = _notificationPrefsLocalKeyBase();
    if (localKeyBase != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('${localKeyBase}_push', _pushNotifications);
        await prefs.setBool('${localKeyBase}_sound', _soundEnabled);
        await prefs.setBool('${localKeyBase}_vibration', _vibrationEnabled);
      } catch (e) {
        debugPrint('Failed to save local notification settings: $e');
      }
    }

    final docId = _notificationPrefsDocId();
    if (docId == null) return;
    try {
      if (!await _ensureFirebaseAuthSession()) return;
      await FirebaseFirestore.instance
          .collection('userPreferences')
          .doc(docId)
          .set({
            'pushNotifications': _pushNotifications,
            'soundEnabled': _soundEnabled,
            'vibrationEnabled': _vibrationEnabled,
            'notificationPrefsUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save remote notification settings: $e');
    }
  }

  Future<List<DocumentReference<Map<String, dynamic>>>>
  _resolveCurrentUserDocRefs() async {
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final seenPaths = <String>{};
    void addRef(DocumentReference<Map<String, dynamic>> ref) {
      if (seenPaths.add(ref.path)) {
        refs.add(ref);
      }
    }

    final userData = UserSession.currentUserData;
    final contactNumber =
        (userData?['contactNumber'] ?? userData?['phoneNumber'])
            ?.toString()
            .trim();
    final docId = (userData?['docId'] ?? userData?['id'])?.toString().trim();

    if (_isResponderRole()) {
      if (docId != null && docId.isNotEmpty) {
        addRef(FirebaseFirestore.instance.collection('semi_admins').doc(docId));
      }
      if (contactNumber != null && contactNumber.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('semi_admins')
            .where('contactNumber', isEqualTo: contactNumber)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          addRef(snapshot.docs.first.reference);
        }
      }
    } else {
      if (docId != null && docId.isNotEmpty) {
        addRef(
          FirebaseFirestore.instance.collection('approved_users').doc(docId),
        );
      }
      if (contactNumber != null && contactNumber.isNotEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('approved_users')
            .where('contactNumber', isEqualTo: contactNumber)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          addRef(snapshot.docs.first.reference);
        }
      }
    }

    if (contactNumber != null && contactNumber.isNotEmpty) {
      final approvedSnapshot = await FirebaseFirestore.instance
          .collection('approved_users')
          .where('contactNumber', isEqualTo: contactNumber)
          .limit(1)
          .get();
      if (approvedSnapshot.docs.isNotEmpty) {
        addRef(approvedSnapshot.docs.first.reference);
      }
      final responderSnapshot = await FirebaseFirestore.instance
          .collection('semi_admins')
          .where('contactNumber', isEqualTo: contactNumber)
          .limit(1)
          .get();
      if (responderSnapshot.docs.isNotEmpty) {
        addRef(responderSnapshot.docs.first.reference);
      }
    }

    return refs;
  }

  Future<void> _refreshProfilePhotoFromFirestore() async {
    try {
      final refs = await _resolveCurrentUserDocRefs();
      if (refs.isEmpty) return;
      for (final ref in refs) {
        final snapshot = await ref.get();
        final data = snapshot.data();
        final url = data?['profilePhotoUrl']?.toString().trim();
        if (url != null && url.isNotEmpty) {
          UserSession.currentUserData?['profilePhotoUrl'] = url;
          await _saveProfilePhotoUrlToCache(url);
          if (mounted) {
            setState(() {
              _profilePhotoUrl = url;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to refresh profile photo URL from Firestore: $e');
    }
  }

  @override
  bool get wantKeepAlive => true;
  static const String _ratingStarAsset = 'assets/icons/rating-star.png';

  Future<void> _updateSemiAdminPresenceOnLogout() async {
    final userData = UserSession.currentUserData;
    final role = (userData?['role'] ?? '').toString().toLowerCase();
    if (!(role == 'semi-admin' ||
        role == 'semi_admin' ||
        role == 'responder')) {
      return;
    }

    final docId =
        (userData?['id'] ?? userData?['contactNumber'])?.toString().trim() ??
        '';
    if (docId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('semi_admins')
          .doc(docId)
          .set({
            'isLoggedIn': false,
            'status': 'offline',
            'isAvailable': false,
            'lastSeenAt': FieldValue.serverTimestamp(),
            'sessionStartedAt': FieldValue.delete(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to mark semi-admin offline: $e');
    }
  }

  static const String _ratingEmptyCircleAsset =
      'assets/icons/rating-empty-circle.png';

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
    if (title == 'Account Security' && _accountSecurityFuture == null) {
      _accountSecurityFuture = _loadAccountSecurityState(forceRefresh: false);
    }

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
                constraints: const BoxConstraints(
                  maxHeight: 600,
                  maxWidth: 500,
                ),
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
                        (rating) =>
                            setDialogState(() => feedbackRating = rating),
                        (value) =>
                            setDialogState(() => selectedProblemType = value),
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
                        onPressed: () async {
                          await _updateSemiAdminPresenceOnLogout();
                          await NotificationService().clearCurrentUserToken();
                          UserSession.clear();
                          if (!context.mounted) return;
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

    // For Android 13+ (API 33+), image_picker uses the system photo picker
    // which doesn't require explicit permission. For older versions, we need storage.
    if (Platform.isAndroid) {
      // Try photos permission first (Android 13+)
      var status = await Permission.photos.status;
      if (status.isGranted || status.isLimited) return true;

      if (status.isDenied) {
        final result = await Permission.photos.request();
        if (result.isGranted || result.isLimited) return true;
      }

      // Fallback to storage for older Android versions
      status = await Permission.storage.status;
      if (status.isGranted) return true;

      if (status.isDenied) {
        final result = await Permission.storage.request();
        if (result.isGranted) return true;
      }

      // If both are permanently denied, show dialog
      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog('Photo Library');
        }
        return false;
      }

      // On Android 13+, if permission is "limited" or we got here,
      // image_picker might still work with the system picker
      return true;
    } else {
      // iOS
      final status = await Permission.photos.status;
      if (status.isGranted || status.isLimited) return true;

      if (status.isDenied) {
        final result = await Permission.photos.request();
        return result.isGranted || result.isLimited;
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog('Photo Library');
        }
        return false;
      }
    }

    return true; // Default to true to let image_picker handle it
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
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.white),
            ),
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
        AppSnackBar.show(
          context,
          'Failed to capture photo. Please try again.',
          type: AppSnackBarType.error,
          useRootOverlay: true,
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
        AppSnackBar.show(
          context,
          'Failed to select photo. Please try again.',
          type: AppSnackBarType.error,
          useRootOverlay: true,
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
          WebUiSettings(context: context, presentStyle: WebPresentStyle.dialog),
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

      // Upload to Firebase Storage and save URL to Firestore
      await _uploadProfilePhotoToFirebase(cropped.path);
    } catch (e) {
      debugPrint('Failed to crop profile photo: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          'Failed to crop photo. Please try again.',
          type: AppSnackBarType.error,
          useRootOverlay: true,
        );
      }
    }
  }

  /// Upload profile photo to Firebase Storage and save URL to Firestore
  Future<void> _uploadProfilePhotoToFirebase(String filePath) async {
    final userData = UserSession.currentUserData;
    final identity =
        (userData?['contactNumber'] ??
                userData?['phoneNumber'] ??
                userData?['id'])
            ?.toString()
            .trim();
    if (identity == null || identity.isEmpty) {
      debugPrint('Cannot upload profile photo: No user identity found');
      return;
    }

    setState(() => _isUploadingPhoto = true);

    try {
      // Create a stable filename using the user's identity
      final sanitizedIdentity = identity.replaceAll(
        RegExp(r'[^a-zA-Z0-9]'),
        '',
      );
      final fileName = 'profile_$sanitizedIdentity.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child(fileName);

      // Upload the file
      final file = File(filePath);
      final uploadTask = await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Get the download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('Profile photo uploaded: $downloadUrl');
      final refs = await _resolveCurrentUserDocRefs();
      if (refs.isEmpty) {
        debugPrint('No user document found for saving profile photo URL');
      } else {
        await Future.wait(
          refs.map(
            (ref) => ref.set({
              'profilePhotoUrl': downloadUrl,
            }, SetOptions(merge: true)),
          ),
        );
        debugPrint('Profile photo URL saved to Firestore');
      }

      await _saveProfilePhotoUrlToCache(downloadUrl);
      UserSession.currentUserData?['profilePhotoUrl'] = downloadUrl;
      if (mounted) {
        setState(() {
          _profilePhotoUrl = downloadUrl;
        });
      }

      if (mounted) {
        AppSnackBar.show(
          context,
          'Profile picture saved!',
          type: AppSnackBarType.success,
          useRootOverlay: true,
        );
      }
    } catch (e) {
      debugPrint('Failed to upload profile photo: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          'Photo selected but failed to save. Will retry on next app open.',
          type: AppSnackBarType.warning,
          useRootOverlay: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
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
                  border: Border.all(color: const Color(0xFFAC1B22), width: 3),
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
                          side: const BorderSide(
                            color: Color(0xFFAC1B22),
                            width: 2,
                          ),
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
        return _buildFeedbackContent(feedbackRating, onRatingChanged);
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
    final phoneNumber =
        (userData['contactNumber'] ?? userData['phoneNumber'])?.toString() ??
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
                      Icon(
                        Icons.error_outline,
                        color: Colors.red[700],
                        size: 18,
                      ),
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
                            fullNameCtl.text =
                                userData['fullName']?.toString() ?? '';
                            emailCtl.text = userData['email']?.toString() ?? '';
                            addressCtl.text =
                                userData['address']?.toString() ?? '';
                            setModalState(() {
                              isEditing = false;
                              errorMessage = null;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFAC1B22),
                              width: 2,
                            ),
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
                                      () => errorMessage =
                                          'Full name is required',
                                    );
                                    return;
                                  }

                                  if (newEmail.isNotEmpty &&
                                      !RegExp(
                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                      ).hasMatch(newEmail)) {
                                    setModalState(
                                      () => errorMessage =
                                          'Invalid email address',
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    isSaving = true;
                                    errorMessage = null;
                                  });

                                  try {
                                    final refs =
                                        await _resolveCurrentUserDocRefs();
                                    if (refs.isEmpty) {
                                      setModalState(() {
                                        isSaving = false;
                                        errorMessage =
                                            'Unable to locate your profile record. Please log in again.';
                                      });
                                      return;
                                    }

                                    final payload = <String, dynamic>{
                                      'fullName': newFullName,
                                      'email': newEmail.isEmpty
                                          ? null
                                          : newEmail,
                                      'address': newAddress,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    };

                                    await Future.wait(
                                      refs.map(
                                        (ref) => ref.set(
                                          payload,
                                          SetOptions(merge: true),
                                        ),
                                      ),
                                    );

                                    // Update local session
                                    UserSession.currentUserData?['fullName'] =
                                        newFullName;
                                    UserSession.currentUserData?['email'] =
                                        newEmail.isEmpty ? null : newEmail;
                                    UserSession.currentUserData?['address'] =
                                        newAddress;

                                    setModalState(() {
                                      isEditing = false;
                                      isSaving = false;
                                    });

                                    if (!context.mounted) return;
                                    AppSnackBar.show(
                                      context,
                                      'Profile updated successfully!',
                                      type: AppSnackBarType.success,
                                      useRootOverlay: true,
                                    );
                                    // Refresh the main page
                                    setState(() {});
                                  } on FirebaseException catch (e) {
                                    debugPrint(
                                      'Firebase error updating profile: ${e.code} - ${e.message}',
                                    );
                                    setModalState(() {
                                      isSaving = false;
                                      if (e.code == 'permission-denied') {
                                        errorMessage =
                                            'Permission denied. Please check your account.';
                                      } else if (e.code == 'unavailable') {
                                        errorMessage =
                                            'Network error. Please check your connection.';
                                      } else {
                                        errorMessage =
                                            'Failed to save: ${e.message}';
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
                          backgroundColor: isEditing
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFAC1B22),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
    final userData = UserSession.currentUserData ?? {};
    final docId = (userData['docId'] ?? userData['id'])?.toString() ?? '';
    final contactNumber =
        (userData['contactNumber'] ?? userData['phoneNumber'])?.toString() ??
        '';

    _accountSecurityFuture ??= _loadAccountSecurityState(forceRefresh: false);

    return StatefulBuilder(
      builder: (context, setModalState) {
        return FutureBuilder<List<dynamic>>(
          future: _accountSecurityFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                _cachedBiometricsAvailable == null &&
                _cachedBiometricsEnabled == null) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFAC1B22)),
                ),
              );
            }

            final biometricsAvailable =
                _cachedBiometricsAvailable ??
                (snapshot.data?[0] as bool? ?? false);
            final biometricsEnabled =
                _cachedBiometricsEnabled ??
                (snapshot.data?[1] as bool? ?? false);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Biometrics Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFAC1B22,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.fingerprint,
                                color: Color(0xFFAC1B22),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Biometric Login',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    biometricsAvailable
                                        ? 'Use fingerprint or face to login'
                                        : 'Not available on this device',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: biometricsEnabled,
                              onChanged: biometricsAvailable
                                  ? (value) async {
                                      final previousValue =
                                          _cachedBiometricsEnabled ??
                                          biometricsEnabled;
                                      setModalState(() {
                                        _cachedBiometricsEnabled = value;
                                      });
                                      final saved = await _setBiometricsEnabled(
                                        value,
                                      );
                                      if (!saved) {
                                        if (!context.mounted) return;
                                        setModalState(() {
                                          _cachedBiometricsEnabled =
                                              previousValue;
                                        });
                                        AppSnackBar.show(
                                          context,
                                          'Failed to update biometric setting.',
                                          type: AppSnackBarType.error,
                                          useRootOverlay: true,
                                        );
                                        return;
                                      }
                                      if (!context.mounted) return;
                                      AppSnackBar.show(
                                        context,
                                        value
                                            ? 'Biometric login enabled'
                                            : 'Biometric login disabled',
                                        type: value
                                            ? AppSnackBarType.success
                                            : AppSnackBarType.info,
                                        useRootOverlay: true,
                                      );
                                    }
                                  : null,
                              activeThumbColor: const Color(0xFFAC1B22),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Change PIN Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFAC1B22,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                color: Color(0xFFAC1B22),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Change PIN',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Update your 4-digit security PIN',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: () {
                              if (contactNumber.trim().isEmpty &&
                                  docId.trim().isEmpty) {
                                AppSnackBar.show(
                                  context,
                                  'No account identity found for this account.',
                                  type: AppSnackBarType.warning,
                                  useRootOverlay: true,
                                );
                                return;
                              }
                              Navigator.pop(context);
                              _showChangePinDialog(docId, contactNumber);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAC1B22),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'CHANGE PIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keep your PIN private. Never share it with anyone.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<dynamic>> _loadAccountSecurityState({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh &&
        _cachedBiometricsAvailable != null &&
        _cachedBiometricsEnabled != null) {
      return [_cachedBiometricsAvailable!, _cachedBiometricsEnabled!];
    }

    final results = await Future.wait<dynamic>([
      _checkBiometricsAvailable(),
      _getBiometricsEnabled(),
    ]);
    _cachedBiometricsAvailable = results[0] as bool;
    _cachedBiometricsEnabled = results[1] as bool;
    return results;
  }

  Future<bool> _checkBiometricsAvailable() async {
    if (kIsWeb) return false;
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (e) {
      debugPrint('Error checking biometrics: $e');
      return false;
    }
  }

  Future<bool> _getBiometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final contactNumber = _currentContactNumber();
      if (contactNumber.isEmpty) return false;

      final cleanPhone = contactNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final localEnabled = prefs.getBool('biometrics_enabled') ?? false;
      final localPhone = prefs.getString('biometrics_phone') ?? '';

      if (!await _ensureFirebaseAuthSession()) {
        return localEnabled && localPhone == cleanPhone;
      }

      // First check Firestore for persistent preference
      final doc = await FirebaseFirestore.instance
          .collection('userPreferences')
          .doc(cleanPhone)
          .get();

      if (doc.exists) {
        final firestoreEnabled =
            doc.data()?['biometricsEnabled'] as bool? ?? false;
        // Always sync local cache with latest remote value.
        await prefs.setBool('biometrics_enabled', firestoreEnabled);
        await prefs.setString('biometrics_phone', cleanPhone);
        return firestoreEnabled;
      }

      // Fall back to SharedPreferences, but only for this exact phone.
      return localEnabled && localPhone == cleanPhone;
    } catch (e) {
      debugPrint('Error getting biometrics setting: $e');
      final contactNumber = _currentContactNumber();
      final cleanPhone = contactNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      final localEnabled = prefs.getBool('biometrics_enabled') ?? false;
      final localPhone = prefs.getString('biometrics_phone') ?? '';
      return localEnabled && localPhone == cleanPhone;
    }
  }

  Future<bool> _setBiometricsEnabled(bool enabled) async {
    try {
      final contactNumber = _currentContactNumber();
      if (contactNumber.isEmpty) return false;

      final cleanPhone = contactNumber.replaceAll(RegExp(r'[^0-9+]'), '');

      // Save to SharedPreferences for local/quick access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', enabled);
      await prefs.setString('biometrics_phone', cleanPhone);

      if (!await _ensureFirebaseAuthSession()) {
        debugPrint(
          'Biometrics preference saved locally only (no Firebase auth session).',
        );
        _cachedBiometricsEnabled = enabled;
        return true;
      }

      // Save to Firestore for persistence across devices (like votes)
      await FirebaseFirestore.instance
          .collection('userPreferences')
          .doc(cleanPhone)
          .set({
            'biometricsEnabled': enabled,
            'biometricsUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      _cachedBiometricsEnabled = enabled;
      debugPrint('Biometrics preference saved.');
      return true;
    } catch (e) {
      debugPrint('Error setting biometrics: $e');
      return false;
    }
  }

  void _showChangePinDialog(String docId, String contactNumber) {
    final collectionName = _isResponderRole()
        ? 'semi_admins'
        : 'approved_users';
    final resolvedDocId = docId.trim().isNotEmpty
        ? docId.trim()
        : _currentUserDocId();
    final resolvedContactNumber = contactNumber.trim().isNotEmpty
        ? contactNumber.trim()
        : _currentContactNumber();

    final currentPinControllers = List.generate(
      4,
      (_) => TextEditingController(),
    );
    final newPinControllers = List.generate(4, (_) => TextEditingController());
    final confirmPinControllers = List.generate(
      4,
      (_) => TextEditingController(),
    );
    final currentPinFocusNodes = List.generate(4, (_) => FocusNode());
    final newPinFocusNodes = List.generate(4, (_) => FocusNode());
    final confirmPinFocusNodes = List.generate(4, (_) => FocusNode());

    int step = 1; // 1: current PIN, 2: new PIN, 3: confirm PIN
    String? errorMessage;
    bool isLoading = false;
    String currentPinEntered = '';
    String newPinEntered = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String getTitle() {
              switch (step) {
                case 1:
                  return 'ENTER CURRENT PIN';
                case 2:
                  return 'ENTER NEW PIN';
                case 3:
                  return 'CONFIRM NEW PIN';
                default:
                  return 'CHANGE PIN';
              }
            }

            String getSubtitle() {
              switch (step) {
                case 1:
                  return 'Enter your current 4-digit PIN';
                case 2:
                  return 'Create a new 4-digit PIN';
                case 3:
                  return 'Re-enter your new PIN to confirm';
                default:
                  return '';
              }
            }

            List<TextEditingController> getControllers() {
              switch (step) {
                case 1:
                  return currentPinControllers;
                case 2:
                  return newPinControllers;
                case 3:
                  return confirmPinControllers;
                default:
                  return currentPinControllers;
              }
            }

            List<FocusNode> getFocusNodes() {
              switch (step) {
                case 1:
                  return currentPinFocusNodes;
                case 2:
                  return newPinFocusNodes;
                case 3:
                  return confirmPinFocusNodes;
                default:
                  return currentPinFocusNodes;
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFFF7F8F3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () {
                          // Dispose controllers and focus nodes
                          for (var c in currentPinControllers) {
                            c.dispose();
                          }
                          for (var c in newPinControllers) {
                            c.dispose();
                          }
                          for (var c in confirmPinControllers) {
                            c.dispose();
                          }
                          for (var f in currentPinFocusNodes) {
                            f.dispose();
                          }
                          for (var f in newPinFocusNodes) {
                            f.dispose();
                          }
                          for (var f in confirmPinFocusNodes) {
                            f.dispose();
                          }
                          Navigator.pop(dialogContext);
                        },
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

                    // Lock icon
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
                        Icons.lock_outline,
                        size: 35,
                        color: Color(0xFFAC1B22),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Title
                    Text(
                      getTitle(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFAC1B22),
                        letterSpacing: 0.5,
                        fontFamily: 'RobotoCondensed',
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      getSubtitle(),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // PIN Input Fields
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        return Container(
                          width: 40,
                          height: 56,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: getControllers()[index],
                            focusNode: getFocusNodes()[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            textAlignVertical: TextAlignVertical.center,
                            maxLength: 1,
                            showCursor: false,
                            obscureText: true,
                            obscuringCharacter: '\u2022',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(1),
                            ],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFAC1B22),
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              final cleanValue = value.replaceAll(
                                RegExp(r'[^0-9]'),
                                '',
                              );
                              if (cleanValue.isEmpty) {
                                getControllers()[index].clear();
                                if (index > 0) {
                                  getFocusNodes()[index - 1].requestFocus();
                                }
                                setDialogState(() => errorMessage = null);
                                return;
                              }

                              final singleChar = cleanValue.substring(
                                cleanValue.length - 1,
                              );
                              if (getControllers()[index].text != singleChar) {
                                getControllers()[index].text = singleChar;
                                getControllers()[index].selection =
                                    const TextSelection.collapsed(offset: 1);
                              }

                              if (index < 3) {
                                getFocusNodes()[index + 1].requestFocus();
                              } else {
                                FocusScope.of(context).unfocus();
                              }
                              setDialogState(() => errorMessage = null);
                            },
                          ),
                        );
                      }),
                    ),

                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Step indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: step > index
                                ? const Color(0xFFAC1B22)
                                : Colors.grey[300],
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 24),

                    // Continue/Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final pin = getControllers()
                                    .map((c) => c.text)
                                    .join();

                                if (pin.length != 4) {
                                  setDialogState(
                                    () => errorMessage =
                                        'Please enter all 4 digits',
                                  );
                                  return;
                                }

                                if (step == 1) {
                                  // Verify current PIN
                                  setDialogState(() => isLoading = true);
                                  try {
                                    bool hasMatchingPin = false;
                                    if (resolvedContactNumber.isNotEmpty) {
                                      final query = await FirebaseFirestore
                                          .instance
                                          .collection(collectionName)
                                          .where(
                                            'contactNumber',
                                            isEqualTo: resolvedContactNumber,
                                          )
                                          .where('pin', isEqualTo: pin)
                                          .limit(1)
                                          .get();
                                      hasMatchingPin = query.docs.isNotEmpty;
                                    } else if (resolvedDocId.isNotEmpty) {
                                      final snapshot = await FirebaseFirestore
                                          .instance
                                          .collection(collectionName)
                                          .doc(resolvedDocId)
                                          .get();
                                      final existingPin =
                                          snapshot.data()?['pin']?.toString() ??
                                          '';
                                      hasMatchingPin = existingPin == pin;
                                    }

                                    if (!hasMatchingPin) {
                                      setDialogState(() {
                                        isLoading = false;
                                        errorMessage = 'Incorrect PIN';
                                        for (var c in currentPinControllers) {
                                          c.clear();
                                        }
                                        currentPinFocusNodes[0].requestFocus();
                                      });
                                      return;
                                    }

                                    currentPinEntered = pin;
                                    setDialogState(() {
                                      isLoading = false;
                                      step = 2;
                                      errorMessage = null;
                                    });
                                    newPinFocusNodes[0].requestFocus();
                                  } catch (e) {
                                    debugPrint('Error verifying PIN: $e');
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMessage =
                                          'Error verifying PIN. Try again.';
                                    });
                                  }
                                } else if (step == 2) {
                                  // Check new PIN is different from current
                                  if (pin == currentPinEntered) {
                                    setDialogState(
                                      () => errorMessage =
                                          'New PIN must be different from current PIN',
                                    );
                                    return;
                                  }
                                  newPinEntered = pin;
                                  setDialogState(() {
                                    step = 3;
                                    errorMessage = null;
                                  });
                                  confirmPinFocusNodes[0].requestFocus();
                                } else if (step == 3) {
                                  // Confirm new PIN matches
                                  if (pin != newPinEntered) {
                                    setDialogState(() {
                                      errorMessage = 'PINs do not match';
                                      for (var c in confirmPinControllers) {
                                        c.clear();
                                      }
                                      confirmPinFocusNodes[0].requestFocus();
                                    });
                                    return;
                                  }

                                  // Update PIN in Firestore
                                  setDialogState(() => isLoading = true);
                                  try {
                                    if (resolvedDocId.isNotEmpty) {
                                      await FirebaseFirestore.instance
                                          .collection(collectionName)
                                          .doc(resolvedDocId)
                                          .set({
                                            'pin': newPinEntered,
                                          }, SetOptions(merge: true));
                                    } else if (resolvedContactNumber
                                        .isNotEmpty) {
                                      final query = await FirebaseFirestore
                                          .instance
                                          .collection(collectionName)
                                          .where(
                                            'contactNumber',
                                            isEqualTo: resolvedContactNumber,
                                          )
                                          .limit(1)
                                          .get();
                                      if (query.docs.isEmpty) {
                                        throw Exception(
                                          'Account record not found',
                                        );
                                      }
                                      await query.docs.first.reference.set({
                                        'pin': newPinEntered,
                                      }, SetOptions(merge: true));
                                    } else {
                                      throw Exception(
                                        'No account identity found for PIN update',
                                      );
                                    }

                                    // Update local session
                                    UserSession.currentUserData?['pin'] =
                                        newPinEntered;

                                    // Close dialog
                                    if (!dialogContext.mounted ||
                                        !context.mounted) {
                                      return;
                                    }
                                    Navigator.pop(dialogContext);
                                    AppSnackBar.show(
                                      context,
                                      'PIN changed successfully!',
                                      type: AppSnackBarType.success,
                                      useRootOverlay: true,
                                    );
                                  } catch (e) {
                                    debugPrint('Error updating PIN: $e');
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMessage =
                                          'Failed to update PIN. Try again.';
                                    });
                                  }
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
                            : Text(
                                step == 3 ? 'SAVE NEW PIN' : 'CONTINUE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
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
    _scheduleNotificationSettingsPersist();
  }

  void _scheduleNotificationSettingsPersist() {
    _notificationPersistDebounce?.cancel();
    _notificationPersistDebounce = Timer(
      _notificationPersistDebounceDelay,
      () => unawaited(_persistNotificationSettings()),
    );
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
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFAC1B22),
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
              AppSnackBar.show(
                context,
                'User Guide coming soon!',
                type: AppSnackBarType.info,
                useRootOverlay: true,
              );
            },
          ),
          _buildHelpItem(
            Icons.contact_support,
            'Contact Support',
            'Get in touch with our team',
            onTap: () async {
              if (!_hasConfiguredSupportEmail()) {
                _showSupportEmailNotConfiguredMessage();
                return;
              }
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
                    AppSnackBar.show(
                      context,
                      'Could not open email app',
                      type: AppSnackBarType.error,
                      useRootOverlay: true,
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                    borderSide: const BorderSide(
                      color: Color(0xFFAC1B22),
                      width: 2,
                    ),
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
                            setModalState(
                              () =>
                                  errorMessage = 'Please select a problem type',
                            );
                            return;
                          }

                          if (description.isEmpty) {
                            setModalState(
                              () =>
                                  errorMessage = 'Please describe the problem',
                            );
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          final userData = UserSession.currentUserData ?? {};
                          final displayName =
                              userData['fullName']?.toString() ?? 'User';
                          final email =
                              userData['email']?.toString() ??
                              'no-email@resq.local';
                          final contact =
                              userData['contactNumber']?.toString() ??
                              userData['phoneNumber']?.toString() ??
                              'N/A';
                          if (!_hasConfiguredSupportEmail() ||
                              !_hasConfiguredEmailJs()) {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage =
                                  'Support email service is not configured yet.';
                            });
                            return;
                          }

                          final sent = await _sendSupportEmail(
                            subject: 'RESQ Problem Report: $problemType',
                            senderName: displayName,
                            senderEmail: email,
                            message:
                                'Problem Type: $problemType\n\n'
                                'Description:\n$description\n\n'
                                '---\n'
                                'Reported by: $displayName\n'
                                'User email: $email\n'
                                'Contact number: $contact',
                          );

                          if (sent) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            AppSnackBar.show(
                              context,
                              'Report sent successfully.',
                              type: AppSnackBarType.success,
                              useRootOverlay: true,
                            );
                          } else {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage =
                                  'Failed to send report. Please try again.';
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
                    borderSide: const BorderSide(
                      color: Color(0xFFAC1B22),
                      width: 2,
                    ),
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
                            setModalState(
                              () => errorMessage = 'Please write your feedback',
                            );
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          final userData = UserSession.currentUserData ?? {};
                          final displayName =
                              userData['fullName']?.toString() ??
                              userData['contactNumber']?.toString() ??
                              'User';
                          final email =
                              userData['email']?.toString() ??
                              'no-email@resq.local';
                          final contact =
                              userData['contactNumber']?.toString() ??
                              userData['phoneNumber']?.toString() ??
                              'N/A';

                          if (!_hasConfiguredSupportEmail() ||
                              !_hasConfiguredEmailJs()) {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage =
                                  'Support email service is not configured yet.';
                            });
                            return;
                          }
                          final sent = await _sendSupportEmail(
                            subject: 'RESQ App Feedback',
                            senderName: displayName,
                            senderEmail: email,
                            message:
                                'Rating: $feedbackRating/5\n\n'
                                'Feedback:\n$feedback\n\n'
                                '---\n'
                                'From: $displayName\n'
                                'User email: $email\n'
                                'Contact number: $contact',
                          );

                          if (sent) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            AppSnackBar.show(
                              context,
                              'Feedback sent. Thank you!',
                              type: AppSnackBarType.success,
                              useRootOverlay: true,
                            );
                          } else {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage =
                                  'Failed to send feedback. Please try again.';
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
            color: Colors.black.withValues(alpha: 0.06),
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
          items: ['App Crashes', 'Feature Not Working', 'Login Issues', 'Other']
              .map((String value) {
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
              })
              .toList(),
          onChanged: onProblemTypeChanged,
        ),
      ),
    );
  }

  Widget _buildRatingIcon(bool isSelected) {
    final assetPath = isSelected ? _ratingStarAsset : _ratingEmptyCircleAsset;
    return SizedBox(width: 36, height: 36, child: Image.asset(assetPath));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileName =
        (UserSession.currentUserData?['fullName'] ??
                UserSession.currentUserData?['contactNumber'] ??
                'User')
            .toString()
            .trim();
    final profileInitial = profileName.isNotEmpty
        ? profileName[0].toUpperCase()
        : '?';
    final hasProfilePhoto =
        _profilePhotoBytes != null ||
        _profilePhoto != null ||
        _profilePhotoUrl != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
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
                    // Show loading indicator while uploading
                    if (_isUploadingPhoto)
                      const SizedBox(
                        width: 110,
                        height: 110,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFFAC1B22),
                        ),
                      ),
                    CircleAvatar(
                      radius: 55,
                      backgroundColor: const Color(0xFFAC1B22),
                      backgroundImage: _profilePhotoBytes != null
                          ? MemoryImage(_profilePhotoBytes!)
                          : (_profilePhoto != null
                                ? FileImage(File(_profilePhoto!.path))
                                : (_profilePhotoUrl != null
                                      ? CachedNetworkImageProvider(
                                          _profilePhotoUrl!,
                                        )
                                      : null)),
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
                          color: Colors.black.withValues(alpha: 0.12),
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
