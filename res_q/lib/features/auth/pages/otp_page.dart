import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class OTPPage extends StatefulWidget {
  const OTPPage({super.key});

  @override
  State<OTPPage> createState() => _OTPPageState();
}

class _OTPPageState extends State<OTPPage> {
  static const String _flowRegistration = 'registration';
  static const String _flowLogin = 'login';

  final TextEditingController _otpCtl = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  bool _loading = false;
  bool _argsInitialized = false;

  String _flowType = _flowRegistration;
  String? _verificationId;
  String? _phoneNumber;
  Map<String, dynamic>? _userData;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _otpDigits => _otpCtl.text.replaceAll(RegExp(r'\D'), '');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _flowType = (args['flowType'] as String?) ?? _flowRegistration;
      _verificationId = args['verificationId'] as String?;
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
    }

    final hasVerificationArgs =
        _verificationId != null &&
        _phoneNumber != null &&
        _phoneNumber!.isNotEmpty;
    final hasRequiredArgs = _flowType == _flowLogin
        ? hasVerificationArgs
        : (hasVerificationArgs && _userData != null);
    if (!hasRequiredArgs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_flowType == _flowLogin) {
          AppSnackBar.show(
            context,
            'Login OTP session expired. Please try again.',
            type: AppSnackBarType.warning,
          );
          Navigator.pop(context, {'verified': false});
        } else {
          AppSnackBar.show(
            context,
            'Registration session expired. Please start again.',
            type: AppSnackBarType.warning,
          );
          Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
        }
      });
    }
  }

  @override
  void dispose() {
    _otpCtl.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verificationId == null || _phoneNumber == null) {
      AppSnackBar.show(
        context,
        _flowType == _flowLogin
            ? 'Login session expired. Please try again.'
            : 'Registration session expired. Please start again.',
        type: AppSnackBarType.warning,
      );
      if (_flowType == _flowLogin) {
        Navigator.pop(context, {'verified': false});
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
      }
      return;
    }

    final code = _otpDigits;
    if (code.length < 6) {
      AppSnackBar.show(
        context,
        'Enter the 6-digit OTP code',
        type: AppSnackBarType.warning,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _auth.signInWithCredential(credential);

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await RegistrationPrefs.savePhoneNumber(_phoneNumber!);
      if (!mounted) return;
      setState(() => _loading = false);

      if (_flowType == _flowLogin) {
        Navigator.pop(context, {
          'verified': true,
          'phoneNumber': _phoneNumber,
          'uid': user.uid,
        });
        return;
      }

      if (_userData == null) {
        AppSnackBar.show(
          context,
          'Registration session expired. Please start again.',
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
        return;
      }

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
      if (!mounted) return;
      setState(() => _loading = false);

      var errorMessage = 'Verification failed';
      if (e.code == 'invalid-verification-code') {
        errorMessage = 'Invalid OTP code. Please try again.';
      } else if (e.code == 'session-expired') {
        errorMessage = 'OTP expired. Please request a new code.';
      }

      AppSnackBar.show(
        context,
        errorMessage,
        type: AppSnackBarType.error,
        duration: const Duration(seconds: 3),
      );
      _otpCtl.clear();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
      _otpCtl.clear();
      setState(() {});
    }
  }

  Future<void> _resend() async {
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
          AppSnackBar.show(
            context,
            'Failed to resend OTP: ${e.message}',
            type: AppSnackBarType.error,
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _verificationId = verificationId;
          });
          AppSnackBar.show(
            context,
            'OTP resent successfully',
            type: AppSnackBarType.success,
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _verificationId = verificationId);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
    }
  }

  Widget _buildOtpBoxes() {
    final code = _otpDigits;
    final activeIndex = code.length >= 6 ? 5 : code.length;

    return GestureDetector(
      onTap: () => _otpFocusNode.requestFocus(),
      child: SizedBox(
        height: 62,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final hasValue = index < code.length;
                final isActive = _otpFocusNode.hasFocus && index == activeIndex;
                return Padding(
                  padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                  child: Container(
                    width: 44,
                    height: 56,
                    alignment: Alignment.center,
                    decoration:
                        registrationFieldDecoration(
                          hasError: false,
                          isValid: hasValue,
                        ).copyWith(
                          border: Border.all(
                            color: isActive
                                ? AppTheme.appRed
                                : (hasValue
                                      ? const Color(0xFF00A458)
                                      : AppTheme.appBlack.withValues(
                                          alpha: 0.35,
                                        )),
                            width: 0.8,
                          ),
                        ),
                    child: Text(
                      hasValue ? code[index] : '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.appBlack,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: TextField(
                focusNode: _otpFocusNode,
                controller: _otpCtl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                cursorColor: Colors.transparent,
                showCursor: false,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
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
              leading: const ResqBackButton.outline(),
              title: Text('VERIFY OTP', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
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
                              'Enter the 6 digit code sent to your\nphone number.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.appBlack,
                                fontFamily: 'RobotoCondensed',
                              ),
                            ),
                            const SizedBox(height: AppDimensions.paddingXLarge),
                            _buildOtpBoxes(),
                            const SizedBox(height: AppDimensions.paddingXLarge),
                            ResqPillButton(
                              label: 'VERIFY',
                              onPressed: _loading ? null : _verify,
                              loading: _loading,
                              height: 48,
                              radius: 30,
                              backgroundColor: AppTheme.appOffYellow,
                              shadowColor: AppTheme.appBlack.withValues(
                                alpha: 0.1,
                              ),
                              shadowBlurRadius: 8,
                              shadowOffset: const Offset(0, 2),
                              textStyle: AppTextStyles.authButton,
                            ),
                            const SizedBox(height: AppDimensions.paddingMedium),
                            TextButton(
                              onPressed: _loading ? null : _resend,
                              child: const Text(
                                'Resend Code',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.appRed,
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
