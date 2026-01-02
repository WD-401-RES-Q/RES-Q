import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

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
  bool _termsClicked = false;
  String? _idPhotoPath;
  bool _obscurePassword = true;
  bool _uploadingPhoto = false;

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

  Widget _logo() {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700),
        children: const [
          TextSpan(
            text: 'RES',
            style: TextStyle(color: appBlue),
          ),
          TextSpan(
            text: 'Q',
            style: TextStyle(color: appRed),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12, color: appBlack),
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
        borderSide: const BorderSide(color: appBlue, width: 1.4),
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
    );
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
    final ScrollController scrollController = ScrollController();
    bool canAgree = false;

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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
                        _logo(),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: appBlue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TERMS AND CONDITIONS',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: appBlack,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Text(
                            _getTermsAndConditionsText(),
                            style: GoogleFonts.quicksand(
                              fontSize: 13,
                              height: 1.6,
                              color: appBlack,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!canAgree)
                      Text(
                        'Scroll to the bottom to continue',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[600],
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
                                side: const BorderSide(color: appBlue),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                'CLOSE',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: appBlue,
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
                                      setState(() {
                                        _agree = true;
                                        _termsClicked = true;
                                      });
                                      Navigator.pop(context);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appBlue,
                                disabledBackgroundColor: Colors.grey[300],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                'I AGREE',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: canAgree ? Colors.white : Colors.grey,
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
  }

  String _getTermsAndConditionsText() {
    return '''TERMS AND CONDITIONS FOR RES-Q APP

Last Updated: December 14, 2025

1. ACCEPTANCE OF TERMS
By creating an account and using the RES-Q emergency response application, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use our services.

2. SERVICE DESCRIPTION
RES-Q is an emergency response application designed to connect users with emergency services, responders, and community support during critical situations. Our services include but are not limited to emergency alerts, location sharing, and community assistance features.

3. USER REGISTRATION
3.1 You must provide accurate, current, and complete information during registration.
3.2 You are responsible for maintaining the confidentiality of your account credentials.
3.3 You must be at least 13 years old to use this service.
3.4 Phone number verification is required for account activation.

4. EMERGENCY SERVICES
4.1 RES-Q is a supplementary tool and should not replace official emergency services (911, local emergency numbers).
4.2 In life-threatening situations, always contact official emergency services first.
4.3 We strive for accuracy but cannot guarantee response times or service availability.

5. USER RESPONSIBILITIES
5.1 You agree not to misuse the emergency alert system.
5.2 False emergency reports may result in account termination and legal action.
5.3 You are responsible for the accuracy of your location and contact information.
5.4 You must respect other users and community members.

6. PRIVACY AND DATA COLLECTION
6.1 We collect and store personal information including name, contact details, location data, and emergency contacts.
6.2 Your data may be shared with emergency responders when you activate emergency services.
6.3 We use industry-standard security measures to protect your information.
6.4 For full details, please review our Privacy Policy.

7. LOCATION SERVICES
7.1 The app requires location access to function properly.
7.2 Your location may be shared with emergency responders and authorized contacts during emergencies.
7.3 You can control location sharing settings in your device and app preferences.

8. CONTENT AND CONDUCT
8.1 You are responsible for any content you post or share through the app.
8.2 Prohibited content includes: harassment, threats, illegal activities, spam, or misleading information.
8.3 We reserve the right to remove content and terminate accounts that violate these terms.

9. LIABILITY DISCLAIMER
9.1 RES-Q is provided "as is" without warranties of any kind.
9.2 We are not liable for delays, failures, or inaccuracies in emergency response.
9.3 We are not responsible for actions or inactions of emergency responders or other users.
9.4 Use of the app is at your own risk.

10. INTELLECTUAL PROPERTY
10.1 All app content, features, and functionality are owned by RES-Q.
10.2 You may not copy, modify, distribute, or reverse engineer any part of the application.

11. ACCOUNT TERMINATION
11.1 We reserve the right to suspend or terminate accounts for violations of these terms.
11.2 You may delete your account at any time through app settings.
11.3 Termination does not relieve you of obligations incurred before termination.

12. MODIFICATIONS TO TERMS
12.1 We may update these Terms and Conditions at any time.
12.2 Continued use of the app after changes constitutes acceptance of new terms.
12.3 Material changes will be notified through the app or email.

13. INDEMNIFICATION
You agree to indemnify and hold harmless RES-Q, its developers, and affiliates from any claims, damages, or expenses arising from your use of the service or violation of these terms.

14. GOVERNING LAW
These terms are governed by the laws of the Philippines. Any disputes shall be resolved in the appropriate courts of the jurisdiction.

15. CONTACT INFORMATION
For questions about these Terms and Conditions, please contact:
Email: support@resq-app.com
Address: [Your Address]

16. EMERGENCY CONTACT CONSENT
By agreeing to these terms, you consent to RES-Q contacting your emergency contacts in situations where you have activated emergency services or are unresponsive.

17. SMS AND NOTIFICATIONS
You consent to receive SMS messages and push notifications related to emergency alerts, account security, and important service updates.

By clicking "I AGREE," you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.''';
  }

  Future<void> _submit() async {
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

    // Start Phone Auth flow: send OTP, then verify on OTP page
    setState(() => _loading = true);

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
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval on Android: sign in, then go to OTP page (autoVerified)
          try {
            await _auth.signInWithCredential(credential);
            if (mounted) {
              setState(() => _loading = false);
              Navigator.pushNamed(
                context,
                '/otp',
                arguments: {
                  'verificationId': null,
                  'phoneNumber': phone,
                  'userData': userData,
                  'autoVerified': true,
                },
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() => _loading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Auto verification failed: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          String msg = e.message ?? 'Phone verification failed';
          if (e.code.isNotEmpty) {
            msg = '${e.code}: $msg';
          }
          if (e.code == 'admin-restricted-operation') {
            msg =
                'Account creation is restricted by project settings. Enable end-user account creation in Firebase Authentication settings.';
          }
          setState(() => _loading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() => _loading = false);
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
          // No-op: OTP page holds verificationId for manual entry
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveUserData(String phone) async {
    try {
      print('DEBUG: _saveUserData called');
      final user = _auth.currentUser;
      print('DEBUG: Current user: ${user?.uid}');

      if (user != null) {
        print('DEBUG: Attempting to save to Firestore...');
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fullName': _fullNameCtl.text.trim(),
          'username': _usernameCtl.text.trim(),
          'email': _emailCtl.text.trim(),
          'contactNumber': phone,
          'address': _addressCtl.text.trim(),
          'dateOfBirth':
              '${_dobMonthCtl.text}/${_dobDayCtl.text}/${_dobYearCtl.text}',
          'idPhotoPath': _idPhotoPath,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Firestore save successful!');

        if (mounted) {
          print('DEBUG: Navigating to /main');
          Navigator.pushReplacementNamed(context, '/main');
        }
      } else {
        print('DEBUG: ERROR - No authenticated user found');
        throw Exception('No authenticated user');
      }
    } catch (e, stackTrace) {
      print('DEBUG: _saveUserData error: $e');
      print('DEBUG: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save account: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
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
                    // BLUE BACK BUTTON
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: appBlue,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Center(child: _logo()),
                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'REGISTER',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: appBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Form(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _fullNameCtl,
                            decoration: _fieldDecoration('FULL NAME'),
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _usernameCtl,
                            decoration: _fieldDecoration('USERNAME'),
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _passwordCtl,
                            obscureText: _obscurePassword,
                            decoration: _fieldDecoration('PASSWORD').copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                  color: appBlack,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _emailCtl,
                            decoration: _fieldDecoration('EMAIL ADDRESS'),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _contactCtl,
                            decoration: _fieldDecoration('CONTACT NUMBER'),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              PhoneNumberFormatter(),
                            ],
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _addressCtl,
                            decoration: _fieldDecoration('HOME ADDRESS'),
                          ),
                          const SizedBox(height: 12),

                          // DOB
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'DATE OF BIRTH',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _dobMonthCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('MM'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _dobDayCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('DD'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _dobYearCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('YYYY'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'SUBMIT PHOTO OF VALID ID',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          SizedBox(
                            height: 40,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _uploadingPhoto ? null : _uploadPhoto,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _idPhotoPath != null
                                    ? const Color(0xFF00A458)
                                    : appRed,
                                disabledBackgroundColor: Colors.grey[400],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: _uploadingPhoto
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : Text(
                                      _idPhotoPath == null
                                          ? 'UPLOAD GOVERNMENT ID'
                                          : '✓ ID UPLOADED',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                child: Checkbox(
                                  key: ValueKey<bool>(_agree),
                                  value: _agree,
                                  onChanged: (v) =>
                                      setState(() => _agree = v ?? false),
                                  checkColor: Colors.white,
                                  fillColor: MaterialStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (states.contains(
                                      MaterialState.disabled,
                                    )) {
                                      return Colors.grey;
                                    }
                                    return appBlue;
                                  }),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showTermsAndConditions,
                                  child: Text(
                                    'AGREE TO TERMS AND CONDITIONS',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: appBlue,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                                backgroundColor: appBlue,
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
