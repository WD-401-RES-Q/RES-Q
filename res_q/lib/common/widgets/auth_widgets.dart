import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../theme/app_theme.dart';
import 'app_snackbar.dart';
import 'custom_form_fields.dart';

const TextAlignVertical _fieldTextAlignVertical = TextAlignVertical.center;

/// Phone number formatter for contact number inputs
class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('-', '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length && i < 11; i++) {
      if (i == 4 || i == 7) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    final string = buffer.toString();
    return TextEditingValue(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

/// RES-Q Logo Widget
class ResqLogo extends StatelessWidget {
  final double fontSize;

  const ResqLogo({super.key, this.fontSize = 26});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/logo/RES-Q_LOGO.svg',
      height: fontSize,
    );
  }
}

/// Shared top header layout for pages that display the RESQ logo.
/// Keeps logo alignment and vertical spacing consistent across screens.
class ResqLogoHeader extends StatelessWidget {
  final Widget? leading;
  final Widget? trailing;
  final Widget? title;
  final EdgeInsetsGeometry padding;
  final double logoSize;
  final double sideSlotWidth;
  final double titleSpacing;
  final double bottomSpacing;
  final double logoRowHeight;

  const ResqLogoHeader({
    super.key,
    this.leading,
    this.trailing,
    this.title,
    this.padding = const EdgeInsets.only(top: 12, left: 24, right: 24),
    this.logoSize = 40,
    this.sideSlotWidth = 56,
    this.titleSpacing = 8,
    this.bottomSpacing = 12,
    this.logoRowHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          SizedBox(
            height: logoRowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: sideSlotWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leading ?? const SizedBox.shrink(),
                  ),
                ),
                Expanded(
                  child: Center(child: ResqLogo(fontSize: logoSize)),
                ),
                SizedBox(
                  width: sideSlotWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          if (title != null) ...[
            SizedBox(height: titleSpacing),
            Center(child: title!),
          ],
          if (bottomSpacing > 0) SizedBox(height: bottomSpacing),
        ],
      ),
    );
  }
}

