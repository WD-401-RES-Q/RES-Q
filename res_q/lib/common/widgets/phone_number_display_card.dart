import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PhoneNumberDisplayCard extends StatelessWidget {
  final String phoneText;
  final VoidCallback? onEditTap;
  final String editTooltip;
  final bool showEditIcon;

  const PhoneNumberDisplayCard({
    super.key,
    required this.phoneText,
    this.onEditTap,
    this.editTooltip = 'Change phone number',
    this.showEditIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.appOffWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.appBlack.withValues(alpha: 0.35),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.appBlack.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.phone_android,
                  size: 28,
                  color: AppTheme.appBlack,
                ),
                const SizedBox(width: 14),
                Text(
                  phoneText,
                  style: const TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: AppTheme.appBlack,
                  ),
                ),
              ],
            ),
          ),
          if (showEditIcon)
            IconButton(
              onPressed: onEditTap,
              icon: const Icon(Icons.edit_outlined, color: AppTheme.appBlack),
              tooltip: editTooltip,
            ),
          SizedBox(width: showEditIcon ? 8 : 16),
        ],
      ),
    );
  }
}
