import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';

class PINCreationPage extends StatefulWidget {
  const PINCreationPage({super.key});

  @override
  State<PINCreationPage> createState() => _PINCreationPageState();
}

class _PINCreationPageState extends State<PINCreationPage> {
  String _pin = '';
  bool _loading = false;
  bool _showError = false;
  String _errorMessage = '';

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

  String _formatPhoneForDisplay(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63')) digits = digits.substring(2);
    if (digits.length == 10) {
      return '+63 ${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    setState(() {
      _showError = false;
      if (value == 'C') {
        _pin = '';
        return;
      }
      if (value == '⌫') {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
        return;
      }
      if (_pin.length < 4) {
        _pin += value;
        if (_pin.length == 4) {
          Future.delayed(const Duration(milliseconds: 200), () {
            _createPin();
          });
        }
      }
    });
  }

  Future<bool> _checkBiometricsAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
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
      return null;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.appRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fingerprint,
                  size: 48,
                  color: AppTheme.appRed,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              Text(
                'ENABLE BIOMETRIC\nLOGIN?',
                style: AppTextStyles.authPageTitle.copyWith(height: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              Text(
                'Would you like to use fingerprint or face recognition for faster login?',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.appBlack,
                  fontFamily: 'RobotoCondensed',
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingSmall),
              Text(
                'You can change this later in settings.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.appBlack.withOpacity(0.6),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.appBlack,
                        side: BorderSide(
                          color: AppTheme.appBlack.withOpacity(0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'No Thanks',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.appBlack,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.appRed,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
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

  Future<void> _saveBiometricsPreference(
    bool enabled,
    String? phoneNumber,
  ) async {
    try {
      // Save to SharedPreferences for local/quick access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', enabled);
      if (phoneNumber != null) {
        await prefs.setString('biometrics_phone', phoneNumber);
      }

      // Save to Firestore for persistence across devices (like votes)
      if (phoneNumber != null) {
        final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
        await _firestore.collection('userPreferences').doc(cleanPhone).set({
          'biometricsEnabled': enabled,
          'biometricsUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Biometrics preference saved to Firestore: $enabled');
      }

      debugPrint('✅ Biometrics preference saved locally: $enabled');
    } catch (e) {
      debugPrint('Error saving biometrics preference: $e');
    }
  }

  Future<void> _createPin() async {
    if (_pin.length != 4) {
      setState(() {
        _showError = true;
        _errorMessage = 'PIN must be exactly 4 digits';
      });
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(_pin)) {
      setState(() {
        _showError = true;
        _errorMessage = 'PIN must contain only numbers';
        _pin = '';
      });
      return;
    }

    setState(() => _loading = true);

    try {
      if (_uid == null) {
        throw Exception('User ID not found');
      }

      final userData = _userData ?? {};
      userData['pin'] = _pin;
      userData['accountStatus'] = 'pending';
      userData['createdAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('pending_users').doc(_uid).set(userData);

      setState(() => _loading = false);

      if (!mounted) return;

      final enableBiometrics = await _showBiometricsOptInDialog();

      if (enableBiometrics != null) {
        await _saveBiometricsPreference(enableBiometrics, _phoneNumber);
      }

      if (!mounted) return;

      await _showApprovalPendingDialog();
    } catch (e) {
      setState(() {
        _loading = false;
        _showError = true;
        _errorMessage = 'Error: $e';
        _pin = '';
      });
      if (mounted) {
        AppSnackBar.show(context, 'Error: $e', type: AppSnackBarType.error);
      }
    }
  }

  Future<void> _showApprovalPendingDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.appOffWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.appRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: AppTheme.appRed,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              Text(
                'ACCOUNT PENDING\nAPPROVAL',
                style: AppTextStyles.authPageTitle.copyWith(height: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              Text(
                'Your account is currently pending admin approval. Please wait up to 48 hours for an administrator to review and approve your account.\n\nOnce approved, you will receive a text message and can login with your PIN.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.appBlack,
                  fontFamily: 'RobotoCondensed',
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              ResqPillButton(
                label: 'GOT IT',
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final hasValue = _pin.length > index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasValue
                ? (_showError ? Colors.red : AppTheme.appRed)
                : Colors.transparent,
            border: Border.all(
              color: _showError ? Colors.red : AppTheme.appBlack,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and logo
            Padding(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingMedium,
                left: AppDimensions.paddingXLarge,
                right: AppDimensions.paddingXLarge,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ResqBackButton.outline(),
                  const ResqLogo(fontSize: 53),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.paddingSmall),
            Text('CREATE PIN', style: AppTextStyles.authPageTitle),
            const SizedBox(height: AppDimensions.paddingSmall),

            // Content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.paddingXLarge,
                        vertical: AppDimensions.paddingMedium,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Set up your 4-digit PIN for fast login',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.appBlack.withOpacity(0.7),
                              fontFamily: 'RobotoCondensed',
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: AppDimensions.paddingLarge),

                          // Phone number display
                          if (_phoneNumber != null && _phoneNumber!.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.appOffWhite,
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusMedium,
                                ),
                                border: Border.all(
                                  color: AppTheme.appBlack.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.phone_android,
                                    color: AppTheme.appBlack,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatPhoneForDisplay(_phoneNumber),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.appBlack,
                                      fontFamily: 'RobotoCondensed',
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: AppDimensions.paddingXLarge),

                          // PIN label
                          Text(
                            'ENTER YOUR PIN',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.appBlack,
                              fontFamily: 'Roboto',
                              letterSpacing: 1,
                            ),
                          ),

                          const SizedBox(height: AppDimensions.paddingMedium),

                          // PIN dots
                          _loading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.appRed,
                                  ),
                                )
                              : _buildPinDots(),

                          // Error message
                          if (_showError) ...[
                            const SizedBox(height: AppDimensions.paddingMedium),
                            Text(
                              _errorMessage,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          const SizedBox(height: AppDimensions.paddingXLarge),

                          // Numpad
                          PinNumpad(
                            enabled: !_loading,
                            onKeyTap: _handlePinKey,
                            actionBackgroundColor: AppTheme.appOffWhite,
                            textColor: AppTheme.appBlack,
                          ),

                          const SizedBox(height: AppDimensions.paddingLarge),

                          Text(
                            'Please remember your PIN.\nYou will need it to login.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.appBlack.withOpacity(0.6),
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
          ],
        ),
      ),
    );
  }
}
