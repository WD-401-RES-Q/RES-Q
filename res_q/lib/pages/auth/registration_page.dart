import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  final _fullNameCtl = TextEditingController();
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

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _fullNameCtl.dispose();
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
    // Validate all required fields
    if (_fullNameCtl.text.trim().isEmpty ||
        _usernameCtl.text.trim().isEmpty ||
        _emailCtl.text.trim().isEmpty ||
        _passwordCtl.text.trim().isEmpty ||
        _contactCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate password strength (Firebase requirement: min 6 chars)
    if (_passwordCtl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate email format
    if (!_emailCtl.text.contains('@') || !_emailCtl.text.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate terms acceptance (Firestore rule requirement)
    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to terms and conditions'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate that photo is uploaded
    if (_idPhotoPath == null || _idPhotoPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Please upload a government ID photo to continue'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _loadingProgress = 0.0;
    });

    // Show loading dialog with progress
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildLoadingDialog(),
      );
    }

    // Format phone number for Firebase (must be in E.164 format: +63XXXXXXXXXX)
    String phone = _contactCtl.text.replaceAll('-', '').trim();
    if (phone.isNotEmpty && !phone.startsWith('+')) {
      phone = phone.startsWith('0') ? '+63${phone.substring(1)}' : '+63$phone';
    }

    final Map<String, dynamic> userData = {
      'fullName': _fullNameCtl.text.trim(),
      'username': _usernameCtl.text.trim(),
      'email': _emailCtl.text.trim(),
      'password': _passwordCtl.text.trim(),
      'contactNumber': phone,
      'address': _addressCtl.text.trim(),
      'dateOfBirth':
          '${_dobMonthCtl.text}/${_dobDayCtl.text}/${_dobYearCtl.text}',
      'idPhotoPath': _idPhotoPath,
      'role': 'user',
    };

    try {
      // Update progress
      _updateProgress(20);

      // Enable Firebase Play Integrity verification for production
      // This verifies app authenticity and prevents unauthorized access
      // Set to false for production to comply with Firebase security requirements
      await _auth.setSettings(appVerificationDisabledForTesting: false);

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
          Navigator.pop(context); // Close loading dialog
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

          // Close loading dialog
          Navigator.pop(context);

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
      Navigator.pop(context); // Close loading dialog
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
                      child: Column(
                        children: [
                          AuthTextField(
                            controller: _fullNameCtl,
                            label: 'FULL NAME',
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _usernameCtl,
                            label: 'USERNAME',
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _passwordCtl,
                            label: 'PASSWORD',
                            obscureText: _obscurePassword,
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
                            label: 'EMAIL ADDRESS',
                            keyboardType: TextInputType.emailAddress,
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
                          ),
                          const SizedBox(height: 10),

                          AuthTextField(
                            controller: _addressCtl,
                            label: 'HOME ADDRESS',
                          ),
                          const SizedBox(height: 12),

                          DateOfBirthInput(
                            monthController: _dobMonthCtl,
                            dayController: _dobDayCtl,
                            yearController: _dobYearCtl,
                          ),
                          const SizedBox(height: 14),

                          IdPhotoUploadWidget(
                            idPhotoPath: _idPhotoPath,
                            uploadingPhoto: _uploadingPhoto,
                            onUpload: _uploadPhoto,
                          ),
                          const SizedBox(height: 14),

                          TermsCheckbox(
                            agreed: _agree,
                            onChanged: () => setState(() => _agree = !_agree),
                            onTermsTap: _showTermsAndConditions,
                          ),
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
