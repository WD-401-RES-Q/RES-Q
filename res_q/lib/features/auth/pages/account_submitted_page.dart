import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_widgets.dart';

class AccountSubmittedPage extends StatelessWidget {
  const AccountSubmittedPage({super.key});

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
              title: Text('ACCOUNT SUBMITTED', style: AppTextStyles.authPageTitle),
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
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.appRed.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            size: 42,
                            color: AppTheme.appRed,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.paddingLarge),
                        Text(
                          'Your account has been submitted for admin review.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.appBlack.withValues(alpha: 0.85),
                            fontFamily: 'RobotoCondensed',
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.paddingSmall),
                        Text(
                          'You can log in after your account is approved.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.appBlack.withValues(alpha: 0.7),
                            fontFamily: 'RobotoCondensed',
                          ),
                        ),
                        const SizedBox(height: AppDimensions.paddingXLarge),
                        ResqPillButton(
                          label: 'BACK TO LOGIN',
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
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

