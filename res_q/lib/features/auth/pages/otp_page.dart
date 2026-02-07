import 'package:flutter/material.dart';
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
  final TextEditingController _otpCtl = TextEditingController();
  bool _loading = false;
  bool _argsInitialized = false;

  String? _verificationId;
  String? _phoneNumber;
  Map<String, dynamic>? _userData;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _verificationId = args['verificationId'] as String?;
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
    }

    final hasRequiredArgs =
        _verificationId != null &&
        _phoneNumber != null &&
        _phoneNumber!.isNotEmpty &&
        _userData != null;
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
    _otpCtl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verificationId == null || _phoneNumber == null || _userData == null) {
      AppSnackBar.show(
        context,
        'Registration session expired. Please start again.',
        type: AppSnackBarType.warning,
      );
      Navigator.pushNamedAndRemoveUntil(context, '/register', (_) => false);
      return;
    }

    final code = _otpCtl.text.trim();
    if (code.length < 6) {
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
        _otpCtl.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      if (mounted) {
        AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
        _otpCtl.clear();
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
            // Fixed header with back button and logo (matching registration page)
            Padding(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingMedium,
                left: AppDimensions.paddingXLarge,
                right: AppDimensions.paddingXLarge,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ResqBackButton.outline(),
                  const ResqLogo(fontSize: 53),
                  const SizedBox(width: 44), // Balance the row
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.paddingSmall),
            Text('VERIFY OTP', style: AppTextStyles.authPageTitle),
            const SizedBox(height: AppDimensions.paddingSmall),

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
                              'Enter the 6 digit code sent to your\nphone number.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.appBlack,
                                fontFamily: 'RobotoCondensed',
                              ),
                            ),

                            const SizedBox(height: AppDimensions.paddingXLarge),

                            // OTP input
                            SizedBox(
                              width: 220,
                              child: TextField(
                                controller: _otpCtl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  letterSpacing: 8,
                                  color: AppTheme.appBlack,
                                ),
                                maxLength: 6,
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: '• • • •',
                                  hintStyle: const TextStyle(
                                    fontSize: 22,
                                    color: Colors.grey,
                                    letterSpacing: 8,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 16,
                                  ),
                                  filled: true,
                                  fillColor: AppTheme.appOffWhite,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMedium,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppTheme.appBlack,
                                      width: 1.5,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMedium,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppTheme.appBlack,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMedium,
                                    ),
                                    borderSide: BorderSide(
                                      color: AppTheme.appRed,
                                      width: 1.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: AppDimensions.paddingXLarge),

                            // VERIFY button using ResqPillButton
                            ResqPillButton(
                              label: 'VERIFY',
                              onPressed: _loading ? null : _verify,
                              loading: _loading,
                            ),

                            const SizedBox(height: AppDimensions.paddingMedium),

                            TextButton(
                              onPressed: _loading ? null : _resend,
                              child: Text(
                                'Resend code',
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
