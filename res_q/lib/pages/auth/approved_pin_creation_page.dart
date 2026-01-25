import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApprovedPinCreationPage extends StatefulWidget {
  const ApprovedPinCreationPage({super.key});

  @override
  State<ApprovedPinCreationPage> createState() =>
      _ApprovedPinCreationPageState();
}

class _ApprovedPinCreationPageState extends State<ApprovedPinCreationPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtl = TextEditingController();
  final TextEditingController _pinCtl = TextEditingController();
  bool _loading = false;
  bool _phoneVerified = false;
  String? _userId;
  Map<String, dynamic>? _userData;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _phoneCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  Future<void> _verifyPhone() async {
    if (!_formKey.currentState!.validate()) return;

    String phone = _phoneCtl.text.trim().replaceAll('-', '');
    if (!phone.startsWith('+')) {
      phone = phone.startsWith('0') ? '+63${phone.substring(1)}' : '+63$phone';
    }

    setState(() => _loading = true);

    try {
      // Check if phone exists in approved_users
      final userQuery = await _firestore
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() => _loading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone number not found or not approved yet. Please wait for admin approval.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final doc = userQuery.docs.first;
      _userId = doc.id;
      _userData = doc.data();

      // Check if PIN already exists
      if (_userData!['pin'] != null &&
          _userData!['pin'].toString().isNotEmpty) {
        setState(() => _loading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have a PIN. Please use the login page.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _loading = false;
        _phoneVerified = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Phone verified! Please create your 4-digit PIN.'),
          backgroundColor: appGreen,
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createPin() async {
    final pin = _pinCtl.text.trim();

    if (pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN must be exactly 4 digits'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN must contain only numbers'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Update the user document with the PIN
      await _firestore.collection('approved_users').doc(_userId).update({
        'pin': pin,
        'pinCreatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _loading = false);

      if (!mounted) return;

      // Navigate back to login with success message
      Navigator.pushReplacementNamed(
        context,
        '/login',
        arguments: {'showPinSuccess': true},
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
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
                    _pinCtl.clear();
                  } else if (value == '⌫') {
                    if (_pinCtl.text.isNotEmpty) {
                      _pinCtl.text = _pinCtl.text.substring(
                        0,
                        _pinCtl.text.length - 1,
                      );
                    }
                  } else {
                    if (_pinCtl.text.length < 4) {
                      _pinCtl.text += value;

                      // Auto-submit when 4 digits are entered
                      if (_pinCtl.text.length == 4) {
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _createPin();
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
      appBar: AppBar(
        backgroundColor: appOffWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: appBlack),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _phoneVerified ? 'CREATE YOUR PIN' : 'VERIFY PHONE',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: appBlack,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _phoneVerified
                            ? 'Enter a 4-digit PIN for quick login'
                            : 'Enter your registered phone number',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: appBlack.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      if (!_phoneVerified) ...[
                        // Phone number input
                        TextFormField(
                          controller: _phoneCtl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 16,
                            color: appBlack,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: '09XX-XXX-XXXX',
                            prefixIcon: const Icon(
                              Icons.phone,
                              color: Colors.black,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.black),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: appBlue,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Enter phone' : null,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _verifyPhone,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appBlue,
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
                                    'VERIFY PHONE',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                          ),
                        ),
                      ] else ...[
                        // PIN Display (dots)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final hasValue = _pinCtl.text.length > index;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasValue ? appBlue : Colors.transparent,
                                border: Border.all(color: appBlack, width: 2),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 32),

                        // Numpad
                        Column(
                          children: [
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
                      ],
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
