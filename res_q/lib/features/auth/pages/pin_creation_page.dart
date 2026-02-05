import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PINCreationPage extends StatefulWidget {
  const PINCreationPage({super.key});

  @override
  State<PINCreationPage> createState() => _PINCreationPageState();
}

class _PINCreationPageState extends State<PINCreationPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final TextEditingController _pinCtl = TextEditingController();
  final TextEditingController _pinConfirmCtl = TextEditingController();
  bool _loading = false;
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  String? _pinError;
  String? _pinConfirmError;

  String? _phoneNumber;
  Map<String, dynamic>? _userData;
  String? _uid;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _phoneNumber = args['phoneNumber'] as String?;
      _userData = args['userData'] as Map<String, dynamic>?;
      _uid = args['uid'] as String?;
    }
  }

  @override
  void dispose() {
    _pinCtl.dispose();
    _pinConfirmCtl.dispose();
    super.dispose();
  }

  String _formatPhoneForDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    // Handle +63XXXXXXXXXX format
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.length == 10) {
      return '+63 ${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  Widget _logo() {
    return SvgPicture.asset(
      'assets/icons/RES-Q_LOGO.svg',
      height: 48,
    );
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
              Text(
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
              Text(
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
                      child: Text(
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.fingerprint,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
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
      debugPrint('✅ Biometrics preference saved: $enabled');
    } catch (e) {
      debugPrint('Error saving biometrics preference: $e');
    }
  }

  Future<void> _createPin() async {
    final pin = _pinCtl.text.trim();
    final pinConfirm = _pinConfirmCtl.text.trim();

    // Clear previous errors
    setState(() {
      _pinError = null;
      _pinConfirmError = null;
    });

    // Validation
    if (pin.length != 4) {
      setState(() => _pinError = 'PIN must be exactly 4 digits');
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _pinError = 'PIN must contain only numbers');
      return;
    }

    if (pin != pinConfirm) {
      setState(() => _pinConfirmError = 'PINs do not match');
      _pinCtl.clear();
      _pinConfirmCtl.clear();
      return;
    }

    setState(() => _loading = true);

    try {
      if (_uid == null) {
        throw Exception('User ID not found');
      }

      // Save PIN and user data to pending_users collection
      final userData = _userData ?? {};
      userData['pin'] = pin; // Add PIN to user data
      userData['accountStatus'] = 'pending';
      userData['createdAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('pending_users').doc(_uid).set(userData);

      setState(() => _loading = false);

      if (!mounted) return;

      // Show biometrics opt-in dialog first
      final enableBiometrics = await _showBiometricsOptInDialog();

      if (enableBiometrics != null) {
        // Save the preference
        await _saveBiometricsPreference(enableBiometrics, _phoneNumber);
      }

      if (!mounted) return;

      // Show success dialog with approval pending message
      await showDialog(
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
                Icon(Icons.pending_actions, size: 64, color: appRed),
                const SizedBox(height: 16),
                Text(
                  'Account Pending Approval',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: appBlack,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account is currently pending admin approval. Please wait up to 48 hours for an administrator to review and approve your account.\n\nOnce approved, you will receive a text message and can create your PIN to login.',
                  style: TextStyle(fontSize: 14, color: appBlack),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'OK',
                      style: TextStyle(
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
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _logo(),
                    const SizedBox(height: 32),
                    Text(
                      'CREATE PIN',
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Set up your 4-digit PIN for fast login',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // Phone number display (read-only)
                    if (_phoneNumber != null && _phoneNumber!.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: appOffWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: appBlack.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_android, color: appBlack),
                            const SizedBox(width: 12),
                            Text(
                              _formatPhoneForDisplay(_phoneNumber),
                              style: TextStyle(
                                fontSize: 16,
                                color: appBlack,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                    // PIN Input
                    Text(
                      'PIN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _pinCtl,
                      keyboardType: TextInputType.number,
                      obscureText: _obscurePin,
                      maxLength: 4,
                      decoration: InputDecoration(
                        hintText: '0000',
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
                            _obscurePin
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePin = !_obscurePin),
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
                    ),
                    if (_pinError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _pinError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    // Confirm PIN Input
                    Text(
                      'CONFIRM PIN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: appBlack,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _pinConfirmCtl,
                      keyboardType: TextInputType.number,
                      obscureText: _obscureConfirm,
                      maxLength: 4,
                      decoration: InputDecoration(
                        hintText: '0000',
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
                            _obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
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
                    ),
                    if (_pinConfirmError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _pinConfirmError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                    // CREATE PIN Button
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        height: 50,
                        width: 210,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _createPin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appBlue,
                            elevation: 3,
                            shadowColor: Colors.black.withOpacity(1),
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
                                  'CREATE PIN',
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
                    const SizedBox(height: 16),
                    Text(
                      'Please remember your PIN. You will need it to login.',
                      style: TextStyle(
                        fontSize: 12,
                        color: appBlack.withOpacity(0.6),
                        fontFamily: 'RobotoCondensed',
                      ),
                      textAlign: TextAlign.center,
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
