import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:ui' as ui;
import '../theme/app_theme.dart';
import 'app_snackbar.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    const double fieldRadius = 12;
    const Color validGreen = Color(0xFF00A458);

    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        final hasValue = controller.text.trim().isNotEmpty;
        final hasError = state.hasError;
        final isValid = hasValue && !hasError;
        final borderColor = hasError
            ? Colors.red
            : (isValid ? validGreen : Colors.black);
        final focusBorderColor = hasError
            ? Colors.red
            : (isValid ? validGreen : AppTheme.appRed);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.appBlack,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              autofillHints: autofillHints,
              autovalidateMode: AutovalidateMode.disabled,
              onChanged: (value) => state.didChange(value),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.appBlack,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hintText ?? label,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppTheme.appBlack.withOpacity(0.5),
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: prefixIcon,
                filled: true,
                fillColor: AppTheme.appOffWhite,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(color: borderColor, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(color: borderColor, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(color: focusBorderColor, width: 1.8),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: const BorderSide(color: Colors.red, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                suffixIcon: suffixIcon,
              ),
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Text(
                state.errorText ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
        color: AppTheme.appBlack.withOpacity(0.5),
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

/// Terms and Conditions Checkbox
/// The checkbox is display-only - user must click link and agree via dialog
class TermsCheckbox extends StatelessWidget {
  final bool agreed;
  final VoidCallback onTermsTap;

  const TermsCheckbox({
    super.key,
    required this.agreed,
    required this.onTermsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Display-only checkbox - not directly toggleable
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Checkbox(
              key: ValueKey<bool>(agreed),
              value: agreed,
              onChanged: null,
              checkColor: Colors.white,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (agreed) return AppTheme.appRed;
                return Colors.grey[400];
              }),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTermsTap,
            child: Text(
              'READ AND AGREE TO TERMS AND CONDITIONS',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.appRed,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
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

  const PhoneInputField({
    super.key,
    required this.controller,
    this.validator,
    this.autovalidateMode,
    this.label = 'CONTACT NUMBER',
    this.autofillHints,
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
        final digits = controller.text.replaceAll(RegExp(r'\D'), '');
        final hasValue = digits.isNotEmpty;
        final hasError = state.hasError;
        final isValid = hasValue && !hasError;
        final borderColor = hasError
            ? Colors.red
            : (isValid ? validGreen : Colors.black);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.appBlack,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.appOffWhite,
                borderRadius: BorderRadius.circular(fieldRadius),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '+63',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  Container(width: 1.5, height: 24, color: borderColor),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        PhilippinePhoneFormatter(),
                      ],
                      autovalidateMode: AutovalidateMode.disabled,
                      autofillHints: autofillHints,
                      onChanged: (value) => state.didChange(value),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.appBlack,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 912-345-6789',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: AppTheme.appBlack.withOpacity(0.5),
                        ),
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
  // Kept for hot-reload compatibility; back is not used in UI.
  final String? initialBackUrl;
  final String? usernameForPath;

  const IdVerificationWidget({
    super.key,
    required this.onUploadComplete,
    this.initialFrontUrl,
    this.initialBackUrl,
    this.usernameForPath,
  });

  @override
  State<IdVerificationWidget> createState() => _IdVerificationWidgetState();
}

class _IdVerificationWidgetState extends State<IdVerificationWidget> {
  final ImagePicker _imagePicker = ImagePicker();

  String? _frontIdUrl;
  String? _frontLocalPath;
  double? _frontAspectRatio;
  Uint8List? _frontBytes;
  bool _uploadingFront = false;
  String? _frontError;

  @override
  void initState() {
    super.initState();
    _frontIdUrl = widget.initialFrontUrl;
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
          side: BorderSide(color: AppTheme.appBlack.withOpacity(0.08)),
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
      shadowColor: Colors.black.withOpacity(0.12),
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

  /// Read image aspect ratio (width / height)
  Future<double?> _getImageAspectRatio(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.height == 0) return null;
      return image.width / image.height;
    } catch (e) {
      debugPrint('Aspect ratio read error: $e');
      return null;
    }
  }

  /// Read image aspect ratio from bytes (width / height)
  Future<double?> _getImageAspectRatioFromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.height == 0) return null;
      return image.width / image.height;
    } catch (e) {
      debugPrint('Aspect ratio read error: $e');
      return null;
    }
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

      final imagePath = pickedFile?.path;
      if (imagePath == null) return;

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

      final bytes = await File(croppedPath).readAsBytes();
      final aspectRatio = await _getImageAspectRatioFromBytes(bytes);

      setState(() {
        _frontAspectRatio = aspectRatio;
        _frontBytes = bytes;
      });

      // Upload to Firebase Storage
      final downloadUrl = await _uploadToFirebase(
        XFile(croppedPath),
        'front',
        bytes,
      );

      setState(() {
        _frontIdUrl = downloadUrl;
        _frontLocalPath = croppedPath;
        _uploadingFront = false;
      });

      // Notify parent
      widget.onUploadComplete(_frontIdUrl, null);

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

    final snapshot = await uploadTask.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception(
          'Upload timed out. Please check your internet connection.',
        );
      },
    );

    return await snapshot.ref.getDownloadURL();
  }

  Widget _buildIdSection({
    required String title,
    required String? uploadedUrl,
    required String? localPath,
    required double? aspectRatio,
    required Uint8List? bytes,
    required bool isUploading,
    required String? error,
    required VoidCallback onUpload,
  }) {
    final bool hasImage =
        bytes != null || localPath != null || uploadedUrl != null;
    final bool hasError = error != null;
    final Color borderColor = hasError ? Colors.red : Colors.black;
    const double boxHeight = 72;

    Widget buildPreview() {
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        );
      }
      if (localPath != null && !kIsWeb) {
        return Image.file(
          File(localPath),
          fit: BoxFit.contain,
          alignment: Alignment.center,
        );
      }
      if (uploadedUrl != null) {
        return Image.network(
          uploadedUrl,
          fit: BoxFit.contain,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '$title (REQUIRED)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.appBlack,
                ),
              ),
            ),
            if (hasError || hasImage) const SizedBox(width: 6),
            if (hasError) const Icon(Icons.cancel, color: Colors.red, size: 16),
            if (!hasError && hasImage)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF00A458),
                size: 16,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double maxPreviewHeight =
                      (MediaQuery.sizeOf(context).height * 0.55)
                          .clamp(200.0, 520.0)
                          .toDouble();
                  final double previewHeight = aspectRatio == null
                      ? boxHeight
                      : (constraints.maxWidth / aspectRatio!)
                            .clamp(boxHeight, maxPreviewHeight)
                            .toDouble();
                  return GestureDetector(
                    onTap: isUploading ? null : onUpload,
                    child: Container(
                      height: previewHeight,
                      decoration: BoxDecoration(
                        color: AppTheme.appOffWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: hasImage
                            ? buildPreview()
                            : Center(
                                child: Text(
                                  'TAP TO UPLOAD',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.appBlack,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: isUploading ? null : onUpload,
                child: Container(
                  height: boxHeight,
                  decoration: BoxDecoration(
                    color: isUploading
                        ? Colors.grey[400]
                        : AppTheme.appOffYellow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: isUploading
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
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
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
          aspectRatio: _frontAspectRatio,
          bytes: _frontBytes,
          isUploading: _uploadingFront,
          error: _frontError,
          onUpload: _pickAndValidateFrontImage,
        ),
      ],
    );
  }
}

class TermsAndConditionsDialog {
  static Future<bool> show(BuildContext context) async {
    final ScrollController scrollController = ScrollController();
    bool canAgree = false;
    bool agreed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            scrollController.addListener(() {
              if (scrollController.position.pixels >=
                  scrollController.position.maxScrollExtent - 20) {
                if (!canAgree) {
                  setDialogState(() {
                    canAgree = true;
                  });
                }
              }
            });

            return Dialog(
              backgroundColor: AppTheme.appOffWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.appBlack.withOpacity(0.12)),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                  maxWidth: 500,
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const ResqLogo(fontSize: 24),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: AppTheme.appRed),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TERMS AND CONDITIONS',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.appBlack,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.appBrightWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.appBlack.withOpacity(0.12),
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Text(
                            _getTermsAndConditionsText(),
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: AppTheme.appBlack,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!canAgree)
                      Text(
                        'Scroll to the bottom to continue',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.appBlack.withOpacity(0.55),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppTheme.appRed,
                                  width: 1.4,
                                ),
                                foregroundColor: AppTheme.appRed,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'CLOSE',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.appRed,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: canAgree
                                  ? () {
                                      agreed = true;
                                      Navigator.pop(context);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.appOffYellow,
                                disabledBackgroundColor: AppTheme.appBlack
                                    .withOpacity(0.15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'I AGREE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: canAgree
                                      ? Colors.white
                                      : AppTheme.appBlack.withOpacity(0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    scrollController.dispose();
    return agreed;
  }

  static String _getTermsAndConditionsText() {
    return '''TERMS AND CONDITIONS FOR RES-Q DISASTER RESPONSE APP

Last Updated: January 2026

IMPORTANT: Please read these terms carefully before using RES-Q. By clicking "I AGREE," you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.

1. ACCEPTANCE OF TERMS
By creating an account and using the RES-Q emergency and disaster response application, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our services.

2. SERVICE DESCRIPTION
RES-Q is a community-based disaster response and emergency assistance application designed to:
- Connect users with emergency services and local responders during disasters
- Facilitate real-time disaster reporting (floods, earthquakes, fires, accidents, etc.)
- Enable location sharing during emergencies for rescue operations
- Provide community assistance and coordination during calamities
- Deliver emergency alerts and notifications

3. USER REGISTRATION AND VERIFICATION
3.1 You must provide accurate, current, and complete information during registration including a valid government-issued ID.
3.2 You are responsible for maintaining the confidentiality of your account credentials and PIN.
3.3 You must be at least 13 years old to use this service.
3.4 Phone number verification via OTP is required for account activation.
3.5 Your account is subject to approval by administrators to ensure community safety.

4. EMERGENCY AND DISASTER SERVICES
4.1 RES-Q is a SUPPLEMENTARY TOOL and should NOT replace official emergency services (911, local emergency hotlines, NDRRMC, LGU disaster offices).
4.2 In life-threatening situations, ALWAYS contact official emergency services FIRST.
4.3 We strive for accuracy but cannot guarantee response times, service availability, or emergency responder actions during disasters.
4.4 Network outages during disasters may affect app functionality.

5. DISASTER REPORTING RESPONSIBILITIES
5.1 You agree to report disasters and emergencies accurately and truthfully.
5.2 FALSE DISASTER REPORTS may result in immediate account termination and potential legal action under applicable laws.
5.3 You are responsible for the accuracy of your location and the information you report.
5.4 Do not report incidents that have already been resolved or are being handled by authorities.

6. LOCATION SERVICES DURING EMERGENCIES
6.1 The app requires location access to function properly during emergencies.
6.2 Your REAL-TIME LOCATION will be automatically shared with:
    - Emergency responders when you report or are involved in an emergency
    - Local disaster response teams
    - Your designated emergency contacts
    - Semi-administrators managing disaster response
6.3 Location data during active emergencies may be retained for rescue coordination and post-incident analysis.
6.4 You may disable location sharing in non-emergency situations through app settings.

7. EMERGENCY CONTACT AUTO-NOTIFICATION
7.1 By agreeing to these terms, you consent to RES-Q automatically notifying your emergency contacts when:
    - You report a disaster or emergency
    - You mark yourself as "in danger" or "needs assistance"
    - You are unresponsive during an active emergency in your area
    - Authorities request welfare checks
7.2 Your emergency contacts will receive your location and status updates.

8. DATA COLLECTION AND PRIVACY DURING DISASTERS
8.1 We collect and store personal information including:
    - Name, contact details, address, and date of birth
    - Government ID photos for verification
    - Location data (especially during emergencies)
    - Disaster reports and photos you submit
    - Emergency contacts
8.2 During active disasters, your data may be shared with:
    - Local Government Units (LGUs)
    - Barangay officials
    - Philippine National Police (PNP)
    - Bureau of Fire Protection (BFP)
    - Medical responders
    - National Disaster Risk Reduction and Management Council (NDRRMC)
8.3 We use industry-standard security measures to protect your information.

9. COMMUNITY CONDUCT
9.1 You must respect other users and community members at all times.
9.2 Prohibited actions include:
    - Filing false or malicious disaster reports
    - Harassment of other users or responders
    - Sharing misleading information about disasters
    - Interfering with rescue operations
    - Spam or irrelevant content
9.3 We reserve the right to remove content and terminate accounts that violate these terms.

10. SMS AND PUSH NOTIFICATIONS
10.1 You consent to receive SMS messages and push notifications for:
    - Emergency alerts in your area
    - Disaster warnings (typhoons, earthquakes, floods, etc.)
    - Account security notifications
    - Status updates on your reports
    - Evacuation notices
10.2 Critical emergency alerts cannot be disabled for your safety.

11. LIABILITY DISCLAIMER
11.1 RES-Q is provided "as is" without warranties of any kind.
11.2 We are NOT liable for:
    - Delays, failures, or inaccuracies in emergency response
    - Actions or inactions of emergency responders or other users
    - Network failures during disasters
    - Damage or injury resulting from use of the app
11.3 Use of the app is at your own risk.

12. INTELLECTUAL PROPERTY
12.1 All app content, features, and functionality are owned by RES-Q.
12.2 Disaster reports and photos you submit may be used for emergency coordination, public safety announcements, and improving disaster response.

13. ACCOUNT TERMINATION
13.1 We reserve the right to suspend or terminate accounts for violations of these terms.
13.2 You may request account deletion through app settings.
13.3 Termination does not relieve you of obligations incurred before termination.
13.4 Emergency data may be retained for legal and public safety purposes.

14. MODIFICATIONS TO TERMS
14.1 We may update these Terms and Conditions at any time.
14.2 Continued use of the app after changes constitutes acceptance of new terms.
14.3 Material changes will be notified through the app.

15. INDEMNIFICATION
You agree to indemnify and hold harmless RES-Q, its developers, affiliates, and partner agencies from any claims, damages, or expenses arising from your use of the service or violation of these terms.

16. GOVERNING LAW
These terms are governed by the laws of the Republic of the Philippines including the Data Privacy Act of 2012 (RA 10173) and the Philippine Disaster Risk Reduction and Management Act (RA 10121). Any disputes shall be resolved in the appropriate courts of the jurisdiction.

17. CONTACT INFORMATION
For questions about these Terms and Conditions:
Email: support@resq-app.com

By clicking "I AGREE," you acknowledge that:
- You have read and understood these Terms and Conditions
- You consent to location sharing during emergencies
- You consent to automatic notification of your emergency contacts
- You consent to receiving emergency alerts and disaster warnings
- You understand your responsibilities in accurate disaster reporting''';
  }
}
