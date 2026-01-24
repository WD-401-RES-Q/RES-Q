import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../ui/app_theme.dart';
import '../../ui/widgets/auth_widgets.dart';
import '../../ui/widgets/terms_dialog.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _contactCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _dobDayCtl = TextEditingController();
  final _dobMonthCtl = TextEditingController();
  final _dobYearCtl = TextEditingController();

  bool _loading = false;
  bool _agree = false;
  String? _idPhotoPath;
  bool _obscurePassword = true;
  bool _uploadingPhoto = false;
  double _loadingProgress = 0.0;
  String? _termsError;
  String? _idPhotoError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    _emailCtl.dispose();
    _contactCtl.dispose();
    _addressCtl.dispose();
    _dobDayCtl.dispose();
    _dobMonthCtl.dispose();
    _dobYearCtl.dispose();
    super.dispose();
  }

  Future<void> _uploadPhoto() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return; // User cancelled
      }

      setState(() => _uploadingPhoto = true);

      // Upload to Firebase Storage under 'id_photos' folder
      final fileName = 'id_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('id_photos')
          .child(
            _usernameCtl.text.trim().isEmpty
                ? 'pending_${DateTime.now().millisecondsSinceEpoch}'
                : _usernameCtl.text.trim(),
          )
          .child(fileName);

      // Upload using bytes (works on both web and mobile) with timeout
      final bytes = await pickedFile.readAsBytes();
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Add timeout to prevent indefinite loading
      final snapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
            'Upload timed out. Please check your internet connection and try again.',
          );
        },
      );

      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _idPhotoPath = downloadUrl;
        _uploadingPhoto = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ ID Photo uploaded successfully'),
            backgroundColor: Color(0xFF00A458),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _uploadingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showTermsAndConditions() async {
    final agreed = await TermsAndConditionsDialog.show(context);
    if (agreed) {
      setState(() {
        _agree = true;
      });
    }
  }

  Future<void> _submit() async {
    final normalizedFirstName =
        _firstNameCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalizedLastName =
        _lastNameCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalizedFullName = '$normalizedFirstName $normalizedLastName';
    final normalizedUsername = _usernameCtl.text.trim();
    final normalizedEmail = _emailCtl.text.trim();
    final normalizedAddress = _addressCtl.text.trim();
    final normalizedContact = _contactCtl.text.trim();
    final dobMonth = _dobMonthCtl.text.trim();
    final dobDay = _dobDayCtl.text.trim();
    final dobYear = _dobYearCtl.text.trim();

    final formValid = _formKey.currentState?.validate() ?? false;
    final termsValid = _agree;
    final idValid = _idPhotoPath != null && _idPhotoPath!.isNotEmpty;
    setState(() {
      _termsError = termsValid ? null : 'Please agree to terms and conditions';
      _idPhotoError =
          idValid ? null : 'Please upload a government ID photo to continue';
    });
    if (!formValid || !termsValid || !idValid) {
      return;
    }

    setState(() {
      _loading = true;
      _loadingProgress = 0.0;
    });

    // Format phone number for Firebase (must be in E.164 format: +63XXXXXXXXXX)
    String phone = normalizedContact.replaceAll('-', '').trim();
    if (phone.isNotEmpty && !phone.startsWith('+')) {
      phone = phone.startsWith('0') ? '+63${phone.substring(1)}' : '+63$phone';
    }

    final Map<String, dynamic> userData = {
      'fullName': normalizedFullName,
      'username': normalizedUsername,
      'email': normalizedEmail.isEmpty ? null : normalizedEmail,
      'password': _passwordCtl.text.trim(),
      'contactNumber': phone,
      'address': normalizedAddress,
      'dateOfBirth': '$dobMonth/$dobDay/$dobYear',
      'idPhotoPath': _idPhotoPath,
      'role': 'user',
    };

    try {
      // Update progress
      _updateProgress(20);

      // Skip app verification only in debug to make emulator/dev testing reliable.
      if (!kIsWeb) {
        await _auth.setSettings(
          appVerificationDisabledForTesting: kDebugMode,
        );
      }

      // Send OTP to phone number via Firebase Auth
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 30),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (rare on most devices)
          // This happens automatically on some Android devices
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);
          String msg = e.message ?? 'Phone verification failed';

          if (e.code == 'invalid-phone-number') {
            msg = 'Invalid phone number. Please check and try again.';
          } else if (e.code == 'too-many-requests') {
            msg = 'Too many attempts. Please try again later.';
          } else if (e.code == 'missing-phone-number') {
            msg = 'Phone number is required.';
          } else if (e.code == 'app-not-authorized') {
            msg = 'App is not authorized. Please check Firebase Console.';
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _updateProgress(100);
          setState(() => _loading = false);

          // Navigate to OTP verification page
          if (mounted) {
            Navigator.pushNamed(
              context,
              '/otp',
              arguments: {
                'verificationId': verificationId,
                'phoneNumber': phone,
                'userData': userData,
              },
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send OTP: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _isValidNamePart(String name) {
    if (name.length < 2) return false;
    if (name.length > 40) return false;
    final parts = name.split(' ');
    final wordPattern = RegExp(r"^[A-Za-z]{2,}([-''][A-Za-z]+)*\.?$");
    final initialPattern = RegExp(r"^[A-Za-z]\.?$");
    for (final part in parts) {
      if (!wordPattern.hasMatch(part) && !initialPattern.hasMatch(part)) {
        return false;
      }
    }
    return true;
  }

  bool _isValidUsername(String username) {
    if (username.length < 3 || username.length > 20) return false;
    return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username);
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 10 && digitsOnly.length <= 15;
  }

  bool _isValidAddress(String address) {
    if (address.length < 5 || address.length > 120) return false;
    return RegExp(r'[A-Za-z0-9]').hasMatch(address);
  }

  bool _isValidDob(String month, String day, String year) {
    final m = int.tryParse(month);
    final d = int.tryParse(day);
    final y = int.tryParse(year);
    if (m == null || d == null || y == null) return false;
    if (y < 1900 || y > DateTime.now().year) return false;
    try {
      final date = DateTime(y, m, d);
      if (date.year != y || date.month != m || date.day != d) return false;
      if (date.isAfter(DateTime.now())) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _validateFirstName(String? value) {
    final normalized =
        (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'First name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid first name';
    return null;
  }

  String? _validateLastName(String? value) {
    final normalized =
        (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Last name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid last name';
    return null;
  }

  String? _validateUsername(String? value) {
    final username = (value ?? '').trim();
    if (username.isEmpty) return 'Username is required';
    if (!_isValidUsername(username)) {
      return '3-20 chars, letters/numbers/_ only';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password is required';
    if ((value ?? '').length < 6) return 'Min 6 characters';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return null;
    return _isValidEmail(email) ? null : 'Enter a valid email address';
  }

  String? _validateContact(String? value) {
    final contact = (value ?? '').trim();
    if (contact.isEmpty) return 'Contact number is required';
    return _isValidPhone(contact) ? null : 'Enter a valid contact number';
  }

  String? _validateAddress(String? value) {
    final address = (value ?? '').trim();
    if (address.isEmpty) return 'Home address is required';
    return _isValidAddress(address) ? null : 'Enter a valid home address';
  }

  String? _validateDobMonth(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'MM';
    final m = int.tryParse(v);
    if (m == null || m < 1 || m > 12) return 'MM';
    return null;
  }

  String? _validateDobDay(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'DD';
    final d = int.tryParse(v);
    if (d == null || d < 1 || d > 31) return 'DD';
    return null;
  }

  String? _validateDobYear(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'YYYY';
    final y = int.tryParse(v);
    final currentYear = DateTime.now().year;
    if (y == null || y < 1900 || y > currentYear) return 'YYYY';
    final month = _dobMonthCtl.text.trim();
    final day = _dobDayCtl.text.trim();
    if (!_isValidDob(month, day, v)) return 'YYYY';
    return null;
  }

  void _updateProgress(double progress) {
    if (mounted) {
      setState(() => _loadingProgress = progress);
    }
  }

  Widget _buildLoadingDialog() {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _loadingProgress / 100,
                    strokeWidth: 8,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFC806),
                    ),
                    backgroundColor: Colors.grey[300],
                  ),
                  Text(
                    '${_loadingProgress.toInt()}%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sending Verification Code',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Please wait while we send an OTP to your phone',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BACK BUTTON AND LOGO ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: AppTheme.appBlue,
                          ),
                        ),
                        const ResqLogo(),
                        const SizedBox(width: 48), // Balance the row
                      ],
                    ),
                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'REGISTER',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.appBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          AuthTextField(
                            controller: _firstNameCtl,
                            label: 'FIRST NAME',
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r"[a-zA-Z .'-]"),
                              ),
                            ],
                            validator: _validateFirstName,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 10),
                          AuthTextField(
                            controller: _lastNameCtl,
                            label: 'LAST NAME',
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r"[a-zA-Z .'-]"),
                              ),
                            ],
                            validator: _validateLastName,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _usernameCtl,
                            label: 'USERNAME',
                            validator: _validateUsername,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _passwordCtl,
                            label: 'PASSWORD',
                            obscureText: _obscurePassword,
                            validator: _validatePassword,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: AppTheme.appBlack,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _emailCtl,
                            label: 'EMAIL ADDRESS (OPTIONAL)',
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _contactCtl,
                            label: 'CONTACT NUMBER',
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              PhoneNumberFormatter(),
                            ],
                            validator: _validateContact,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _addressCtl,
                            label: 'HOME ADDRESS',
                            validator: _validateAddress,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 12),

                          DateOfBirthInput(
                            monthController: _dobMonthCtl,
                            dayController: _dobDayCtl,
                            yearController: _dobYearCtl,
                            monthValidator: _validateDobMonth,
                            dayValidator: _validateDobDay,
                            yearValidator: _validateDobYear,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: 14),

                          IdPhotoUploadWidget(
                            idPhotoPath: _idPhotoPath,
                            uploadingPhoto: _uploadingPhoto,
                            onUpload: _uploadPhoto,
                          ),
                          if (_idPhotoError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _idPhotoError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),

                          TermsCheckbox(
                            agreed: _agree,
                            onChanged: () => setState(() {
                              _agree = !_agree;
                              if (_agree) _termsError = null;
                            }),
                            onTermsTap: _showTermsAndConditions,
                          ),
                          if (_termsError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _termsError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),

                          SizedBox(
                            height: 42,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  (_loading ||
                                      _uploadingPhoto ||
                                      _idPhotoPath == null)
                                  ? null
                                  : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.appBlue,
                                disabledBackgroundColor: Colors.grey[400],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      'CREATE ACCOUNT',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
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
          ),
        ),
      ),
    );
  }
}
