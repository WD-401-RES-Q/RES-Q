import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/auth_api_service.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class LoginVerifyPage extends StatefulWidget {
  const LoginVerifyPage({super.key});

  @override
  State<LoginVerifyPage> createState() => _LoginVerifyPageState();
}

class _LoginVerifyPageState extends State<LoginVerifyPage>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  Timer? _resendTimer;
  int _resendSeconds = 30;
  bool _loading = false;
  bool _argsInitialized = false;
  String? _inlineError;

  String _phone = '';
  String _mode = 'register';

  bool get _isRegisterMode => _mode == 'register';

  String get _otpCode => _otpControllers.map((ctl) => ctl.text).join();

  bool get _canVerify => _otpCode.length == 6 && !_loading;

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
    _startResendTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = (args?['phone'] as String? ?? '').trim();
    _mode = (args?['mode'] as String? ?? 'register').trim();
    if (_phone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _shakeController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  String _formatPhoneDisplay(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    String localDigits = digits;
    if (localDigits.startsWith('63') && localDigits.length >= 12) {
      localDigits = localDigits.substring(2);
    } else if (localDigits.startsWith('0') && localDigits.length == 11) {
      localDigits = localDigits.substring(1);
    }
    if (localDigits.length == 10) {
      return '+63 ${localDigits.substring(0, 3)}-${localDigits.substring(3, 6)}-${localDigits.substring(6)}';
    }
    return phone;
  }

  void _onOtpChanged(int index, String value) {
    final sanitized = value.replaceAll(RegExp(r'\D'), '');
    if (sanitized != value) {
      _otpControllers[index].text = sanitized;
      _otpControllers[index].selection = TextSelection.collapsed(
        offset: sanitized.length,
      );
      return;
    }

    if (sanitized.length > 1) {
      final keep = sanitized.substring(sanitized.length - 1);
      _otpControllers[index].text = keep;
      _otpControllers[index].selection = const TextSelection.collapsed(
        offset: 1,
      );
    }

    if (sanitized.isNotEmpty && index < _otpFocusNodes.length - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (sanitized.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }

    if (_inlineError != null) {
      setState(() => _inlineError = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _triggerInvalidCode([String message = 'Incorrect code']) async {
    setState(() {
      _inlineError = message;
    });
    _shakeController.forward(from: 0);
    for (final controller in _otpControllers) {
      controller.clear();
    }
    if (_otpFocusNodes.isNotEmpty) {
      _otpFocusNodes.first.requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    if (!_canVerify || _phone.isEmpty) return;

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      await AuthApiService.instance.verifyOtp(phone: _phone, otp: _otpCode);
      if (!mounted) return;

      if (_isRegisterMode) {
        Navigator.pushNamed(
          context,
          '/login/register',
          arguments: <String, dynamic>{'phone': _phone},
        );
        return;
      }

      Navigator.pushNamed(
        context,
        '/login/create-pin',
        arguments: <String, dynamic>{'phone': _phone, 'mode': 'reset_pin'},
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      await _triggerInvalidCode(
        e.message.isEmpty ? 'Incorrect code' : e.message,
      );
    } catch (_) {
      if (!mounted) return;
      await _triggerInvalidCode('Incorrect code');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0 || _loading || _phone.isEmpty) return;

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      await AuthApiService.instance.resendOtp(phone: _phone);
      if (!mounted) return;
      _startResendTimer();
      AppSnackBar.show(context, 'Code sent.', type: AppSnackBarType.success);
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Unable to resend code.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildOtpBox(int index) {
    final value = _otpControllers[index].text;
    final hasValue = value.isNotEmpty;
    final hasError = _inlineError != null;

    return SizedBox(
      width: 44,
      height: 56,
      child: Container(
        decoration: registrationFieldDecoration(
          hasError: hasError,
          isValid: hasValue,
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (value) => _onOtpChanged(index, value),
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
              title: Text('VERIFY CODE', style: AppTextStyles.authPageTitle),
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
                          if (_isRegisterMode) ...[
                            const RegistrationProgressBar(currentStep: 1),
                            const SizedBox(height: AppDimensions.paddingLarge),
                          ],
                          Text(
                            'We sent a 6-digit code to ${_formatPhoneDisplay(_phone)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.appBlack.withValues(alpha: 0.74),
                              fontFamily: 'RobotoCondensed',
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
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List<Widget>.generate(6, (index) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: index == 5 ? 0 : 8,
                                  ),
                                  child: _buildOtpBox(index),
                                );
                              }),
                            ),
                          ),
                          RegistrationValidationMessage(
                            message: _inlineError,
                            reserveSpace: false,
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),
                          ResqPillButton(
                            label: 'Verify Code',
                            onPressed: _canVerify ? _verifyCode : null,
                            loading: _loading,
                            height: 48,
                            radius: 30,
                            backgroundColor: AppTheme.appRed,
                            disabledColor: AppTheme.appBlack.withValues(
                              alpha: 0.25,
                            ),
                            shadowColor: AppTheme.appRed.withValues(alpha: 0.3),
                            shadowBlurRadius: 16,
                            shadowOffset: const Offset(0, 4),
                            textStyle: AppTextStyles.authButton,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),
                          TextButton(
                            onPressed: (_resendSeconds == 0 && !_loading)
                                ? _resendCode
                                : null,
                            child: Text(
                              _resendSeconds == 0
                                  ? 'Resend code'
                                  : 'Resend code in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _resendSeconds == 0
                                    ? AppTheme.appRed
                                    : AppTheme.appBlack.withValues(alpha: 0.45),
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
