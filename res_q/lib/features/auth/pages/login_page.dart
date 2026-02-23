import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/auth_api_service.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtl = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  String _selectedCountryCode = '+63';

  bool _loading = false;
  String? _inlineError;

  String get _phoneDigits => _phoneCtl.text.replaceAll(RegExp(r'\D'), '');

  String get _fullPhoneNumber => '$_selectedCountryCode$_phoneDigits';

  bool get _canContinue => _phoneDigits.length == 10 && !_loading;

  @override
  void initState() {
    super.initState();
    _phoneCtl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneCtl.removeListener(_onPhoneChanged);
    _phoneCtl.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    if (!mounted) return;
    setState(() {
      if (_inlineError != null && _phoneDigits.length <= 10) {
        _inlineError = null;
      }
    });
  }

  Future<void> _handleContinue() async {
    if (!_canContinue) return;

    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      final status = await AuthApiService.instance.checkPhone(
        phone: _fullPhoneNumber,
      );

      if (!mounted) return;

      switch (status) {
        case PhoneCheckStatus.approved:
          await Navigator.pushNamed(
            context,
            '/login/pin',
            arguments: <String, dynamic>{'phone': _fullPhoneNumber},
          );
          break;
        case PhoneCheckStatus.pending:
          await showPendingModal(
            context,
            onDismiss: () {
              if (!mounted) return;
              _phoneFocusNode.requestFocus();
            },
          );
          break;
        case PhoneCheckStatus.notFound:
          await AuthApiService.instance.resendOtp(phone: _fullPhoneNumber);
          if (!mounted) return;
          await Navigator.pushNamed(
            context,
            '/login/verify',
            arguments: <String, dynamic>{
              'phone': _fullPhoneNumber,
              'mode': 'register',
            },
          );
          break;
      }
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inlineError = 'Unable to continue. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
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
              title: Text('WELCOME', style: AppTextStyles.authPageTitle),
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Enter your phone number to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.appBlack.withValues(
                                  alpha: 0.72,
                                ),
                                fontFamily: 'RobotoCondensed',
                              ),
                            ),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            CustomPhoneField(
                              controller: _phoneCtl,
                              focusNode: _phoneFocusNode,
                              enableCountrySelector: true,
                              countryCode: _selectedCountryCode,
                              countryCodeOptions: const ['+63'],
                              onCountryCodeChanged: (code) {
                                if (code == null ||
                                    code == _selectedCountryCode) {
                                  return;
                                }
                                setState(() => _selectedCountryCode = code);
                              },
                              validator: validatePhilippinePhone,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                            ),
                            RegistrationValidationMessage(
                              message: _inlineError,
                              reserveSpace: false,
                            ),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            ResqPillButton(
                              label: 'Continue',
                              onPressed: _canContinue ? _handleContinue : null,
                              loading: _loading,
                              height: 48,
                              radius: 30,
                              backgroundColor: AppTheme.appRed,
                              disabledColor: AppTheme.appBlack.withValues(
                                alpha: 0.25,
                              ),
                              shadowColor: AppTheme.appRed.withValues(
                                alpha: 0.3,
                              ),
                              shadowBlurRadius: 16,
                              shadowOffset: const Offset(0, 4),
                              textStyle: AppTextStyles.authButton,
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
