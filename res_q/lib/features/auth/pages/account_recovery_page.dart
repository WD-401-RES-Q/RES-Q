import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/account_recovery_widgets.dart';

enum _RecoveryStep { emailEntry, emailOtp, newPhone }

class AccountRecoveryPage extends StatefulWidget {
  const AccountRecoveryPage({super.key});

  @override
  State<AccountRecoveryPage> createState() => _AccountRecoveryPageState();
}

class _AccountRecoveryPageState extends State<AccountRecoveryPage> {
  static const Color appOffWhite = Color(0xFFF7F8F3);

  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _otpCtl = TextEditingController();
  final _newPhoneCtl = TextEditingController();
  final _confirmPhoneCtl = TextEditingController();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-east2',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  _RecoveryStep _step = _RecoveryStep.emailEntry;
  bool _loading = false;

  String? _recoveryChallengeId;
  String? _recoverySessionToken;
  String _otpError = '';
  String _phoneError = '';

  @override
  void initState() {
    super.initState();
    _otpCtl.addListener(_onFieldStateChanged);
    _newPhoneCtl.addListener(_onFieldStateChanged);
    _confirmPhoneCtl.addListener(_onFieldStateChanged);
  }

  @override
  void dispose() {
    _otpCtl.removeListener(_onFieldStateChanged);
    _newPhoneCtl.removeListener(_onFieldStateChanged);
    _confirmPhoneCtl.removeListener(_onFieldStateChanged);
    _emailCtl.dispose();
    _otpCtl.dispose();
    _newPhoneCtl.dispose();
    _confirmPhoneCtl.dispose();
    super.dispose();
  }

  void _onFieldStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _isOtpComplete => _otpCtl.text.trim().length == 6;

