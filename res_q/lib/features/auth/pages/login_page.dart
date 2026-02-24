import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../semi_admin/pages/semi_admin_main_page.dart';
import '../../home/pages/home_page.dart';
import '../../../common/services/user_session.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/phone_lookup_service.dart';
import '../../../common/utils/security_hash.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const bool _enableSemiAdminBootstrap = false;
  static const String _semiAdminBootstrapDoneKey = 'semi_admin_bootstrap_done';

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _initializing = true;
  bool _startupArgsApplied = false;
  bool _requiresOtpForApprovedLogin = true;
  final TextEditingController _pinCtl = TextEditingController();
  final TextEditingController _phoneCtl = TextEditingController();
  bool _showPinSuccess = false;
  bool _showPinError = false;
  String _pinErrorMessage = '';
  bool _showPhoneError = false;
  String _phoneErrorMessage = '';
  bool _isPendingApprovalPhone = false;
  bool _isBanDialogVisible = false;
  bool _isPendingDialogVisible = false;
  bool _showSavedPhoneCard = false;
  bool _isPhoneVerifiedForPin = false;

  // Shake animation
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Biometrics
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _canUseBiometrics = false;
  bool _biometricsEnabled = false;
  String? _biometricsPhone;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhoneLookupService _phoneLookupService = PhoneLookupService.instance;
  final TrustedDeviceService _trustedDeviceService =
      TrustedDeviceService.instance;

  bool get _isPinUnlocked => _isPhoneVerifiedForPin;

  bool _isPinMatch(Map<String, dynamic> userData, String pin) {
    final storedPinHash = userData['pin_hash']?.toString();
    if (storedPinHash != null && storedPinHash.isNotEmpty) {
      if (storedPinHash == SecurityHash.sha256Hex(pin)) {
        return true;
      }
    }

    final storedPin = userData['pin']?.toString();
    if (storedPin != null && storedPin == pin) {
      return true;
    }

    return false;
  }

  bool _isLikelyEncryptedField(Map<String, dynamic> userData, String field) {
    final rawValue = userData[field];
    if (rawValue is! String) {
      return false;
    }

    final value = rawValue.trim();
    if (value.isEmpty) {
      return false;
    }

    final mirroredCipher = userData['${field}_cipher'];
    if (mirroredCipher is String && mirroredCipher.trim() == value) {
      return true;
    }

    if (userData['${field}_encrypted'] == true) {
      final looksBase64 = RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(value);
      return looksBase64 && value.length >= 40 && !value.contains(' ');
    }

    return false;
  }

  String _readReadableField(
    Map<String, dynamic> userData,
    String field, {
    List<String> fallbacks = const [],
  }) {
    final rawValue = userData[field];
    if (rawValue is String) {
      final value = rawValue.trim();
      if (value.isNotEmpty && !_isLikelyEncryptedField(userData, field)) {
        return value;
      }
    }

    for (final fallbackField in fallbacks) {
      final fallbackValue = userData[fallbackField];
      if (fallbackValue is String && fallbackValue.trim().isNotEmpty) {
        return fallbackValue.trim();
      }
    }

    return '';
  }

  Map<String, dynamic> _buildSessionUserData({
    required DocumentSnapshot<Map<String, dynamic>> userDoc,
    required String contactNumber,
  }) {
    final userData = <String, dynamic>{
      ...?userDoc.data(),
      'docId': userDoc.id,
      'contactNumber': contactNumber,
    };

    final fullName = _readReadableField(
      userData,
      'fullName',
      fallbacks: const ['displayName'],
    );
    final email = _readReadableField(userData, 'email');
    final address = _readReadableField(userData, 'address');

    if (fullName.isNotEmpty) {
      userData['fullName'] = fullName;
    } else {
      userData.remove('fullName');
    }
    if (email.isNotEmpty) {
      userData['email'] = email;
    } else {
      userData.remove('email');
    }
    if (address.isNotEmpty) {
      userData['address'] = address;
    } else {
      userData.remove('address');
    }

    return userData;
  }

  Future<void> _saveApprovedLoginState(String phoneDigits) async {
    await RegistrationPrefs.savePhoneNumber(phoneDigits);
    await RegistrationPrefs.setApprovedLoginCompleted(true);
  }

  Future<void> _recordSuccessfulApprovedLogin({
    required String phoneDigits,
    String? approvedUserDocId,
  }) async {
    try {
      await _saveApprovedLoginState(phoneDigits);
      await RegistrationPrefs.saveLastActivityNow();
      await _trustedDeviceService.markTrusted('+63$phoneDigits');
      if (approvedUserDocId != null && approvedUserDocId.isNotEmpty) {
        await _firestore
            .collection('approved_users')
            .doc(approvedUserDocId)
            .set({
              'lastLoginTimestamp': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed to persist trusted login metadata: $e');
    }
  }

  void _syncNotificationUserId(Map<String, dynamic> userData) {
    final phoneNumber =
        (userData['contactNumber'] ?? userData['phoneNumber'])
            ?.toString()
            .replaceAll(RegExp(r'[^0-9]'), '') ??
        '';
    final fallbackId =
        (userData['id'] ?? userData['docId'])?.toString().trim() ?? '';
    final resolvedUserId = phoneNumber.isNotEmpty ? phoneNumber : fallbackId;

    if (resolvedUserId.isEmpty) {
      debugPrint('No notification userId found in userData');
      debugPrint('Available fields: ${userData.keys.toList()}');
      return;
    }

    UserSession.setUserId(resolvedUserId);
    NotificationService().setUserId(resolvedUserId);
    if (phoneNumber.isNotEmpty) {
      debugPrint('UserSession userId set to phone number: $resolvedUserId');
      return;
    }
    debugPrint(
      'UserSession userId set to fallback document id: $resolvedUserId',
    );
  }

  Future<void> _updateSemiAdminPresence({
    required Map<String, dynamic> semiAdminData,
    required bool isLoggedIn,
  }) async {
    try {
      final docId =
          (semiAdminData['id'] ?? semiAdminData['contactNumber'])
              ?.toString()
              .trim() ??
          '';
      if (docId.isEmpty) return;

      final payload = <String, dynamic>{
        'isLoggedIn': isLoggedIn,
        'status': isLoggedIn ? 'available' : 'offline',
        'isAvailable': isLoggedIn,
        'lastSeenAt': FieldValue.serverTimestamp(),
      };

      if (isLoggedIn) {
        payload['lastLoginAt'] = FieldValue.serverTimestamp();
        payload['sessionStartedAt'] = FieldValue.serverTimestamp();
      } else {
        payload['sessionStartedAt'] = FieldValue.delete();
      }

      await _firestore
          .collection('semi_admins')
          .doc(docId)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update semi-admin presence: $e');
    }
  }

  Future<void> _ensureFirebaseSession() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        return;
      }
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      debugPrint(
        'Firebase anonymous sign-in ready: ${userCredential.user?.uid}',
      );
    } catch (authError) {
      debugPrint('Firebase anonymous sign-in failed: $authError');
    }
  }

  @override
  void initState() {
    super.initState();
    _initShakeAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Keep startup responsive: defer non-critical startup work until
      // after the first frame and run it in the background.
      unawaited(_initialize());
      unawaited(_checkBiometrics());
    });
  }

  void _initShakeAnimation() {
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  Future<void> _checkBiometrics() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (mounted) {
        setState(() {
          _canUseBiometrics = canAuthenticate && availableBiometrics.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('Biometrics check error: $e');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    final phoneInput = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    if (phoneInput.isEmpty || phoneInput.length != 10) {
      _showError('Please enter your phone number first');
      return;
    }

    // Keep last used phone for faster next login.
    await RegistrationPrefs.savePhoneNumber(phoneInput);

    if (!_canUseBiometrics) {
      _showError('Biometrics not available on this device. Please use PIN.');
      return;
    }

    // Check if biometrics is enabled for this phone number
    final phone = '+63$phoneInput';

    // First check local cache, then Firestore if needed
    if (!_biometricsEnabled || _biometricsPhone != phone) {
      // Try loading from Firestore
      await _loadBiometricsFromFirestore(phone);
    }

    // Re-check after potential Firestore load
    if (!_biometricsEnabled || _biometricsPhone != phone) {
      _showError(
        'Biometric login not enabled for this account. Please use PIN or enable biometrics in settings.',
      );
      return;
    }

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to login to RES-Q',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        setState(() => _loading = true);
        await _verifyWithBiometrics();
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: $e');
      _showError(_biometricErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected biometric auth error: $e');
      _showError('Biometric authentication failed');
    }
  }

  String _biometricErrorMessage(PlatformException error) {
    final code = error.code.toLowerCase();
    final details = '${error.message ?? ''} ${error.details ?? ''}'
        .toLowerCase();
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      if (code.contains('notenrolled')) {
        return 'No Face ID/Touch ID is enrolled. Set it up first in iOS Settings.';
      }
      if (code.contains('passcodenotset')) {
        return 'Set a device passcode first, then try Face ID/Touch ID again.';
      }
      if (code.contains('lockedout')) {
        return 'Biometrics is locked. Unlock the device with passcode and retry.';
      }
      if (code.contains('notavailable') ||
          code.contains('denied') ||
          details.contains('permission')) {
        return 'Face ID permission is disabled. Enable it for RES-Q in iOS Settings.';
      }
    }

    return 'Biometric authentication failed';
  }

  Future<void> _verifyWithBiometrics() async {
    final phoneInput = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneInput';

    try {
      final accountQueries = await Future.wait<dynamic>([
        _firestore
            .collection('semi_admins')
            .where('contactNumber', isEqualTo: phone)
            .limit(1)
            .get(),
        _phoneLookupService.getFirstApprovedUserDoc(phone),
      ]);
      final semiAdminQuery =
          accountQueries[0] as QuerySnapshot<Map<String, dynamic>>;
      final userDoc =
          accountQueries[1] as QueryDocumentSnapshot<Map<String, dynamic>>?;

      if (semiAdminQuery.docs.isNotEmpty) {
        debugPrint('Ã¢Å“â€¦ Semi-admin biometric login successful!');
        await _ensureFirebaseSession();
        // Persist phone locally for faster next login.
        await _recordSuccessfulApprovedLogin(phoneDigits: phoneInput);
        // Set user session data for semi-admin
        final semiAdminData = semiAdminQuery.docs.first.data();
        final sessionData = {
          ...semiAdminData,
          'id': semiAdminQuery.docs.first.id,
        };
        UserSession.setUserData(sessionData);
        _syncNotificationUserId(sessionData);
        await _updateSemiAdminPresence(
          semiAdminData: {...semiAdminData, 'id': semiAdminQuery.docs.first.id},
          isLoggedIn: true,
        );
        setState(() => _loading = false);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainScreen()),
          );
        }
        return;
      }

      if (userDoc == null) {
        final accountStatus = await _phoneLookupService.lookupAccountStatus(
          phone,
        );
        setState(() => _loading = false);
        if (accountStatus.isBannedAccount) {
          await _showBannedAccountDialog(
            isPermanentBan: accountStatus.isPermanentBan,
            bannedUntil: accountStatus.bannedUntil,
            banReasons: accountStatus.banReasons,
          );
        } else if (accountStatus.isPendingAccount) {
          await _showPendingApprovalDialog();
        } else {
          _showError('No account found with this phone number.');
        }
        return;
      }

      final userData = _buildSessionUserData(
        userDoc: userDoc,
        contactNumber: phone,
      );
      final accountStatus = (userData['accountStatus'] as String?)
          ?.trim()
          .toLowerCase();
      final isBanned = _isBannedStatus(accountStatus);
      if (isBanned) {
        setState(() => _loading = false);
        await _showBannedAccountDialog(
          isPermanentBan: _isPermanentBanData(userData, isBanned),
          bannedUntil: _parseBanUntil(userData['bannedUntil']),
          banReasons: _parseBanReasons(userData['banReasons']),
        );
        return;
      }

      final isApprovedAccount =
          accountStatus == 'approved' || userData['isApproved'] == true;
      if (!isApprovedAccount) {
        setState(() => _loading = false);
        await _showPendingApprovalDialog();
        return;
      }

      // Sign in to Firebase Auth anonymously
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          'Ã¢Å“â€¦ Firebase Anonymous Sign-In successful: ${userCredential.user?.uid}',
        );
      } catch (authError) {
        debugPrint(
          'Ã¢Å¡Â Ã¯Â¸Â Firebase Anonymous Sign-In failed: $authError',
        );
      }

      // Login successful
      // Persist phone locally for faster next login.
      await _recordSuccessfulApprovedLogin(
        phoneDigits: phoneInput,
        approvedUserDocId: userDoc.id,
      );
      UserSession.setUserData(userData);
      _syncNotificationUserId(userData);
      _finishAutofillContext(); // Trigger "Save to Google" prompt
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const MainPage(showWelcomeBackOnLoad: true),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Error: $e');
    }
  }

  void _finishAutofillContext() {
    try {
      TextInput.finishAutofillContext();
    } catch (e) {
      debugPrint('Failed to finish autofill: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      AppSnackBar.show(context, message, type: AppSnackBarType.error);
    }
  }

  void _onPhoneChanged(String _) {
    final shouldRebuild =
        _pinCtl.text.isNotEmpty ||
        _showPinError ||
        _pinErrorMessage.isNotEmpty ||
        _isPhoneVerifiedForPin ||
        _isPendingApprovalPhone ||
        _showPhoneError ||
        _phoneErrorMessage.isNotEmpty;

    if (shouldRebuild) {
      setState(() {
        _showPinError = false;
        _pinErrorMessage = '';
        _pinCtl.clear();
        _isPhoneVerifiedForPin = false;
        _isPendingApprovalPhone = false;
        _showPhoneError = false;
        _phoneErrorMessage = '';
      });
      _requiresOtpForApprovedLogin = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (!_startupArgsApplied) {
      _startupArgsApplied = true;
      final trustedPhone = args?['trustedPhone'] as String?;
      final directPin = args?['directPin'] == true;
      final trustedDigits = _extractLocalPhoneDigits(trustedPhone);
      if (trustedDigits.length == 10) {
        setState(() {
          _phoneCtl.text = _formatPhoneNumber(trustedDigits);
          _showSavedPhoneCard = true;
        });
      }

      if (directPin && trustedDigits.length == 10) {
        setState(() {
          _isPhoneVerifiedForPin = true;
          _showSavedPhoneCard = true;
          _showPhoneError = false;
          _phoneErrorMessage = '';
        });
        _requiresOtpForApprovedLogin = false;
      } else {
        _requiresOtpForApprovedLogin = true;
      }
    }

    if (args != null && args['showPinSuccess'] == true) {
      setState(() => _showPinSuccess = true);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showPinSuccess = false);
        }
      });
    }
  }

  String _extractLocalPhoneDigits(String? rawPhone) {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      return '';
    }

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

  Future<void> _initialize() async {
    await _loadSavedData();
    if (mounted) {
      setState(() => _initializing = false);
    }
    if (kDebugMode && _enableSemiAdminBootstrap) {
      // Keep maintenance work out of normal app startup to reduce APK jank.
      unawaited(_seedAndBackfillSemiAdminPresence());
    }
  }

  Future<void> _seedAndBackfillSemiAdminPresence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyBootstrapped =
          prefs.getBool(_semiAdminBootstrapDoneKey) ?? false;
      if (alreadyBootstrapped) return;

      await _seedSemiAdminsIfEmpty();
      await _backfillSemiAdminPresenceDefaults();
      await prefs.setBool(_semiAdminBootstrapDoneKey, true);
    } catch (e) {
      debugPrint('Failed semi-admin bootstrap: $e');
    }
  }

  Future<void> _loadSavedData() async {
    try {
      // Load biometrics preferences from local cache first.
      final prefs = await SharedPreferences.getInstance();
      _biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;
      final cachedBiometricsPhone = _normalizeBiometricsPhone(
        prefs.getString('biometrics_phone'),
      );
      _biometricsPhone = cachedBiometricsPhone.isEmpty
          ? null
          : cachedBiometricsPhone;
      if (_biometricsEnabled && _biometricsPhone == null) {
        _biometricsEnabled = false;
        await prefs.setBool('biometrics_enabled', false);
      }
      if (_biometricsPhone != null &&
          _biometricsPhone != prefs.getString('biometrics_phone')) {
        await prefs.setString('biometrics_phone', _biometricsPhone!);
      }
      debugPrint(
        'Biometrics enabled: $_biometricsEnabled, phone: $_biometricsPhone',
      );

      final approvedLoginCompleted =
          await RegistrationPrefs.isApprovedLoginCompleted();

      // Load saved phone number for convenience
      final trustedPhone = await _trustedDeviceService.getTrustedPhone();
      final trustedPhoneDigits = trustedPhone?.replaceAll(RegExp(r'\D'), '');
      final hasTrustedPhone =
          trustedPhoneDigits != null && trustedPhoneDigits.length >= 10;
      final fallbackSavedPhone = await RegistrationPrefs.getPhoneNumber();
      final savedPhone = hasTrustedPhone
          ? trustedPhoneDigits.substring(trustedPhoneDigits.length - 10)
          : fallbackSavedPhone;
      if (savedPhone != null && savedPhone.isNotEmpty && mounted) {
        setState(() {
          _phoneCtl.text = _formatPhoneNumber(savedPhone);
          _showSavedPhoneCard = approvedLoginCompleted || hasTrustedPhone;
          _isPhoneVerifiedForPin = hasTrustedPhone;
          _isPendingApprovalPhone = false;
          _showPhoneError = false;
          _phoneErrorMessage = '';
        });
        if (hasTrustedPhone) {
          _requiresOtpForApprovedLogin = false;
        }
        // Sync biometrics from Firestore in background.
        unawaited(
          _loadBiometricsFromFirestore(
            '+63${savedPhone.replaceAll(RegExp(r'\D'), '')}',
          ),
        );
      } else if (mounted) {
        setState(() {
          _showSavedPhoneCard = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved data: $e');
    }
  }

  String _normalizeBiometricsPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+63$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+63${digits.substring(1)}';
    }
    if (digits.length == 12 && digits.startsWith('63')) return '+$digits';
    if (phone.trim().startsWith('+')) {
      return '+${digits.isNotEmpty ? digits : phone.trim().substring(1)}';
    }
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<void> _loadBiometricsFromFirestore(String phone) async {
    try {
      final cleanPhone = _normalizeBiometricsPhone(phone);
      if (cleanPhone.isEmpty) return;
      final doc = await _firestore
          .collection('userPreferences')
          .doc(cleanPhone)
          .get();

      if (!doc.exists) {
        return;
      }

      final data = doc.data();
      final firestoreBiometricsEnabled =
          data?['biometricsEnabled'] as bool? ?? false;

      // Always sync local cache from Firestore, including "false",
      // so disable/enable changes persist correctly.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', firestoreBiometricsEnabled);
      await prefs.setString('biometrics_phone', cleanPhone);

      if (mounted) {
        setState(() {
          _biometricsEnabled = firestoreBiometricsEnabled;
          _biometricsPhone = cleanPhone;
        });
      } else {
        _biometricsEnabled = firestoreBiometricsEnabled;
        _biometricsPhone = cleanPhone;
      }

      debugPrint(
        'Loaded biometrics preference from Firestore: '
        '${firestoreBiometricsEnabled ? 'enabled' : 'disabled'} for $cleanPhone',
      );
    } catch (e) {
      debugPrint('Error loading biometrics from Firestore: $e');
    }
  }

  @override
  void dispose() {
    _pinCtl.dispose();
    _phoneCtl.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.reset();
    _shakeController.forward();
  }

  void _resetPinWithError(String message) {
    setState(() {
      _pinCtl.clear();
      _showPinError = true;
      _pinErrorMessage = message;
    });
    _triggerShake();

    // Auto-hide error after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showPinError = false);
      }
    });
  }

  Future<bool> _startOtpChallenge(
    String phone, {
    String flowType = 'login',
  }) async {
    final otpCompleter = Completer<bool>();

    try {
      if (!kIsWeb) {
        await _auth.setSettings(appVerificationDisabledForTesting: kDebugMode);
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
          } catch (_) {}
          if (!otpCompleter.isCompleted) {
            otpCompleter.complete(true);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            AppSnackBar.show(
              context,
              e.message ?? 'Phone verification failed',
              type: AppSnackBarType.error,
            );
          }
          if (!otpCompleter.isCompleted) {
            otpCompleter.complete(false);
          }
        },
        codeSent: (String verificationId, int? resendToken) async {
          if (!mounted) {
            if (!otpCompleter.isCompleted) {
              otpCompleter.complete(false);
            }
            return;
          }

          final result = await Navigator.pushNamed(
            context,
            '/otp',
            arguments: {
              'flowType': flowType,
              'verificationId': verificationId,
              'phoneNumber': phone,
            },
          );
          final isVerified = result == true;
          if (!otpCompleter.isCompleted) {
            otpCompleter.complete(isVerified);
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );

      final verified = await otpCompleter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
      return verified;
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Failed to send OTP. Please try again.',
          type: AppSnackBarType.error,
        );
      }
      return false;
    }
  }

  Future<void> _submit() async {
    final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');

    if (phoneDigits.isEmpty) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Enter phone number';
        _pinCtl.clear();
        _showPinError = false;
        _pinErrorMessage = '';
      });
      return;
    }

    if (phoneDigits.length != 10) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Enter 10 digits';
        _pinCtl.clear();
        _showPinError = false;
        _pinErrorMessage = '';
      });
      return;
    }

    if (!phoneDigits.startsWith('9')) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Must start with 9';
        _pinCtl.clear();
        _showPinError = false;
        _pinErrorMessage = '';
      });
      return;
    }

    if (_initializing) {
      AppSnackBar.show(
        context,
        'Initializing... Please wait a moment.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final phone = '+63$phoneDigits';
    if (_isPinUnlocked && _pinCtl.text.trim().length == 4) {
      setState(() {
        _showPhoneError = false;
        _loading = true;
      });
      await _verifyPinOnly();
      return;
    }

    setState(() {
      _loading = true;
      _showPhoneError = false;
      _phoneErrorMessage = '';
    });

    try {
      final status = await _phoneLookupService.lookupAccountStatus(
        phone,
        useCache: false,
      );
      if (!mounted) return;

      if (status.isBannedAccount) {
        setState(() {
          _loading = false;
          _isPhoneVerifiedForPin = false;
          _isPendingApprovalPhone = false;
        });
        await _showBannedAccountDialog(
          isPermanentBan: status.isPermanentBan,
          bannedUntil: status.bannedUntil,
          banReasons: status.banReasons,
        );
        return;
      }

      if (status.isPendingAccount) {
        setState(() {
          _loading = false;
          _isPhoneVerifiedForPin = false;
          _isPendingApprovalPhone = true;
          _pinCtl.clear();
          _showPinError = false;
          _pinErrorMessage = '';
        });
        await _showPendingApprovalDialog();
        return;
      }

      if (!status.hasAnyAccount) {
        setState(() {
          _loading = false;
          _isPhoneVerifiedForPin = false;
          _isPendingApprovalPhone = false;
          _showPhoneError = false;
          _phoneErrorMessage = '';
          _pinCtl.clear();
          _showPinError = false;
          _pinErrorMessage = '';
        });

        await _startOtpChallenge(phone, flowType: 'registration-entry');
        if (!mounted) return;
        return;
      }

      if (_requiresOtpForApprovedLogin) {
        final otpVerified = await _startOtpChallenge(phone, flowType: 'login');
        if (!mounted) return;
        if (!otpVerified) {
          setState(() => _loading = false);
          return;
        }
      }

      await RegistrationPrefs.savePhoneNumber(phoneDigits);
      if (!mounted) return;

      setState(() {
        _loading = false;
        _isPhoneVerifiedForPin = true;
        _isPendingApprovalPhone = false;
        _showPhoneError = false;
        _phoneErrorMessage = '';
        _showSavedPhoneCard = true;
      });
      _requiresOtpForApprovedLogin = false;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _showPhoneError = true;
        _phoneErrorMessage = 'Unable to check account. Please try again.';
        _isPhoneVerifiedForPin = false;
      });
      AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
    }
  }

  Future<void> _verifyPinOnly() async {
    final pin = _pinCtl.text.trim();
    final phoneInput = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');

    // Validate phone number
    if (phoneInput.isEmpty) {
      setState(() => _loading = false);
      _resetPinWithError('Please enter your phone number');
      return;
    }

    if (phoneInput.length != 10) {
      setState(() => _loading = false);
      _resetPinWithError('Phone number must be 10 digits');
      return;
    }

    if (pin.length != 4) {
      setState(() => _loading = false);
      _resetPinWithError('PIN must be exactly 4 digits');
      return;
    }

    // Format phone number to match Firebase format
    final phone = '+63$phoneInput';

    try {
      final authQueries = await Future.wait<dynamic>([
        _firestore
            .collection('semi_admins')
            .where('contactNumber', isEqualTo: phone)
            .where('pin', isEqualTo: pin)
            .limit(1)
            .get(),
        _phoneLookupService.getFirstApprovedUserDoc(phone),
      ]);
      final semiAdminQuery =
          authQueries[0] as QuerySnapshot<Map<String, dynamic>>;
      final userDoc =
          authQueries[1] as QueryDocumentSnapshot<Map<String, dynamic>>?;

      if (semiAdminQuery.docs.isNotEmpty) {
        debugPrint('Ã¢Å“â€¦ Semi-admin login successful via PIN!');
        await _ensureFirebaseSession();
        // Persist phone locally for faster next login.
        await _recordSuccessfulApprovedLogin(phoneDigits: phoneInput);
        // Set user session data for semi-admin
        final semiAdminData = semiAdminQuery.docs.first.data();
        final sessionData = {
          ...semiAdminData,
          'id': semiAdminQuery.docs.first.id,
        };
        UserSession.setUserData(sessionData);
        _syncNotificationUserId(sessionData);
        await _updateSemiAdminPresence(
          semiAdminData: {...semiAdminData, 'id': semiAdminQuery.docs.first.id},
          isLoggedIn: true,
        );
        setState(() => _loading = false);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainScreen()),
          );
        }
        return;
      }

      if (userDoc == null) {
        setState(() {
          _loading = false;
          _pinCtl.clear();
          _showPinError = false;
          _pinErrorMessage = '';
        });
        final validation = await _phoneLookupService.lookupAccountStatus(
          phone,
          useCache: false,
        );
        if (validation.isBannedAccount) {
          await _showBannedAccountDialog(
            isPermanentBan: validation.isPermanentBan,
            bannedUntil: validation.bannedUntil,
            banReasons: validation.banReasons,
          );
          return;
        }
        if (!validation.hasAnyAccount) {
          _resetPinWithError('No account found with this phone number.');
          return;
        }
        if (validation.isPendingAccount) {
          await _showPendingApprovalDialog();
          return;
        }
        _resetPinWithError('Wrong PIN');
        return;
      }

      final userData = _buildSessionUserData(
        userDoc: userDoc,
        contactNumber: phone,
      );
      final isBanned = _isBannedStatus(userData['accountStatus']);
      if (isBanned) {
        setState(() {
          _loading = false;
          _pinCtl.clear();
          _showPinError = false;
          _pinErrorMessage = '';
        });
        await _showBannedAccountDialog(
          isPermanentBan: _isPermanentBanData(userData, isBanned),
          bannedUntil: _parseBanUntil(userData['bannedUntil']),
          banReasons: _parseBanReasons(userData['banReasons']),
        );
        return;
      }

      if (!_isPinMatch(userData, pin)) {
        setState(() {
          _loading = false;
          _pinCtl.clear();
          _showPinError = false;
          _pinErrorMessage = '';
        });
        _resetPinWithError('Wrong PIN');
        return;
      }

      final accountStatus = (userData['accountStatus'] as String?)
          ?.trim()
          .toLowerCase();

      final isApprovedAccount =
          accountStatus == 'approved' || userData['isApproved'] == true;
      if (!isApprovedAccount) {
        setState(() => _loading = false);
        await _showPendingApprovalDialog();
        return;
      }

      // Sign in to Firebase Auth anonymously
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          'Ã¢Å“â€¦ Firebase Anonymous Sign-In successful: ${userCredential.user?.uid}',
        );
      } catch (authError) {
        debugPrint(
          'Ã¢Å¡Â Ã¯Â¸Â Firebase Anonymous Sign-In failed: $authError',
        );
      }

      // Login successful
      // Persist phone locally for faster next login.
      await _recordSuccessfulApprovedLogin(
        phoneDigits: phoneInput,
        approvedUserDocId: userDoc.id,
      );
      UserSession.setUserData(userData);
      _syncNotificationUserId(userData);
      _finishAutofillContext(); // Trigger "Save to Google" prompt
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const MainPage(showWelcomeBackOnLoad: true),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      _resetPinWithError('Error occurred. Please try again.');
      if (mounted) {
        AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
      }
    }
  }

  /// Seed 5 semi-admin users if collection is empty. Runs on init.
  Future<void> _seedSemiAdminsIfEmpty() async {
    debugPrint('Ã°Å¸â€Â Checking if semi_admins collection exists...');
    try {
      final existing = await _firestore
          .collection('semi_admins')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint(
          'Ã¢Å“â€œ semi_admins collection already exists. Skipping seed.',
        );
        return;
      }

      debugPrint('Ã°Å¸â€œÂ semi_admins collection empty. Starting seed...');

      final seedUsers = [
        {
          'fullName': 'Semi Admin One',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639111111111',
          'pin': '1111',
          'isLoggedIn': false,
          'status': 'offline',
          'isAvailable': false,
        },
        {
          'fullName': 'Semi Admin Two',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639222222222',
          'pin': '2222',
          'isLoggedIn': false,
          'status': 'offline',
          'isAvailable': false,
        },
        {
          'fullName': 'Semi Admin Three',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639333333333',
          'pin': '3333',
          'isLoggedIn': false,
          'status': 'offline',
          'isAvailable': false,
        },
        {
          'fullName': 'Semi Admin Four',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639444444444',
          'pin': '4444',
          'isLoggedIn': false,
          'status': 'offline',
          'isAvailable': false,
        },
        {
          'fullName': 'Semi Admin Five',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639555555555',
          'pin': '5555',
          'isLoggedIn': false,
          'status': 'offline',
          'isAvailable': false,
        },
      ];

      final batch = _firestore.batch();
      for (final user in seedUsers) {
        final ref = _firestore
            .collection('semi_admins')
            .doc(user['contactNumber'] as String);
        batch.set(ref, user);
      }
      await batch.commit();
      debugPrint(
        'Ã¢Å“â€¦ Successfully seeded 5 semi-admin users to Firestore!',
      );
    } catch (e) {
      debugPrint('Ã¢ÂÅ’ Failed to seed semi_admins: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _backfillSemiAdminPresenceDefaults() async {
    try {
      final snapshot = await _firestore.collection('semi_admins').get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      var updateCount = 0;

      for (final snapshotDoc in snapshot.docs) {
        final data = snapshotDoc.data();
        final patch = <String, dynamic>{};

        final hasIsLoggedIn = data['isLoggedIn'] is bool;
        final isLoggedIn = hasIsLoggedIn ? data['isLoggedIn'] as bool : false;
        final hasIsAvailable = data['isAvailable'] is bool;
        final statusRaw = (data['status'] as String? ?? '')
            .trim()
            .toLowerCase();

        if (!hasIsLoggedIn) {
          patch['isLoggedIn'] = false;
        }
        if (!hasIsAvailable) {
          patch['isAvailable'] = false;
        }

        if (!isLoggedIn) {
          if (statusRaw != 'offline') {
            patch['status'] = 'offline';
          }
          if (data['isAvailable'] != false) {
            patch['isAvailable'] = false;
          }
        } else if (statusRaw != 'busy' && statusRaw != 'available') {
          patch['status'] = 'available';
        }

        if (patch.isEmpty) {
          continue;
        }

        patch['lastSeenAt'] = FieldValue.serverTimestamp();
        batch.set(snapshotDoc.reference, patch, SetOptions(merge: true));
        updateCount++;
      }

      if (updateCount > 0) {
        await batch.commit();
        debugPrint(
          'Backfilled semi-admin presence defaults for $updateCount responders',
        );
      }
    } catch (e) {
      debugPrint('Failed to backfill semi-admin presence defaults: $e');
    }
  }

  bool _isBannedStatus(dynamic rawStatus) {
    return rawStatus is String && rawStatus.trim().toUpperCase() == 'BANNED';
  }

  bool _isPermanentBanData(Map<String, dynamic> data, bool isBanned) {
    if (!isBanned) {
      return false;
    }
    if (data['isPermanent'] == true) {
      return true;
    }
    final banType = (data['banType'] ?? '').toString().trim().toLowerCase();
    if (banType == 'permanent') {
      return true;
    }
    return data['bannedUntil'] == null;
  }

  DateTime? _parseBanUntil(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map<String, dynamic>) {
      final seconds = value['seconds'] ?? value['_seconds'];
      final nanoseconds = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;
      if (seconds is int) {
        final nanos = nanoseconds is int
            ? nanoseconds
            : (nanoseconds is num ? nanoseconds.toInt() : 0);
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000) + (nanos ~/ 1000000),
        );
      }
    }
    return null;
  }

  List<String> _parseBanReasons(dynamic rawReasons) {
    if (rawReasons is! List) return const <String>[];
    return rawReasons
        .map((reason) => reason.toString().trim())
        .where((reason) => reason.isNotEmpty)
        .toList(growable: false);
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
    if (!mounted || _isBanDialogVisible) return;

    _isBanDialogVisible = true;
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

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                    color: appBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: appBlue, width: 2),
                  ),
                  child: const Icon(Icons.block, size: 48, color: appBlue),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: appBlue,
                    letterSpacing: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: appBlack.withValues(alpha: 0.85),
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
                      color: appBlack,
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
                      color: appBlack.withValues(alpha: 0.8),
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
                      backgroundColor: appBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBanDialogVisible = false;
        });
      } else {
        _isBanDialogVisible = false;
      }
    }
  }

  Future<void> _showPendingApprovalDialog() async {
    if (!mounted || _isPendingDialogVisible) return;

    _isPendingDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                    color: appBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: appBlue, width: 2),
                  ),
                  child: Icon(Icons.hourglass_top, size: 48, color: appBlue),
                ),
                const SizedBox(height: 16),
                Text(
                  'ACCOUNT PENDING',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: appBlue,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Awaiting Admin Approval',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: appBlack,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account is currently pending admin approval. This usually takes up to 48 hours.\n\nYou will receive a text message once approved and can then log in with your PIN.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: appBlack.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'GOT IT',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 16,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _isPendingDialogVisible = false;
    }
  }

  Widget _logo() {
    return SvgPicture.asset('assets/icons/logo/RES-Q_LOGO.svg', height: 40);
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    if (!_isPinUnlocked) {
      final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
      if (_isPendingApprovalPhone && phoneDigits.length == 10) {
        setState(() {
          _showPhoneError = false;
          _phoneErrorMessage = '';
          _showPinError = false;
          _pinErrorMessage = '';
          _pinCtl.clear();
        });
        unawaited(_showPendingApprovalDialog());
        return;
      }
      final message = phoneDigits.isEmpty
          ? 'Please enter your phone number first.'
          : phoneDigits.length < 10
          ? 'Please complete your 10-digit phone number first.'
          : (_phoneErrorMessage.isNotEmpty
                ? _phoneErrorMessage
                : 'Verifying phone number. Please wait.');
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = message;
        _showPinError = false;
        _pinErrorMessage = '';
        _pinCtl.clear();
      });
      return;
    }
    setState(() {
      _showPinError = false; // Clear error when user starts typing
      if (value == PinNumpad.clearKey || value == 'C') {
        _pinCtl.clear();
        return;
      }
      if (value == PinNumpad.backspaceKey || value == '\u232b') {
        if (_pinCtl.text.isNotEmpty) {
          _pinCtl.text = _pinCtl.text.substring(0, _pinCtl.text.length - 1);
        }
        return;
      }
      if (_pinCtl.text.length < 4) {
        _pinCtl.text += value;
        if (_pinCtl.text.length == 4) {
          Future.delayed(const Duration(milliseconds: 200), () {
            _submit();
          });
        }
      }
    });
  }

  // Phone number formatter for PH format (9XX-XXX-XXXX)
  String _formatPhoneNumber(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 3 || i == 6) {
        buffer.write('-');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _formatPhoneWithCountryCode(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '+63';
    return '+63 ${_formatPhoneNumber(digits)}';
  }

  void _enablePhoneFieldEditing() {
    setState(() {
      _showSavedPhoneCard = false;
      _isPhoneVerifiedForPin = false;
      _isPendingApprovalPhone = false;
      _showPhoneError = false;
      _phoneErrorMessage = '';
      _showPinError = false;
      _pinErrorMessage = '';
      _pinCtl.clear();
    });
    _requiresOtpForApprovedLogin = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed logo at top
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  _logo(),
                  const SizedBox(height: 12),
                  Text('LOGIN', style: AppTextStyles.authPageTitle),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Phone Number Field with +63 prefix
                                Text(
                                  'PHONE NUMBER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: appBlack,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (_showSavedPhoneCard)
                                  Container(
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: appOffWhite,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: appBlack.withValues(alpha: 0.3),
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.phone_android,
                                                size: 28,
                                                color: appBlack,
                                              ),
                                              const SizedBox(width: 14),
                                              Text(
                                                _formatPhoneWithCountryCode(
                                                  _phoneCtl.text,
                                                ),
                                                style: const TextStyle(
                                                  fontFamily: 'RobotoCondensed',
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 16,
                                                  color: appBlack,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _enablePhoneFieldEditing,
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: appBlack,
                                          ),
                                          tooltip: 'Change phone number',
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: appOffWhite,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.black,
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Phone icon
                                        const Padding(
                                          padding: EdgeInsets.only(left: 12),
                                          child: Icon(
                                            Icons.phone_outlined,
                                            color: Colors.black,
                                          ),
                                        ),
                                        // +63 prefix
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            '+63',
                                            style: TextStyle(
                                              fontFamily: 'RobotoCondensed',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: appBlack,
                                            ),
                                          ),
                                        ),
                                        // Divider
                                        Container(
                                          width: 1.5,
                                          height: 28,
                                          color: Colors.black,
                                        ),
                                        // Phone input field
                                        Expanded(
                                          child: TextFormField(
                                            controller: _phoneCtl,
                                            textAlign: TextAlign.left,
                                            textAlignVertical:
                                                TextAlignVertical.center,
                                            keyboardType: TextInputType.phone,
                                            autofillHints: const [
                                              AutofillHints.telephoneNumber,
                                            ],
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                10,
                                              ),
                                              TextInputFormatter.withFunction((
                                                oldValue,
                                                newValue,
                                              ) {
                                                return TextEditingValue(
                                                  text: _formatPhoneNumber(
                                                    newValue.text,
                                                  ),
                                                  selection:
                                                      TextSelection.collapsed(
                                                        offset:
                                                            _formatPhoneNumber(
                                                              newValue.text,
                                                            ).length,
                                                      ),
                                                );
                                              }),
                                            ],
                                            style: const TextStyle(
                                              fontFamily: 'RobotoCondensed',
                                              fontWeight: FontWeight.w400,
                                              fontSize: 14,
                                              color: appBlack,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: '912-345-6789',
                                              hintStyle: TextStyle(
                                                fontFamily: 'RobotoCondensed',
                                                fontWeight: FontWeight.w400,
                                                fontSize: 14,
                                                color: appBlack.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                              border: InputBorder.none,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 16,
                                                  ),
                                            ),
                                            onChanged: _onPhoneChanged,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // Show phone error message below phone input, outside the box
                                if (_showPhoneError) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      _phoneErrorMessage,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                if (!_isPinUnlocked) ...[
                                  ResqPillButton(
                                    label: 'CONTINUE',
                                    onPressed: _loading ? null : _submit,
                                    loading: _loading,
                                    backgroundColor: appBlue,
                                    shadowColor: appBlue.withValues(alpha: 0.3),
                                    shadowBlurRadius: 12,
                                    shadowOffset: const Offset(0, 4),
                                    textStyle: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    'ENTER YOUR PIN',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: appBlack,
                                      fontFamily: 'Roboto',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),

                                  // PIN Display (dots) with shake animation
                                  AnimatedBuilder(
                                    animation: _shakeAnimation,
                                    builder: (context, child) {
                                      final offset =
                                          _shakeAnimation.value *
                                          10 *
                                          (1 - _shakeAnimation.value) *
                                          ((_shakeController.value * 8)
                                                          .floor() %
                                                      2 ==
                                                  0
                                              ? 1
                                              : -1);
                                      return Transform.translate(
                                        offset: Offset(offset, 0),
                                        child: child,
                                      );
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(4, (index) {
                                        final hasValue =
                                            _pinCtl.text.length > index;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: hasValue
                                                ? (_showPinError
                                                      ? Colors.red
                                                      : appBlue)
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: _showPinError
                                                  ? Colors.red
                                                  : appBlack,
                                              width: 2,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),

                                  if (_showPinError) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _pinErrorMessage,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  const SizedBox(height: 24),

                                  PinNumpad(
                                    enabled: !_loading,
                                    onKeyTap: _handlePinKey,
                                    actionBackgroundColor: appOffWhite,
                                    textColor: appBlack,
                                    showBiometrics: true,
                                    onBiometricsTap:
                                        _authenticateWithBiometrics,
                                  ),

                                  const SizedBox(height: 20),

                                  if (_showPinSuccess) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00A458),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Pin is good to go! Enter the pin in the pin section.',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  Align(
                                    alignment: Alignment.center,
                                    child: TextButton(
                                      onPressed: () => Navigator.pushNamed(
                                        context,
                                        '/forgot-pin',
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 0),
                                      ),
                                      child: Text(
                                        'Forgot PIN?',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: appBlue,
                                          fontFamily: 'RobotoCondensed',
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
