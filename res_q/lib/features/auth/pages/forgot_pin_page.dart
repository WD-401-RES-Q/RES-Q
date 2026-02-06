import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';

class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtl = TextEditingController();
  final TextEditingController _pinCtl = TextEditingController();
  bool _loading = false;
  bool _phoneVerified = false;
  String? _userId;
  Map<String, dynamic>? _userData;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void dispose() {
    _phoneCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  Future<void> _verifyPhone() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneDigits';

    setState(() => _loading = true);

    try {
      // Check if phone exists in approved_users
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() => _loading = false);
        if (!mounted) return;
        AppSnackBar.show(
          context,
          'Phone number not found or not approved yet. Please wait for admin approval.',
          type: AppSnackBarType.error,
        );
        return;
      }

      final doc = userQuery.docs.first;
      _userId = doc.id;
      _userData = doc.data();

      // Allow PIN reset - no longer blocking users who have existing PIN
      setState(() {
        _loading = false;
        _phoneVerified = true;
      });

      if (!mounted) return;
      AppSnackBar.show(
        context,
        '✓ Phone verified! Please enter your new 4-digit PIN.',
        type: AppSnackBarType.success,
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
    }
  }

  Future<bool> _checkBiometricsAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return canAuthenticate && availableBiometrics.isNotEmpty;
    } catch (e) {
      debugPrint('Biometrics check error: $e');
      return false;
    }
  }

  Future<bool?> _showBiometricsOptInDialog() async {
    final canUseBiometrics = await _checkBiometricsAvailable();

    if (!canUseBiometrics || !mounted) {
      return null; // Skip if biometrics not available
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: appBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint, size: 48, color: appBlue),
              ),
              const SizedBox(height: 20),
              const Text(
                'Enable Biometric Login?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Would you like to use fingerprint or face recognition for faster login?',
                style: TextStyle(
                  fontSize: 14,
                  color: appBlack.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You can change this later in settings.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: appBlack,
                        side: BorderSide(color: appBlack.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'No Thanks',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: appBlack,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            size: 18,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Enable',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
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

  Future<void> _saveBiometricsPreference(
    bool enabled,
    String? phoneNumber,
  ) async {
    try {
      // Save to SharedPreferences for local/quick access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', enabled);
      if (phoneNumber != null) {
        await prefs.setString('biometrics_phone', phoneNumber);
      }

      // Save to Firestore for persistence across devices (like votes)
      if (phoneNumber != null) {
        final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
        await _firestore
            .collection('userPreferences')
            .doc(cleanPhone)
            .set({
              'biometricsEnabled': enabled,
              'biometricsUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        debugPrint('✅ Biometrics preference saved to Firestore: $enabled');
      }

      debugPrint(
        '✅ Biometrics preference saved locally: $enabled for phone: $phoneNumber',
      );
    } catch (e) {
      debugPrint('Error saving biometrics preference: $e');
    }
  }

  Future<void> _createPin() async {
    final pin = _pinCtl.text.trim();

    if (pin.length != 4) {
      AppSnackBar.show(
        context,
        'PIN must be exactly 4 digits',
        type: AppSnackBarType.error,
      );
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      AppSnackBar.show(
        context,
        'PIN must contain only numbers',
        type: AppSnackBarType.error,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Update the user document with the PIN
      await _firestore.collection('approved_users').doc(_userId).update({
        'pin': pin,
        'pinCreatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _loading = false);

      if (!mounted) return;

      // Show biometrics opt-in dialog
      final phoneNumber = _userData?['contactNumber'] as String?;
      final enableBiometrics = await _showBiometricsOptInDialog();

      if (enableBiometrics != null) {
        await _saveBiometricsPreference(enableBiometrics, phoneNumber);
      }

      if (!mounted) return;

      // Navigate back to login with success message
      Navigator.pushReplacementNamed(
        context,
        '/login',
        arguments: {'showPinSuccess': true},
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
    }
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    setState(() {
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
          Future.delayed(const Duration(milliseconds: 300), () {
            _createPin();
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingMedium,
                left: AppDimensions.paddingXLarge,
                right: AppDimensions.paddingXLarge,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ResqBackButton.outline(onPressed: () => Navigator.pop(context)),
                  const ResqLogo(fontSize: 53),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.paddingSmall),
            Text(
              _phoneVerified ? 'RESET PIN' : 'FORGOT PIN',
              style: AppTextStyles.authPageTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.paddingXSmall),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      behavior: HitTestBehavior.opaque,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.paddingXLarge,
                            vertical: AppDimensions.paddingXSmall,
                          ),
                          child: Align(
                            alignment: const Alignment(0, -0.2),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _phoneVerified
                                          ? 'Enter a new 4-digit PIN'
                                          : 'Enter your registered phone number to reset your PIN',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.appBlack.withOpacity(0.7),
                                        fontFamily: 'RobotoCondensed',
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: AppDimensions.paddingSmall),

                                    if (!_phoneVerified) ...[
                                      PhoneInputField(
                                        controller: _phoneCtl,
                                        validator: validatePhilippinePhone,
                                        autofillHints: const [
                                          AutofillHints.telephoneNumber,
                                        ],
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                      ),
                                      const SizedBox(height: AppDimensions.paddingLarge),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 50,
                                        child: ElevatedButton(
                                          onPressed: _loading ? null : _verifyPhone,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: appBlue,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(50),
                                            ),
                                          ),
                                          child: _loading
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Text(
                                                  'VERIFY',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                    fontFamily: 'Roboto',
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ] else ...[
                                      // PIN Display (dots)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: List.generate(4, (index) {
                                          final hasValue = _pinCtl.text.length > index;
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: hasValue ? appBlue : Colors.transparent,
                                              border: Border.all(
                                                color: appBlack,
                                                width: 2,
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                      const SizedBox(height: 32),

                                      // Numpad
                                      PinNumpad(
                                        enabled: !_loading,
                                        onKeyTap: _handlePinKey,
                                        actionBackgroundColor: appOffWhite,
                                        textColor: appBlack,
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
