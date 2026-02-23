import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/auth_api_service.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';
import '../../../common/widgets/phone_number_display_card.dart';

class LoginPinPage extends StatefulWidget {
  const LoginPinPage({super.key});

  @override
  State<LoginPinPage> createState() => _LoginPinPageState();
}

class _LoginPinPageState extends State<LoginPinPage>
    with SingleTickerProviderStateMixin {
  static const int _maxAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 15);

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _argsInitialized = false;
  String _phone = '';
  String _pin = '';
  bool _loading = false;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  String? _inlineError;
  bool _canUseBiometrics = false;
  bool _biometricEnabledForPhone = false;
  Timer? _lockTimer;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  bool get _isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  String get _phoneDigits => _phone.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final argPhone = (args?['phone'] as String? ?? '').trim();
    if (argPhone.isNotEmpty) {
      _phone = argPhone;
      _preparePhoneState();
      return;
    }
    _loadSavedPhone();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedPhone() async {
    final savedDigits = await RegistrationPrefs.getPhoneNumber();
    if (!mounted) return;
    if (savedDigits == null || savedDigits.trim().isEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    final normalized = savedDigits.replaceAll(RegExp(r'\D'), '');
    if (normalized.length == 10) {
      _phone = '+63$normalized';
      await _preparePhoneState();
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _preparePhoneState() async {
    if (_phone.isEmpty) return;
    final digits = _phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      _phone = '+63$digits';
    } else if (digits.length == 12 && digits.startsWith('63')) {
      _phone = '+$digits';
    }
    await _checkBiometricAvailability();
    if (mounted) setState(() {});
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final available = await _localAuth.getAvailableBiometrics();

      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('biometrics_enabled') ?? false;
      final prefPhone = (prefs.getString('biometrics_phone') ?? '').trim();
      final normalizedPref = prefPhone.replaceAll(RegExp(r'[^0-9+]'), '');
      final normalizedCurrent = _phone.replaceAll(RegExp(r'[^0-9+]'), '');

      _canUseBiometrics = (canCheck || isSupported) && available.isNotEmpty;
      _biometricEnabledForPhone =
          enabled &&
          normalizedPref.isNotEmpty &&
          normalizedCurrent.isNotEmpty &&
          normalizedPref == normalizedCurrent;
    } catch (_) {
      _canUseBiometrics = false;
      _biometricEnabledForPhone = false;
    }
  }

  String _formatPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    String localDigits = digits;
    if (localDigits.startsWith('63') && localDigits.length == 12) {
      localDigits = localDigits.substring(2);
    }
    if (localDigits.length == 10) {
      return '+63 ${localDigits.substring(0, 3)}-${localDigits.substring(3, 6)}-${localDigits.substring(6)}';
    }
    return phone;
  }

  String _remainingLockText() {
    if (_lockedUntil == null) return '';
    final remaining = _lockedUntil!.difference(DateTime.now());
    if (remaining.isNegative) return '';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isLocked) {
        timer.cancel();
        setState(() {
          _failedAttempts = 0;
          _lockedUntil = null;
          _inlineError = null;
        });
        return;
      }
      setState(() {});
    });
  }

  void _clearPinWithShake(String message) {
    setState(() {
      _inlineError = message;
      _pin = '';
    });
    _shakeController.forward(from: 0);
  }

  void _onNumpadTap(String value) {
    if (_loading || _isLocked) return;
    setState(() {
      _inlineError = null;
      if (value == PinNumpad.clearKey) {
        _pin = '';
        return;
      }
      if (value == PinNumpad.backspaceKey) {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
        return;
      }
      if (_pin.length >= 4) return;
      _pin += value;
    });

    if (_pin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _submitPin();
      });
    }
  }

  Future<void> _submitPin() async {
    if (_loading || _isLocked || _phone.isEmpty || _pin.length != 4) return;

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      final result = await AuthApiService.instance.loginWithPin(
        phone: _phone,
        pin: _pin,
      );

      await RegistrationPrefs.savePhoneNumber(
        _phoneDigits.length == 12 ? _phoneDigits.substring(2) : _phoneDigits,
      );
      await RegistrationPrefs.setApprovedLoginCompleted(true);
      await TrustedDeviceService.instance.markTrusted(_phone);

      final sessionData = <String, dynamic>{
        ...result.userData,
        'id': result.userId,
        'contactNumber': _phone,
        'phoneNumber': _phone,
        'isApproved': true,
      };
      UserSession.setUserData(sessionData);
      NotificationService().setUserId(_phoneDigits);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/main', (_) => false);
    } on AuthApiException catch (e) {
      if (!mounted) return;

      if (e.message.toLowerCase().contains('incorrect pin')) {
        _failedAttempts += 1;
        if (_failedAttempts >= _maxAttempts) {
          _lockedUntil = DateTime.now().add(_lockDuration);
          _startLockTimer();
          _clearPinWithShake('Too many attempts. Try again in 15 minutes.');
        } else {
          _clearPinWithShake('Incorrect PIN');
        }
      } else {
        _clearPinWithShake(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      _clearPinWithShake('Unable to log in right now.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleBiometricTap() async {
    if (!_canUseBiometrics || !_biometricEnabledForPhone || _loading) return;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to continue',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!mounted) return;

      if (authenticated) {
        AppSnackBar.show(
          context,
          'Biometric authentication successful. Enter PIN to continue.',
          type: AppSnackBarType.success,
        );
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Biometric authentication failed.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _onForgotPin() async {
    if (_loading || _phone.isEmpty) return;
    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      await AuthApiService.instance.resendOtp(phone: _phone);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/login/verify',
        arguments: <String, dynamic>{'phone': _phone, 'mode': 'reset_pin'},
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Unable to start reset flow.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
              leading: const ResqBackButton.outline(),
              title: Text('LOGIN', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PhoneNumberDisplayCard(
                            phoneText: _formatPhone(_phone),
                            onEditTap: _loading
                                ? null
                                : () => Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/login',
                                    (_) => false,
                                  ),
                            editTooltip: 'Edit number',
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),
                          Text(
                            'Enter your 4-digit PIN',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.appBlack.withValues(alpha: 0.84),
                              fontFamily: 'RobotoCondensed',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),
                          AnimatedBuilder(
                            animation: _shakeAnimation,
                            builder: (context, child) {
                              final offset =
                                  _shakeAnimation.value *
                                  10 *
                                  (1 - _shakeAnimation.value) *
                                  ((_shakeController.value * 8).floor() % 2 == 0
                                      ? 1
                                      : -1);
                              return Transform.translate(
                                offset: Offset(offset, 0),
                                child: child,
                              );
                            },
                            child: PinDots(
                              filled: _pin.length,
                              error: _inlineError != null,
                            ),
                          ),
                          if (_isLocked) ...[
                            const SizedBox(height: AppDimensions.paddingSmall),
                            Text(
                              'Too many attempts. Try again in ${_remainingLockText()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                          RegistrationValidationMessage(
                            message: _inlineError,
                            reserveSpace: false,
                          ),
                          const SizedBox(height: AppDimensions.paddingXLarge),
                          PinNumpad(
                            enabled: !_loading && !_isLocked,
                            onKeyTap: _onNumpadTap,
                            showBiometrics:
                                _canUseBiometrics && _biometricEnabledForPhone,
                            onBiometricsTap: _handleBiometricTap,
                            backgroundColor: AppTheme.appOffWhite,
                            actionBackgroundColor: AppTheme.appOffWhite,
                            textColor: AppTheme.appBlack,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: _loading ? null : _onForgotPin,
                              child: const Text(
                                'Forgot PIN?',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.appRed,
                                  decoration: TextDecoration.underline,
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
          ],
        ),
      ),
    );
  }
}
