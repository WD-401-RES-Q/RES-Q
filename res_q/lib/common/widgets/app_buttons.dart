import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../constants/app_dimensions.dart';

class ResqPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final double radius;
  final double? width;
  final Color backgroundColor;
  final Color disabledColor;
  final Color shadowColor;
  final TextStyle? textStyle;

  const ResqPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.height = 48,
    this.radius = 30,
    this.width,
    this.backgroundColor = AppTheme.appOffYellow,
    this.disabledColor = const Color(0xFFBDBDBD),
    this.shadowColor = const Color(0x66000000),
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 4,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (loading || onPressed == null) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: disabledColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: textStyle ?? AppTextStyles.authButton,
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// Back button style variants
enum ResqBackButtonStyle {
  /// White background with dark icon and shadow (default)
  standard,

  /// Red brand background with white icon
  branded,

  /// Transparent with red icon and subtle border
  outline,

  /// Minimal ghost style with no background
  ghost,
}

class ResqBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final double iconSize;
  final double radius;
  final List<BoxShadow>? boxShadow;
  final ResqBackButtonStyle style;

  const ResqBackButton({
    super.key,
    this.onPressed,
    this.size = 44,
    this.backgroundColor,
    this.iconColor,
    this.iconSize = AppDimensions.iconMedium,
    this.radius = AppDimensions.radiusMedium,
    this.boxShadow,
    this.style = ResqBackButtonStyle.standard,
  });

  /// Creates a branded back button with red background
  const ResqBackButton.branded({
    super.key,
    this.onPressed,
    this.size = 44,
    this.iconSize = AppDimensions.iconMedium,
    this.radius = AppDimensions.radiusMedium,
  }) : style = ResqBackButtonStyle.branded,
       backgroundColor = null,
       iconColor = null,
       boxShadow = null;

  /// Creates an outline back button with red border
  const ResqBackButton.outline({
    super.key,
    this.onPressed,
    this.size = 44,
    this.iconSize = AppDimensions.iconMedium,
    this.radius = AppDimensions.radiusMedium,
  }) : style = ResqBackButtonStyle.outline,
       backgroundColor = null,
       iconColor = null,
       boxShadow = null;

  /// Creates a ghost back button with no background
  const ResqBackButton.ghost({
    super.key,
    this.onPressed,
    this.size = 44,
    this.iconSize = AppDimensions.iconMedium,
    this.radius = AppDimensions.radiusMedium,
  }) : style = ResqBackButtonStyle.ghost,
       backgroundColor = null,
       iconColor = null,
       boxShadow = null;

  Color _getBackgroundColor() {
    if (backgroundColor != null) return backgroundColor!;
    switch (style) {
      case ResqBackButtonStyle.standard:
        return Colors.white;
      case ResqBackButtonStyle.branded:
        return AppTheme.appRed;
      case ResqBackButtonStyle.outline:
      case ResqBackButtonStyle.ghost:
        return Colors.transparent;
    }
  }

  Color _getIconColor() {
    if (iconColor != null) return iconColor!;
    switch (style) {
      case ResqBackButtonStyle.standard:
        return AppTheme.appBlack;
      case ResqBackButtonStyle.branded:
        return Colors.white;
      case ResqBackButtonStyle.outline:
      case ResqBackButtonStyle.ghost:
        return AppTheme.appRed;
    }
  }

  List<BoxShadow> _getBoxShadow() {
    if (boxShadow != null) return boxShadow!;
    switch (style) {
      case ResqBackButtonStyle.standard:
        return [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
      case ResqBackButtonStyle.branded:
        return [
          BoxShadow(
            color: AppTheme.appRed.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];
      case ResqBackButtonStyle.outline:
      case ResqBackButtonStyle.ghost:
        return [];
    }
  }

  Border? _getBorder() {
    switch (style) {
      case ResqBackButtonStyle.outline:
        return Border.all(color: AppTheme.appRed.withOpacity(0.3), width: 1.5);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBackgroundColor();
    final fgColor = _getIconColor();
    final shadow = _getBoxShadow();
    final border = _getBorder();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        splashColor: style == ResqBackButtonStyle.branded
            ? Colors.white.withOpacity(0.2)
            : AppTheme.appRed.withOpacity(0.1),
        highlightColor: style == ResqBackButtonStyle.branded
            ? Colors.white.withOpacity(0.1)
            : AppTheme.appRed.withOpacity(0.05),
        onTap: onPressed ?? () => Navigator.pop(context),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radius),
            border: border,
            boxShadow: shadow,
          ),
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: fgColor,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class PinNumpad extends StatelessWidget {
  final ValueChanged<String> onKeyTap;
  final bool enabled;
  final double buttonSize;
  final double gap;
  final Color backgroundColor;
  final Color actionBackgroundColor;
  final Color textColor;
  final Color? borderColor;
  final TextStyle? textStyle;
  final TextStyle? actionTextStyle;
  final bool showBiometrics;
  final VoidCallback? onBiometricsTap;

  const PinNumpad({
    super.key,
    required this.onKeyTap,
    this.enabled = true,
    this.buttonSize = 70,
    this.gap = 12,
    this.backgroundColor = AppColors.appOffWhite,
    this.actionBackgroundColor = AppColors.appOffWhite,
    this.textColor = AppColors.appBlack,
    this.borderColor,
    this.textStyle,
    this.actionTextStyle,
    this.showBiometrics = false,
    this.onBiometricsTap,
  });

  Widget _buildButton(
    String value, {
    bool isAction = false,
    bool isBiometrics = false,
  }) {
    final resolvedBorderColor = borderColor ?? textColor.withOpacity(0.3);
    final resolvedStyle = isAction
        ? (actionTextStyle ??
              TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'Roboto',
              ))
        : (textStyle ??
              TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'Roboto',
              ));

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: ElevatedButton(
        onPressed: enabled
            ? (isBiometrics ? onBiometricsTap : () => onKeyTap(value))
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isAction ? actionBackgroundColor : backgroundColor,
          foregroundColor: textColor,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: resolvedBorderColor, width: 1),
          ),
          padding: EdgeInsets.zero,
        ),
        child: isBiometrics
            ? Icon(Icons.fingerprint, size: 32, color: textColor)
            : Text(value, style: resolvedStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton('1'),
            SizedBox(width: gap),
            _buildButton('2'),
            SizedBox(width: gap),
            _buildButton('3'),
          ],
        ),
        SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton('4'),
            SizedBox(width: gap),
            _buildButton('5'),
            SizedBox(width: gap),
            _buildButton('6'),
          ],
        ),
        SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton('7'),
            SizedBox(width: gap),
            _buildButton('8'),
            SizedBox(width: gap),
            _buildButton('9'),
          ],
        ),
        SizedBox(height: gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            showBiometrics
                ? _buildButton('', isAction: true, isBiometrics: true)
                : _buildButton('C', isAction: true),
            SizedBox(width: gap),
            _buildButton('0'),
            SizedBox(width: gap),
            _buildButton('⌫', isAction: true),
          ],
        ),
      ],
    );
  }
}
