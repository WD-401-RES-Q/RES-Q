import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_widgets.dart';

class LoginSuccessPage extends StatelessWidget {
  const LoginSuccessPage({super.key});

  String _formatPhoneForDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63')) {
      digits = digits.substring(2);
    }
    if (digits.length == 10) {
      return '+63 ${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String? phoneNumber;
    if (args is Map) {
      phoneNumber = args['phoneNumber'] as String?;
    }

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
              title: Text('WELCOME BACK', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingXLarge,
                      vertical: AppDimensions.paddingMedium,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'You are now logged in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.appBlack.withValues(alpha: 0.8),
                            fontFamily: 'RobotoCondensed',
                          ),
                        ),
                        if (phoneNumber != null && phoneNumber.isNotEmpty) ...[
                          const SizedBox(height: AppDimensions.paddingLarge),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.appOffWhite,
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusMedium,
                              ),
                              border: Border.all(
                                color: AppTheme.appBlack.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.phone_android,
                                  color: AppTheme.appBlack,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _formatPhoneForDisplay(phoneNumber),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: AppTheme.appBlack,
                                    fontFamily: 'RobotoCondensed',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppDimensions.paddingXLarge),
                        ResqPillButton(
                          label: 'CONTINUE',
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/main',
                            (_) => false,
                          ),
                          backgroundColor: AppTheme.appRed,
                          shadowColor: AppTheme.appRed.withValues(alpha: 0.3),
                          shadowBlurRadius: 8,
                          shadowOffset: const Offset(0, 3),
                        ),
                      ],
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