  bool get _canContinuePhoneStep {
    final newDigits = _newPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = _confirmPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    return newDigits.length == 10 &&
        confirmDigits.length == 10 &&
        newDigits == confirmDigits;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Email is required';
    }
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!isValid) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String _recoveryFunctionErrorMessage(
    FirebaseFunctionsException error, {
    required String fallback,
  }) {
    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!.trim();
    }

    switch (error.code) {
      case 'not-found':
        return 'No account found with this email address.';
      case 'deadline-exceeded':
        return 'Code expired. Please resend and try again.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait and try again.';
      case 'permission-denied':
        return 'Verification failed. Please try again.';
      case 'already-exists':
        return 'Phone number already in use. Please try another one.';
      case 'invalid-argument':
        return 'Invalid input. Please review and try again.';
      default:
        return fallback;
    }
  }

  Future<void> _continueWithEmail() async {
    if (!_emailFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _recoveryChallengeId = null;
      _recoverySessionToken = null;
      _otpCtl.clear();
      _otpError = '';
    });

    await _sendEmailOtp(moveToOtpStep: true);
  }

  Future<void> _sendEmailOtp({bool moveToOtpStep = false}) async {
    final email = _emailCtl.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      if (mounted) {
        AppSnackBar.show(context, emailError, type: AppSnackBarType.warning);
      }
      return;
    }

    setState(() {
      _loading = true;
      _otpError = '';
    });

    try {
      final callable = _functions.httpsCallable('requestAccountRecoveryOtp');
      final response = await callable.call({
        'email': email,
        if (_recoveryChallengeId != null && _recoveryChallengeId!.isNotEmpty)
          'challengeId': _recoveryChallengeId,
      });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final challengeId = data['challengeId']?.toString().trim() ?? '';
      if (challengeId.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Missing recovery challenge id.',
        );
      }

      if (!mounted) return;
      final debugOtp = data['debugOtp']?.toString().trim();
      final responseMessage = data['message']?.toString().trim();
      final successMessage =
          debugOtp != null && debugOtp.isNotEmpty && kDebugMode
          ? 'Verification code sent. Debug OTP: $debugOtp'
          : (responseMessage != null && responseMessage.isNotEmpty
                ? responseMessage
                : 'Verification code sent to your email.');

      setState(() {
        _loading = false;
        _recoveryChallengeId = challengeId;
        if (moveToOtpStep) {
          _step = _RecoveryStep.emailOtp;
        }
      });
      AppSnackBar.show(context, successMessage, type: AppSnackBarType.success);
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        _recoveryFunctionErrorMessage(
          error,
          fallback: 'Failed to send verification code. Please try again.',
        ),
        type: AppSnackBarType.error,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Failed to send verification code. Please try again.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _verifyEmailOtp() async {
    final otp = _otpCtl.text.trim();
    if (otp.length != 6) {
      setState(() {
        _otpError = 'Enter the 6-digit code sent to your email.';
      });
      return;
    }

    final challengeId = _recoveryChallengeId;
    if (challengeId == null || challengeId.isEmpty) {
      setState(() {
        _otpError = 'Session expired. Please request a new code.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _otpError = '';
    });

    try {
      final callable = _functions.httpsCallable('verifyAccountRecoveryOtp');
      final response = await callable.call({
        'challengeId': challengeId,
        'otpCode': otp,
      });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final sessionToken = data['sessionToken']?.toString().trim() ?? '';
      if (sessionToken.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'internal',
          message: 'Missing recovery session token.',
        );
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpError = '';
        _recoverySessionToken = sessionToken;
        _step = _RecoveryStep.newPhone;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpError = _recoveryFunctionErrorMessage(
          error,
          fallback: 'Failed to verify the code. Please try again.',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpError = 'Failed to verify the code. Please try again.';
      });
    }
  }

  Future<void> _continueWithNewPhone() async {
    if (!_phoneFormKey.currentState!.validate()) {
      return;
    }

    if (_recoverySessionToken == null || _recoverySessionToken!.isEmpty) {
      setState(() {
        _phoneError = 'Session expired. Please verify your code again.';
        _step = _RecoveryStep.emailOtp;
      });
      return;
    }

    final newDigits = _newPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = _confirmPhoneCtl.text.replaceAll(RegExp(r'\D'), '');

    if (newDigits != confirmDigits) {
      setState(() {
        _phoneError = 'Phone numbers do not match. Please try again.';
      });
      return;
    }

    await _startPhoneOtpForRecovery('+63$newDigits');
  }

  Future<void> _startPhoneOtpForRecovery(String updatedPhone) async {
    final sessionToken = _recoverySessionToken;
    if (sessionToken == null || sessionToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otpError = 'Session expired. Please verify your code again.';
        _step = _RecoveryStep.emailOtp;
      });
      return;
    }

    final otpCompleter = Completer<bool>();
    setState(() {
      _loading = true;
      _phoneError = '';
    });

    try {
      if (!kIsWeb) {
        await _auth.setSettings(appVerificationDisabledForTesting: kDebugMode);
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: updatedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
          } catch (_) {}
          if (!mounted) return;
          if (!otpCompleter.isCompleted) {
            otpCompleter.complete(true);
          }
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            final message = error.message?.trim();
            _phoneError = (message != null && message.isNotEmpty)
                ? message
                : 'Unable to send OTP to this number. Please try again.';
          });
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

          setState(() => _loading = false);
          final result = await Navigator.pushNamed(
            context,
            '/otp',
            arguments: {
              'flowType': 'account-recovery',
              'verificationId': verificationId,
              'phoneNumber': updatedPhone,
              'recoverySessionToken': sessionToken,
            },
          );
          if (!otpCompleter.isCompleted) {
            otpCompleter.complete(result == true);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );

      await otpCompleter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );

      if (!mounted) return;
      if (_loading) {
        setState(() => _loading = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _phoneError = 'Failed to start phone verification. Please try again.';
      });
    }
  }

  String _stepTitle() {
    switch (_step) {
      case _RecoveryStep.emailEntry:
        return 'Recover Your Account';
      case _RecoveryStep.emailOtp:
        return 'Verify Email Code';
      case _RecoveryStep.newPhone:
        return 'Set New Phone Number';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
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
              title: Text(_stepTitle(), style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
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
                            if (_step == _RecoveryStep.emailEntry)
                              AccountRecoveryEmailStep(
                                formKey: _emailFormKey,
                                emailController: _emailCtl,
                                loading: _loading,
                                onContinue: _continueWithEmail,
                                emailValidator: _validateEmail,
                              ),
                            if (_step == _RecoveryStep.emailOtp)
                              AccountRecoveryOtpStep(
                                otpController: _otpCtl,
                                otpError: _otpError,
                                loading: _loading,
                                isOtpComplete: _isOtpComplete,
                                onVerify: _verifyEmailOtp,
                                onResend: _sendEmailOtp,
                              ),
                            if (_step == _RecoveryStep.newPhone)
                              AccountRecoveryPhoneStep(
                                formKey: _phoneFormKey,
                                newPhoneController: _newPhoneCtl,
                                confirmPhoneController: _confirmPhoneCtl,
                                phoneError: _phoneError,
                                loading: _loading,
                                canContinue: _canContinuePhoneStep,
                                onContinue: _continueWithNewPhone,
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
