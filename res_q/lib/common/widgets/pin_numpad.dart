import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
  });

  Widget _buildButton(String value, {bool isAction = false}) {
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
        onPressed: enabled ? () => onKeyTap(value) : null,
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
        child: Text(value, style: resolvedStyle),
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
            _buildButton('C', isAction: true),
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
