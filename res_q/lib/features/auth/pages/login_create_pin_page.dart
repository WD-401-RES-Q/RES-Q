import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';

class LoginCreatePinPage extends StatefulWidget {
  const LoginCreatePinPage({super.key});

  @override
  State<LoginCreatePinPage> createState() => _LoginCreatePinPageState();
}

class _LoginCreatePinPageState extends State<LoginCreatePinPage> {
  bool _argsInitialized = false;
  String _phone = '';
  String _mode = 'register';
  String? _userId;
  String? _name;
  String? _email;

  String _pin = '';

  bool get _isRegisterMode => _mode == 'register';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = (args?['phone'] as String? ?? '').trim();
    _mode = (args?['mode'] as String? ?? 'register').trim();
    _userId = (args?['userId'] as String?)?.trim();
    _name = (args?['name'] as String?)?.trim();
    _email = (args?['email'] as String?)?.trim();

    if (_phone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pop(context);
      });
    }
  }

  void _onNumpadTap(String value) {
    setState(() {
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
        Navigator.pushNamed(
          context,
          '/login/confirm-pin',
          arguments: <String, dynamic>{
            'phone': _phone,
            'mode': _mode,
            'userId': _userId,
            'name': _name,
            'email': _email,
            'pin': _pin,
          },
        );
      });
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
              title: Text('CREATE PIN', style: AppTextStyles.authPageTitle),
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
                            const RegistrationProgressBar(currentStep: 3),
                            const SizedBox(height: AppDimensions.paddingLarge),
                          ],
                          Text(
                            'Set your 4-digit PIN',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.appBlack.withValues(alpha: 0.84),
                              fontFamily: 'RobotoCondensed',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),
                          PinDots(filled: _pin.length),
                          const SizedBox(height: AppDimensions.paddingXLarge),
                          PinNumpad(
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
