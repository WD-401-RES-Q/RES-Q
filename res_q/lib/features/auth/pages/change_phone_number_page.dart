import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/services/notification_service.dart';
import '../../../common/services/phone_lookup_service.dart';
import '../../../common/services/registration_prefs.dart';
import '../../../common/services/trusted_device_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/custom_form_fields.dart';

class ChangePhoneNumberPage extends StatefulWidget {
  const ChangePhoneNumberPage({super.key});

  @override
  State<ChangePhoneNumberPage> createState() => _ChangePhoneNumberPageState();
}

class _ChangePhoneNumberPageState extends State<ChangePhoneNumberPage> {
  static const String _phoneLookupScopeKey = 'change-phone-number';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneCtl = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PhoneLookupService _phoneLookupService = PhoneLookupService.instance;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phoneCtl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneLookupService.cancelDebounce(_phoneLookupScopeKey);
    _phoneCtl.removeListener(_onPhoneChanged);
    _phoneCtl.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    _phoneLookupService.cancelDebounce(_phoneLookupScopeKey);
    if (phoneDigits.length != 10) return;

    _phoneLookupService
        .debouncedLookupAccountStatus(
          scopeKey: _phoneLookupScopeKey,
          phone: '+63$phoneDigits',
        )
        .catchError((_) => null);
  }

  bool _isAccountApproved(Map<String, dynamic> data) {
    final isApproved = data['isApproved'];
    if (isApproved is bool) {
      return isApproved;
    }
    final accountStatus = (data['accountStatus'] as String?)
        ?.trim()
        .toLowerCase();
    return accountStatus == 'approved';
  }

  Future<void> _submitPhoneNumber() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final phoneDigits = _phoneCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneDigits';

    setState(() => _loading = true);

    try {
      final lookup = await _phoneLookupService.lookupAccountStatus(
        phone,
        useCache: false,
      );
      if (!mounted) return;

      if (lookup.isBannedAccount) {
        setState(() => _loading = false);
        AppSnackBar.show(
          context,
          'This account is restricted. Please contact support.',
          type: AppSnackBarType.error,
        );
        return;
      }

      if (lookup.isPendingAccount && !lookup.hasApprovedAccount) {
        setState(() => _loading = false);
        AppSnackBar.show(
          context,
          'Your account is pending admin approval.',
          type: AppSnackBarType.warning,
        );
        return;
      }

      if (!lookup.hasApprovedAccount) {
        setState(() => _loading = false);
        AppSnackBar.show(
          context,
          'No approved account found for this number.',
          type: AppSnackBarType.error,
        );
        return;
      }

      final userDoc = await _phoneLookupService.getFirstApprovedUserDoc(phone);
      if (!mounted) return;
      if (userDoc == null || !_isAccountApproved(userDoc.data())) {
        setState(() => _loading = false);
        AppSnackBar.show(
          context,
          'No approved account found for this number.',
          type: AppSnackBarType.error,
        );
        return;
      }

      await _startOtpChallenge(
        phone: phone,
        phoneDigits: phoneDigits,
        userDoc: userDoc,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Unable to verify this number. Please try again.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _startOtpChallenge({
    required String phone,
    required String phoneDigits,
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _loading = false);
          AppSnackBar.show(
            context,
            e.message ?? 'Failed to send OTP.',
            type: AppSnackBarType.error,
          );
        },
        codeSent: (String verificationId, int? resendToken) async {
          if (!mounted) return;
          setState(() => _loading = false);

          final otpResult = await Navigator.pushNamed(
            context,
            '/otp',
            arguments: {
              'flowType': 'login',
              'verificationId': verificationId,
              'phoneNumber': phone,
            },
          );

          if (!mounted) return;
          final verified = otpResult is Map && otpResult['verified'] == true;
          if (!verified) {
            return;
          }

          await _completeLogin(
            userDoc: userDoc,
            phone: phone,
            phoneDigits: phoneDigits,
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Failed to send OTP. Please try again.',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _completeLogin({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String phone,
    required String phoneDigits,
  }) async {
    setState(() => _loading = true);

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final sessionData = <String, dynamic>{
        ...userDoc.data(),
        'docId': userDoc.id,
        'contactNumber': phone,
        'phoneNumber': phone,
        'isApproved': true,
        'lastLoginTimestamp': nowIso,
      };

      await Future.wait([
        RegistrationPrefs.savePhoneNumber(phoneDigits),
        RegistrationPrefs.setApprovedLoginCompleted(true),
        TrustedDeviceService.instance.markTrusted(phone),
        _firestore.collection('approved_users').doc(userDoc.id).set({
          'lastLoginTimestamp': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      ]);

      UserSession.setUserData(sessionData);
      final normalizedUserId = phone.replaceAll(RegExp(r'\D'), '');
      final resolvedUserId = normalizedUserId.isEmpty
          ? userDoc.id
          : normalizedUserId;
      UserSession.setUserId(resolvedUserId);
      NotificationService().setUserId(resolvedUserId);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/main', (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBar.show(
        context,
        'Failed to complete login. Please try again.',
        type: AppSnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
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
              title: Text('CHANGE NUMBER', style: AppTextStyles.authPageTitle),
              titleSpacing: AppDimensions.paddingSmall,
              bottomSpacing: AppDimensions.paddingSmall,
            ),
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
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Enter your approved account number to continue.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.appBlack.withValues(alpha: 0.7),
                                fontFamily: 'RobotoCondensed',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            CustomPhoneField(
                              controller: _phoneCtl,
                              validator: validatePhilippinePhone,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                            ),
                            const SizedBox(height: AppDimensions.paddingLarge),
                            ResqPillButton(
                              label: 'CONTINUE',
                              loading: _loading,
                              onPressed: _loading ? null : _submitPhoneNumber,
                              height: 48,
                              radius: 30,
                              backgroundColor: AppTheme.appOffYellow,
                              shadowColor: AppTheme.appBlack.withValues(
                                alpha: 0.1,
                              ),
                              shadowBlurRadius: 8,
                              shadowOffset: const Offset(0, 2),
                              textStyle: AppTextStyles.authButton,
                            ),
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
