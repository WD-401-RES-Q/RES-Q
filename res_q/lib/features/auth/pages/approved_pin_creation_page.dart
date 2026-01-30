import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/app_buttons.dart';

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
  final LocalAuthentication _localAuth = LocalAuthentication();

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

      // Allow PIN reset - no longer blocking users who have existing PIN
      setState(() {
        _loading = false;
        _phoneVerified = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Phone verified! Please enter your new 4-digit PIN.'),
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

  Future<bool> _checkBiometricsAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return canAuthenticate && availableBiometrics.isNotEmpty;
    } catch (e) {
      debugPrint('Biometrics check error: $e');
      return false;
    }
  }

  Future<bool?> _showBiometricsOptInDialog() async {
    final canUseBiometrics = await _checkBiometricsAvailable();

    if (!canUseBiometrics || !mounted) {
      return null; // Skip if biometrics not available
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: appBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint,
                  size: 48,
                  color: appBlue,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Enable Biometric Login?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: appBlack,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Would you like to use fingerprint or face recognition for faster login?',
                style: TextStyle(
                  fontSize: 14,
                  color: appBlack.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You can change this later in settings.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: appBlack,
                        side: BorderSide(color: appBlack.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'No Thanks',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: appBlack,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            size: 18,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Enable',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveBiometricsPreference(bool enabled, String? phoneNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', enabled);
      if (phoneNumber != null) {
        await prefs.setString('biometrics_phone', phoneNumber);
      }
      debugPrint('✅ Biometrics preference saved: $enabled for phone: $phoneNumber');
    } catch (e) {
      debugPrint('Error saving biometrics preference: $e');
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

      // Show biometrics opt-in dialog
      final phoneNumber = _userData?['contactNumber'] as String?;
      final enableBiometrics = await _showBiometricsOptInDialog();

      if (enableBiometrics != null) {
        await _saveBiometricsPreference(enableBiometrics, phoneNumber);
      }

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
          Future.delayed(const Duration(milliseconds: 300), () {
            _createPin();
          });
        }
      }
    });
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
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
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
                        _phoneVerified ? 'RESET PIN' : 'FORGOT PIN',
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
                            ? 'Enter a new 4-digit PIN'
                            : 'Enter your registered phone number to reset your PIN',
                        style: TextStyle(
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
                                    'VERIFY',
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
                        PinNumpad(
                          enabled: !_loading,
                          onKeyTap: _handlePinKey,
                          actionBackgroundColor: appOffWhite,
                          textColor: appBlack,
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
      ),
    );
  }
}
