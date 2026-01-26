import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../common/widgets/pin_numpad.dart';
import '../../home/pages/home_page.dart';
import '../../semi_admin/pages/semi_admin_main_page.dart';
import '../../../common/services/user_session.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _initializing = true;
  final TextEditingController _pinCtl = TextEditingController();
  final TextEditingController _phoneCtl = TextEditingController();
  bool _showPinSuccess = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && args['showPinSuccess'] == true) {
      setState(() => _showPinSuccess = true);
      // Auto-hide after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showPinSuccess = false);
        }
      });
    }
  }

  Future<void> _initialize() async {
    await _seedSemiAdminsIfEmpty();
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  @override
  void dispose() {
    _pinCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_initializing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Initializing... Please wait a moment.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    await _verifyPinOnly();
  }

  // PIN login - verify both phone number and PIN together
  Future<void> _verifyPinOnly() async {
    final pin = _pinCtl.text.trim();
    final phoneInput = _phoneCtl.text.trim();

    // Validate phone number
    if (phoneInput.isEmpty) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your phone number'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (pin.length != 4) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN must be exactly 4 digits'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Format phone number to match Firebase format
    String phone = phoneInput.replaceAll('-', '').trim();
    if (phone.isNotEmpty && !phone.startsWith('+')) {
      phone = phone.startsWith('0') ? '+63${phone.substring(1)}' : '+63$phone';
    }

    try {
      // First check semi_admins collection
      final semiAdminQuery = await _firestore
          .collection('semi_admins')
          .where('contactNumber', isEqualTo: phone)
          .where('pin', isEqualTo: pin)
          .limit(1)
          .get();

      if (semiAdminQuery.docs.isNotEmpty) {
        // Semi-admin found - route to SemiAdminMainPage
        debugPrint('✅ Semi-admin login successful via PIN!');
        setState(() => _loading = false);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainPage()),
          );
        }
        return;
      }

      // Find user by both phone number AND PIN in approved_users
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .where('pin', isEqualTo: pin)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid phone number or PIN. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        _pinCtl.clear();
        return;
      }

      final userData = userQuery.docs.first.data();
      final accountStatus = userData['accountStatus'] as String?;

      // Check if account is approved
      if (accountStatus != 'approved') {
        setState(() => _loading = false);
        if (mounted) {
          _showPendingApprovalDialog();
        }
        return;
      }

      // Sign in to Firebase Auth anonymously
      try {
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          '✅ Firebase Anonymous Sign-In successful: ${userCredential.user?.uid}',
        );
      } catch (authError) {
        debugPrint('⚠️ Firebase Anonymous Sign-In failed: $authError');
        // Continue anyway - user data is verified in Firestore
      }

      // Login successful
      UserSession.setUserData(userData);
      setState(() => _loading = false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MainPage()));
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Seed 5 semi-admin users if collection is empty. Runs on init.
  Future<void> _seedSemiAdminsIfEmpty() async {
    debugPrint('🔍 Checking if semi_admins collection exists...');
    try {
      final existing = await _firestore
          .collection('semi_admins')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint('✓ semi_admins collection already exists. Skipping seed.');
        return;
      }

      debugPrint('📝 semi_admins collection empty. Starting seed...');

      final seedUsers = [
        {
          'username': 'semiadmin1',
          'fullName': 'Semi Admin One',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639111111111',
          'pin': '1111',
        },
        {
          'username': 'semiadmin2',
          'fullName': 'Semi Admin Two',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639222222222',
          'pin': '2222',
        },
        {
          'username': 'semiadmin3',
          'fullName': 'Semi Admin Three',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639333333333',
          'pin': '3333',
        },
        {
          'username': 'semiadmin4',
          'fullName': 'Semi Admin Four',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639444444444',
          'pin': '4444',
        },
        {
          'username': 'semiadmin5',
          'fullName': 'Semi Admin Five',
          'password': 'semi1234',
          'role': 'semi-admin',
          'contactNumber': '+639555555555',
          'pin': '5555',
        },
      ];

      final batch = _firestore.batch();
      for (final user in seedUsers) {
        final ref = _firestore
            .collection('semi_admins')
            .doc(user['username'] as String);
        batch.set(ref, user);
      }
      await batch.commit();
      debugPrint('✅ Successfully seeded 5 semi-admin users to Firestore!');
    } catch (e) {
      debugPrint('❌ Failed to seed semi_admins: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
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
                'Account Pending Approval',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account is currently pending admin approval. Please wait up to 48 hours for an administrator to review and approve your account.',
                style: GoogleFonts.poppins(fontSize: 14, color: appBlack),
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
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12, color: appBlack),
      prefixIcon: prefixIcon,
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
    );
  }

  Widget _logo() {
    return SvgPicture.asset(
      'assets/icons/RESQ-LOGO.svg',
      height: 80,
      width: 120,
    );
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    setState(() {
      if (value == 'C') {
        _pinCtl.clear();
        return;
      }
      if (value == '⌫') {
        if (_pinCtl.text.isNotEmpty) {
          _pinCtl.text = _pinCtl.text.substring(0, _pinCtl.text.length - 1);
        }
        return;
      }
      if (_pinCtl.text.length < 4) {
        _pinCtl.text += value;
        if (_pinCtl.text.length == 4) {
          Future.delayed(const Duration(milliseconds: 200), () {
            _submit();
          });
        }
      }
    });
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _logo(),

                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // PIN Login (for both regular users and semi-admins)
                            // Phone Number Field
                            Text(
                              'PHONE NUMBER',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: appBlack,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _phoneCtl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                color: appBlack,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter Phone Number',
                                hintStyle: TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                  color: appBlack.withOpacity(0.5),
                                ),
                                prefixIcon: const Icon(
                                  Icons.phone_outlined,
                                  color: Colors.black,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF7F8F3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                              ),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Enter phone number'
                                  : null,
                            ),
                            const SizedBox(height: 20),

                            Text(
                              'ENTER YOUR PIN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: appBlack,
                                fontFamily: 'Roboto',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),

                            // PIN Display (dots)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(4, (index) {
                                final hasValue = _pinCtl.text.length > index;
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasValue
                                        ? appBlue
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: appBlack,
                                      width: 2,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 24),

                            // Numpad
                            PinNumpad(
                              enabled: !_loading,
                              onKeyTap: _handlePinKey,
                              actionBackgroundColor: appOffWhite,
                              textColor: appBlack,
                            ),

                          const SizedBox(height: 20),

                          // Success message for PIN creation
                          if (_showPinSuccess) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A458),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pin is good to go! Enter the pin in the pin section.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          Align(
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pushNamed(
                                    context,
                                    '/approved-pin-creation',
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                  ),
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Approved Account? ',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            color: appBlack,
                                            fontFamily: 'RobotoCondensed',
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'Create PIN Here!',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: appBlue,
                                            fontFamily: 'RobotoCondensed',
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Register link
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/register'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'No Account yet? ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: appBlack,
                                        fontFamily: 'RobotoCondensed',
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Register Now!',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: appBlue,
                                        fontFamily: 'RobotoCondensed',
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
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
