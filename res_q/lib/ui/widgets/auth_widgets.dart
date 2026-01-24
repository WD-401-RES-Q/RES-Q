import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

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
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
        children: const [
          TextSpan(
            text: 'RES',
            style: TextStyle(color: AppTheme.appBlue),
          ),
          TextSpan(
            text: 'Q',
            style: TextStyle(color: AppTheme.appRed),
          ),
        ],
      ),
    );
  }
}

/// Custom Text Field for auth pages
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.suffixIcon,
    this.validator,
    this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      autovalidateMode: autovalidateMode,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 12, color: AppTheme.appBlack),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.black87, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.black87, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppTheme.appBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        errorStyle: GoogleFonts.poppins(
          fontSize: 11,
          color: Colors.red,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon,
      ),
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
          style: GoogleFonts.poppins(
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
                    style: GoogleFonts.poppins(
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

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12, color: AppTheme.appBlack),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.black87, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.black87, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AppTheme.appBlue, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DATE OF BIRTH',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.appBlack,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: monthController,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration('MM'),
                validator: monthValidator,
                autovalidateMode: autovalidateMode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: dayController,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration('DD'),
                validator: dayValidator,
                autovalidateMode: autovalidateMode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: yearController,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration('YYYY'),
                validator: yearValidator,
                autovalidateMode: autovalidateMode,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Terms and Conditions Checkbox
class TermsCheckbox extends StatelessWidget {
  final bool agreed;
  final VoidCallback onChanged;
  final VoidCallback onTermsTap;

  const TermsCheckbox({
    super.key,
    required this.agreed,
    required this.onChanged,
    required this.onTermsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Checkbox(
            key: ValueKey<bool>(agreed),
            value: agreed,
            onChanged: (v) => onChanged(),
            checkColor: Colors.white,
            fillColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey;
              }
              return AppTheme.appBlue;
            }),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTermsTap,
            child: Text(
              'AGREE TO TERMS AND CONDITIONS',
              style: GoogleFonts.poppins(
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
