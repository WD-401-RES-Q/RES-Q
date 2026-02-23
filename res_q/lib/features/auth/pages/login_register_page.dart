import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/auth_api_service.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_flow_widgets.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class LoginRegisterPage extends StatefulWidget {
  const LoginRegisterPage({super.key});

  @override
  State<LoginRegisterPage> createState() => _LoginRegisterPageState();
}

class _LoginRegisterPageState extends State<LoginRegisterPage> {
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _emailCtl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _argsInitialized = false;
  String _phone = '';
  String? _inlineError;

  bool get _canContinue => _nameCtl.text.trim().isNotEmpty && !_loading;

  @override
  void initState() {
    super.initState();
    _nameCtl.addListener(_onFieldChanged);
    _emailCtl.addListener(_onFieldChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = (args?['phone'] as String? ?? '').trim();
    if (_phone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _nameCtl.removeListener(_onFieldChanged);
    _emailCtl.removeListener(_onFieldChanged);
    _nameCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {
      _inlineError = null;
    });
  }

  String? _validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Full name is required';
    }
    if (trimmed.length < 2) {
      return 'Enter a valid full name';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(trimmed)) {
      return 'Enter a valid email';
    }
    return null;
  }

  Future<void> _createAccount() async {
    if (!_canContinue || _phone.isEmpty) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      final userId = await AuthApiService.instance.register(
        phone: _phone,
        name: _nameCtl.text.trim(),
        email: _emailCtl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/login/create-pin',
        arguments: <String, dynamic>{
          'phone': _phone,
          'userId': userId,
          'name': _nameCtl.text.trim(),
          'email': _emailCtl.text.trim(),
          'mode': 'register',
        },
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = 'Unable to create account.');
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
              title: Text('REGISTER', style: AppTextStyles.authPageTitle),
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
                            const RegistrationProgressBar(currentStep: 2),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            CustomTextFormField(
                              controller: _nameCtl,
                              label: 'FULL NAME',
                              hintText: 'e.g. Juan Dela Cruz',
                              validator: _validateName,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              textCapitalization: TextCapitalization.words,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(80),
                                NameCapitalizationFormatter(),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.paddingMedium),
                            CustomTextFormField(
                              controller: _emailCtl,
                              label: 'EMAIL (OPTIONAL)',
                              hintText: 'e.g. juan@email.com',
                              validator: _validateEmail,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(120),
                              ],
                            ),
                            RegistrationValidationMessage(
                              message: _inlineError,
                              reserveSpace: false,
                            ),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            ResqPillButton(
                              label: 'Create Account',
                              onPressed: _canContinue ? _createAccount : null,
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
