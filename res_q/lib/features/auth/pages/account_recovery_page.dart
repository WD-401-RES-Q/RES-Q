import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/phone_lookup_service.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/utils/security_hash.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';

enum _RecoveryStep { emailEntry, emailOtp, newPhone, createPin, confirmPin }

class AccountRecoveryPage extends StatefulWidget {
  const AccountRecoveryPage({super.key});

  @override
  State<AccountRecoveryPage> createState() => _AccountRecoveryPageState();
}

class _AccountRecoveryPageState extends State<AccountRecoveryPage>
    with SingleTickerProviderStateMixin {
  static const Color appBlue = Color(0xFFAC1B22);
  static const Color appBlack = Color(0xFF212121);
  static const Color appOffWhite = Color(0xFFF7F8F3);

  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _otpCtl = TextEditingController();
  final _newPhoneCtl = TextEditingController();
  final _confirmPhoneCtl = TextEditingController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhoneLookupService _phoneLookupService = PhoneLookupService.instance;
  final TrustedDeviceService _trustedDeviceService =
      TrustedDeviceService.instance;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  _RecoveryStep _step = _RecoveryStep.emailEntry;
  bool _loading = false;

  String _otpHash = '';
  DateTime? _otpExpiresAt;
  String _otpError = '';
  String _phoneError = '';
  String _pinError = '';

  String _pin = '';
  String _confirmPin = '';

  String? _accountCollection;
  String? _accountDocId;
  Map<String, dynamic>? _accountData;
  String? _updatedPhone;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _otpCtl.addListener(_onFieldStateChanged);
    _newPhoneCtl.addListener(_onFieldStateChanged);
    _confirmPhoneCtl.addListener(_onFieldStateChanged);
  }

  @override
  void dispose() {
    _otpCtl.removeListener(_onFieldStateChanged);
    _newPhoneCtl.removeListener(_onFieldStateChanged);
    _confirmPhoneCtl.removeListener(_onFieldStateChanged);
    _emailCtl.dispose();
    _otpCtl.dispose();
    _newPhoneCtl.dispose();
    _confirmPhoneCtl.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _onFieldStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _isOtpComplete => _otpCtl.text.trim().length == 6;

  bool get _canContinuePhoneStep {
    final newDigits = _newPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = _confirmPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    return newDigits.length == 10 &&
        confirmDigits.length == 10 &&
        newDigits == confirmDigits;
  }

  void _triggerShake() {
    _shakeController
      ..reset()
      ..forward();
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Email is required';
    }
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!isValid) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String _normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findByEmail(
    String collection,
    String normalizedEmail,
  ) async {
    final lowerQuery = await _firestore
        .collection(collection)
        .where('emailLower', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (lowerQuery.docs.isNotEmpty) {
      return lowerQuery.docs.first;
    }

    final exactQuery = await _firestore
        .collection(collection)
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (exactQuery.docs.isNotEmpty) {
      return exactQuery.docs.first;
    }

    return null;
  }

  Future<void> _continueWithEmail() async {
    if (!_emailFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _otpError = '';
    });

    try {
      final normalizedEmail = _normalizeEmail(_emailCtl.text);

      final approvedDoc = await _findByEmail('approved_users', normalizedEmail);
      QueryDocumentSnapshot<Map<String, dynamic>>? accountDoc = approvedDoc;
      var collection = 'approved_users';

      if (accountDoc == null) {
        final pendingDoc = await _findByEmail('pending_users', normalizedEmail);
        accountDoc = pendingDoc;
        collection = 'pending_users';
      }

      if (accountDoc == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
        });
        AppSnackBar.show(
          context,
          'No account found with this email address.',
          type: AppSnackBarType.error,
        );
        return;
      }

      _accountCollection = collection;
      _accountDocId = accountDoc.id;
      _accountData = accountDoc.data();

      await _sendEmailOtp();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _RecoveryStep.emailOtp;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Failed to start account recovery. Please try again.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _sendEmailOtp() async {
    final random = Random.secure();
    final code = (100000 + random.nextInt(900000)).toString();
    _otpHash = SecurityHash.sha256Hex(code);
    _otpExpiresAt = DateTime.now().add(const Duration(minutes: 10));
    _otpCtl.clear();
    _otpError = '';

    if (!mounted) return;
    final message = kDebugMode
        ? 'Verification code sent. Debug OTP: $code'
        : 'Verification code sent to your email.';
    AppSnackBar.show(context, message, type: AppSnackBarType.success);
  }

  Future<void> _verifyEmailOtp() async {
    final otp = _otpCtl.text.trim();
    if (otp.length != 6) {
      setState(() {
        _otpError = 'Enter the 6-digit code sent to your email.';
      });
      return;
    }

    final expired =
        _otpExpiresAt == null || DateTime.now().isAfter(_otpExpiresAt!);
    if (expired) {
      setState(() {
        _otpError = 'Code expired. Please resend and try again.';
      });
      return;
    }

    final otpHash = SecurityHash.sha256Hex(otp);
    if (_otpHash.isEmpty || _otpHash != otpHash) {
      setState(() {
        _otpError = 'Incorrect code';
      });
      return;
    }

    setState(() {
      _otpError = '';
      _step = _RecoveryStep.newPhone;
    });
  }

  Future<void> _continueWithNewPhone() async {
    if (!_phoneFormKey.currentState!.validate()) {
      return;
    }

    final newDigits = _newPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = _confirmPhoneCtl.text.replaceAll(RegExp(r'\D'), '');

    if (newDigits != confirmDigits) {
      setState(() {
        _phoneError = 'Phone numbers do not match. Please try again.';
      });
      return;
    }

    final newPhone = '+63$newDigits';
    final oldPhone =
        (_accountData?['contactNumber'] ?? _accountData?['phoneNumber'])
            ?.toString()
            .trim();

    setState(() {
      _loading = true;
      _phoneError = '';
    });

    try {
      if (oldPhone != newPhone) {
        final conflict = await _phoneLookupService.lookupAccountStatus(
          newPhone,
          useCache: false,
        );
        if (conflict.hasApprovedAccount ||
            conflict.isPendingAccount ||
            conflict.hasResponderAccount) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _phoneError =
                'Phone number already in use. Please try another one.';
          });
          return;
        }
      }

      final collection = _accountCollection!;
      final docId = _accountDocId!;
      await _firestore.collection(collection).doc(docId).set({
        'contactNumber': newPhone,
        'phoneNumber': newPhone,
        'contactNumber_hash': SecurityHash.sha256Hex(newPhone),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _updatedPhone = newPhone;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _RecoveryStep.createPin;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _phoneError = 'Failed to update phone number. Please try again.';
      });
    }
  }

  void _handlePinKey(String value) {
    if (_loading) return;

    final isConfirm = _step == _RecoveryStep.confirmPin;
    final active = isConfirm ? _confirmPin : _pin;
    if (value == PinNumpad.clearKey || value == 'C') {
      setState(() {
        _pinError = '';
        if (isConfirm) {
          _confirmPin = '';
        } else {
          _pin = '';
        }
      });
      return;
    }

    if (value == PinNumpad.backspaceKey || value == '\u232b') {
      if (active.isEmpty) return;
      setState(() {
        _pinError = '';
        if (isConfirm) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        } else {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      });
      return;
    }

    if (active.length >= 4) return;

    setState(() {
      _pinError = '';
      if (isConfirm) {
        _confirmPin += value;
      } else {
        _pin += value;
      }
    });

    final updatedLength = isConfirm ? _confirmPin.length : _pin.length;
    if (updatedLength != 4) return;

    Future.delayed(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      if (!isConfirm) {
        setState(() {
          _step = _RecoveryStep.confirmPin;
        });
        return;
      }

      if (_confirmPin != _pin) {
        setState(() {
          _pinError = 'PINs do not match';
          _confirmPin = '';
        });
        _triggerShake();
        return;
      }

      _saveRecoveredPinAndFinish();
    });
  }

  Future<void> _saveRecoveredPinAndFinish() async {
    setState(() => _loading = true);
    try {
      final collection = _accountCollection!;
      final docId = _accountDocId!;
      final hashedPin = SecurityHash.sha256Hex(_pin);
      final payload = <String, dynamic>{
        'pin_hash': hashedPin,
        'hashedPin': hashedPin,
        'pinCreatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (collection == 'responders') {
        payload['hasPinCreated'] = true;
      }
      await _firestore
          .collection(collection)
          .doc(docId)
          .set(payload, SetOptions(merge: true));

      final updated = _updatedPhone ?? '';
      final updatedDigits = updated.replaceAll(RegExp(r'\D'), '');
      if (updatedDigits.length >= 10) {
        final local = updatedDigits.substring(updatedDigits.length - 10);
        await RegistrationPrefs.savePhoneNumber(local);
      }
      if (updated.isNotEmpty) {
        await _trustedDeviceService.markTrusted(updated);
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (_) => false,
        arguments: {'showRecoverySuccess': true},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pinError = 'Failed to save your new PIN. Please try again.';
        _confirmPin = '';
        _step = _RecoveryStep.confirmPin;
      });
      _triggerShake();
    }
  }

  Widget _buildPinDots() {
    final activePin = _step == _RecoveryStep.confirmPin ? _confirmPin : _pin;
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final offset =
            _shakeAnimation.value *
            10 *
            (1 - _shakeAnimation.value) *
            ((_shakeController.value * 8).floor() % 2 == 0 ? 1 : -1);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final filled = activePin.length > index;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (_pinError.isNotEmpty ? Colors.red : appBlue)
                  : Colors.transparent,
              border: Border.all(
                color: _pinError.isNotEmpty ? Colors.red : appBlack,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          AuthTextField(
            controller: _emailCtl,
            label: 'EMAIL ADDRESS',
            hintText: 'Enter your registered email',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: _validateEmail,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 20),
          ResqPillButton(
            label: 'CONTINUE',
            onPressed: _loading ? null : _continueWithEmail,
            loading: _loading,
            backgroundColor: appBlue,
            shadowColor: appBlue.withValues(alpha: 0.3),
            shadowBlurRadius: 12,
            shadowOffset: const Offset(0, 4),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Column(
      children: [
        Text(
          'Enter the 6-digit code sent to your email.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: appBlack.withValues(alpha: 0.75),
            fontFamily: 'RobotoCondensed',
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _otpCtl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.left,
            maxLength: 6,
            decoration: InputDecoration(
              counterText: '',
              hintText: '• • • • • •',
              hintStyle: const TextStyle(
                fontSize: 22,
                color: Colors.grey,
                letterSpacing: 8,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                borderSide: const BorderSide(color: appBlack, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                borderSide: const BorderSide(color: appBlack, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                borderSide: const BorderSide(color: appBlue, width: 1.8),
              ),
            ),
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 8,
              color: appBlack,
            ),
          ),
        ),
        if (_otpError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _otpError,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        ResqPillButton(
          label: 'VERIFY CODE',
          onPressed: (_loading || !_isOtpComplete) ? null : _verifyEmailOtp,
          loading: _loading,
          backgroundColor: appBlue,
          shadowColor: appBlue.withValues(alpha: 0.3),
          shadowBlurRadius: 12,
          shadowOffset: const Offset(0, 4),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading ? null : _sendEmailOtp,
          child: const Text(
            'Resend code',
            style: TextStyle(
              fontSize: 13,
              color: appBlue,
              fontWeight: FontWeight.w700,
              fontFamily: 'RobotoCondensed',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    final newDigits = _newPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = _confirmPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final mismatchMessage =
        newDigits.length == 10 &&
            confirmDigits.length == 10 &&
            newDigits != confirmDigits
        ? 'Phone numbers do not match. Please try again.'
        : '';
    final effectivePhoneError = _phoneError.isNotEmpty
        ? _phoneError
        : mismatchMessage;
    return Form(
      key: _phoneFormKey,
      child: Column(
        children: [
          PhoneInputField(
            controller: _newPhoneCtl,
            label: 'NEW PHONE NUMBER',
            validator: validatePhilippinePhone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: 10),
          PhoneInputField(
            controller: _confirmPhoneCtl,
            label: 'CONFIRM PHONE NUMBER',
            validator: validatePhilippinePhone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          if (effectivePhoneError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                effectivePhoneError,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ResqPillButton(
            label: 'CONTINUE',
            onPressed: (_loading || !_canContinuePhoneStep)
                ? null
                : _continueWithNewPhone,
            loading: _loading,
            backgroundColor: appBlue,
            shadowColor: appBlue.withValues(alpha: 0.3),
            shadowBlurRadius: 12,
            shadowOffset: const Offset(0, 4),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinStep() {
    final isConfirm = _step == _RecoveryStep.confirmPin;
    return Column(
      children: [
        Text(
          isConfirm
              ? 'Confirm your new 4-digit PIN'
              : 'Create your new 4-digit PIN',
          style: TextStyle(
            fontSize: 14,
            color: appBlack.withValues(alpha: 0.75),
            fontFamily: 'RobotoCondensed',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _buildPinDots(),
        if (_pinError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _pinError,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 22),
        PinNumpad(
          enabled: !_loading,
          onKeyTap: _handlePinKey,
          actionBackgroundColor: appOffWhite,
          textColor: appBlack,
        ),
      ],
    );
  }

  String _stepTitle() {
    switch (_step) {
      case _RecoveryStep.emailEntry:
        return 'Recover Your Account';
      case _RecoveryStep.emailOtp:
        return 'Verify Email Code';
      case _RecoveryStep.newPhone:
        return 'Set New Phone Number';
      case _RecoveryStep.createPin:
        return 'Create New PIN';
      case _RecoveryStep.confirmPin:
        return 'Confirm New PIN';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appOffWhite,
      body: SafeArea(
        child: Column(
          children: [
            ResqLogoHeader(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingMedium,
                left: AppDimensions.paddingXLarge,
                right: AppDimensions.paddingXLarge,
              ),
              leading: const ResqBackButton.outline(),
              title: Text(_stepTitle(), style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingXLarge,
                          vertical: AppDimensions.paddingMedium,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_step == _RecoveryStep.emailEntry)
                              _buildEmailStep(),
                            if (_step == _RecoveryStep.emailOtp)
                              _buildOtpStep(),
                            if (_step == _RecoveryStep.newPhone)
                              _buildPhoneStep(),
                            if (_step == _RecoveryStep.createPin ||
                                _step == _RecoveryStep.confirmPin)
                              _buildPinStep(),
                          ],
                        ),
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
