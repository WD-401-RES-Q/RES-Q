import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
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
  final TextEditingController _usernameCtl = TextEditingController();
  final TextEditingController _passCtl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _initializing = true;
  bool _isPinLogin = true; // Use PIN login by default
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
    _usernameCtl.dispose();
    _passCtl.dispose();
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

    try {
      final username = _usernameCtl.text.trim();
      final password = _passCtl.text;

      // If using PIN login mode - directly verify PIN (no phone needed)
      if (_isPinLogin) {
        await _verifyPinOnly();
        return;
      }

      // Check semi-admins first (username/password login)
      debugPrint('🔍 Checking semi_admins for username: $username');
      final semiAdminQuery = await _firestore
          .collection('semi_admins')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      debugPrint(
        '📊 Semi-admin query returned ${semiAdminQuery.docs.length} documents',
      );

      if (semiAdminQuery.docs.isNotEmpty) {
        final semiAdminData = semiAdminQuery.docs.first.data();
        final storedPassword = semiAdminData['password'] as String?;
        debugPrint('✓ Semi-admin found. Validating password...');

        if (storedPassword != null && storedPassword == password) {
          debugPrint('✅ Semi-admin login successful!');
          setState(() => _loading = false);
          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SemiAdminMainPage()),
          );
          return;
        } else {
          debugPrint('❌ Semi-admin password mismatch');
          setState(() => _loading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid password'),
              backgroundColor: const Color(0xFFAC1B22),
            ),
          );
          return;
        }
      }
      debugPrint(
        'ℹ️ Username not found in semi_admins, checking other collections...',
      );

      // Check pending first (block login if still pending)
      final pendingQuery = await _firestore
          .collection('pending_users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (pendingQuery.docs.isNotEmpty) {
        setState(() => _loading = false);
        if (!mounted) return;

        _showPendingApprovalDialog();
        return;
      }

      // Check approved users collection (only approved can log in)
      final approvedQuery = await _firestore
          .collection('approved_users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (approvedQuery.docs.isNotEmpty) {
        final userData = approvedQuery.docs.first.data();
        final accountStatus = userData['accountStatus'] as String?;
        final storedPassword = userData['password'] as String?;

        // Must be explicitly approved
        if (accountStatus != null && accountStatus != 'approved') {
          setState(() => _loading = false);
          if (!mounted) return;
          _showPendingApprovalDialog();
          return;
        }

        if (storedPassword != null && storedPassword == password) {
          UserSession.setUserData(userData);
          setState(() => _loading = false);
          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainPage()),
          );
          return;
        } else {
          setState(() => _loading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid password'),
              backgroundColor: const Color(0xFFAC1B22),
            ),
          );
          return;
        }
      }

      // User not found in any collection
      setState(() => _loading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'User "$username" not found. For semi-admin: semiadmin1-5 / semi1234',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // PIN login - look up PIN in Firestore to find associated phone number
  Future<void> _verifyPinOnly() async {
    final pin = _pinCtl.text.trim();

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

    try {
      // Find user by PIN only - this will find the phone number associated with this PIN
      final userQuery = await _firestore
          .collection('approved_users')
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

  Future<void> _verifyPhoneForPin() async {
    final phoneInput = _usernameCtl.text.trim();

    // Format phone number
    String phone = phoneInput.replaceAll('-', '').trim();
    if (phone.isNotEmpty && !phone.startsWith('+')) {
      phone = phone.startsWith('0') ? '+63${phone.substring(1)}' : '+63$phone';
    }

    try {
      // Check if phone exists in approved_users
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        // Check if pending
        final pendingQuery = await _firestore
            .collection('pending_users')
            .where('contactNumber', isEqualTo: phone)
            .limit(1)
            .get();

        setState(() => _loading = false);
        if (mounted) {
          if (pendingQuery.docs.isNotEmpty) {
            _showPendingApprovalDialog();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Phone number not found. Please register first.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        return;
      }

      // Phone found and approved - show PIN field
      setState(() {
        _loading = false;
        _pinCtl.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Phone verified. Please enter your PIN.'),
            backgroundColor: Color(0xFF00A458),
            duration: Duration(seconds: 2),
          ),
        );
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

  Future<void> _verifyPin() async {
    final pin = _pinCtl.text.trim();

    if (pin.length < 4) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN must be at least 4 digits'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use PIN login mode'),
          backgroundColor: Colors.orange,
        ),
      );
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
        },
        {
          'username': 'semiadmin2',
          'fullName': 'Semi Admin Two',
          'password': 'semi1234',
          'role': 'semi-admin',
        },
        {
          'username': 'semiadmin3',
          'fullName': 'Semi Admin Three',
          'password': 'semi1234',
          'role': 'semi-admin',
        },
        {
          'username': 'semiadmin4',
          'fullName': 'Semi Admin Four',
          'password': 'semi1234',
          'role': 'semi-admin',
        },
        {
          'username': 'semiadmin5',
          'fullName': 'Semi Admin Five',
          'password': 'semi1234',
          'role': 'semi-admin',
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

  Widget _numpadButton(String value, {bool isAction = false}) {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        onPressed: _loading
            ? null
            : () {
                setState(() {
                  if (value == 'C') {
                    // Clear all
                    _pinCtl.clear();
                  } else if (value == '⌫') {
                    // Delete last digit
                    if (_pinCtl.text.isNotEmpty) {
                      _pinCtl.text = _pinCtl.text.substring(
                        0,
                        _pinCtl.text.length - 1,
                      );
                    }
                  } else {
                    // Add digit (max 4)
                    if (_pinCtl.text.length < 4) {
                      _pinCtl.text += value;

                      // Auto-submit when 4 digits are entered
                      if (_pinCtl.text.length == 4) {
                        Future.delayed(const Duration(milliseconds: 200), () {
                          _submit();
                        });
                      }
                    }
                  }
                });
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isAction ? appOffWhite : Colors.white,
          foregroundColor: appBlack,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: appBlack.withOpacity(0.3), width: 1),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: isAction ? 24 : 28,
            fontWeight: FontWeight.w600,
            color: appBlack,
            fontFamily: 'Roboto',
          ),
        ),
      ),
    );
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
                    const SizedBox(height: 32),
                    Text(
                      'LOGIN',
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 28),

                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Login Mode Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(() {
                                          _isPinLogin = true;
                                          _usernameCtl.clear();
                                          _passCtl.clear();
                                          _pinCtl.clear();
                                          _phoneCtl.clear();
                                        });
                                      },
                                child: Text(
                                  'PIN',
                                  style: TextStyle(
                                    color: _isPinLogin ? appBlue : Colors.grey,
                                    fontWeight: _isPinLogin
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const Text(' | '),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(() {
                                          _isPinLogin = false;
                                          _usernameCtl.clear();
                                          _passCtl.clear();
                                          _pinCtl.clear();
                                          _phoneCtl.clear();
                                        });
                                      },
                                child: Text(
                                  'Semi-Admin',
                                  style: TextStyle(
                                    color: !_isPinLogin ? appBlue : Colors.grey,
                                    fontWeight: !_isPinLogin
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Show Username input for Semi-Admin login
                          if (!_isPinLogin) ...[
                            Text(
                              'USERNAME',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: appBlack,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _usernameCtl,
                              keyboardType: TextInputType.text,
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                color: appBlack,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter Username',
                                hintStyle: TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                  color: appBlack.withOpacity(0.5),
                                ),
                                prefixIcon: const Icon(
                                  Icons.person_outline,
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
                                  ? 'Enter username'
                                  : null,
                            ),
                            const SizedBox(height: 15),
                          ],

                          // PIN Field (only show if PIN login - simple and direct)
                          if (_isPinLogin) ...[
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
                            Column(
                              children: [
                                // Row 1: 1, 2, 3
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _numpadButton('1'),
                                    const SizedBox(width: 12),
                                    _numpadButton('2'),
                                    const SizedBox(width: 12),
                                    _numpadButton('3'),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Row 2: 4, 5, 6
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _numpadButton('4'),
                                    const SizedBox(width: 12),
                                    _numpadButton('5'),
                                    const SizedBox(width: 12),
                                    _numpadButton('6'),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Row 3: 7, 8, 9
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _numpadButton('7'),
                                    const SizedBox(width: 12),
                                    _numpadButton('8'),
                                    const SizedBox(width: 12),
                                    _numpadButton('9'),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Row 4: Clear, 0, Delete
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _numpadButton('C', isAction: true),
                                    const SizedBox(width: 12),
                                    _numpadButton('0'),
                                    const SizedBox(width: 12),
                                    _numpadButton('⌫', isAction: true),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                          ],

                          // Password (only for semi-admin)
                          if (!_isPinLogin) ...[
                            Text(
                              'PASSWORD',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _passCtl,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                hintText: 'Enter Password',
                                hintStyle: TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                  color: appBlack.withOpacity(0.5),
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Colors.black,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF7F8F3),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.black,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.black,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                ),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Password too short'
                                  : null,
                            ),
                            const SizedBox(height: 20),
                          ],

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
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/forgot'),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                  ),
                                  child: Text(
                                    'FORGOT PASSWORD?',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: appBlack,
                                      fontFamily: 'RobotoCondensed',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => Navigator.pushNamed(
                                    context,
                                    '/approved-pin-creation',
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                  ),
                                  child: Text(
                                    'Account Approved? Create PIN here',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: appBlue,
                                      fontFamily: 'RobotoCondensed',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // LOGIN button
                          Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              height: 50,
                              width: 210, // 👈 control button width here
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appBlue,
                                  elevation: 3, // 👈 shadow depth
                                  shadowColor: Colors.black.withOpacity(
                                    1,
                                  ), // 👈 shadow color
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'LOGIN',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w400,
                                          color: Colors.white,
                                          fontFamily: 'RobotoCondensed',
                                          fontSize: 18,
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // REGISTER button (yellow)
                          Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              height: 50,
                              width: 210, // 👈 same width as LOGIN
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/register'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appRed,
                                  elevation: 3, // 👈 shadow depth
                                  shadowColor: Colors.black.withOpacity(
                                    1,
                                  ), // 👈 shadow color
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                                child: Text(
                                  'REGISTER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                    fontFamily: 'RobotoCondensed',
                                    fontSize: 18,
                                  ),
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
