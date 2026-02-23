import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/auth_widgets.dart';

class LoginSubmittedPage extends StatelessWidget {
  const LoginSubmittedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                title: Text(
                  'ACCOUNT SUBMITTED',
                  style: AppTextStyles.authPageTitle,
                ),
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
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: AppTheme.appRed.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 52,
                              color: AppTheme.appRed,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),
                          Text(
                            'You\'re all set!',
                            style: AppTextStyles.authPageTitle.copyWith(
                              fontSize: 28,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppDimensions.paddingSmall),
                          Text(
                            'Your account has been submitted for review. We\'ll notify you once it\'s approved.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.appBlack.withValues(alpha: 0.75),
                              fontFamily: 'RobotoCondensed',
                              height: 1.4,
                            ),
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
      ),
    );
  }
}
