import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:easy_stepper/easy_stepper.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/phone_lookup_service.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';
import '../../../common/widgets/terms_and_conditions_widget.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  static const int _maxAddressLength = 256;
  static const int _maxImageUploadBytes = 4 * 1024 * 1024;
  static const String _phoneLookupScopeKey = 'register';
  static const int _minimumAllowedAge = 13;
  static const int _adultAgeThreshold = 18;

  static const List<String> _adultAcceptedIdTypes = [
    'UMID',
    "Driver's License",
    'Passport',
    "Voter's ID",
    'PhilSys National ID',
    'ePhilID',
    'PRC ID',
    'Postal ID',
    'SSS ID',
  ];

  static const List<String> _minorAcceptedIdTypes = [
    'School ID',
    'PhilSys National ID',
    'ePhilID',
    'Passport',
  ];

  final _adultFormKey = GlobalKey<FormState>();
  final _minorPage1FormKey = GlobalKey<FormState>();
  final _minorPage3FormKey = GlobalKey<FormState>();

  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _contactCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final ValueNotifier<bool> _termsAgreed = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _termsError = ValueNotifier<String?>(null);

  final _parentFirstNameCtl = TextEditingController();
  final _parentLastNameCtl = TextEditingController();
  final _parentContactCtl = TextEditingController();

  bool _loading = false;
  bool _ageGateCompleted = true;
  bool _isMinor = true;
  int _adultStep = 0;
  int _minorStep = 0;

  DateTime? _selectedDateOfBirth;

  String? _adultIdType;
  String? _minorIdType;
  String? _parentIdType;

  String? _frontIdUrl;
  String? _selfieWithIdUrl;
  String? _parentFrontIdUrl;
  String? _parentSelfieWithIdUrl;
  String? _psaBirthCertificateUrl;

  bool _uploadingPsa = false;

  String? _dobError;
  String? _idPhotoError;
  String? _parentIdPhotoError;
  String? _adultIdTypeError;
  String? _minorIdTypeError;
  String? _parentIdTypeError;
  String? _psaError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhoneLookupService _phoneLookupService = PhoneLookupService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  bool _routeArgsInitialized = false;
  bool _isPhonePreVerified = false;
  String? _preVerifiedPhoneNumber;

  @override
  void initState() {
    super.initState();
    _contactCtl.addListener(_onContactChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeArgsInitialized) return;
    _routeArgsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;

    final rawPhone = args['phoneNumber'] as String?;
    if (rawPhone == null || rawPhone.trim().isEmpty) return;

    final digits = _extractPhoneDigits(rawPhone);
    if (digits.length != 10) return;

    _contactCtl.text = _formatPhoneInput(digits);
    _preVerifiedPhoneNumber = '+63$digits';
    _isPhonePreVerified = args['phoneVerified'] == true;
  }

  @override
  void dispose() {
    _phoneLookupService.cancelDebounce(_phoneLookupScopeKey);
    _contactCtl.removeListener(_onContactChanged);
    _termsAgreed.dispose();
    _termsError.dispose();

    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _emailCtl.dispose();
    _contactCtl.dispose();
    _addressCtl.dispose();
    _parentFirstNameCtl.dispose();
    _parentLastNameCtl.dispose();
    _parentContactCtl.dispose();
    super.dispose();
  }

  void _onIdUploadComplete(String? frontUrl, String? selfieUrl) {
    setState(() {
      _frontIdUrl = frontUrl;
      _selfieWithIdUrl = selfieUrl;
      if (frontUrl != null && selfieUrl != null) {
        _idPhotoError = null;
      }
    });
  }

  void _onParentIdUploadComplete(String? frontUrl, String? selfieUrl) {
    setState(() {
      _parentFrontIdUrl = frontUrl;
      _parentSelfieWithIdUrl = selfieUrl;
      if (frontUrl != null && selfieUrl != null) {
        _parentIdPhotoError = null;
      }
    });
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final birthdayPassed =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!birthdayPassed) {
      age -= 1;
    }
    return age;
  }

  String _formatDateForStorage(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDateForDisplay(DateTime date) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthName = months[date.month - 1];
    return '$monthName ${date.day}, ${date.year}';
  }

  String _extractPhoneDigits(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('63')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  String _formatPhoneInput(String digits) {
    final clean = digits.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length && i < 10; i++) {
      if (i == 3 || i == 6) {
        buffer.write('-');
      }
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }

  Future<void> _showAgeGateModal() async {
    final selectedDate =
        _selectedDateOfBirth ??
        DateTime.now().subtract(const Duration(days: 365 * _adultAgeThreshold));

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'SELECT DATE OF BIRTH',
      builder: (pickerContext, child) {
        final themed = Theme.of(pickerContext).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.appRed,
            onPrimary: Colors.white,
            onSurface: AppTheme.appBlack,
            surface: AppTheme.appOffWhite,
          ),
        );
        return Theme(data: themed, child: child!);
      },
    );

    if (!mounted) return;
    if (picked == null) {
      if (_selectedDateOfBirth == null) {
        setState(() {
          _dobError = 'Date of birth is required';
        });
      }
      return;
    }

    final age = _calculateAge(picked);
    setState(() {
      _selectedDateOfBirth = picked;
      _isMinor = age < _adultAgeThreshold;
      _ageGateCompleted = true;
      _adultStep = 0;
      _minorStep = 0;
      _dobError = null;
      _termsAgreed.value = false;
      _termsError.value = null;
      if (!_isMinor) {
        _parentFirstNameCtl.clear();
        _parentLastNameCtl.clear();
        _parentContactCtl.clear();
        _parentFrontIdUrl = null;
        _parentSelfieWithIdUrl = null;
        _parentIdType = null;
        _psaBirthCertificateUrl = null;
      }
    });
  }

  Future<bool> _checkPhoneNumberExists(String phone) async {
    try {
      return await _phoneLookupService.hasRegistrationConflict(phone);
    } catch (e) {
      debugPrint('Error checking phone number: $e');
      return false;
    }
  }

  String _formatBanUntil(DateTime? bannedUntil) {
    if (bannedUntil == null) {
      return '';
    }
    final date = DateTime(
      bannedUntil.year,
      bannedUntil.month,
      bannedUntil.day,
      bannedUntil.hour,
      bannedUntil.minute,
    );
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour24 = date.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = hour24 >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year $hour12:$minute $meridiem';
  }

  Future<void> _showBannedAccountDialog({
    required bool isPermanentBan,
    DateTime? bannedUntil,
    List<String> banReasons = const <String>[],
  }) async {
    if (!mounted) return;

    final reasonText = banReasons.isEmpty ? '' : banReasons.join(', ');
    final formattedUntil = _formatBanUntil(bannedUntil);
    final title = isPermanentBan
        ? 'ACCOUNT PERMANENTLY BANNED'
        : 'ACCOUNT TEMPORARILY BANNED';
    final subtitle = isPermanentBan
        ? 'Your account is permanently banned and cannot access RES-Q.'
        : 'Your account is temporarily banned and cannot access RES-Q right now.';
    final untilText = isPermanentBan || formattedUntil.isEmpty
        ? ''
        : 'Ban ends on: $formattedUntil';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppTheme.appBlack.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.appRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.appRed, width: 2),
                ),
                child: const Icon(
                  Icons.block,
                  size: 48,
                  color: AppTheme.appRed,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.appRed,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.appBlack.withValues(alpha: 0.85),
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              if (untilText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  untilText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.appBlack,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (reasonText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Reason(s): $reasonText',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.appBlack.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.appRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.8,
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearLocalAuthArtifactsForBan() async {
    try {
      await Future.wait<void>([
        RegistrationPrefs.clearPhoneNumber(),
        RegistrationPrefs.setApprovedLoginCompleted(false),
        TrustedDeviceService.instance.clearTrustedDevice(),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometrics_enabled');
      await prefs.remove('biometrics_phone');
      UserSession.clear();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Failed to clear banned-account auth artifacts: $e');
    }
  }

  Future<void> _handleBannedAccount({
    required bool isPermanentBan,
    DateTime? bannedUntil,
    List<String> banReasons = const <String>[],
  }) async {
    await _showBannedAccountDialog(
      isPermanentBan: isPermanentBan,
      bannedUntil: bannedUntil,
      banReasons: banReasons,
    );
    await _clearLocalAuthArtifactsForBan();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<bool> _checkEmailExists(String normalizedEmail) async {
    try {
      final approvedByLower = await _firestore
          .collection('approved_users')
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (approvedByLower.docs.isNotEmpty) {
        return true;
      }

      final pendingByLower = await _firestore
          .collection('pending_users')
          .where('emailLower', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (pendingByLower.docs.isNotEmpty) {
        return true;
      }

      final approvedExact = await _firestore
          .collection('approved_users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (approvedExact.docs.isNotEmpty) {
        return true;
      }

      final pendingExact = await _firestore
          .collection('pending_users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      return pendingExact.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking email: $e');
      return false;
    }
  }

  void _onContactChanged() {
    final phoneDigits = _contactCtl.text.replaceAll(RegExp(r'\D'), '');
    final normalized = phoneDigits.length == 10 ? '+63$phoneDigits' : null;
    if (_isPhonePreVerified &&
        normalized != null &&
        normalized != _preVerifiedPhoneNumber) {
      _isPhonePreVerified = false;
    }
    _phoneLookupService.cancelDebounce(_phoneLookupScopeKey);
    if (phoneDigits.length != 10) return;

    unawaited(
      _phoneLookupService
          .debouncedLookupAccountStatus(
            scopeKey: _phoneLookupScopeKey,
            phone: '+63$phoneDigits',
          )
          .catchError((error) {
            debugPrint('Registration phone lookup failed: $error');
            return null;
          }),
    );
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.appOffWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Select Image Source',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.appBlack,
            ),
          ),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildImageSourceOption(
                  icon: Icons.photo_camera,
                  label: 'Camera',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                const SizedBox(height: 10),
                _buildImageSourceOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0.5,
      shadowColor: AppTheme.appBlack.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.appRed),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.appBlack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPsa() async {
    if (_uploadingPsa) return;

    final source = await _showImageSourcePicker();
    if (source == null) return;

    try {
      setState(() {
        _uploadingPsa = true;
        _psaError = null;
      });

      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );

      if (picked == null) {
        setState(() => _uploadingPsa = false);
        return;
      }

      final phoneDigits = _contactCtl.text.replaceAll(RegExp(r'\D'), '');
      final pathKey = phoneDigits.isEmpty
          ? 'pending_${DateTime.now().millisecondsSinceEpoch}'
          : phoneDigits;
      final fileName = 'psa_birth_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('id_photos')
          .child(pathKey)
          .child(fileName);

      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageUploadBytes) {
        if (!mounted) return;
        setState(() {
          _uploadingPsa = false;
        });
        await _showImageSizeLimitDialog();
        return;
      }
      final snapshot = await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await snapshot.ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _psaBirthCertificateUrl = downloadUrl;
        _uploadingPsa = false;
        _psaError = null;
      });
      AppSnackBar.show(
        context,
        'PSA Birth Certificate uploaded successfully.',
        type: AppSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPsa = false;
        _psaError = 'Failed to upload PSA Birth Certificate.';
      });
      AppSnackBar.show(
        context,
        'Failed to upload document: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _showImageSizeLimitDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Image Too Large',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack,
          ),
        ),
        content: const Text(
          'The maximum allowed image size is 4 MB. Please choose a smaller image.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.appBlack,
            fontFamily: 'RobotoCondensed',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                color: AppTheme.appRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExpandedNetworkPreview({
    required String title,
    required String imageUrl,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppTheme.appRed),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.55,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.broken_image,
                        color: AppTheme.appBlack.withValues(alpha: 0.35),
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isValidNamePart(String name) {
    if (name.length < 2 || name.length > 40) return false;
    final parts = name.split(' ');
    final wordPattern = RegExp(r"^[A-Za-z]{2,}([-''][A-Za-z]+)*\.?$");
    final initialPattern = RegExp(r"^[A-Za-z]\.?$");
    for (final part in parts) {
      if (!wordPattern.hasMatch(part) && !initialPattern.hasMatch(part)) {
        return false;
      }
    }
    return true;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  String _normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  String? _validateRequiredEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email is required';
    if (!_isValidEmail(email)) return 'Enter a valid email address';
    return null;
  }

  bool _isValidAddress(String address) {
    if (address.length < 5 || address.length > _maxAddressLength) return false;
    return RegExp(r'[A-Za-z0-9]').hasMatch(address);
  }

  bool _isValidGuardianPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('9')) return true;
    if (digits.length == 11 && digits.startsWith('09')) return true;
    if (digits.length == 12 && digits.startsWith('63')) return true;
    return false;
  }

  String? _validateFirstName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'First name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid first name';
    return null;
  }

  String? _validateLastName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Last name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid last name';
    return null;
  }

  String? _validateAddress(String? value) {
    final address = (value ?? '').trim();
    if (address.isEmpty) return 'Home address is required';
    if (address.length > _maxAddressLength) {
      return 'Address must be $_maxAddressLength characters or fewer';
    }
    return _isValidAddress(address) ? null : 'Enter a valid home address';
  }

  String? _validateParentFirstName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Parent/guardian first name is required';
    if (!_isValidNamePart(normalized)) {
      return 'Enter a valid parent/guardian first name';
    }
    return null;
  }

  String? _validateParentLastName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Parent/guardian last name is required';
    if (!_isValidNamePart(normalized)) {
      return 'Enter a valid parent/guardian last name';
    }
    return null;
  }

  String? _validateParentContact(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Parent/guardian phone or email is required';
    }
    if (_isValidEmail(input)) return null;
    if (_isValidGuardianPhone(input)) return null;
    return 'Enter a valid phone number or email';
  }

  List<TextInputFormatter> _nameInputFormatters() {
    return [
      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z .'-]")),
      const NameCapitalizationFormatter(),
    ];
  }

  String? _currentUserFrontIdFieldError() {
    if (_idPhotoError == null || _frontIdUrl != null) return null;
    return _isMinor
        ? 'Please upload the minor\'s ID photo'
        : 'Please upload your valid ID photo';
  }

  String? _currentUserSelfieIdFieldError() {
    if (_idPhotoError == null || _selfieWithIdUrl != null) return null;
    return _isMinor
        ? 'Please upload the minor\'s selfie with ID'
        : 'Please upload your selfie with ID';
  }

  String? _parentFrontIdFieldError() {
    if (_parentIdPhotoError == null || _parentFrontIdUrl != null) return null;
    return 'Please upload parent/guardian ID photo';
  }

  String? _parentSelfieIdFieldError() {
    if (_parentIdPhotoError == null || _parentSelfieWithIdUrl != null) {
      return null;
    }
    return 'Please upload parent/guardian selfie with ID';
  }

  Widget _buildDobSummary() {
    final selectedDate = _selectedDateOfBirth;
    final value = selectedDate == null
        ? 'Select date of birth'
        : _formatDateForDisplay(selectedDate);
    return CustomDatePicker(
      valueText: value,
      isPlaceholder: selectedDate == null,
      onChange: _loading ? null : _showAgeGateModal,
      hasError: _dobError != null,
      isValid: selectedDate != null && _dobError == null,
      errorText: _dobError,
    );
  }

  Widget _buildInlineTermsAndAgreement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TermsAndConditionsWidget(
          enabled: !_loading,
          initiallyAgreed: _termsAgreed.value,
          onAgreementChanged: (agreed) {
            _termsAgreed.value = agreed;
            if (agreed && _termsError.value != null) {
              _termsError.value = null;
            }
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: _termsError,
          builder: (context, message, _) {
            return RegistrationValidationMessage(message: message);
          },
        ),
      ],
    );
  }

  Widget _buildMinorProgress() {
    const total = 5;
    final step = _minorStep + 1;

    return Column(
      children: [
        Text(
          'STEP $step OF $total',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _minorStep.toDouble()),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, animatedStep, _) {
            final clampedAnimated = animatedStep.clamp(
              0.0,
              (total - 1).toDouble(),
            );
            final activeStep = clampedAnimated.floor().clamp(0, total - 1);
            final lineProgress = (clampedAnimated - activeStep).clamp(0.0, 1.0);

            return EasyStepper(
              activeStep: activeStep,
              enableStepTapping: false,
              steppingEnabled: false,
              direction: Axis.horizontal,
              disableScroll: true,
              fitWidth: true,
              showTitle: false,
              showStepBorder: false,
              showLoadingAnimation: false,
              internalPadding: 8,
              stepRadius: 13,
              borderThickness: 1.2,
              defaultStepBorderType: BorderType.normal,
              activeStepBorderType: BorderType.normal,
              finishedStepBorderType: BorderType.normal,
              unreachedStepBorderType: BorderType.normal,
              activeStepBoxShadow: const [],
              finishedStepBoxShadow: const [],
              unreachedStepBoxShadow: const [],
              activeStepBackgroundColor: AppTheme.appRed,
              finishedStepBackgroundColor: AppTheme.appRed,
              unreachedStepBackgroundColor: AppTheme.appOffWhite,
              activeStepTextColor: Colors.white,
              finishedStepTextColor: Colors.white,
              unreachedStepTextColor: AppTheme.appBlack.withValues(alpha: 0.62),
              activeStepIconColor: Colors.white,
              finishedStepIconColor: Colors.white,
              unreachedStepIconColor: AppTheme.appBlack.withValues(alpha: 0.62),
              activeStepBorderColor: AppTheme.appOffYellow,
              finishedStepBorderColor: AppTheme.appOffYellow,
              unreachedStepBorderColor: AppTheme.appBlack.withValues(
                alpha: 0.32,
              ),
              lineStyle: LineStyle(
                lineType: LineType.normal,
                lineLength: double.infinity,
                lineThickness: 2.4,
                defaultLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                unreachedLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                activeLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                finishedLineColor: AppTheme.appRed.withValues(alpha: 0.45),
                progressColor: AppTheme.appRed,
                progress: activeStep >= total - 1 ? 1.0 : lineProgress,
                borderRadius: BorderRadius.circular(6),
              ),
              steps: List.generate(total, (index) {
                final isCompleted = index < clampedAnimated;
                final isActive = index == activeStep;
                return EasyStep(
                  enabled: false,
                  customStep: _buildMinorStepperCircle(
                    index: index,
                    isCompleted: isCompleted,
                    isActive: isActive,
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMinorStepperCircle({
    required int index,
    required bool isCompleted,
    required bool isActive,
  }) {
    final isReached = isCompleted || isActive;
    final outerRingColor = isReached
        ? AppTheme.appOffYellow
        : AppTheme.appBlack.withValues(alpha: 0.32);
    final innerRingColor = isReached
        ? AppTheme.appRed
        : AppTheme.appBlack.withValues(alpha: 0.32);
    final backgroundColor = isReached ? AppTheme.appRed : AppTheme.appOffWhite;
    final labelColor = isReached
        ? Colors.white
        : AppTheme.appBlack.withValues(alpha: 0.62);

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: outerRingColor, width: 1.4),
      ),
      padding: const EdgeInsets.all(1.8),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          border: Border.all(color: innerRingColor, width: 1.2),
        ),
        alignment: Alignment.center,
        child: isCompleted
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
              ),
      ),
    );
  }

  Widget _buildMinorBackButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppTheme.appBlack.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton(
        onPressed: _loading
            ? null
            : () {
                if (_minorStep == 0) {
                  Navigator.of(context).maybePop();
                  return;
                }
                setState(() {
                  _minorStep -= 1;
                });
              },
        style: OutlinedButton.styleFrom(
          backgroundColor: AppTheme.appOffWhite,
          side: BorderSide(color: AppTheme.appRed.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          'BACK',
          style: TextStyle(color: AppTheme.appRed, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  bool _validateMinorStep(int step) {
    if (step == 0) {
      return _minorPage1FormKey.currentState?.validate() ?? false;
    }

    if (step == 1) {
      final hasFrontId = _frontIdUrl != null;
      final hasSelfie = _selfieWithIdUrl != null;
      setState(() {
        _minorIdTypeError = _minorIdType == null
            ? 'Select the minor\'s ID type'
            : null;
        if (hasFrontId && hasSelfie) {
          _idPhotoError = null;
        } else if (!hasFrontId && !hasSelfie) {
          _idPhotoError = 'Please upload minor ID and selfie with ID';
        } else if (!hasFrontId) {
          _idPhotoError = 'Please upload the minor\'s ID photo';
        } else {
          _idPhotoError = 'Please upload the minor\'s selfie with ID';
        }
        _psaError = _psaBirthCertificateUrl == null
            ? 'Please upload the PSA Birth Certificate'
            : null;
      });
      return _minorIdType != null &&
          hasFrontId &&
          hasSelfie &&
          _psaBirthCertificateUrl != null;
    }

    if (step == 2) {
      return _minorPage3FormKey.currentState?.validate() ?? false;
    }

    if (step == 3) {
      final hasParentFront = _parentFrontIdUrl != null;
      final hasParentSelfie = _parentSelfieWithIdUrl != null;
      setState(() {
        _parentIdTypeError = _parentIdType == null
            ? 'Select parent/guardian ID type'
            : null;
        if (hasParentFront && hasParentSelfie) {
          _parentIdPhotoError = null;
        } else if (!hasParentFront && !hasParentSelfie) {
          _parentIdPhotoError = 'Please upload parent ID and selfie with ID';
        } else if (!hasParentFront) {
          _parentIdPhotoError = 'Please upload parent/guardian ID photo';
        } else {
          _parentIdPhotoError = 'Please upload parent/guardian selfie with ID';
        }
      });
      return _parentIdType != null && hasParentFront && hasParentSelfie;
    }

    if (step == 4) {
      final agreed = _termsAgreed.value;
      _termsError.value = agreed
          ? null
          : 'Please read and agree to the Terms and Conditions.';
      return agreed;
    }

    return false;
  }

  bool _isAdultInfoComplete() {
    return _validateFirstName(_firstNameCtl.text) == null &&
        _validateLastName(_lastNameCtl.text) == null &&
        _validateRequiredEmail(_emailCtl.text) == null &&
        validatePhilippinePhone(_contactCtl.text) == null &&
        _validateAddress(_addressCtl.text) == null &&
        _selectedDateOfBirth != null;
  }

  Future<void> _nextAdultStepOrSubmit() async {
    if (_adultStep == 0) {
      final valid = _adultFormKey.currentState?.validate() ?? false;
      if (!valid) {
        AppSnackBar.show(
          context,
          'Please complete the required fields before continuing.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      final selectedDate = _selectedDateOfBirth;
      if (selectedDate == null) {
        setState(() {
          _dobError = 'Date of birth is required';
        });
        AppSnackBar.show(
          context,
          'Please select your date of birth before continuing.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      final age = _calculateAge(selectedDate);
      if (age < _minimumAllowedAge) {
        AppSnackBar.show(
          context,
          'Registration is only allowed for users aged 13 and above.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      if (age < _adultAgeThreshold) {
        setState(() {
          _isMinor = true;
          _minorStep = 1;
          _adultStep = 0;
        });
        return;
      }

      setState(() {
        _adultStep = 1;
        _isMinor = false;
      });
      return;
    }

    if (_adultStep == 1) {
      final hasFrontId = _frontIdUrl != null;
      final hasSelfie = _selfieWithIdUrl != null;
      setState(() {
        _adultIdTypeError = _adultIdType == null
            ? 'Please select an ID type'
            : null;
        if (hasFrontId && hasSelfie) {
          _idPhotoError = null;
        } else if (!hasFrontId && !hasSelfie) {
          _idPhotoError = 'Please upload your ID and selfie with ID';
        } else if (!hasFrontId) {
          _idPhotoError = 'Please upload your valid ID photo';
        } else {
          _idPhotoError = 'Please upload your selfie with ID';
        }
      });

      if (_adultIdType == null || !hasFrontId || !hasSelfie) {
        AppSnackBar.show(
          context,
          'Please complete the required fields before continuing.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      setState(() {
        _adultStep = 2;
      });
      return;
    }

    await _submit();
  }

  Future<void> _nextMinorStepOrSubmit() async {
    if (!_validateMinorStep(_minorStep)) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Please complete the required fields before continuing.',
          type: AppSnackBarType.warning,
        );
      }
      return;
    }

    if (_minorStep == 0) {
      final selectedDate = _selectedDateOfBirth;
      if (selectedDate == null) {
        setState(() {
          _dobError = 'Date of birth is required';
        });
        AppSnackBar.show(
          context,
          'Please select your date of birth before continuing.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      final age = _calculateAge(selectedDate);
      if (age < _minimumAllowedAge) {
        AppSnackBar.show(
          context,
          'Registration is only allowed for users aged 13 and above.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      if (age >= _adultAgeThreshold) {
        setState(() {
          _isMinor = false;
          _adultStep = 1;
          _minorStep = 0;
        });
        return;
      }
    }

    if (_minorStep < 4) {
      setState(() {
        _minorStep += 1;
      });
      return;
    }

    await _submit();
  }

  Future<void> _submit() async {
    final selectedDate = _selectedDateOfBirth;
    if (!_ageGateCompleted || selectedDate == null) {
      setState(() {
        _dobError = 'Date of birth is required';
      });
      AppSnackBar.show(
        context,
        'Please select your date of birth before continuing.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final normalizedFirstName = _firstNameCtl.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedLastName = _lastNameCtl.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedAddress = _addressCtl.text.trim();
    final normalizedEmail = _normalizeEmail(_emailCtl.text);

    final normalizedParentFirstName = _parentFirstNameCtl.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final normalizedParentLastName = _parentLastNameCtl.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedParentContact = _parentContactCtl.text.trim();

    final isAdultValid = !_isMinor ? _isAdultInfoComplete() : true;
    if (!isAdultValid) {
      AppSnackBar.show(
        context,
        'Please complete your information before creating an account.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    if (_validateRequiredEmail(normalizedEmail) != null) {
      AppSnackBar.show(
        context,
        'Please enter a valid email address before continuing.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    if (!_termsAgreed.value) {
      _termsError.value = 'Please read and agree to the Terms and Conditions.';
      return;
    }

    final hasFrontId = _frontIdUrl != null;
    final hasSelfie = _selfieWithIdUrl != null;
    final hasParentFront = !_isMinor || _parentFrontIdUrl != null;
    final hasParentSelfie = !_isMinor || _parentSelfieWithIdUrl != null;

    setState(() {
      if (!_isMinor) {
        _adultIdTypeError = _adultIdType == null
            ? 'Please select an ID type'
            : null;
      }

      if (hasFrontId && hasSelfie) {
        _idPhotoError = null;
      } else if (!hasFrontId && !hasSelfie) {
        _idPhotoError = 'Please upload your ID and selfie with ID';
      } else if (!hasFrontId) {
        _idPhotoError = 'Please upload your valid ID photo';
      } else {
        _idPhotoError = 'Please upload your selfie with ID';
      }

      if (_isMinor) {
        _minorIdTypeError = _minorIdType == null
            ? 'Please select the minor\'s ID type'
            : null;
        _psaError = _psaBirthCertificateUrl == null
            ? 'Please upload the PSA Birth Certificate'
            : null;
        _parentIdTypeError = _parentIdType == null
            ? 'Please select parent ID type'
            : null;

        if (hasParentFront && hasParentSelfie) {
          _parentIdPhotoError = null;
        } else if (!hasParentFront && !hasParentSelfie) {
          _parentIdPhotoError =
              'Please upload parent/guardian ID and selfie with ID';
        } else if (!hasParentFront) {
          _parentIdPhotoError = 'Please upload parent/guardian ID photo';
        } else {
          _parentIdPhotoError = 'Please upload parent/guardian selfie with ID';
        }
      }
    });

    final hasAdultIdType = !_isMinor ? _adultIdType != null : true;
    final hasMinorData = !_isMinor
        ? true
        : (_minorIdType != null &&
              _psaBirthCertificateUrl != null &&
              _parentIdType != null &&
              hasParentFront &&
              hasParentSelfie &&
              (_minorPage3FormKey.currentState?.validate() ?? false));

    if (!hasAdultIdType || !hasFrontId || !hasSelfie || !hasMinorData) {
      return;
    }

    setState(() => _loading = true);

    final phoneDigits = _contactCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneDigits';
    final isUsingPreVerifiedPhone =
        _isPhonePreVerified && _preVerifiedPhoneNumber == phone;

    await RegistrationPrefs.savePhoneNumber(phoneDigits);
    if (!mounted) return;

    final accountStatus = await _phoneLookupService.lookupAccountStatus(
      phone,
      useCache: false,
    );
    if (!mounted) return;
    if (accountStatus.isBannedAccount) {
      setState(() => _loading = false);
      await _handleBannedAccount(
        isPermanentBan: accountStatus.isPermanentBan,
        bannedUntil: accountStatus.bannedUntil,
        banReasons: accountStatus.banReasons,
      );
      return;
    }

    final phoneExists = await _checkPhoneNumberExists(phone);
    if (!mounted) return;
    if (phoneExists) {
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'This phone number is already registered or pending approval. Please use a different number.',
        type: AppSnackBarType.error,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final emailExists = await _checkEmailExists(normalizedEmail);
    if (!mounted) return;
    if (emailExists) {
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'This email address is already registered. Please use a different email.',
        type: AppSnackBarType.error,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    final userData = <String, dynamic>{
      'firstName': normalizedFirstName,
      'lastName': normalizedLastName,
      'fullName': '$normalizedFirstName $normalizedLastName',
      'email': normalizedEmail,
      'emailLower': normalizedEmail,
      'phoneNumber': phone,
      'contactNumber': phone,
      'address': normalizedAddress,
      'dateOfBirth': _formatDateForStorage(selectedDate),
      'dateOfBirthDisplay': _formatDateForDisplay(selectedDate),
      'isApproved': false,
      'isMinor': _isMinor,
      'lastLoginTimestamp': null,
      'createdAt': null,
      'idType': _isMinor ? _minorIdType : _adultIdType,
      'idImageUrl': _frontIdUrl,
      'selfieImageUrl': _selfieWithIdUrl,
      'status': 'pending',
      'accountStatus': 'pending',
      'role': 'user',
    };

    if (_isMinor) {
      userData['psaBirthCertificateUrl'] = _psaBirthCertificateUrl;
      userData['parentFirstName'] = normalizedParentFirstName;
      userData['parentLastName'] = normalizedParentLastName;
      userData['parentName'] =
          '$normalizedParentFirstName $normalizedParentLastName'.trim();
      userData['parentContact'] = normalizedParentContact;
      userData['parentIdType'] = _parentIdType;
      userData['parentIdImageUrl'] = _parentFrontIdUrl;
      userData['parentSelfieImageUrl'] = _parentSelfieWithIdUrl;
    }

    if (isUsingPreVerifiedPhone) {
      final uid = _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        setState(() => _loading = false);
        AppSnackBar.show(
          context,
          'Phone verification expired. Please verify again.',
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      setState(() => _loading = false);
      _finishAutofillContext();
      Navigator.pushNamed(
        context,
        '/pin-creation',
        arguments: {'phoneNumber': phone, 'userData': userData, 'uid': uid},
      );
      return;
    }

    try {
      if (!kIsWeb) {
        await _auth.setSettings(appVerificationDisabledForTesting: kDebugMode);
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 30),
        verificationCompleted: (_) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _loading = false);
          AppSnackBar.show(
            context,
            e.message ?? 'Phone verification failed',
            type: AppSnackBarType.error,
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() => _loading = false);
          _finishAutofillContext();

          Navigator.pushNamed(
            context,
            '/otp',
            arguments: {
              'flowType': 'registration',
              'verificationId': verificationId,
              'phoneNumber': phone,
              'userData': userData,
            },
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Failed to send OTP: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  void _finishAutofillContext() {
    try {
      TextInput.finishAutofillContext();
    } catch (_) {}
  }

  Widget _buildAdultProgress() {
    const total = 3;
    final step = _adultStep + 1;

    return Column(
      children: [
        Text(
          'STEP $step OF $total',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _adultStep.toDouble()),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, animatedStep, _) {
            final clampedAnimated = animatedStep.clamp(
              0.0,
              (total - 1).toDouble(),
            );
            final activeStep = clampedAnimated.floor().clamp(0, total - 1);
            final lineProgress = (clampedAnimated - activeStep).clamp(0.0, 1.0);

            return EasyStepper(
              activeStep: activeStep,
              enableStepTapping: false,
              steppingEnabled: false,
              direction: Axis.horizontal,
              disableScroll: true,
              fitWidth: true,
              showTitle: false,
              showStepBorder: false,
              showLoadingAnimation: false,
              internalPadding: 8,
              stepRadius: 13,
              borderThickness: 1.2,
              defaultStepBorderType: BorderType.normal,
              activeStepBorderType: BorderType.normal,
              finishedStepBorderType: BorderType.normal,
              unreachedStepBorderType: BorderType.normal,
              activeStepBoxShadow: const [],
              finishedStepBoxShadow: const [],
              unreachedStepBoxShadow: const [],
              activeStepBackgroundColor: AppTheme.appRed,
              finishedStepBackgroundColor: AppTheme.appRed,
              unreachedStepBackgroundColor: AppTheme.appOffWhite,
              activeStepTextColor: Colors.white,
              finishedStepTextColor: Colors.white,
              unreachedStepTextColor: AppTheme.appBlack.withValues(alpha: 0.62),
              activeStepIconColor: Colors.white,
              finishedStepIconColor: Colors.white,
              unreachedStepIconColor: AppTheme.appBlack.withValues(alpha: 0.62),
              activeStepBorderColor: AppTheme.appOffYellow,
              finishedStepBorderColor: AppTheme.appOffYellow,
              unreachedStepBorderColor: AppTheme.appBlack.withValues(
                alpha: 0.32,
              ),
              lineStyle: LineStyle(
                lineType: LineType.normal,
                lineLength: double.infinity,
                lineThickness: 2.4,
                defaultLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                unreachedLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                activeLineColor: AppTheme.appBlack.withValues(alpha: 0.18),
                finishedLineColor: AppTheme.appRed.withValues(alpha: 0.45),
                progressColor: AppTheme.appRed,
                progress: activeStep >= total - 1 ? 1.0 : lineProgress,
                borderRadius: BorderRadius.circular(6),
              ),
              steps: List.generate(total, (index) {
                final isCompleted = index < clampedAnimated;
                final isActive = index == activeStep;
                return EasyStep(
                  enabled: false,
                  customStep: _buildMinorStepperCircle(
                    index: index,
                    isCompleted: isCompleted,
                    isActive: isActive,
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAdultStepContent() {
    if (_adultStep == 0) {
      return Form(
        key: _adultFormKey,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomTextFormField(
                    controller: _firstNameCtl,
                    label: 'FIRST NAME',
                    hintText: 'e.g. Juan',
                    autofillHints: const [AutofillHints.givenName],
                    inputFormatters: _nameInputFormatters(),
                    textCapitalization: TextCapitalization.words,
                    validator: _validateFirstName,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ),
                const SizedBox(width: AppDimensions.paddingSmall),
                Expanded(
                  child: CustomTextFormField(
                    controller: _lastNameCtl,
                    label: 'LAST NAME',
                    hintText: 'e.g. Dela Cruz',
                    autofillHints: const [AutofillHints.familyName],
                    inputFormatters: _nameInputFormatters(),
                    textCapitalization: TextCapitalization.words,
                    validator: _validateLastName,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            CustomTextFormField(
              controller: _emailCtl,
              label: 'EMAIL ADDRESS',
              hintText: 'e.g. juan@email.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: _validateRequiredEmail,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            CustomPhoneField(
              controller: _contactCtl,
              label: 'PHONE NUMBER',
              validator: validatePhilippinePhone,
              autofillHints: const [AutofillHints.telephoneNumber],
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            CustomAddressField(
              controller: _addressCtl,
              label: 'COMPLETE ADDRESS',
              hintText: 'e.g. Blk 3 Lot 2, Brgy. Mabini, QC',
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxAddressLength),
              ],
              autofillHints: const [AutofillHints.fullStreetAddress],
              validator: _validateAddress,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            _buildDobSummary(),
          ],
        ),
      );
    }

    if (_adultStep == 1) {
      return Column(
        children: [
          CustomDropdownField(
            label: 'ID TYPE',
            hint: 'Select valid ID',
            items: _adultAcceptedIdTypes,
            value: _adultIdType,
            errorText: _adultIdTypeError,
            onChanged: (value) {
              setState(() {
                _adultIdType = value;
                _adultIdTypeError = null;
              });
            },
          ),
          const SizedBox(height: AppDimensions.paddingLarge),
          IdVerificationWidget(
            onUploadComplete: _onIdUploadComplete,
            initialFrontUrl: _frontIdUrl,
            initialBackUrl: _selfieWithIdUrl,
            usernameForPath: _contactCtl.text.replaceAll(RegExp(r'\D'), ''),
            frontValidationError: _currentUserFrontIdFieldError(),
            selfieValidationError: _currentUserSelfieIdFieldError(),
          ),
        ],
      );
    }

    return _buildInlineTermsAndAgreement();
  }

  Widget _buildAdultBackButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppTheme.appBlack.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: OutlinedButton(
        onPressed: (_loading || _adultStep == 0)
            ? null
            : () {
                setState(() {
                  _adultStep -= 1;
                });
              },
        style: OutlinedButton.styleFrom(
          backgroundColor: AppTheme.appOffWhite,
          side: BorderSide(color: AppTheme.appRed.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          'BACK',
          style: TextStyle(color: AppTheme.appRed, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String get _adultPrimaryLabel => _adultStep < 2 ? 'NEXT' : 'CREATE';
  bool get _adultPrimaryEnabled => _adultStep < 2 || _termsAgreed.value;

  Widget _buildMinorStepContent() {
    switch (_minorStep) {
      case 0:
        return Form(
          key: _minorPage1FormKey,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomTextFormField(
                      controller: _firstNameCtl,
                      label: 'FIRST NAME',
                      hintText: 'e.g. Juan',
                      inputFormatters: _nameInputFormatters(),
                      textCapitalization: TextCapitalization.words,
                      validator: _validateFirstName,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingSmall),
                  Expanded(
                    child: CustomTextFormField(
                      controller: _lastNameCtl,
                      label: 'LAST NAME',
                      hintText: 'e.g. Dela Cruz',
                      inputFormatters: _nameInputFormatters(),
                      textCapitalization: TextCapitalization.words,
                      validator: _validateLastName,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              CustomTextFormField(
                controller: _emailCtl,
                label: 'EMAIL ADDRESS',
                hintText: 'e.g. juan@email.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: _validateRequiredEmail,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              CustomPhoneField(
                controller: _contactCtl,
                label: 'PHONE NUMBER',
                validator: validatePhilippinePhone,
                autofillHints: const [AutofillHints.telephoneNumber],
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              CustomAddressField(
                controller: _addressCtl,
                label: 'COMPLETE ADDRESS',
                hintText: 'e.g. Blk 3 Lot 2, Brgy. Mabini, QC',
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxAddressLength),
                ],
                validator: _validateAddress,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              _buildDobSummary(),
            ],
          ),
        );
      case 1:
        return Column(
          children: [
            CustomDropdownField(
              label: 'MINOR ID TYPE',
              hint: 'Select minor valid ID',
              items: _minorAcceptedIdTypes,
              value: _minorIdType,
              errorText: _minorIdTypeError,
              onChanged: (value) {
                setState(() {
                  _minorIdType = value;
                  _minorIdTypeError = null;
                });
              },
            ),
            const SizedBox(height: AppDimensions.paddingLarge),
            IdVerificationWidget(
              onUploadComplete: _onIdUploadComplete,
              initialFrontUrl: _frontIdUrl,
              initialBackUrl: _selfieWithIdUrl,
              usernameForPath:
                  '${_contactCtl.text.replaceAll(RegExp(r'\\D'), '')}_minor',
              frontValidationError: _currentUserFrontIdFieldError(),
              selfieValidationError: _currentUserSelfieIdFieldError(),
            ),
            const SizedBox(height: AppDimensions.paddingLarge),
            CustomUploadField(
              label: 'PSA BIRTH CERTIFICATE',
              hasPreview: _psaBirthCertificateUrl != null,
              preview: _psaBirthCertificateUrl == null
                  ? const SizedBox.shrink()
                  : Image.network(
                      _psaBirthCertificateUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.broken_image,
                          color: AppTheme.appBlack.withValues(alpha: 0.35),
                          size: 28,
                        ),
                      ),
                    ),
              uploading: _uploadingPsa,
              onUpload: _pickAndUploadPsa,
              onPreviewTap: _psaBirthCertificateUrl == null
                  ? null
                  : () => _showExpandedNetworkPreview(
                      title: 'PSA Birth Certificate Preview',
                      imageUrl: _psaBirthCertificateUrl!,
                    ),
              errorText: _psaError,
              status: (_psaError?.trim().isNotEmpty ?? false)
                  ? UploadFieldStatus.error
                  : (_psaBirthCertificateUrl != null
                        ? UploadFieldStatus.success
                        : UploadFieldStatus.none),
            ),
          ],
        );
      case 2:
        return Form(
          key: _minorPage3FormKey,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PARENT OR GUARDIAN\'S CONSENT',
                  style: AppTextStyles.authLabel.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSmall),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomTextFormField(
                      controller: _parentFirstNameCtl,
                      label: 'PARENT FIRST NAME',
                      hintText: 'e.g. Maria',
                      inputFormatters: _nameInputFormatters(),
                      textCapitalization: TextCapitalization.words,
                      validator: _validateParentFirstName,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingSmall),
                  Expanded(
                    child: CustomTextFormField(
                      controller: _parentLastNameCtl,
                      label: 'PARENT LAST NAME',
                      hintText: 'e.g. Santos',
                      inputFormatters: _nameInputFormatters(),
                      textCapitalization: TextCapitalization.words,
                      validator: _validateParentLastName,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              CustomTextFormField(
                controller: _parentContactCtl,
                label: 'PARENT PHONE OR EMAIL',
                hintText: 'e.g. 912-345-6789 or parent@email.com',
                keyboardType: TextInputType.emailAddress,
                validator: _validateParentContact,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
            ],
          ),
        );
      case 3:
        return Column(
          children: [
            CustomDropdownField(
              label: 'PARENT ID TYPE',
              hint: 'Select parent valid ID',
              items: _adultAcceptedIdTypes,
              value: _parentIdType,
              errorText: _parentIdTypeError,
              onChanged: (value) {
                setState(() {
                  _parentIdType = value;
                  _parentIdTypeError = null;
                });
              },
            ),
            const SizedBox(height: AppDimensions.paddingLarge),
            IdVerificationWidget(
              onUploadComplete: _onParentIdUploadComplete,
              initialFrontUrl: _parentFrontIdUrl,
              initialBackUrl: _parentSelfieWithIdUrl,
              usernameForPath:
                  '${_contactCtl.text.replaceAll(RegExp(r'\\D'), '')}_guardian',
              frontValidationError: _parentFrontIdFieldError(),
              selfieValidationError: _parentSelfieIdFieldError(),
            ),
          ],
        );
      case 4:
      default:
        return _buildInlineTermsAndAgreement();
    }
  }

  String get _minorPrimaryLabel {
    if (_minorStep < 4) return 'NEXT';
    return 'CREATE';
  }

  bool get _minorPrimaryEnabled => _minorStep < 4 || _termsAgreed.value;

  bool get _isTermsStepActive =>
      _ageGateCompleted &&
      ((!_isMinor && _adultStep == 2) || (_isMinor && _minorStep == 4));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            ResqLogoHeader(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingMedium,
                left: AppDimensions.paddingXLarge,
                right: AppDimensions.paddingXLarge,
              ),
              leading: const ResqBackButton.outline(),
              title: Text('REGISTER', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: 0,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final formViewportHeight = constraints.maxHeight;
                  final formContent = GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 360,
                        minHeight: _isTermsStepActive
                            ? (formViewportHeight -
                                  (AppDimensions.paddingXSmall * 2))
                            : 0,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingXLarge,
                          vertical: AppDimensions.paddingXSmall,
                        ),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_ageGateCompleted) ...[
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppTheme.appRed,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Preparing registration...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.appBlack.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontFamily: 'RobotoCondensed',
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ] else ...[
                                if (_isMinor) ...[
                                  _buildMinorProgress(),
                                  const SizedBox(
                                    height: AppDimensions.paddingMedium,
                                  ),
                                ] else ...[
                                  _buildAdultProgress(),
                                  const SizedBox(
                                    height: AppDimensions.paddingMedium,
                                  ),
                                ],
                              ],

                              if (_ageGateCompleted && !_isMinor) ...[
                                if (_adultStep == 2) ...[
                                  Expanded(child: _buildAdultStepContent()),
                                ] else ...[
                                  _buildAdultStepContent(),
                                ],
                                SizedBox(
                                  height: _adultStep == 2
                                      ? AppDimensions.paddingSmall
                                      : AppDimensions.paddingLarge,
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: _termsAgreed,
                                  builder: (context, _, child) {
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: _buildAdultBackButton(),
                                        ),
                                        const SizedBox(
                                          width: AppDimensions.paddingSmall,
                                        ),
                                        Expanded(
                                          child: ResqPillButton(
                                            label: _adultPrimaryLabel,
                                            loading: _loading,
                                            onPressed:
                                                (_loading ||
                                                    !_adultPrimaryEnabled)
                                                ? null
                                                : _nextAdultStepOrSubmit,
                                            height: 48,
                                            radius: 30,
                                            backgroundColor:
                                                AppTheme.appOffYellow,
                                            shadowColor: AppTheme.appBlack
                                                .withValues(alpha: 0.1),
                                            shadowBlurRadius: 8,
                                            shadowOffset: const Offset(0, 2),
                                            textStyle: AppTextStyles.authButton,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],

                              if (_ageGateCompleted && _isMinor) ...[
                                if (_minorStep == 4) ...[
                                  Expanded(child: _buildMinorStepContent()),
                                ] else ...[
                                  _buildMinorStepContent(),
                                ],
                                SizedBox(
                                  height: _minorStep == 4
                                      ? AppDimensions.paddingSmall
                                      : AppDimensions.paddingLarge,
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: _termsAgreed,
                                  builder: (context, _, child) {
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: _buildMinorBackButton(),
                                        ),
                                        const SizedBox(
                                          width: AppDimensions.paddingSmall,
                                        ),
                                        Expanded(
                                          child: ResqPillButton(
                                            label: _minorPrimaryLabel,
                                            loading: _loading,
                                            onPressed:
                                                (_loading ||
                                                    !_minorPrimaryEnabled)
                                                ? null
                                                : _nextMinorStepOrSubmit,
                                            height: 48,
                                            radius: 30,
                                            backgroundColor:
                                                AppTheme.appOffYellow,
                                            shadowColor: AppTheme.appBlack
                                                .withValues(alpha: 0.1),
                                            shadowBlurRadius: 8,
                                            shadowOffset: const Offset(0, 2),
                                            textStyle: AppTextStyles.authButton,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );

                  if (_isTermsStepActive) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: formContent,
                    );
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(child: formContent),
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
