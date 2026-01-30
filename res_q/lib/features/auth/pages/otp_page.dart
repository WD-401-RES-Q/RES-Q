import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/services/registration_prefs.dart';

class OTPPage extends StatefulWidget {
  const OTPPage({super.key});

  @override
  State<OTPPage> createState() => _OTPPageState();
}

class _OTPPageState extends State<OTPPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final TextEditingController _otpCtl = TextEditingController();
  bool _loading = false;

  String? _verificationId;
  String? _phoneNumber;
  Map<String, dynamic>? _userData;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _verificationId = args['verificationId'] as String?;
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
    }
  }

  @override
  void dispose() {
    _otpCtl.dispose();
    super.dispose();
  }

  Widget _logo() {
    return SvgPicture.asset(
      'assets/icons/RES-Q_LOGO.svg',
      height: 48,
    );
  }

  Future<void> _verify() async {
    final code = _otpCtl.text.trim();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP code')),
      );
      return;
    }

    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification ID not found')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Create phone auth credential
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );

      // Sign in with credential
      await _auth.signInWithCredential(credential);

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // Clear saved phone number after successful OTP verification
      await RegistrationPrefs.clearPhoneNumber();

      // Navigate to PIN creation page instead of saving directly
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/pin-creation',
          arguments: {
            'phoneNumber': _phoneNumber,
            'userData': _userData,
            'uid': user.uid,
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _loading = false);

      String errorMessage = 'Verification failed';
      if (e.code == 'invalid-verification-code') {
        errorMessage = 'Invalid OTP code. Please try again.';
      } else if (e.code == 'session-expired') {
        errorMessage = 'OTP expired. Please request a new code.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: appBlue,
            duration: const Duration(seconds: 3),
          ),
        );
        _otpCtl.clear();
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        _otpCtl.clear();
      }
    }
  }

  Future<void> _saveUserData() async {
    try {
      final user = _auth.currentUser;
      print('DEBUG: Saving user data. User ID: ${user?.uid}');

      if (user != null && _userData != null) {
        print('DEBUG: User data: $_userData');

        // Store newly verified users in a pending collection for admin review
        await _firestore.collection('pending_users').doc(user.uid).set({
          'fullName': _userData!['fullName'],
          'username': _userData!['username'],
          'email': _userData!['email'],
          'password': _userData!['password'],
          'contactNumber': _userData!['contactNumber'],
          'address': _userData!['address'],
          'dateOfBirth': _userData!['dateOfBirth'],
          'idPhotoPath': _userData!['idPhotoPath'],
          'role': 'user',
          'accountStatus': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('DEBUG: Successfully saved to pending_users collection');

        // Sign the phone-auth session out so only approved accounts can log in later
        await _auth.signOut();
        print('DEBUG: User signed out after pending save');
      } else {
        print('DEBUG: ERROR - user is null or userData is null');
      }
    } catch (e) {
      print('DEBUG: Error in _saveUserData: $e');
      rethrow;
    }
  }

  Future<void> _showApprovalPendingDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pending_actions, size: 64, color: appRed),
              const SizedBox(height: 16),
              Text(
                'Registration Successful!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been created and is pending admin approval. You will be able to login within 48 hours once an administrator approves your account.',
                style: const TextStyle(
                  fontSize: 14,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'OK',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resend() async {
    if (_phoneNumber == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Phone number not found')));
      return;
    }

    setState(() => _loading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneNumber!,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to resend OTP: ${e.message}')),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _loading = false;
            _verificationId = verificationId;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OTP resent successfully')),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() => _verificationId = verificationId);
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
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
                    // BLUE BACK BUTTON (icon only)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: appBlue,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Logo + title
                    Center(child: _logo()),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'VERIFY OTP',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: appBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: Text(
                        'Enter the 6 digit code sent to your\nphone number.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: appBlack,
                          fontFamily: 'RobotoCondensed',
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // OTP input
                    Center(
                      child: SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _otpCtl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            letterSpacing: 8,
                          ),
                          maxLength: 6,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '• • • •',
                            hintStyle: const TextStyle(
                              fontSize: 22,
                              color: Colors.grey,
                              letterSpacing: 8,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.black87,
                                width: 1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.black87,
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: appBlue,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // VERIFY button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'VERIFY',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Center(
                      child: TextButton(
                        onPressed: _resend,
                        child: Text(
                          'Resend code',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: appBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
