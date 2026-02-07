import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../home/pages/home_page.dart';
import '../../semi_admin/pages/semi_admin_main_page.dart';
import '../../../common/services/user_session.dart';
import '../../../common/services/registration_prefs.dart';
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
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _initializing = true;
  final TextEditingController _pinCtl = TextEditingController();
  final TextEditingController _phoneCtl = TextEditingController();
  bool _showPinSuccess = false;
  bool _showPinError = false;
  String _pinErrorMessage = '';
  bool _showPhoneError = false;
  String _phoneErrorMessage = '';

  // Shake animation
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Biometrics
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _canUseBiometrics = false;
  bool _biometricsEnabled = false;
  String? _biometricsPhone;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initialize();
    _initShakeAnimation();
    _checkBiometrics();
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
      _showError('Biometric authentication failed');
    }
  }

  Future<void> _verifyWithBiometrics() async {
    final phoneInput = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneInput';

    try {
      // Check semi_admins collection first
      final semiAdminQuery = await _firestore
          .collection('semi_admins')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (semiAdminQuery.docs.isNotEmpty) {
        debugPrint('✅ Semi-admin biometric login successful!');
        // Persist phone locally for faster next login.
        await RegistrationPrefs.savePhoneNumber(phoneInput);
        // Set user session data for semi-admin
        final semiAdminData = semiAdminQuery.docs.first.data();
        UserSession.setUserData({
          ...semiAdminData,
          'id': semiAdminQuery.docs.first.id,
        });
        setState(() => _loading = false);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainPage()),
          );
        }
        return;
      }

      // Check approved_users collection
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() => _loading = false);
        _showError('Phone number not found. Please register first.');
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = {...userDoc.data(), 'docId': userDoc.id};
      final accountStatus = userData['accountStatus'] as String?;

      if (accountStatus != 'approved') {
        setState(() => _loading = false);
        _showPendingApprovalDialog();
        return;
      }

      // Sign in to Firebase Auth anonymously
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          '✅ Firebase Anonymous Sign-In successful: ${userCredential.user?.uid}',
        );
      } catch (authError) {
        debugPrint('⚠️ Firebase Anonymous Sign-In failed: $authError');
      }

      // Login successful
      // Persist phone locally for faster next login.
      await RegistrationPrefs.savePhoneNumber(phoneInput);
      UserSession.setUserData(userData);

      // Use phone number as user ID for easier tracking
      // Note: Firestore uses 'contactNumber' as the field name
      final phoneNumber =
          (userData['contactNumber'] ?? userData['phoneNumber'])
              ?.toString()
              .replaceAll(RegExp(r'[^0-9]'), '') ??
          '';
      if (phoneNumber.isNotEmpty) {
        UserSession.setUserId(phoneNumber);
        debugPrint('✅ UserSession userId set to phone number: $phoneNumber');
      } else {
        debugPrint('⚠️ No phone number found in userData');
        debugPrint('   Available fields: ${userData.keys.toList()}');
      }
      _finishAutofillContext(); // Trigger "Save to Google" prompt
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage()));
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && args['showPinSuccess'] == true) {
      setState(() => _showPinSuccess = true);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showPinSuccess = false);
        }
      });
    }
  }

  Future<void> _initialize() async {
    await _seedSemiAdminsIfEmpty();
    await _loadSavedData();
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _loadSavedData() async {
    try {
      // Load saved phone number for convenience
      final savedPhone = await RegistrationPrefs.getPhoneNumber();
      if (savedPhone != null && savedPhone.isNotEmpty && mounted) {
        setState(() {
          _phoneCtl.text = _formatPhoneNumber(savedPhone);
        });
        // Also load biometrics from Firestore for this phone
        await _loadBiometricsFromFirestore(
          '+63${savedPhone.replaceAll(RegExp(r'\D'), '')}',
        );
      }

      // Load biometrics preferences from local cache
      final prefs = await SharedPreferences.getInstance();
      _biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;
      _biometricsPhone = prefs.getString('biometrics_phone');
      debugPrint(
        '📱 Biometrics enabled: $_biometricsEnabled, phone: $_biometricsPhone',
      );
    } catch (e) {
      debugPrint('Error loading saved data: $e');
    }
  }

  Future<void> _loadBiometricsFromFirestore(String phone) async {
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      final doc = await _firestore
          .collection('userPreferences')
          .doc(cleanPhone)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final firestoreBiometricsEnabled =
            data?['biometricsEnabled'] as bool? ?? false;

        if (firestoreBiometricsEnabled) {
          // Update local SharedPreferences with Firestore value
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('biometrics_enabled', true);
          await prefs.setString('biometrics_phone', cleanPhone);

          _biometricsEnabled = true;
          _biometricsPhone = cleanPhone;
          debugPrint(
            '✅ Loaded biometrics preference from Firestore: enabled for $cleanPhone',
          );
        }
      }
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

  Future<void> _submit() async {
    final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');

    if (phoneDigits.isEmpty) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Enter phone number';
      });
      return;
    }

    if (phoneDigits.length != 10) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Enter 10 digits';
      });
      return;
    }

    if (!phoneDigits.startsWith('9')) {
      setState(() {
        _showPhoneError = true;
        _phoneErrorMessage = 'Must start with 9';
      });
      return;
    }

    setState(() => _showPhoneError = false);

    if (_initializing) {
      AppSnackBar.show(
        context,
        'Initializing... Please wait a moment.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    setState(() => _loading = true);
    await _verifyPinOnly();
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
      // First check semi_admins collection
      final semiAdminQuery = await _firestore
          .collection('semi_admins')
          .where('contactNumber', isEqualTo: phone)
          .where('pin', isEqualTo: pin)
          .limit(1)
          .get();

      if (semiAdminQuery.docs.isNotEmpty) {
        debugPrint('✅ Semi-admin login successful via PIN!');
        // Persist phone locally for faster next login.
        await RegistrationPrefs.savePhoneNumber(phoneInput);
        // Set user session data for semi-admin
        final semiAdminData = semiAdminQuery.docs.first.data();
        UserSession.setUserData({
          ...semiAdminData,
          'id': semiAdminQuery.docs.first.id,
        });
        setState(() => _loading = false);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainPage()),
          );
        }
        return;
      }

      // Find user by both phone number AND PIN in approved_users
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .where('pin', isEqualTo: pin)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() => _loading = false);
        _resetPinWithError('Wrong PIN');
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = {...userDoc.data(), 'docId': userDoc.id};
      final accountStatus = userData['accountStatus'] as String?;

      if (accountStatus != 'approved') {
        setState(() => _loading = false);
        _showPendingApprovalDialog();
        return;
      }

      // Sign in to Firebase Auth anonymously
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          '✅ Firebase Anonymous Sign-In successful: ${userCredential.user?.uid}',
        );
      } catch (authError) {
        debugPrint('⚠️ Firebase Anonymous Sign-In failed: $authError');
      }

      // Login successful
      // Persist phone locally for faster next login.
      await RegistrationPrefs.savePhoneNumber(phoneInput);
      UserSession.setUserData(userData);

      // Use phone number as user ID for easier tracking
      // Note: Firestore uses 'contactNumber' as the field name
      final phoneNumber =
          (userData['contactNumber'] ?? userData['phoneNumber'])
              ?.toString()
              .replaceAll(RegExp(r'[^0-9]'), '') ??
          '';
      if (phoneNumber.isNotEmpty) {
        UserSession.setUserId(phoneNumber);
        debugPrint('✅ UserSession userId set to phone number: $phoneNumber');
      } else {
        debugPrint('⚠️ No phone number found in userData');
        debugPrint('   Available fields: ${userData.keys.toList()}');
      }
      _finishAutofillContext(); // Trigger "Save to Google" prompt
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage()));
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
    debugPrint('🔍 Checking if semi_admins collection exists...');
    try {
      final existing = await _firestore
          .collection('semi_admins')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint('✓ semi_admins collection already exists. Skipping seed.');
        return;
      }

      debugPrint('📝 semi_admins collection empty. Starting seed...');

      final seedUsers = [
        {
          'fullName': 'Semi Admin One',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639111111111',
          'pin': '1111',
        },
        {
          'fullName': 'Semi Admin Two',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639222222222',
          'pin': '2222',
        },
        {
          'fullName': 'Semi Admin Three',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639333333333',
          'pin': '3333',
        },
        {
          'fullName': 'Semi Admin Four',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639444444444',
          'pin': '4444',
        },
        {
          'fullName': 'Semi Admin Five',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639555555555',
          'pin': '5555',
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
      debugPrint('✅ Successfully seeded 5 semi-admin users to Firestore!');
    } catch (e) {
      debugPrint('❌ Failed to seed semi_admins: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pending_actions, size: 64, color: appRed),
              const SizedBox(height: 16),
              Text(
                'Account Pending Approval',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account is currently pending admin approval. Please wait up to 48 hours for an administrator to review and approve your account.',
                style: const TextStyle(fontSize: 14, color: appBlack),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'OK',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

  Widget _logo() {
    return SvgPicture.asset(
      'assets/icons/RES-Q_LOGO.svg',
      height: 53,
    );
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    setState(() {
      _showPinError = false; // Clear error when user starts typing
      if (value == 'C') {
        _pinCtl.clear();
        return;
      }
      if (value == '⌫') {
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
                  Text(
                    'LOGIN',
                    style: AppTextStyles.authPageTitle,
                  ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
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
                                              color: appBlack.withOpacity(0.5),
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 16,
                                                ),
                                          ),
                                          onChanged: (_) {
                                            if (_showPhoneError) {
                                              setState(
                                                () => _showPhoneError = false,
                                              );
                                            }
                                          },
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
                                        ((_shakeController.value * 8).floor() %
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
                                    mainAxisAlignment: MainAxisAlignment.center,
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

                                // Error text below PIN
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

                                // Numpad with biometrics (always show biometrics button)
                                PinNumpad(
                                  enabled: !_loading,
                                  onKeyTap: _handlePinKey,
                                  actionBackgroundColor: appOffWhite,
                                  textColor: appBlack,
                                  showBiometrics: true,
                                  onBiometricsTap: _authenticateWithBiometrics,
                                ),

                                const SizedBox(height: 20),

                                // Success message for PIN creation
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

                                const SizedBox(height: 10),

                                // Register link
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton(
                                    onPressed: () => Navigator.pushNamed(
                                      context,
                                      '/register',
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                    ),
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'No Account yet? ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w400,
                                              color: appBlack,
                                              fontFamily: 'RobotoCondensed',
                                            ),
                                          ),
                                          TextSpan(
                                            text: 'Register Now!',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: appBlue,
                                              fontFamily: 'RobotoCondensed',
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
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
