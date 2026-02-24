import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/utils/security_hash.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';

class PINCreationPage extends StatefulWidget {
  const PINCreationPage({super.key});

  @override
  State<PINCreationPage> createState() => _PINCreationPageState();
}

class _PINCreationPageState extends State<PINCreationPage>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmingPin = false;
  bool _loading = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _argsInitialized = false;

  String? _phoneNumber;
  Map<String, dynamic>? _userData;
  String? _uid;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-east2',
  );
  final LocalAuthentication _localAuth = LocalAuthentication();
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnimation = CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
      _uid = args['uid'] as String?;
    }

    _uid ??= FirebaseAuth.instance.currentUser?.uid;

    final hasRequiredArgs =
        _phoneNumber != null &&
        _phoneNumber!.isNotEmpty &&
        _userData != null &&
        _uid != null &&
        _uid!.isNotEmpty;
    if (!hasRequiredArgs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackBar.show(
          context,
          'Registration session expired. Please start again.',
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String _formatPhoneForDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.length == 10) {
      return '+63 ${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  String get _activePin => _isConfirmingPin ? _confirmPin : _pin;

  void _triggerShake() {
    _shakeController
      ..reset()
      ..forward();
  }

  void _resetConfirmStepWithError(String message) {
    setState(() {
      _showError = true;
      _errorMessage = message;
      _confirmPin = '';
    });
    _triggerShake();
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    if (value == PinNumpad.clearKey || value == 'C') {
      setState(() {
        _showError = false;
        _errorMessage = '';
        if (_isConfirmingPin) {
          _confirmPin = '';
        } else {
          _pin = '';
        }
      });
      return;
    }

    if (value == PinNumpad.backspaceKey || value == '\u232b') {
      setState(() {
        _showError = false;
        _errorMessage = '';
        if (_isConfirmingPin) {
          if (_confirmPin.isNotEmpty) {
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
          }
        } else if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      });
      return;
    }

    if (_isConfirmingPin) {
      if (_confirmPin.length >= 4) return;
      setState(() {
        _showError = false;
        _errorMessage = '';
        _confirmPin += value;
      });

      if (_confirmPin.length == 4) {
        Future.delayed(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          if (_confirmPin != _pin) {
            _resetConfirmStepWithError('PINs do not match');
            return;
          }
          _createPin();
        });
      }
      return;
    }

    if (_pin.length >= 4) return;
    setState(() {
      _showError = false;
      _errorMessage = '';
      _pin += value;
    });

    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() {
          _isConfirmingPin = true;
          _confirmPin = '';
          _showError = false;
          _errorMessage = '';
        });
      });
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

    if (!mounted) {
      return null;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.appRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fingerprint,
                  size: 48,
                  color: AppTheme.appRed,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              Text(
                'ENABLE BIOMETRIC\nLOGIN?',
                style: AppTextStyles.authPageTitle.copyWith(height: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              Text(
                'Would you like to use fingerprint or face recognition for faster login?',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.appBlack,
                  fontFamily: 'RobotoCondensed',
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              if (!canUseBiometrics) ...[
                const SizedBox(height: AppDimensions.paddingSmall),
                Text(
                  'Biometrics is not available on this device yet. You can continue now and enable it later in app settings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.appBlack.withValues(alpha: 0.7),
                    fontFamily: 'RobotoCondensed',
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppDimensions.paddingSmall),
              Text(
                'You can change this later in settings.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.appBlack.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.appBlack,
                        side: BorderSide(
                          color: AppTheme.appBlack.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'No Thanks',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.appBlack,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canUseBiometrics
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canUseBiometrics
                            ? AppTheme.appRed
                            : AppTheme.appBlack.withValues(alpha: 0.35),
                        disabledBackgroundColor: AppTheme.appBlack.withValues(
                          alpha: 0.35,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.fingerprint,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
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
      final cleanPhone = phoneNumber?.replaceAll(RegExp(r'[^0-9+]'), '');

      // Save to SharedPreferences for local/quick access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', enabled);
      if (cleanPhone != null && cleanPhone.isNotEmpty) {
        await prefs.setString('biometrics_phone', cleanPhone);
      }

      // Save to Firestore for persistence across devices (like votes)
      if (cleanPhone != null && cleanPhone.isNotEmpty) {
        await _firestore.collection('userPreferences').doc(cleanPhone).set({
          'biometricsEnabled': enabled,
          'biometricsUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('Biometrics preference saved to Firestore: $enabled');
      }

      debugPrint('Biometrics preference saved locally: $enabled');
    } catch (e) {
      debugPrint('Error saving biometrics preference: $e');
    }
  }

  Future<void> _endTemporaryAuthSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Sign-out after registration failed: $e');
    }
  }

  Future<void> _createPin() async {
    if (_phoneNumber == null || _userData == null) {
      if (mounted) {
        AppSnackBar.show(
          context,
          'Registration session expired. Please start again.',
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
      }
      return;
    }

    if (_pin.length != 4) {
      setState(() {
        _showError = true;
        _errorMessage = 'PIN must be exactly 4 digits';
      });
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(_pin)) {
      setState(() {
        _showError = true;
        _errorMessage = 'PIN must contain only numbers';
        _pin = '';
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception('User ID not found');
      }
      _uid = uid;

      final userData = _userData ?? {};
      final hashedPin = SecurityHash.sha256Hex(_pin);
      userData['pin_hash'] = hashedPin;
      userData['hashedPin'] = hashedPin;
      userData['accountStatus'] = 'pending';
      userData['contactNumber'] = _phoneNumber;

      try {
        final registerCallable = _functions.httpsCallable(
          'registerUserEncrypted',
        );
        await registerCallable.call({...userData, 'uid': uid});
      } on FirebaseFunctionsException catch (functionError) {
        const fallbackCodes = <String>{
          'unavailable',
          'not-found',
          'deadline-exceeded',
        };
        if (!fallbackCodes.contains(functionError.code)) {
          rethrow;
        }
        debugPrint(
          'registerUserEncrypted callable failed (${functionError.code}). Falling back to direct Firestore write.',
        );
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['pinCreatedAt'] = FieldValue.serverTimestamp();
        await _firestore
            .collection('pending_users')
            .doc(uid)
            .set(userData, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() => _loading = false);

      final enableBiometrics = await _showBiometricsOptInDialog();

      if (enableBiometrics != null) {
        await _saveBiometricsPreference(enableBiometrics, _phoneNumber);
      }

      if (!mounted) return;
      await _endTemporaryAuthSession();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/account-submitted',
        (_) => false,
      );
    } catch (e) {
      var message = 'Registration failed. Please try again.';
      if (e is FirebaseFunctionsException) {
        if (e.code == 'already-exists') {
          message =
              'This phone number is already registered or pending approval.';
        } else if (e.code == 'invalid-argument') {
          message = e.message ?? 'Invalid registration details.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
      } else {
        message = 'Error: $e';
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _showError = true;
          _errorMessage = message;
          _pin = '';
          _confirmPin = '';
          _isConfirmingPin = false;
        });
      }
      if (mounted) {
        AppSnackBar.show(context, message, type: AppSnackBarType.error);
      }
    }
  }

  Widget _buildPinDots() {
    final activePin = _activePin;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final hasValue = activePin.length > index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasValue
                ? (_showError ? Colors.red : AppTheme.appRed)
                : Colors.transparent,
            border: Border.all(
              color: _showError ? Colors.red : AppTheme.appBlack,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              leading: ResqBackButton.outline(
                onPressed: () {
                  if (_isConfirmingPin && !_loading) {
                    setState(() {
                      _isConfirmingPin = false;
                      _confirmPin = '';
                      _showError = false;
                      _errorMessage = '';
                    });
                    return;
                  }
                  Navigator.pop(context);
                },
              ),
              title: Text('CREATE PIN', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),

            // Content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingXLarge,
                        vertical: AppDimensions.paddingMedium,
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isConfirmingPin
                                ? 'Confirm your 4-digit PIN'
                                : 'Set up your 4-digit PIN for fast login',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.appBlack.withValues(alpha: 0.7),
                              fontFamily: 'RobotoCondensed',
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: AppDimensions.paddingLarge),

                          // Phone number display
                          if (_phoneNumber != null && _phoneNumber!.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.appOffWhite,
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusMedium,
                                ),
                                border: Border.all(
                                  color: AppTheme.appBlack.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.phone_android,
                                    color: AppTheme.appBlack,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatPhoneForDisplay(_phoneNumber),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.appBlack,
                                      fontFamily: 'RobotoCondensed',
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: AppDimensions.paddingXLarge),

                          // PIN label
                          Text(
                            _isConfirmingPin
                                ? 'CONFIRM YOUR PIN'
                                : 'ENTER YOUR PIN',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.appBlack,
                              fontFamily: 'Roboto',
                              letterSpacing: 1,
                            ),
                          ),

                          const SizedBox(height: AppDimensions.paddingMedium),

                          // PIN dots
                          _loading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.appRed,
                                  ),
                                )
                              : AnimatedBuilder(
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
                                  child: _buildPinDots(),
                                ),

                          // Error message
                          if (_showError) ...[
                            const SizedBox(height: AppDimensions.paddingMedium),
                            Text(
                              _errorMessage,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          const SizedBox(height: AppDimensions.paddingXLarge),

                          // Numpad
                          PinNumpad(
                            enabled: !_loading,
                            onKeyTap: _handlePinKey,
                            actionBackgroundColor: AppTheme.appOffWhite,
                            textColor: AppTheme.appBlack,
                          ),

                          const SizedBox(height: AppDimensions.paddingLarge),

                          Text(
                            _isConfirmingPin
                                ? 'Re-enter the same 4 digits to continue.'
                                : 'Please remember your PIN.\nYou will need it to login.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.appBlack.withValues(alpha: 0.6),
                              fontFamily: 'RobotoCondensed',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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
