import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/services/user_session.dart';
import '../../semi_admin/pages/semi_admin_main_page.dart';

/// PIN setup page shown to semi-admins on their first login.
/// This allows responders to create their own PIN when their account
/// was created without one by the admin.
class SemiAdminPinSetupPage extends StatefulWidget {
  const SemiAdminPinSetupPage({super.key});

  @override
  State<SemiAdminPinSetupPage> createState() => _SemiAdminPinSetupPageState();
}

class _SemiAdminPinSetupPageState extends State<SemiAdminPinSetupPage> {
  String _pin = '';
  String _confirmPin = '';
  bool _loading = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _argsInitialized = false;
  bool _isConfirmStep = false;

  String? _semiAdminDocId;
  Map<String, dynamic>? _semiAdminData;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsInitialized) return;
    _argsInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _semiAdminDocId = args['docId'] as String?;
      _semiAdminData = args['semiAdminData'] as Map<String, dynamic>?;
    }

    final hasRequiredArgs = _semiAdminDocId != null && _semiAdminDocId!.isNotEmpty;
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
      // Update the semi_admin document with the new PIN
      await _firestore.collection('semi_admins').doc(_semiAdminDocId).update({
        'pin': _pin,
        'requiresPasswordSetup': false,
        'pinSetAt': FieldValue.serverTimestamp(),
        'isLoggedIn': true,
        'status': 'available',
        'isAvailable': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });

      // Update local session data
      final updatedData = {
        ...?_semiAdminData,
        'id': _semiAdminDocId,
        'pin': _pin,
        'requiresPasswordSetup': false,
      };
      UserSession.setUserData(updatedData);

      if (!mounted) return;

      AppSnackBar.show(
        context,
        'PIN created successfully!',
        type: AppSnackBarType.success,
      );

      // Navigate to semi-admin main screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SemiAdminMainScreen()),
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

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirmStep ? _confirmPin : _pin;
    final displayName = _semiAdminData?['fullName'] ?? 'Responder';

    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMedium,
                vertical: AppDimensions.paddingSmall,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: _goBack,
                    color: AppTheme.appBlack,
                  ),
                  const Spacer(),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.appRed.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        size: 40,
                        color: AppTheme.appRed,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Welcome message
                    Text(
                      'Welcome, $displayName!',
                      style: AppTextStyles.headline.copyWith(
                        color: AppTheme.appBlack,
                        fontSize: 24,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Instructions
                    Text(
                      _isConfirmStep
                          ? 'Confirm your 4-digit PIN'
                          : 'Create a 4-digit PIN to secure your account',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // PIN dots
                    PinDotsRow(
                      length: currentPin.length,
                      error: _showError,
                    ),
                    const SizedBox(height: 12),

                    // Error message
                    if (_showError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage,
                          style: AppTextStyles.body.copyWith(
                            color: Colors.red,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Loading indicator
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(
                          color: AppTheme.appRed,
                        ),
                      ),

                    const SizedBox(height: 24),

                    // PIN Numpad
                    PinNumpad(
                      onKey: _handlePinKey,
                      disabled: _loading,
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
