import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:ui' as ui;
import '../theme/app_theme.dart';

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
      'assets/icons/RES-Q_LOGO.svg',
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
  });

  @override
  Widget build(BuildContext context) {
    const double fieldRadius = 12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.roboto(
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
          validator: validator,
          autovalidateMode: autovalidateMode,
          style: GoogleFonts.roboto(
            fontSize: 13,
            color: AppTheme.appBlack,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText ?? label,
            hintStyle: GoogleFonts.roboto(
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
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: const BorderSide(color: AppTheme.appBlue, width: 1.8),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            errorMaxLines: 2,
            errorStyle: GoogleFonts.roboto(
              fontSize: 11,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
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
          style: GoogleFonts.roboto(
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
                        : '✓ ID UPLOADED',
                    style: GoogleFonts.roboto(
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
                    color: uploadingPhoto ? Colors.grey[400] : AppTheme.appRed,
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

  InputDecoration _fieldDecoration(String label, {bool hasError = false}) {
    const double fieldRadius = 12;

    return InputDecoration(
      hintText: label,
      hintStyle: GoogleFonts.roboto(
        fontSize: 12,
        color: AppTheme.appBlack.withOpacity(0.5),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: AppTheme.appOffWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppTheme.appBlue, width: 1.8),
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DATE OF BIRTH',
              style: GoogleFonts.roboto(
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: GoogleFonts.roboto(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'MM',
                      hasError: monthError != null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: dayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: GoogleFonts.roboto(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'DD',
                      hasError: dayError != null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (value) => state.didChange(value),
                    style: GoogleFonts.roboto(
                      fontSize: 13,
                      color: AppTheme.appBlack,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      'YYYY',
                      hasError: yearError != null,
                    ),
                  ),
                ),
              ],
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Text(
                state.errorText ?? '',
                style: GoogleFonts.roboto(
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
                if (agreed) return AppTheme.appBlue;
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
              style: GoogleFonts.roboto(
                fontSize: 11,
                color: AppTheme.appBlue,
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
    // Remove all non-digits
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
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

  const PhoneInputField({
    super.key,
    required this.controller,
    this.validator,
    this.autovalidateMode,
    this.label = 'CONTACT NUMBER',
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

    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      autovalidateMode: autovalidateMode,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.roboto(
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
                border: Border.all(
                  color: state.hasError ? Colors.red : Colors.black,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '+63',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.appBlack,
                      ),
                    ),
                  ),
                  Container(
                    width: 1.5,
                    height: 24,
                    color: state.hasError ? Colors.red : Colors.black,
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        PhilippinePhoneFormatter(),
                      ],
                      autovalidateMode: AutovalidateMode.disabled,
                      onChanged: (value) => state.didChange(value),
                      style: GoogleFonts.roboto(
                        fontSize: 13,
                        color: AppTheme.appBlack,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                    hintText: 'e.g. 912-345-6789',
                        hintStyle: GoogleFonts.roboto(
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
                style: GoogleFonts.roboto(
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

/// ID keywords to check for validation
const List<String> _idKeywords = [
  'NAME',
  'BIRTHDATE',
  'DATE OF BIRTH',
  'DOB',
  'ADDRESS',
  'ID NO',
  'VALID',
  'EXPIRY',
  'SEX',
  'NATIONALITY',
  'BIRTHDAY',
  'SURNAME',
  'GIVEN NAME',
  'MIDDLE NAME',
  'SIGNATURE',
  'PLACE OF BIRTH',
  'CIVIL STATUS',
];

const List<String> _idFrontKeywords = [
  'NAME',
  'SURNAME',
  'GIVEN NAME',
  'MIDDLE NAME',
  'BIRTHDATE',
  'DATE OF BIRTH',
  'DOB',
  'SEX',
  'NATIONALITY',
  'PLACE OF BIRTH',
  'ID NO',
];

const List<String> _idBackKeywords = [
  'ADDRESS',
  'VALID',
  'EXPIRY',
  'EXPIRATION',
  'DATE ISSUED',
  'ISSUED',
  'RESTRICTIONS',
  'CONDITIONS',
  'SIGNATURE',
];

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
  {'name': 'Barangay ID', 'icon': 'location_city'},
];

/// Standard ID card aspect ratio (credit card size: 85.6mm x 53.98mm)
const double _idAspectRatioMin = 1.4; // Allow some tolerance
const double _idAspectRatioMax = 1.8; // Allow some tolerance

class _IdValidationResult {
  final bool isValid;
  final bool wrongSide;
  final String? message;

  const _IdValidationResult({
    required this.isValid,
    this.wrongSide = false,
    this.message,
  });
}

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
                      color: AppTheme.appBlue,
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
                      style: GoogleFonts.roboto(
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
                      color: AppTheme.appBlue,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Please upload a clear photo of any of the following government-issued IDs:',
                style: GoogleFonts.roboto(
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
                            Icon(
                              iconData,
                              color: AppTheme.appBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                id['name']!,
                                style: GoogleFonts.roboto(
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
                  color: AppTheme.appBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tips_and_updates,
                      color: AppTheme.appBlue,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Make sure your ID photo is clear, well-lit, and shows the entire card including your photo.',
                        style: GoogleFonts.roboto(
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
  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.appBlack.withOpacity(0.08)),
        ),
        title: Text(
          'Select Image Source',
          style: GoogleFonts.roboto(
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
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
            _buildSourceOption(
              icon: Icons.photo_library,
              label: 'Gallery',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
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
              Icon(icon, color: AppTheme.appBlue),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.roboto(
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

  int _countKeywordMatches(String text, List<String> keywords) {
    int count = 0;
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        count++;
      }
    }
    return count;
  }

  /// Check if image has ID-like aspect ratio
  Future<bool> _checkAspectRatio(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final width = image.width.toDouble();
      final height = image.height.toDouble();

      // Calculate aspect ratio (always width/height, landscape orientation)
      final aspectRatio = width > height ? width / height : height / width;

      return aspectRatio >= _idAspectRatioMin && aspectRatio <= _idAspectRatioMax;
    } catch (e) {
      debugPrint('Aspect ratio check error: $e');
      return true; // On error, skip this check
    }
  }

  /// Check if image contains a face (most IDs have photos)
  Future<bool> _checkForFace(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableClassification: false,
          enableLandmarks: false,
          enableTracking: false,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      // Valid ID should have exactly one face (the ID holder's photo)
      return faces.isNotEmpty && faces.length <= 2;
    } catch (e) {
      debugPrint('Face detection error: $e');
      return true; // On error, skip this check
    }
  }

  /// Validate ID image using ML Kit text recognition, face detection, and aspect ratio
  Future<_IdValidationResult> _validateIdImage(
    String imagePath, {
    required bool isFront,
  }) async {
    // Skip ML Kit validation on web (not supported)
    if (kIsWeb) return const _IdValidationResult(isValid: true);

    try {
      // Step 1: Check aspect ratio (ID cards have standard dimensions)
      final hasValidAspectRatio = await _checkAspectRatio(imagePath);
      if (!hasValidAspectRatio) {
        return const _IdValidationResult(
          isValid: false,
          message:
              'Image does not appear to be an ID card. Please take a photo of a standard-sized ID.',
        );
      }

      // Step 2: Check for face (front of ID should have a photo)
      if (isFront) {
        final hasFace = await _checkForFace(imagePath);
        if (!hasFace) {
          return const _IdValidationResult(
            isValid: false,
            message:
                'No ID photo detected. Valid IDs must have a visible photo of the holder. Please upload a clear photo of your ID.',
          );
        }
      }

      // Step 3: Text recognition and keyword matching
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final text = recognizedText.text.toUpperCase();

      // Check minimum text content - IDs have substantial text
      if (text.length < 30 || recognizedText.blocks.length < 3) {
        return const _IdValidationResult(
          isValid: false,
          message:
              'Not enough text detected. Please take a clear photo of your entire ID with all text visible.',
        );
      }

      final frontMatches = _countKeywordMatches(text, _idFrontKeywords);
      final backMatches = _countKeywordMatches(text, _idBackKeywords);
      final totalKeywordMatches = _countKeywordMatches(text, _idKeywords);

      // More stringent: require at least 3 keyword matches for front
      if (isFront) {
        if (backMatches > frontMatches && backMatches >= 2) {
          return const _IdValidationResult(
            isValid: false,
            wrongSide: true,
            message:
                'This looks like the BACK of an ID. Please upload the FRONT.',
          );
        }

        // Front must have at least 3 keywords matched
        if (frontMatches < 3 && totalKeywordMatches < 4) {
          return const _IdValidationResult(
            isValid: false,
            message:
                'This does not appear to be a valid government ID. Tap the (i) button to see accepted IDs. Please upload a clear photo of the FRONT of your ID.',
          );
        }
      } else {
        if (frontMatches > backMatches && frontMatches >= 2) {
          return const _IdValidationResult(
            isValid: false,
            wrongSide: true,
            message:
                'This looks like the FRONT of an ID. Please upload the BACK.',
          );
        }

        // Back must have at least 2 keywords matched
        if (backMatches < 2 && totalKeywordMatches < 3) {
          return const _IdValidationResult(
            isValid: false,
            message:
                'This does not appear to be a valid ID back. Please upload a clear photo of the BACK of your ID.',
          );
        }
      }

      return const _IdValidationResult(isValid: true);
    } catch (e) {
      debugPrint('ML Kit validation error: $e');
      // On error, be strict - don't allow upload
      return const _IdValidationResult(
        isValid: false,
        message:
            'Could not verify the image. Please try again with a clearer photo.',
      );
    }
  }

  /// Pick and validate image for front of ID
  Future<void> _pickAndValidateFrontImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _uploadingFront = true;
        _frontError = null;
      });

      // Validate image with ML Kit
      final validation = await _validateIdImage(
        pickedFile.path,
        isFront: true,
      );

      if (!validation.isValid) {
        final errorMessage = validation.message ??
            'This does not appear to be a valid ID. Please take a clear photo of your government ID.';
        setState(() {
          _uploadingFront = false;
          _frontError = errorMessage;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.wrongSide
                    ? errorMessage
                    : 'Image validation failed. Tips: Ensure good lighting, avoid blur, capture the entire ID.',
                style: GoogleFonts.roboto(fontSize: 12),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Upload to Firebase Storage
      final downloadUrl = await _uploadToFirebase(pickedFile, 'front');

      setState(() {
        _frontIdUrl = downloadUrl;
        _frontLocalPath = pickedFile.path;
        _uploadingFront = false;
      });

      // Notify parent
      widget.onUploadComplete(_frontIdUrl, null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Front of ID uploaded successfully',
              style: GoogleFonts.roboto(fontSize: 12),
            ),
            backgroundColor: const Color(0xFF00A458),
            duration: const Duration(seconds: 2),
          ),
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
  Future<String> _uploadToFirebase(XFile pickedFile, String side) async {
    final fileName = 'id_${side}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final username = widget.usernameForPath?.trim().isNotEmpty == true
        ? widget.usernameForPath!.trim()
        : 'pending_${DateTime.now().millisecondsSinceEpoch}';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('id_photos')
        .child(username)
        .child(fileName);

    final bytes = await pickedFile.readAsBytes();
    final uploadTask = storageRef.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final snapshot = await uploadTask.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception('Upload timed out. Please check your internet connection.');
      },
    );

    return await snapshot.ref.getDownloadURL();
  }

  Widget _buildIdSection({
    required String title,
    required String? uploadedUrl,
    required String? localPath,
    required bool isUploading,
    required String? error,
    required VoidCallback onUpload,
  }) {
    final bool hasImage = localPath != null || uploadedUrl != null;
    final bool hasError = error != null;
    final Color borderColor = hasError ? Colors.red : Colors.black;
    const double boxHeight = 72;

    Widget buildPreview() {
      if (localPath != null && !kIsWeb) {
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
        );
      }
      if (uploadedUrl != null) {
        return Image.network(
          uploadedUrl,
          fit: BoxFit.cover,
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
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.appBlack,
                ),
              ),
            ),
            if (hasError || hasImage) const SizedBox(width: 6),
            if (hasError)
              const Icon(
                Icons.cancel,
                color: Colors.red,
                size: 16,
              ),
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
              child: GestureDetector(
                onTap: isUploading ? null : onUpload,
                child: Container(
                  height: boxHeight,
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
                              style: GoogleFonts.roboto(
                                fontSize: 13,
                                color: AppTheme.appBlack,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                  ),
                ),
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
                    color: isUploading ? Colors.grey[400] : AppTheme.appRed,
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
            style: GoogleFonts.roboto(
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
              style: GoogleFonts.roboto(
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
                  color: AppTheme.appBlue,
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
                side: BorderSide(
                  color: AppTheme.appBlack.withOpacity(0.12),
                ),
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
                          icon: const Icon(
                            Icons.close,
                            color: AppTheme.appBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TERMS AND CONDITIONS',
                      style: GoogleFonts.roboto(
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
                            style: GoogleFonts.roboto(
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
                        style: GoogleFonts.roboto(
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
                                  color: AppTheme.appBlue,
                                  width: 1.4,
                                ),
                                foregroundColor: AppTheme.appBlue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'CLOSE',
                                style: GoogleFonts.roboto(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.appBlue,
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
                                backgroundColor: AppTheme.appRed,
                                disabledBackgroundColor:
                                    AppTheme.appBlack.withOpacity(0.15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'I AGREE',
                                style: GoogleFonts.roboto(
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
