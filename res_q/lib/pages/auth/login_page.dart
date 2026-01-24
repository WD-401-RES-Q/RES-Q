import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home_page.dart';
import '../semi-admin/semi_admin_main_page.dart';
import '../../services/user_session.dart';
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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initialize();
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

      // Check semi-admins first
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
                          // Username
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
                            style: const TextStyle(  // Add this line
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
                              prefixIcon: const Icon(Icons.person_outline, color: Colors.black),
                              filled: true,
                              fillColor: const Color(0xFFF7F8F3), // background color
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), // rounded corners
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Enter username' : null,
                          ),
                          const SizedBox(height: 15),

                          // Password
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
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility : Icons.visibility_off,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF7F8F3), // background color
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), // rounded corners
                                borderSide: const BorderSide(color: Colors.black, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 6) ? 'Password too short' : null,
                          ),

                          const SizedBox(height: 20),

                          Align(
                            alignment: Alignment.center, // change from centerRight to center
                            child: TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/forgot'),
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
                                  shadowColor: Colors.black.withOpacity(1), // 👈 shadow color
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
                                    : const Text(
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
                                  shadowColor: Colors.black.withOpacity(1), // 👈 shadow color
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
