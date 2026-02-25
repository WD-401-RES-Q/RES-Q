import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/utils/security_hash.dart';
import '../../../common/services/user_session.dart';

/// PIN setup page shown to responders on their first login.
/// This allows responders to create their own PIN when their account
/// was created without one by the admin.
class ResponderPinSetupPage extends StatefulWidget {
  const ResponderPinSetupPage({super.key});

  @override
  State<ResponderPinSetupPage> createState() => _ResponderPinSetupPageState();
}

class _ResponderPinSetupPageState extends State<ResponderPinSetupPage> {
  String _pin = '';
  String _confirmPin = '';
  bool _loading = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _argsInitialized = false;
  bool _isConfirmStep = false;

  String? _responderDocId;
  Map<String, dynamic>? _responderData;
  String? _phoneNumber;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TrustedDeviceService _trustedDeviceService =
      TrustedDeviceService.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _responderDocId = args['docId'] as String?;
      _responderData = args['responderData'] as Map<String, dynamic>?;
      _phoneNumber = args['phoneNumber'] as String?;
    }

    final hasRequiredArgs =
        _responderDocId != null && _responderDocId!.isNotEmpty;
    if (!hasRequiredArgs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackBar.show(
          context,
          'Session expired. Please login again.',
          type: AppSnackBarType.warning,
        );
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      });
    }
  }

  void _handlePinKey(String value) {
    if (_loading) return;
    setState(() {
      _showError = false;
      if (value == PinNumpad.clearKey || value == 'C') {
        if (_isConfirmStep) {
          _confirmPin = '';
        } else {
          _pin = '';
        }
        return;
      }
      if (value == PinNumpad.backspaceKey || value == '\u232b') {
        if (_isConfirmStep) {
          if (_confirmPin.isNotEmpty) {
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
          }
        } else {
          if (_pin.isNotEmpty) {
            _pin = _pin.substring(0, _pin.length - 1);
          }
        }
        return;
      }

      if (_isConfirmStep) {
        if (_confirmPin.length < 4) {
          _confirmPin += value;
          if (_confirmPin.length == 4) {
            Future.delayed(const Duration(milliseconds: 200), () {
              _verifyAndSavePin();
            });
          }
        }
      } else {
        if (_pin.length < 4) {
          _pin += value;
          if (_pin.length == 4) {
            Future.delayed(const Duration(milliseconds: 200), () {
              setState(() {
                _isConfirmStep = true;
              });
            });
          }
        }
      }
    });
  }

  Future<void> _verifyAndSavePin() async {
    if (_pin != _confirmPin) {
      setState(() {
        _showError = true;
        _errorMessage = 'PINs do not match. Please try again.';
        _pin = '';
        _confirmPin = '';
        _isConfirmStep = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final hashedPin = SecurityHash.sha256Hex(_pin);
      // Update the responder document with the new PIN
      await _firestore.collection('responders').doc(_responderDocId).update({
        'pin_hash': hashedPin,
        'hashedPin': hashedPin,
        'pin': FieldValue.delete(),
        'hasPinCreated': true,
        'pinSetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local session data
      final updatedData = {
        ...?_responderData,
        'id': _responderDocId,
        'pin_hash': hashedPin,
        'hashedPin': hashedPin,
        'hasPinCreated': true,
      };
      UserSession.setUserData(updatedData);

      final phone = (_phoneNumber ?? _responderData?['contactNumber'] ?? '')
          .toString()
          .trim();
      if (phone.isNotEmpty) {
        final digits = phone.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 10) {
          await RegistrationPrefs.savePhoneNumber(
            digits.substring(digits.length - 10),
          );
        }
        await _trustedDeviceService.markTrusted(phone);
      }

      if (!mounted) return;

      AppSnackBar.show(
        context,
        'PIN created successfully!',
        type: AppSnackBarType.success,
      );

      // After first-time setup, continue through PIN login.
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (_) => false,
        arguments: {
          if (phone.isNotEmpty) 'trustedPhone': phone,
          'directPin': true,
        },
      );
    } catch (e) {
      debugPrint('Error setting up PIN: $e');
      setState(() {
        _loading = false;
        _showError = true;
        _errorMessage = 'Failed to save PIN. Please try again.';
        _pin = '';
        _confirmPin = '';
        _isConfirmStep = false;
      });
    }
  }

  void _goBack() {
    if (_isConfirmStep) {
      setState(() {
        _isConfirmStep = false;
        _confirmPin = '';
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _buildPinDots(String currentPin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (index) {
        final isFilled = index < currentPin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (_showError ? Colors.red : AppTheme.appRed)
                : Colors.transparent,
            border: Border.all(
              color: _showError
                  ? Colors.red
                  : AppTheme.appBlack.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirmStep ? _confirmPin : _pin;
    final displayName = _responderData?['fullName'] ?? 'Responder';

    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppDimensions.paddingSmall,
                  left: AppDimensions.paddingXSmall,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 24),
                  onPressed: _goBack,
                  color: AppTheme.appBlack,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingXLarge,
                    vertical: AppDimensions.paddingSmall,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: AppTheme.appRed.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            size: 46,
                            color: AppTheme.appRed,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.paddingXLarge),
                        Text(
                          'Welcome, $displayName!',
                          style: AppTextStyles.heading1.copyWith(
                            color: AppTheme.appBlack,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppDimensions.paddingSmall),
                        Text(
                          _isConfirmStep
                              ? 'Confirm your personal PIN'
                              : 'Set your personal PIN',
                          style: AppTextStyles.inputText.copyWith(
                            color: AppTheme.appBlack.withValues(alpha: 0.55),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        _loading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.appRed,
                                ),
                              )
                            : _buildPinDots(currentPin),
                        if (_showError) ...[
                          const SizedBox(height: AppDimensions.paddingMedium),
                          Text(
                            _errorMessage,
                            style: AppTextStyles.inputText.copyWith(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 28),
                        PinNumpad(
                          onKeyTap: _handlePinKey,
                          enabled: !_loading,
                          buttonSize: 78,
                          gap: 12,
                          actionBackgroundColor: AppTheme.appOffWhite,
                          textColor: AppTheme.appBlack,
                        ),
                        const SizedBox(height: AppDimensions.paddingLarge),
                      ],
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
