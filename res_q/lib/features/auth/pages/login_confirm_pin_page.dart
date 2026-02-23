import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/auth_api_service.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class LoginConfirmPinPage extends StatefulWidget {
  const LoginConfirmPinPage({super.key});

  @override
  State<LoginConfirmPinPage> createState() => _LoginConfirmPinPageState();
}

class _LoginConfirmPinPageState extends State<LoginConfirmPinPage>
    with SingleTickerProviderStateMixin {
  bool _argsInitialized = false;

  String _phone = '';
  String _mode = 'register';
  String _sourcePin = '';
  String? _userId;
  String? _name;
  String? _email;

  String _confirmPin = '';
  bool _loading = false;
  String? _inlineError;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  bool get _isRegisterMode => _mode == 'register';

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
    _phone = (args?['phone'] as String? ?? '').trim();
    _mode = (args?['mode'] as String? ?? 'register').trim();
    _sourcePin = (args?['pin'] as String? ?? '').trim();
    _userId = (args?['userId'] as String?)?.trim();
    _name = (args?['name'] as String?)?.trim();
    _email = (args?['email'] as String?)?.trim();

    if (_phone.isEmpty || _sourcePin.length != 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _clearConfirmPin() {
    setState(() {
      _confirmPin = '';
    });
  }

  Future<void> _triggerMismatch() async {
    setState(() {
      _inlineError = 'PINs don\'t match';
      _confirmPin = '';
    });
    _shakeController.forward(from: 0);
  }

  void _onNumpadTap(String value) {
    if (_loading) return;
    setState(() {
      _inlineError = null;
      if (value == PinNumpad.clearKey) {
        _confirmPin = '';
        return;
      }
      if (value == PinNumpad.backspaceKey) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
        return;
      }
      if (_confirmPin.length >= 4) return;
      _confirmPin += value;
    });

    if (_confirmPin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _submitConfirmPin();
      });
    }
  }

  Future<void> _submitConfirmPin() async {
    if (_loading || _confirmPin.length != 4) return;
    if (_confirmPin != _sourcePin) {
      await _triggerMismatch();
      return;
    }

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      await AuthApiService.instance.setPin(
        phone: _phone,
        pin: _sourcePin,
        userId: _userId,
        name: _name,
        email: _email,
        resetPin: !_isRegisterMode,
      );

      if (!mounted) return;

      if (_isRegisterMode) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login/submitted',
          (route) => route.settings.name == '/login',
          arguments: <String, dynamic>{'phone': _phone},
        );
        return;
      }

      AppSnackBar.show(
        context,
        'PIN updated successfully.',
        type: AppSnackBarType.success,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login/pin',
        (route) => route.settings.name == '/login',
        arguments: <String, dynamic>{'phone': _phone},
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
      _clearConfirmPin();
      _shakeController.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Unable to save PIN.');
      _clearConfirmPin();
      _shakeController.forward(from: 0);
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
              title: Text('CONFIRM PIN', style: AppTextStyles.authPageTitle),
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
                            const RegistrationProgressBar(currentStep: 4),
                            const SizedBox(height: AppDimensions.paddingLarge),
                          ],
                          Text(
                            'Confirm your PIN',
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
                              filled: _confirmPin.length,
                              error: _inlineError != null,
                            ),
                          ),
                          RegistrationValidationMessage(
                            message: _inlineError,
                            reserveSpace: false,
                          ),
                          const SizedBox(height: AppDimensions.paddingXLarge),
                          PinNumpad(
                            enabled: !_loading,
                            onKeyTap: _onNumpadTap,
                            showBiometrics: false,
                            backgroundColor: AppTheme.appOffWhite,
                            actionBackgroundColor: AppTheme.appOffWhite,
                            textColor: AppTheme.appBlack,
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
