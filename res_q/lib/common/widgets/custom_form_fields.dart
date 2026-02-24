import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

const double _validationTopSpacing = 6;
const double _validationSlotHeight = 18;
const Color _validGreen = Color(0xFF00A458);

class RegistrationFieldTokens {
  static const double radius = 12;
  static const double fieldHeight = 48;
  static const double uploadFieldHeight = 72;
  static const double borderWidth = 0.7;
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    vertical: 14,
    horizontal: 16,
  );
  static const TextStyle labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppTheme.appBlack,
  );
  static const TextStyle valueStyle = TextStyle(
    fontSize: 13,
    color: AppTheme.appBlack,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle errorStyle = TextStyle(
    fontSize: 11,
    color: Colors.red,
    fontWeight: FontWeight.w500,
  );
  static TextStyle hintStyle({double alpha = 0.5}) => TextStyle(
    fontSize: 12,
    color: AppTheme.appBlack.withValues(alpha: alpha),
    fontWeight: FontWeight.w400,
  );
}

BoxDecoration registrationFieldDecoration({
  required bool hasError,
  bool isValid = false,
  double radius = RegistrationFieldTokens.radius,
  Color fillColor = AppTheme.appOffWhite,
}) {
  final borderColor = hasError
      ? Colors.red
      : (isValid ? _validGreen : AppTheme.appBlack.withValues(alpha: 0.35));
  final shadowColor = hasError
      ? Colors.red.withValues(alpha: 0.18)
      : (isValid
            ? _validGreen.withValues(alpha: 0.16)
            : AppTheme.appBlack.withValues(alpha: 0.1));

  return BoxDecoration(
    color: fillColor,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: borderColor,
      width: RegistrationFieldTokens.borderWidth,
    ),
    boxShadow: [
      BoxShadow(color: shadowColor, blurRadius: 8, offset: const Offset(0, 2)),
    ],
  );
}

InputDecoration registrationInputDecoration({
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: RegistrationFieldTokens.hintStyle(),
    isDense: false,
    contentPadding: RegistrationFieldTokens.contentPadding,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  );
}

enum UploadFieldStatus { none, success, error }

class RegistrationValidationMessage extends StatelessWidget {
  final String? message;
  final bool reserveSpace;
  final bool showIcon;
  final IconData icon;
  final TextStyle style;

  const RegistrationValidationMessage({
    super.key,
    this.message,
    this.reserveSpace = true,
    this.showIcon = true,
    this.icon = Icons.error_outline_rounded,
    this.style = RegistrationFieldTokens.errorStyle,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedMessage = message?.trim();
    final hasMessage = trimmedMessage != null && trimmedMessage.isNotEmpty;

    Widget? content;
    if (hasMessage) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (showIcon) ...[
              Icon(icon, size: 13, color: style.color ?? Colors.red),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                trimmedMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    if (!reserveSpace && content == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: _validationTopSpacing),
      child: reserveSpace
          ? SizedBox(height: _validationSlotHeight, child: content)
          : content,
    );
  }
}

class RegistrationFieldContainer extends StatelessWidget {
  final String label;
  final Widget child;
  final bool hasError;
  final bool isValid;
  final String? errorText;
  final bool reserveErrorSpace;
  final double fieldHeight;
  final Color fillColor;

  const RegistrationFieldContainer({
    super.key,
    required this.label,
    required this.child,
    this.hasError = false,
    this.isValid = false,
    this.errorText,
    this.reserveErrorSpace = true,
    this.fieldHeight = RegistrationFieldTokens.fieldHeight,
    this.fillColor = AppTheme.appOffWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RegistrationFieldTokens.labelStyle),
        const SizedBox(height: 4),
        Container(
          height: fieldHeight,
          clipBehavior: Clip.antiAlias,
          decoration: registrationFieldDecoration(
            hasError: hasError,
            isValid: isValid,
            fillColor: fillColor,
          ),
          child: child,
        ),
        RegistrationValidationMessage(
          message: hasError ? errorText : null,
          reserveSpace: reserveErrorSpace,
        ),
      ],
    );
  }
}

class CustomTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final int minLines;
  final int maxLines;
  final double fieldHeight;

  const CustomTextFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.validator,
    this.autovalidateMode,
    this.keyboardType,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.minLines = 1,
    this.maxLines = 1,
    this.fieldHeight = RegistrationFieldTokens.fieldHeight,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMultiLineField = maxLines > 1 || minLines > 1;

    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        final hasValue = controller.text.trim().isNotEmpty;
        final hasError = state.hasError;
        final isValid = hasValue && !hasError;
        return RegistrationFieldContainer(
          label: label,
          hasError: hasError,
          isValid: isValid,
          errorText: state.errorText,
          fieldHeight: fieldHeight,
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            textAlign: TextAlign.left,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            autofillHints: autofillHints,
            autovalidateMode: AutovalidateMode.disabled,
            textInputAction: textInputAction,
            minLines: isMultiLineField ? minLines : null,
            maxLines: isMultiLineField ? maxLines : 1,
            textCapitalization: textCapitalization,
            onChanged: state.didChange,
            textAlignVertical: TextAlignVertical.center,
            style: RegistrationFieldTokens.valueStyle,
            decoration: registrationInputDecoration(
              hintText: hintText ?? label,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
            ),
          ),
        );
      },
    );
  }
}

class NameCapitalizationFormatter extends TextInputFormatter {
  const NameCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    var capitalizeNext = true;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final isLetter = RegExp(r'[A-Za-z]').hasMatch(char);
      if (isLetter) {
        buffer.write(capitalizeNext ? char.toUpperCase() : char.toLowerCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        if (char == ' ' || char == '-' || char == '\'') {
          capitalizeNext = true;
        }
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }
}

class CustomPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool enableCountrySelector;
  final String countryCode;
  final List<String> countryCodeOptions;
  final ValueChanged<String?>? onCountryCodeChanged;

  const CustomPhoneField({
    super.key,
    required this.controller,
    this.label = 'PHONE NUMBER',
    this.hintText = 'e.g. 912-345-6789',
    this.validator,
    this.autovalidateMode,
    this.autofillHints,
    this.focusNode,
    this.enableCountrySelector = false,
    this.countryCode = '+63',
    this.countryCodeOptions = const ['+63'],
    this.onCountryCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        final hasError = state.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RegistrationFieldTokens.labelStyle),
            const SizedBox(height: 4),
            Container(
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.appOffWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasError ? Colors.red : Colors.black,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.phone_outlined, color: Colors.black),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: enableCountrySelector ? 66 : 40,
                    child: enableCountrySelector
                        ? DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: countryCode,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                              ),
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.appBlack,
                              ),
                              items: countryCodeOptions
                                  .map(
                                    (code) => DropdownMenuItem<String>(
                                      value: code,
                                      child: Text(code),
                                    ),
                                  )
                                  .toList(),
                              onChanged: onCountryCodeChanged,
                            ),
                          )
                        : const Text(
                            '+63',
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.appBlack,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1.5, height: 28, color: Colors.black),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      textAlign: TextAlign.left,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _PhilippinePhoneFormatter(),
                      ],
                      autofillHints: autofillHints,
                      autovalidateMode: AutovalidateMode.disabled,
                      onChanged: state.didChange,
                      style: const TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        color: AppTheme.appBlack,
                      ),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: AppTheme.appBlack.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            RegistrationValidationMessage(
              message: hasError ? state.errorText : null,
              reserveSpace: true,
            ),
          ],
        );
      },
    );
  }
}

class CustomAddressField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final int minLines;
  final int maxLines;
  final double fieldHeight;

  const CustomAddressField({
    super.key,
    required this.controller,
    this.label = 'COMPLETE ADDRESS',
    this.hintText = 'e.g. Blk 3 Lot 2, Brgy. Mabini, QC',
    this.validator,
    this.autovalidateMode,
    this.inputFormatters,
    this.autofillHints,
    this.minLines = 1,
    this.maxLines = 1,
    this.fieldHeight = RegistrationFieldTokens.fieldHeight,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTextFormField(
      controller: controller,
      label: label,
      hintText: hintText,
      validator: validator,
      autovalidateMode: autovalidateMode,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      keyboardType: TextInputType.streetAddress,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      minLines: minLines,
      maxLines: maxLines,
      fieldHeight: fieldHeight,
    );
  }
}