/// Custom Text Field for auth pages
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final Iterable<String>? autofillHints;
  final TextStyle? labelTextStyle;
  final TextStyle? textStyle;
  final TextStyle? hintTextStyle;
  final bool reserveErrorSpace;
  final double reservedErrorHeight;
  final TextStyle? errorTextStyle;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.autovalidateMode,
    this.autofillHints,
    this.labelTextStyle,
    this.textStyle,
    this.hintTextStyle,
    this.reserveErrorSpace = false,
    this.reservedErrorHeight = 30,
    this.errorTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    const double fieldRadius = 12;
    const Color validGreen = Color(0xFF00A458);

    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        final errorText = state.errorText ?? '';
        final showError = state.hasError && errorText.trim().isNotEmpty;
        const defaultErrorTextStyle = TextStyle(
          fontSize: 11,
          color: Colors.red,
          fontWeight: FontWeight.w500,
        );
        const defaultLabelTextStyle = TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.appBlack,
        );
        final effectiveLabelTextStyle = labelTextStyle ?? defaultLabelTextStyle;
        const defaultInputTextStyle = TextStyle(
          fontSize: 13,
          color: AppTheme.appBlack,
          fontWeight: FontWeight.w500,
        );
        final effectiveInputTextStyle = textStyle ?? defaultInputTextStyle;
        final effectiveHintTextStyle =
            hintTextStyle ??
            TextStyle(
              fontSize: 12,
              color: AppTheme.appBlack.withValues(alpha: 0.5),
              fontWeight: FontWeight.w400,
            );
        final effectiveErrorTextStyle = errorTextStyle ?? defaultErrorTextStyle;
        final hasValue = controller.text.trim().isNotEmpty;
        final hasError = state.hasError;
        final isValid = hasValue && !hasError;
        final borderColor = hasError
            ? Colors.red
            : (isValid
                  ? validGreen
                  : AppTheme.appBlack.withValues(alpha: 0.35));
        final shadowColor = hasError
            ? Colors.red.withValues(alpha: 0.18)
            : (isValid
                  ? validGreen.withValues(alpha: 0.16)
                  : AppTheme.appBlack.withValues(alpha: 0.1));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: effectiveLabelTextStyle),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fieldRadius),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextFormField(
                controller: controller,
                obscureText: obscureText,
                textAlign: TextAlign.left,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                autofillHints: autofillHints,
                autovalidateMode: AutovalidateMode.disabled,
                onChanged: (value) => state.didChange(value),
                textAlignVertical: _fieldTextAlignVertical,
                style: effectiveInputTextStyle,
                decoration: InputDecoration(
                  hintText: hintText ?? label,
                  hintStyle: effectiveHintTextStyle,
                  prefixIcon: prefixIcon,
                  suffixIcon: suffixIcon,
                  filled: true,
                  fillColor: AppTheme.appOffWhite,
                  isDense: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  constraints: const BoxConstraints(minHeight: 48),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    borderSide: BorderSide(color: borderColor, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    borderSide: BorderSide(color: borderColor, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    borderSide: BorderSide(color: borderColor, width: 1),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    borderSide: BorderSide(color: Colors.red, width: 1),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    borderSide: BorderSide(color: Colors.red, width: 1),
                  ),
                ),
              ),
            ),
            if (reserveErrorSpace || showError) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: reserveErrorSpace ? reservedErrorHeight : null,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    showError ? errorText : ' ',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: effectiveErrorTextStyle.copyWith(
                      color: showError
                          ? (effectiveErrorTextStyle.color ?? Colors.red)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// ID Photo Upload Widget
class IdPhotoUploadWidget extends StatelessWidget {
  final String? idPhotoPath;
  final bool uploadingPhoto;
  final VoidCallback onUpload;

  const IdPhotoUploadWidget({
    super.key,
    required this.idPhotoPath,
    required this.uploadingPhoto,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUBMIT PHOTO OF VALID ID',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.appBlack,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Center(
                  child: Text(
                    idPhotoPath == null
                        ? '(Required) UPLOAD GOVERNMENT ID'
                        : '? ID UPLOADED',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: uploadingPhoto ? null : onUpload,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: uploadingPhoto
                        ? Colors.grey[400]
                        : AppTheme.appOffYellow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: uploadingPhoto
                        ? const SizedBox(
                            height: 30,
                            width: 30,
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
                            size: 32,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Date of Birth Input Widget
class DateOfBirthInput extends StatelessWidget {
  final TextEditingController monthController;
  final TextEditingController dayController;
  final TextEditingController yearController;
  final String? Function(String?)? monthValidator;
  final String? Function(String?)? dayValidator;
  final String? Function(String?)? yearValidator;
  final AutovalidateMode? autovalidateMode;

  const DateOfBirthInput({
    super.key,
    required this.monthController,
    required this.dayController,
    required this.yearController,
    this.monthValidator,
    this.dayValidator,
    this.yearValidator,
    this.autovalidateMode,
  });

  InputDecoration _fieldDecoration(
    String label, {
    bool hasError = false,
    bool isValid = false,
  }) {
    const double fieldRadius = 12;
    const Color validGreen = Color(0xFF00A458);
    final enabledColor = isValid ? validGreen : Colors.black;
    final focusedColor = isValid ? validGreen : AppTheme.appRed;

    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(
        fontSize: 12,
        color: AppTheme.appBlack.withValues(alpha: 0.5),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: AppTheme.appOffWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: enabledColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: enabledColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: focusedColor, width: 1.8),
      ),
      errorText: hasError ? '' : null,
      errorStyle: const TextStyle(fontSize: 0, height: 0),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      autovalidateMode: autovalidateMode,
      validator: (_) {
        final monthError = monthValidator?.call(monthController.text);
        final dayError = dayValidator?.call(dayController.text);
        final yearError = yearValidator?.call(yearController.text);

        final List<String> parts = [];
        if (monthError != null) parts.add('month');
        if (dayError != null) parts.add('day');
        if (yearError != null) parts.add('year');

        if (parts.isEmpty) return null;
        return 'Invalid ${parts.join(', ')}';
      },
      builder: (state) {
        final monthError = monthValidator?.call(monthController.text);
        final dayError = dayValidator?.call(dayController.text);
        final yearError = yearValidator?.call(yearController.text);
        final monthValid =
            monthError == null && monthController.text.trim().isNotEmpty;
        final dayValid =
            dayError == null && dayController.text.trim().isNotEmpty;
        final yearValid =
            yearError == null && yearController.text.trim().isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DATE OF BIRTH',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.appBlack,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: monthController,
                    textAlign: TextAlign.left,
                    textAlignVertical: _fieldTextAlignVertical,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.birthdayMonth],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'MM',
                      hasError: monthError != null,
                      isValid: monthValid,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: dayController,
                    textAlign: TextAlign.left,
                    textAlignVertical: _fieldTextAlignVertical,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.birthdayDay],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'DD',
                      hasError: dayError != null,
                      isValid: dayValid,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: yearController,
                    textAlign: TextAlign.left,
                    textAlignVertical: _fieldTextAlignVertical,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.birthdayYear],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'YYYY',
                      hasError: yearError != null,
                      isValid: yearValid,
                    ),
                  ),
                ),
              ],
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Text(
                state.errorText ?? '',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Phone number formatter for PH format (9XX-XXX-XXXX)
class PhilippinePhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Accept common autofill formats (e.g. +63..., 09..., spaces/dashes) and
    // normalize to the 10-digit PH mobile format (9XXXXXXXXX) for this field.
    String text = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Autofill/paste sometimes includes prefixes like 0, 63, or even 00.
    // Strip those until we're down to the expected local 10-digit form.
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

    // If extra digits remain (e.g. extensions), keep the first 10 digits.
    if (text.length > 10) {
      text = text.substring(0, 10);
    }
    final buffer = StringBuffer();

    // Format as 9XX-XXX-XXXX (10 digits max)
    for (int i = 0; i < text.length && i < 10; i++) {
      if (i == 3 || i == 6) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    final string = buffer.toString();
    return TextEditingValue(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

/// Phone input field with fixed +63 prefix for Philippine numbers
class PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final String label;
  final Iterable<String>? autofillHints;
  final TextStyle? labelTextStyle;
  final TextStyle? textStyle;
  final TextStyle? hintTextStyle;
  final bool reserveErrorSpace;
  final double reservedErrorHeight;
  final TextStyle? errorTextStyle;

  const PhoneInputField({
    super.key,
    required this.controller,
    this.validator,
    this.autovalidateMode,
    this.label = 'CONTACT NUMBER',
    this.autofillHints,
    this.labelTextStyle,
    this.textStyle,
    this.hintTextStyle,
    this.reserveErrorSpace = false,
    this.reservedErrorHeight = 30,
    this.errorTextStyle,
  });

  /// Get the full phone number with +63 prefix
  String get fullPhoneNumber {
    final digits = controller.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return '+63$digits';
  }

  @override
  Widget build(BuildContext context) {
    const double fieldRadius = 12;
    const Color validGreen = Color(0xFF00A458);

    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        final errorText = state.errorText ?? '';
        final showError = state.hasError && errorText.trim().isNotEmpty;
        const defaultErrorTextStyle = TextStyle(
          fontSize: 11,
          color: Colors.red,
          fontWeight: FontWeight.w500,
        );
        const defaultLabelTextStyle = TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.appBlack,
        );
        final effectiveLabelTextStyle = labelTextStyle ?? defaultLabelTextStyle;
        const defaultInputTextStyle = TextStyle(
          fontSize: 13,
          color: AppTheme.appBlack,
          fontWeight: FontWeight.w500,
        );
        final effectiveInputTextStyle = textStyle ?? defaultInputTextStyle;
        final effectiveHintTextStyle =
            hintTextStyle ??
            TextStyle(
              fontSize: 12,
              color: AppTheme.appBlack.withValues(alpha: 0.5),
            );
        final effectiveErrorTextStyle = errorTextStyle ?? defaultErrorTextStyle;
        final digits = controller.text.replaceAll(RegExp(r'\D'), '');
        final hasValue = digits.isNotEmpty;
        final hasError = state.hasError;
        final isValid = hasValue && !hasError;
        final borderColor = hasError
            ? Colors.red
            : (isValid
                  ? validGreen
                  : AppTheme.appBlack.withValues(alpha: 0.35));
        final shadowColor = hasError
            ? Colors.red
            : (isValid ? validGreen : AppTheme.appBlack);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: effectiveLabelTextStyle),
            const SizedBox(height: 4),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.appOffWhite,
                borderRadius: BorderRadius.circular(fieldRadius),
                border: Border.all(color: borderColor, width: 0.7),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '+63',
                      style: effectiveInputTextStyle.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    width: 1.2,
                    height: 24,
                    color: AppTheme.appBlack.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      textAlign: TextAlign.left,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        PhilippinePhoneFormatter(),
                      ],
                      autovalidateMode: AutovalidateMode.disabled,
                      autofillHints: autofillHints,
                      onChanged: (value) => state.didChange(value),
                      textAlignVertical: _fieldTextAlignVertical,
                      style: effectiveInputTextStyle,
                      decoration: InputDecoration(
                        hintText: 'e.g. 912-345-6789',
                        hintStyle: effectiveHintTextStyle,
                        isDense: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (reserveErrorSpace || showError) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: reserveErrorSpace ? reservedErrorHeight : null,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    showError ? errorText : ' ',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: effectiveErrorTextStyle.copyWith(
                      color: showError
                          ? (effectiveErrorTextStyle.color ?? Colors.red)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Validator for Philippine phone numbers (10 digits starting with 9)
String? validatePhilippinePhone(String? value) {
  final phone = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (phone.isEmpty) return 'Contact number is required';
  if (phone.length != 10) return 'Enter 10 digits (9XX XXX XXXX)';
  if (!phone.startsWith('9')) return 'Number must start with 9';
  return null;
}

/// List of accepted valid ID types for the info dialog
const List<Map<String, String>> _acceptedIdTypes = [
  {'name': 'Philippine National ID (PhilSys)', 'icon': 'credit_card'},
  {'name': 'Driver\'s License (LTO)', 'icon': 'directions_car'},
  {'name': 'Passport', 'icon': 'flight'},
  {'name': 'SSS ID / UMID', 'icon': 'badge'},
  {'name': 'GSIS ID', 'icon': 'account_balance'},
  {'name': 'PRC ID', 'icon': 'school'},
  {'name': 'Voter\'s ID / COMELEC ID', 'icon': 'how_to_vote'},
  {'name': 'Postal ID', 'icon': 'mail'},
  {'name': 'PhilHealth ID', 'icon': 'local_hospital'},
  {'name': 'TIN ID', 'icon': 'receipt'},
  {'name': 'Student ID (with school seal)', 'icon': 'school'},
  {'name': 'Company ID (with company seal)', 'icon': 'business'},
  {'name': 'Senior Citizen ID', 'icon': 'elderly'},
  {'name': 'PWD ID', 'icon': 'accessible'},
  {'name': 'OFW ID', 'icon': 'public'},
  {'name': 'Birth Certificate (PSA/NSO)', 'icon': 'description'},
  {'name': 'Barangay ID', 'icon': 'location_city'},
];

enum _IdImageSource { camera, gallery }

/// Widget for uploading and verifying front and back of ID
class IdVerificationWidget extends StatefulWidget {
  final Function(String? frontUrl, String? backUrl) onUploadComplete;
  final String? initialFrontUrl;
  // Reused to preload selfie-with-ID when available.
  final String? initialBackUrl;
  final String? usernameForPath;
  final String? frontValidationError;
  final String? selfieValidationError;

  const IdVerificationWidget({
    super.key,
    required this.onUploadComplete,
    this.initialFrontUrl,
    this.initialBackUrl,
    this.usernameForPath,
    this.frontValidationError,
    this.selfieValidationError,
  });

  @override
  State<IdVerificationWidget> createState() => _IdVerificationWidgetState();
}

class _IdVerificationWidgetState extends State<IdVerificationWidget> {
  static const int _maxUploadBytes = 4 * 1024 * 1024;
  final ImagePicker _imagePicker = ImagePicker();

  String? _frontIdUrl;
  String? _frontLocalPath;
  Uint8List? _frontBytes;
  bool _uploadingFront = false;
  String? _frontError;
  String? _selfieWithIdUrl;
  String? _selfieWithIdLocalPath;
  Uint8List? _selfieWithIdBytes;
  bool _uploadingSelfieWithId = false;
  String? _selfieWithIdError;

  @override
  void initState() {
    super.initState();
    _frontIdUrl = widget.initialFrontUrl;
    _selfieWithIdUrl = widget.initialBackUrl;
  }

  /// Show dialog with accepted ID types
  void _showAcceptedIdsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.appBlack.withValues(alpha: 0.08)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: 400,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.appRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ACCEPTED VALID IDs',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppTheme.appRed,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Please upload a clear photo of any of the following IDs or documents:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.appBlack.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: _acceptedIdTypes.map((id) {
                      IconData iconData;
                      switch (id['icon']) {
                        case 'credit_card':
                          iconData = Icons.credit_card;
                          break;
                        case 'directions_car':
                          iconData = Icons.directions_car;
                          break;
                        case 'flight':
                          iconData = Icons.flight;
                          break;
                        case 'badge':
                          iconData = Icons.badge;
                          break;
                        case 'account_balance':
                          iconData = Icons.account_balance;
                          break;
                        case 'school':
                          iconData = Icons.school;
                          break;
                        case 'how_to_vote':
                          iconData = Icons.how_to_vote;
                          break;
                        case 'mail':
                          iconData = Icons.mail;
                          break;
                        case 'local_hospital':
                          iconData = Icons.local_hospital;
                          break;
                        case 'receipt':
                          iconData = Icons.receipt;
                          break;
                        case 'business':
                          iconData = Icons.business;
                          break;
                        case 'elderly':
                          iconData = Icons.elderly;
                          break;
                        case 'accessible':
                          iconData = Icons.accessible;
                          break;
                        case 'public':
                          iconData = Icons.public;
                          break;
                        case 'description':
                          iconData = Icons.description;
                          break;
                        case 'location_city':
                          iconData = Icons.location_city;
                          break;
                        default:
                          iconData = Icons.badge;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(iconData, color: AppTheme.appRed, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                id['name']!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.appBlack,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.appRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tips_and_updates,
                      color: AppTheme.appRed,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Make sure your ID or document photo is clear, well-lit, and shows the entire page.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.appBlack,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show dialog to choose between camera and gallery
  Future<_IdImageSource?> _showImageSourceDialog() async {
    return showDialog<_IdImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.appBlack.withValues(alpha: 0.08)),
        ),
        title: Text(
          'Select Image Source',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.appBlack,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSourceOption(
              icon: Icons.camera_alt,
              label: 'Camera',
              onTap: () => Navigator.pop(context, _IdImageSource.camera),
            ),
            const SizedBox(height: 8),
            _buildSourceOption(
              icon: Icons.photo_library,
              label: 'Gallery',
              onTap: () => Navigator.pop(context, _IdImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizePath(String path) {
    if (path.startsWith('file://')) {
      return Uri.parse(path).toFilePath();
    }
    return path;
  }

  Future<String?> _cropImage(String path) async {
    if (kIsWeb) return path;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Document',
            toolbarColor: AppTheme.appRed,
            toolbarWidgetColor: Colors.white,
            hideBottomControls: false,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Document',
            aspectRatioLockEnabled: false,
            rotateButtonsHidden: false,
            resetButtonHidden: false,
          ),
        ],
      );
      return cropped?.path;
    } catch (e) {
      debugPrint('Crop failed: $e');
      return null;
    }
  }

  Future<bool> _showIdUploadDisclaimer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.appBlack.withValues(alpha: 0.08)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppTheme.appRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'UPLOAD REMINDER',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(
                      Icons.close,
                      color: AppTheme.appRed,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a clear photo of a valid ID or document only.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.appBlack.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.appOffYellow.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.appOffYellow.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppTheme.appRed,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All submissions are reviewed by an admin. If you upload a random picture or a photo that is not a valid document/ID, your registration will not be approved.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.appBlack.withValues(alpha: 0.9),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.appRed,
                        side: BorderSide(
                          color: AppTheme.appRed.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.appRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('I Understand'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return confirmed ?? false;
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.appRed),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.appBlack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick and validate image for front of ID
  Future<void> _pickAndValidateFrontImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source == _IdImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;
      final imagePath = pickedFile.path;

      setState(() {
        _uploadingFront = true;
        _frontError = null;
      });

      final normalizedPath = _normalizePath(imagePath);
      final croppedPath = await _cropImage(normalizedPath);
      if (croppedPath == null) {
        setState(() {
          _uploadingFront = false;
        });
        return;
      }

      final proceed = await _showIdUploadDisclaimer();
      if (!proceed) {
        setState(() {
          _uploadingFront = false;
        });
        return;
      }

      final uploadFile = kIsWeb ? pickedFile : XFile(croppedPath);
      final bytes = await uploadFile.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        setState(() {
          _uploadingFront = false;
        });
        await _showImageSizeLimitDialog();
        return;
      }
      setState(() {
        _frontBytes = bytes;
      });

      // Upload to Firebase Storage
      final downloadUrl = await _uploadToFirebase(uploadFile, 'front', bytes);

      setState(() {
        _frontIdUrl = downloadUrl;
        _frontLocalPath = croppedPath;
        _uploadingFront = false;
      });

      // Notify parent
      widget.onUploadComplete(_frontIdUrl, _selfieWithIdUrl);

      if (mounted) {
        AppSnackBar.show(
          context,
          'Front of ID uploaded successfully',
          type: AppSnackBarType.success,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      setState(() {
        _uploadingFront = false;
        _frontError = 'Failed to upload: $e';
      });
    }
  }

  /// Pick and validate image for selfie with ID (camera or gallery)
  Future<void> _pickAndValidateSelfieWithIdImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source == _IdImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;
      final imagePath = pickedFile.path;

      setState(() {
        _uploadingSelfieWithId = true;
        _selfieWithIdError = null;
      });

      final normalizedPath = _normalizePath(imagePath);
      final croppedPath = await _cropImage(normalizedPath);
      if (croppedPath == null) {
        setState(() {
          _uploadingSelfieWithId = false;
        });
        return;
      }

      final proceed = await _showIdUploadDisclaimer();
      if (!proceed) {
        setState(() {
          _uploadingSelfieWithId = false;
        });
        return;
      }

      final uploadFile = kIsWeb ? pickedFile : XFile(croppedPath);
      final bytes = await uploadFile.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        setState(() {
          _uploadingSelfieWithId = false;
        });
        await _showImageSizeLimitDialog();
        return;
      }
      setState(() {
        _selfieWithIdBytes = bytes;
      });

      final downloadUrl = await _uploadToFirebase(
        uploadFile,
        'selfie_with_id',
        bytes,
      );

      setState(() {
        _selfieWithIdUrl = downloadUrl;
        _selfieWithIdLocalPath = croppedPath;
        _uploadingSelfieWithId = false;
      });

      widget.onUploadComplete(_frontIdUrl, _selfieWithIdUrl);

      if (mounted) {
        AppSnackBar.show(
          context,
          'Selfie with ID uploaded successfully',
          type: AppSnackBarType.success,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      setState(() {
        _uploadingSelfieWithId = false;
        _selfieWithIdError = 'Failed to upload: $e';
      });
    }
  }

  /// Upload image to Firebase Storage
  Future<String> _uploadToFirebase(
    XFile pickedFile,
    String side,
    Uint8List? bytes,
  ) async {
    final fileName = 'id_${side}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final username = widget.usernameForPath?.trim().isNotEmpty == true
        ? widget.usernameForPath!.trim()
        : 'pending_${DateTime.now().millisecondsSinceEpoch}';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('id_photos')
        .child(username)
        .child(fileName);

    final uploadBytes = bytes ?? await pickedFile.readAsBytes();
    final uploadTask = storageRef.putData(
      uploadBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    late TaskSnapshot snapshot;
    try {
      snapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
            'Upload timed out. Please check your internet connection.',
          );
        },
      );
    } on FirebaseException catch (e) {
      if (kIsWeb && kDebugMode && e.code == 'unauthorized') {
        throw Exception(
          'Web test upload blocked by Storage rules. Deploy `storage.rules` or use Firebase Emulator with Storage enabled.',
        );
      }
      rethrow;
    }

    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _showImageSizeLimitDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Image Too Large',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.appBlack,
          ),
        ),
        content: const Text(
          'The maximum allowed image size is 4 MB. Please choose a smaller image.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.appBlack,
            fontFamily: 'RobotoCondensed',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                color: AppTheme.appRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExpandedPreviewDialog({
    required String title,
    Uint8List? bytes,
    String? localPath,
    String? uploadedUrl,
  }) async {
    if (!mounted) return;

    Widget preview;
    if (bytes != null) {
      preview = Image.memory(bytes, fit: BoxFit.contain);
    } else if (localPath != null && !kIsWeb) {
      preview = Image.file(File(localPath), fit: BoxFit.contain);
    } else if (uploadedUrl != null) {
      preview = Image.network(
        uploadedUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.broken_image,
            color: AppTheme.appBlack.withValues(alpha: 0.35),
            size: 42,
          ),
        ),
      );
    } else {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppTheme.appRed),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.55,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: preview),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdSection({
    required String title,
    required String? uploadedUrl,
    required String? localPath,
    required Uint8List? bytes,
    required bool isUploading,
    required String? error,
    required VoidCallback onUpload,
  }) {
    final bool hasImage =
        bytes != null || localPath != null || uploadedUrl != null;
    final bool hasError = error?.trim().isNotEmpty ?? false;

    Widget buildPreview() {
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        );
      }
      if (localPath != null && !kIsWeb) {
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        );
      }
      if (uploadedUrl != null) {
        return Image.network(
          uploadedUrl,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.grey[400],
                size: 36,
              ),
            );
          },
        );
      }
      return const SizedBox.shrink();
    }

    return CustomUploadField(
      label: title,
      hasPreview: hasImage,
      preview: buildPreview(),
      uploading: isUploading,
      onUpload: onUpload,
      onPreviewTap: hasImage
          ? () => _showExpandedPreviewDialog(
              title: '$title Preview',
              bytes: bytes,
              localPath: localPath,
              uploadedUrl: uploadedUrl,
            )
          : null,
      errorText: error,
      status: hasError
          ? UploadFieldStatus.error
          : (hasImage ? UploadFieldStatus.success : UploadFieldStatus.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SUBMIT PHOTO OF VALID ID',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.appBlack,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showAcceptedIdsDialog,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppTheme.appRed,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    'i',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Front of ID
        _buildIdSection(
          title: 'FRONT OF ID',
          uploadedUrl: _frontIdUrl,
          localPath: _frontLocalPath,
          bytes: _frontBytes,
          isUploading: _uploadingFront,
          error: _frontError ?? widget.frontValidationError,
          onUpload: _pickAndValidateFrontImage,
        ),
        const SizedBox(height: 14),

        // Selfie with ID (camera or gallery)
        _buildIdSection(
          title: 'SELFIE WITH ID',
          uploadedUrl: _selfieWithIdUrl,
          localPath: _selfieWithIdLocalPath,
          bytes: _selfieWithIdBytes,
          isUploading: _uploadingSelfieWithId,
          error: _selfieWithIdError ?? widget.selfieValidationError,
          onUpload: _pickAndValidateSelfieWithIdImage,
        ),
      ],
    );
  }
}
