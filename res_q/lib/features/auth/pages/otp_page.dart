import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/services/registration_prefs.dart';

class OTPPage extends StatefulWidget {
  const OTPPage({super.key});

  @override
  State<OTPPage> createState() => _OTPPageState();
}

class _OTPPageState extends State<OTPPage> {
  static const int _otpLength = 6;
  static const double _otpBoxSpacing = 8;

  final List<TextEditingController> _otpDigitControllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );
  bool _isProgrammaticOtpUpdate = false;
  bool _loading = false;
  bool _argsInitialized = false;

  String _flowType = 'registration';
  String? _verificationId;
  String? _phoneNumber;
  Map<String, dynamic>? _userData;
  String? _recoverySessionToken;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _otpCode =>
      _otpDigitControllers.map((controller) => controller.text).join();

  bool get _isOtpComplete =>
      _otpDigitControllers.every((controller) => controller.text.length == 1);

  bool get _requiresUserData => _flowType == 'registration';

  bool get _requiresRecoveryToken => _flowType == 'account-recovery';

  String _expiredSessionMessage() {
    if (_requiresRecoveryToken) {
      return 'Recovery session expired. Please start account recovery again.';
    }
    if (_requiresUserData) {
      return 'Registration session expired. Please start again.';
    }
    return 'Login session expired. Please try again.';
  }

  String _expiredSessionRoute() {
    if (_requiresRecoveryToken) {
      return '/recover-account';
    }
    if (_requiresUserData) {
      return '/register';
    }
    return '/login';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _flowType =
          (args['flowType'] as String?)?.trim().toLowerCase() ?? 'registration';
      _verificationId = args['verificationId'] as String?;
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
      _recoverySessionToken = args['recoverySessionToken'] as String?;
    }

    final hasRequiredArgs =
        _verificationId != null &&
        _phoneNumber != null &&
        _phoneNumber!.isNotEmpty &&
        (!_requiresUserData || _userData != null) &&
        (!_requiresRecoveryToken ||
            (_recoverySessionToken != null &&
                _recoverySessionToken!.trim().isNotEmpty));
    if (!hasRequiredArgs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackBar.show(
          context,
          _expiredSessionMessage(),
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          _expiredSessionRoute(),
          (_) => false,
        );
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _otpDigitControllers) {
      controller.dispose();
    }
    for (final focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _clearOtpInputs({bool focusFirstField = true}) {
    _isProgrammaticOtpUpdate = true;
    for (final controller in _otpDigitControllers) {
      controller.clear();
    }
    _isProgrammaticOtpUpdate = false;

    if (mounted) {
      setState(() {});
    }

    if (focusFirstField && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _otpFocusNodes.first.requestFocus();
      });
    }
  }

  void _fillOtpDigits(String rawDigits, {required int startIndex}) {
    final digits = rawDigits.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    _isProgrammaticOtpUpdate = true;
    int nextFocusIndex = startIndex;
    for (
      int digitIndex = 0;
      digitIndex < digits.length && nextFocusIndex < _otpLength;
      digitIndex++, nextFocusIndex++
    ) {
      _otpDigitControllers[nextFocusIndex].text = digits[digitIndex];
      _otpDigitControllers[nextFocusIndex].selection =
          const TextSelection.collapsed(offset: 1);
    }
    _isProgrammaticOtpUpdate = false;

    if (!mounted) return;
    setState(() {});

    if (nextFocusIndex >= _otpLength) {
      _otpFocusNodes[_otpLength - 1].unfocus();
      return;
    }
    _otpFocusNodes[nextFocusIndex].requestFocus();
  }

  void _handleOtpChanged(int index, String value) {
    if (_isProgrammaticOtpUpdate) return;

    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      if (index > 0) {
        _otpFocusNodes[index - 1].requestFocus();
        final previousController = _otpDigitControllers[index - 1];
        previousController.selection = TextSelection.collapsed(
          offset: previousController.text.length,
        );
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (digits.length > 1) {
      _fillOtpDigits(digits, startIndex: index);
      return;
    }

    _isProgrammaticOtpUpdate = true;
    _otpDigitControllers[index].text = digits;
    _otpDigitControllers[index].selection = const TextSelection.collapsed(
      offset: 1,
    );
    _isProgrammaticOtpUpdate = false;

    if (index < _otpLength - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    } else {
      _otpFocusNodes[index].unfocus();
    }
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleOtpKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpDigitControllers[index].text.isEmpty &&
        index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
      final previousController = _otpDigitControllers[index - 1];
      previousController.selection = TextSelection.collapsed(
        offset: previousController.text.length,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _maskedPhoneNumber() {
    final rawPhone = _phoneNumber?.trim();
    if (rawPhone == null || rawPhone.isEmpty) {
      return '+63 *** *** ****';
    }

    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return '+63 *** *** ****';
    }

    String normalized = digits;
    if (normalized.length == 10) {
      normalized = '63$normalized';
    } else if (normalized.length == 11 && normalized.startsWith('0')) {
      normalized = '63${normalized.substring(1)}';
    } else if (normalized.length > 12) {
      normalized = normalized.substring(normalized.length - 12);
    }

    final last4 = normalized.length >= 4
        ? normalized.substring(normalized.length - 4)
        : normalized;
    return '+63 *** *** $last4';
  }

  Widget _buildOtpDigitField({required int index, required double boxWidth}) {
    return SizedBox(
      width: boxWidth,
      child: Focus(
        onKeyEvent: (_, event) => _handleOtpKeyEvent(index, event),
        child: TextField(
          controller: _otpDigitControllers[index],
          focusNode: _otpFocusNodes[index],
          autofocus: index == 0,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          textInputAction: index == _otpLength - 1
              ? TextInputAction.done
              : TextInputAction.next,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack,
            fontFamily: 'Roboto',
          ),
          cursorColor: AppTheme.appRed,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.appOffWhite,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: BorderSide(
                color: AppTheme.appBlack.withValues(alpha: 0.35),
                width: 1.4,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: BorderSide(
                color: AppTheme.appBlack.withValues(alpha: 0.35),
                width: 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: BorderSide(color: AppTheme.appRed, width: 1.8),
            ),
          ),
          onChanged: (value) => _handleOtpChanged(index, value),
          onTap: () {
            _otpDigitControllers[index].selection = TextSelection.collapsed(
              offset: _otpDigitControllers[index].text.length,
            );
          },
        ),
      ),
    );
  }

  Widget _buildOtpInputRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawBoxWidth =
            (constraints.maxWidth - (_otpBoxSpacing * (_otpLength - 1))) /
            _otpLength;
        final boxWidth = rawBoxWidth.clamp(42.0, 50.0).toDouble();
        final rowWidth =
            (boxWidth * _otpLength) + (_otpBoxSpacing * (_otpLength - 1));

        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: rowWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_otpLength, (index) {
                final rightPadding = index == _otpLength - 1
                    ? 0.0
                    : _otpBoxSpacing;
                return Padding(
                  padding: EdgeInsets.only(right: rightPadding),
                  child: _buildOtpDigitField(index: index, boxWidth: boxWidth),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Future<void> _verify() async {
    if (_verificationId == null ||
        _phoneNumber == null ||
        (_requiresUserData && _userData == null) ||
        (_requiresRecoveryToken &&
            (_recoverySessionToken == null ||
                _recoverySessionToken!.trim().isEmpty))) {
      AppSnackBar.show(
        context,
        _expiredSessionMessage(),
        type: AppSnackBarType.warning,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        _expiredSessionRoute(),
        (_) => false,
      );
      return;
    }

    final code = _otpCode;
    if (!_isOtpComplete) {
      AppSnackBar.show(
        context,
        'Enter the 6-digit OTP code',
        type: AppSnackBarType.warning,
      );
      return;
    }

    if (_verificationId == null) {
      AppSnackBar.show(
        context,
        'Verification ID not found',
        type: AppSnackBarType.error,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Create phone auth credential
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );

      // Sign in with credential
      await _auth.signInWithCredential(credential);

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      if (!mounted) return;
      setState(() => _loading = false);

      if (_flowType == 'login') {
        if (mounted) {
          Navigator.pop(context, true);
        }
        return;
      }

      if (_flowType == 'registration-entry') {
        await RegistrationPrefs.savePhoneNumber(_phoneNumber!);
        if (!mounted) return;

        Navigator.pushReplacementNamed(
          context,
          '/register',
          result: true,
          arguments: {'phoneNumber': _phoneNumber, 'phoneVerified': true},
        );
        return;
      }

      if (_flowType == 'account-recovery') {
        final sessionToken = _recoverySessionToken?.trim() ?? '';
        if (sessionToken.isEmpty) {
          AppSnackBar.show(
            context,
            'Recovery session expired. Please start account recovery again.',
            type: AppSnackBarType.warning,
          );
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/recover-account',
            (_) => false,
          );
          return;
        }

        Navigator.pushReplacementNamed(
          context,
          '/pin-creation',
          arguments: {
            'flowType': 'account-recovery',
            'phoneNumber': _phoneNumber,
            'recoverySessionToken': sessionToken,
          },
        );
        return;
      }

      // Keep the locally-saved phone number so the Login page can prefill it
      // for faster logins (PIN/biometrics) after admin approval.

      await RegistrationPrefs.savePhoneNumber(_phoneNumber!);
      if (!mounted) return;

      // Navigate to PIN creation page.
      Navigator.pushReplacementNamed(
        context,
        '/pin-creation',
        arguments: {
          'phoneNumber': _phoneNumber,
          'userData': _userData,
          'uid': user.uid,
        },
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }

      String errorMessage = 'Verification failed';
      if (e.code == 'invalid-verification-code') {
        errorMessage = 'Invalid OTP code. Please try again.';
      } else if (e.code == 'session-expired') {
        errorMessage = 'OTP expired. Please request a new code.';
      }

      if (mounted) {
        AppSnackBar.show(
          context,
          errorMessage,
          type: AppSnackBarType.error,
          duration: const Duration(seconds: 3),
        );
        _clearOtpInputs();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      if (mounted) {
        AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
        _clearOtpInputs();
      }
    }
  }

  void _resend() async {
    if (_phoneNumber == null) {
      AppSnackBar.show(
        context,
        'Phone number not found',
        type: AppSnackBarType.error,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneNumber!,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _loading = false);
          if (mounted) {
            AppSnackBar.show(
              context,
              'Failed to resend OTP: ${e.message}',
              type: AppSnackBarType.error,
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _verificationId = verificationId;
          });
          _clearOtpInputs();
          if (mounted) {
            AppSnackBar.show(
              context,
              'OTP resent successfully',
              type: AppSnackBarType.success,
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _verificationId = verificationId);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      if (mounted) {
        AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
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
              title: Text('ENTER OTP', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
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
                          horizontal: AppDimensions.paddingXLarge,
                          vertical: AppDimensions.paddingMedium,
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Enter the 6-digit code sent to',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.appBlack.withValues(alpha: 0.8),
                                fontFamily: 'RobotoCondensed',
                              ),
                            ),
                            const SizedBox(height: AppDimensions.paddingXSmall),
                            Text(
                              _maskedPhoneNumber(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.appBlack,
                                fontFamily: 'Roboto',
                              ),
                            ),

                            const SizedBox(height: AppDimensions.paddingXLarge),

                            _buildOtpInputRow(),
                            const SizedBox(height: AppDimensions.paddingXLarge),

                            ResqPillButton(
                              label: 'VERIFY',
                              onPressed: (_loading || !_isOtpComplete)
                                  ? null
                                  : _verify,
                              loading: _loading,
                              backgroundColor: AppTheme.appRed,
                              shadowColor: AppTheme.appRed.withValues(
                                alpha: 0.35,
                              ),
                              shadowBlurRadius: 12,
                              shadowOffset: const Offset(0, 4),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFamily: 'Roboto',
                              ),
                            ),

                            const SizedBox(height: AppDimensions.paddingMedium),
                            Text(
                              'Didn\'t receive the code?',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.appBlack.withValues(
                                  alpha: 0.65,
                                ),
                                fontFamily: 'RobotoCondensed',
                              ),
                            ),

                            TextButton(
                              onPressed: _loading ? null : _resend,
                              child: const Text(
                                'Resend code',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.appRed,
                                  fontFamily: 'Roboto',
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
          ],
        ),
      ),
    );
  }
}