class CustomDropdownField extends StatelessWidget {
  final String label;
  final String hint;
  final List<String> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;
  final bool enabled;
  final double fieldHeight;

  const CustomDropdownField({
    super.key,
    required this.label,
    required this.hint,
    required this.items,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
    this.fieldHeight = RegistrationFieldTokens.fieldHeight,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText?.trim().isNotEmpty ?? false;
    final isValid = value != null && !hasError;

    return RegistrationFieldContainer(
      label: label,
      hasError: hasError,
      isValid: isValid,
      errorText: errorText,
      fieldHeight: fieldHeight,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              hint,
              style: RegistrationFieldTokens.hintStyle(alpha: 0.55),
            ),
          ),
          icon: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.keyboard_arrow_down_rounded),
          ),
          style: RegistrationFieldTokens.valueStyle,
          dropdownColor: AppTheme.appOffWhite,
          borderRadius: BorderRadius.circular(RegistrationFieldTokens.radius),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(item),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class CustomDatePicker extends StatelessWidget {
  final String label;
  final String valueText;
  final bool isPlaceholder;
  final String? helperText;
  final VoidCallback? onChange;
  final bool hasError;
  final bool isValid;
  final String? errorText;

  const CustomDatePicker({
    super.key,
    this.label = 'DATE OF BIRTH',
    required this.valueText,
    this.isPlaceholder = false,
    this.helperText,
    this.onChange,
    this.hasError = false,
    this.isValid = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RegistrationFieldContainer(
          label: label,
          hasError: hasError,
          isValid: isValid,
          errorText: errorText,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: AppTheme.appBlack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  valueText,
                  style: isPlaceholder
                      ? RegistrationFieldTokens.hintStyle(alpha: 0.7)
                      : RegistrationFieldTokens.valueStyle,
                ),
              ),
              TextButton(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppTheme.appRed,
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: _validationTopSpacing),
          Text(
            helperText!,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.appBlack.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class CustomUploadField extends StatelessWidget {
  final String label;
  final Widget preview;
  final bool hasPreview;
  final bool uploading;
  final VoidCallback? onUpload;
  final VoidCallback? onPreviewTap;
  final String? errorText;
  final UploadFieldStatus status;
  final double fieldHeight;
  final bool isRequired;

  const CustomUploadField({
    super.key,
    required this.label,
    required this.preview,
    required this.hasPreview,
    required this.uploading,
    required this.onUpload,
    this.onPreviewTap,
    this.errorText,
    this.status = UploadFieldStatus.none,
    this.fieldHeight = RegistrationFieldTokens.uploadFieldHeight,
    this.isRequired = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasError =
        status == UploadFieldStatus.error ||
        (errorText?.trim().isNotEmpty ?? false);
    final isComplete = status == UploadFieldStatus.success || hasPreview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                isRequired ? '$label (REQUIRED)' : label,
                style: RegistrationFieldTokens.labelStyle,
              ),
            ),
            if (hasError || isComplete) const SizedBox(width: 6),
            if (hasError) const Icon(Icons.cancel, color: Colors.red, size: 16),
            if (!hasError && isComplete)
              const Icon(Icons.check_circle, color: _validGreen, size: 16),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: hasPreview ? onPreviewTap : null,
                child: Container(
                  height: fieldHeight,
                  clipBehavior: Clip.antiAlias,
                  decoration: registrationFieldDecoration(hasError: hasError),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      RegistrationFieldTokens.radius - 2,
                    ),
                    child: hasPreview ? preview : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: uploading ? null : onUpload,
                child: Container(
                  height: fieldHeight,
                  decoration: BoxDecoration(
                    color: uploading ? Colors.grey[400] : AppTheme.appOffYellow,
                    borderRadius: BorderRadius.circular(
                      RegistrationFieldTokens.radius,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.appBlack.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: uploading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        RegistrationValidationMessage(message: hasError ? errorText : null),
      ],
    );
  }
}

class _PhilippinePhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'\D'), '');

    while (text.length > 10) {
      if (text.startsWith('0')) {
        text = text.substring(1);
        continue;
      }
      if (text.startsWith('63')) {
        text = text.substring(2);
        continue;
      }
      break;
    }

    if (text.length > 10) {
      text = text.substring(0, 10);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 10; i++) {
      if (i == 3 || i == 6) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
