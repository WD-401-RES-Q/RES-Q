import 'package:flutter/material.dart';

import '../constants/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

class RegistrationProgressBar extends StatelessWidget {
  const RegistrationProgressBar({
    super.key,
    required this.currentStep,
    this.totalSteps = 4,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final step = currentStep.clamp(1, totalSteps);
    return Row(
      children: List<Widget>.generate(totalSteps, (index) {
        final isFilled = index < step;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: isFilled
                  ? AppTheme.appRed
                  : AppTheme.appBlack.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    this.count = 4,
    required this.filled,
    this.error = false,
  });

  final int count;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final filledCount = filled.clamp(0, count);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (index) {
        final isFilled = index < filledCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 16 : 14,
          height: isFilled ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (error ? Colors.red : AppTheme.appRed)
                : Colors.transparent,
            border: Border.all(
              color: error
                  ? Colors.red
                  : AppTheme.appBlack.withValues(alpha: 0.5),
              width: 1.4,
            ),
          ),
        );
      }),
    );
  }
}

class PendingModal extends StatelessWidget {
  const PendingModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.appBlack.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.paddingLarge),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppTheme.appRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                size: 34,
                color: AppTheme.appRed,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.paddingMedium),
          Text(
            'Account Under Review',
            textAlign: TextAlign.center,
            style: AppTextStyles.authPageTitle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: AppDimensions.paddingSmall),
          Text(
            'Your account is still being reviewed by our team. You\'ll be notified once it\'s approved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 14,
              color: AppTheme.appBlack.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppDimensions.paddingLarge),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.appRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text('Got it', style: AppTextStyles.authButton),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showPendingModal(
  BuildContext context, {
  required VoidCallback onDismiss,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: AppTheme.appOffWhite,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const PendingModal(),
  );
  onDismiss();
}
