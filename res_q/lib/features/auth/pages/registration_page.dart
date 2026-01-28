import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/theme/app_text_styles.dart';
import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/auth_widgets.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/services/registration_prefs.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _contactCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _dobDayCtl = TextEditingController();
  final _dobMonthCtl = TextEditingController();
  final _dobYearCtl = TextEditingController();
  final _pinCtl = TextEditingController();

  bool _loading = false;
  bool _agree = false;
  bool _dobSubmitAttempted = false;
  String? _frontIdUrl;
  bool _obscurePassword = true;
  String? _termsError;
  String? _idPhotoError;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final savedPhone = await RegistrationPrefs.getPhoneNumber();
    if (savedPhone != null && mounted) {
      // Remove +63 prefix if present for display
      final displayPhone = savedPhone.startsWith('+63')
          ? savedPhone.substring(3)
          : savedPhone;
      setState(() {
        _contactCtl.text = displayPhone;
      });
    }
  }

  @override
  void dispose() {
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    _emailCtl.dispose();
    _contactCtl.dispose();
    _addressCtl.dispose();
    _dobDayCtl.dispose();
    _dobMonthCtl.dispose();
    _dobYearCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  void _onIdUploadComplete(String? frontUrl, String? backUrl) {
    setState(() {
      _frontIdUrl = frontUrl;
      if (frontUrl != null) {
        _idPhotoError = null;
      }
    });
  }

  Future<void> _showTermsAndConditions() async {
    final agreed = await TermsAndConditionsDialog.show(context);
    if (agreed) {
      setState(() {
        _agree = true;
        _termsError = null;
      });
    }
  }

  Future<bool> _checkPhoneNumberExists(String phone) async {
    try {
      // Check in pending_users
      final pendingQuery = await FirebaseFirestore.instance
          .collection('pending_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (pendingQuery.docs.isNotEmpty) {
        return true;
      }

      // Check in approved_users
      final approvedQuery = await FirebaseFirestore.instance
          .collection('approved_users')
          .where('contactNumber', isEqualTo: phone)
          .limit(1)
          .get();

      return approvedQuery.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking phone number: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    _dobSubmitAttempted = true;
    final normalizedFirstName = _firstNameCtl.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedLastName = _lastNameCtl.text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedFullName = '$normalizedFirstName $normalizedLastName';
    final normalizedUsername = _usernameCtl.text.trim();
    final normalizedEmail = _emailCtl.text.trim();
    final normalizedAddress = _addressCtl.text.trim();
    final dobMonth = _dobMonthCtl.text.trim();
    final dobDay = _dobDayCtl.text.trim();
    final dobYear = _dobYearCtl.text.trim();

    final formValid = _formKey.currentState?.validate() ?? false;
    final termsValid = _agree;
    final idValid = _frontIdUrl != null;

    setState(() {
      _termsError = termsValid
          ? null
          : 'Please read and agree to terms and conditions';
      _idPhotoError =
          idValid ? null : 'Please upload the front of your government ID';
    });

    if (!formValid || !termsValid || !idValid) {
      return;
    }

    setState(() {
      _loading = true;
    });

    // Format phone number for Firebase (E.164 format: +63XXXXXXXXXX)
    final phoneDigits = _contactCtl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+63$phoneDigits';

    // Save phone number for convenience
    await RegistrationPrefs.savePhoneNumber(phoneDigits);

    // Check if phone number already exists
    final phoneExists = await _checkPhoneNumberExists(phone);
    if (phoneExists) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This phone number is already registered. Please use a different number.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final Map<String, dynamic> userData = {
      'fullName': normalizedFullName,
      'username': normalizedUsername,
      'email': normalizedEmail.isEmpty ? null : normalizedEmail,
      'password': _passwordCtl.text.trim(),
      'pin': _pinCtl.text.trim(),
      'contactNumber': phone,
      'address': normalizedAddress,
      'dateOfBirth': '$dobMonth/$dobDay/$dobYear',
      'idPhotoFront': _frontIdUrl,
      'idPhotoBack': null,
      'role': 'user',
    };

    try {
      if (!kIsWeb) {
        await _auth.setSettings(appVerificationDisabledForTesting: kDebugMode);
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 30),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (rare on most devices)
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);
          String msg = e.message ?? 'Phone verification failed';

          if (e.code == 'invalid-phone-number') {
            msg = 'Invalid phone number. Please check and try again.';
          } else if (e.code == 'too-many-requests') {
            msg = 'Too many attempts. Please try again later.';
          } else if (e.code == 'missing-phone-number') {
            msg = 'Phone number is required.';
          } else if (e.code == 'app-not-authorized') {
            msg = 'App is not authorized. Please check Firebase Console.';
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() => _loading = false);

          if (mounted) {
            Navigator.pushNamed(
              context,
              '/otp',
              arguments: {
                'verificationId': verificationId,
                'phoneNumber': phone,
                'userData': userData,
              },
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout
        },
      );
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send OTP: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _isValidNamePart(String name) {
    if (name.length < 2) return false;
    if (name.length > 40) return false;
    final parts = name.split(' ');
    final wordPattern = RegExp(r"^[A-Za-z]{2,}([-''][A-Za-z]+)*\.?$");
    final initialPattern = RegExp(r"^[A-Za-z]\.?$");
    for (final part in parts) {
      if (!wordPattern.hasMatch(part) && !initialPattern.hasMatch(part)) {
        return false;
      }
    }
    return true;
  }

  bool _isValidUsername(String username) {
    if (username.length < 3 || username.length > 20) return false;
    return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(username);
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidAddress(String address) {
    if (address.length < 5 || address.length > 120) return false;
    return RegExp(r'[A-Za-z0-9]').hasMatch(address);
  }

  bool _isValidDob(String month, String day, String year) {
    final m = int.tryParse(month);
    final d = int.tryParse(day);
    final y = int.tryParse(year);
    if (m == null || d == null || y == null) return false;
    if (y < 1900 || y > DateTime.now().year) return false;
    try {
      final date = DateTime(y, m, d);
      if (date.year != y || date.month != m || date.day != d) return false;
      if (date.isAfter(DateTime.now())) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _validateFirstName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'First name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid first name';
    return null;
  }

  String? _validateLastName(String? value) {
    final normalized = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Last name is required';
    if (!_isValidNamePart(normalized)) return 'Enter a valid last name';
    return null;
  }

  String? _validateUsername(String? value) {
    final username = (value ?? '').trim();
    if (username.isEmpty) return 'Username is required';
    if (!_isValidUsername(username)) {
      return '3-20 chars, letters/numbers/_ only';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    if (password.length < 8 || !hasUpper || !hasNumber || !hasSpecial) {
      return '8+ chars, uppercase, number, special char (!@#\$%^&*)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email address is required';
    return _isValidEmail(email) ? null : 'Enter a valid email address';
  }

  String? _validateAddress(String? value) {
    final address = (value ?? '').trim();
    if (address.isEmpty) return 'Home address is required';
    return _isValidAddress(address) ? null : 'Enter a valid home address';
  }

  String? _validateDobMonth(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return _dobSubmitAttempted ? 'Month is required' : null;
    final m = int.tryParse(v);
    if (v.length != 2) return 'Use 2 digits (MM)';
    if (m == null || m < 1 || m > 12) return 'Invalid month';
    return null;
  }

  String? _validateDobDay(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return _dobSubmitAttempted ? 'Day is required' : null;
    final d = int.tryParse(v);
    if (v.length != 2) return 'Use 2 digits (DD)';
    if (d == null || d < 1 || d > 31) return 'Invalid day';
    return null;
  }

  String? _validateDobYear(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return _dobSubmitAttempted ? 'Year is required' : null;
    if (v.length != 4) return 'Use 4 digits (YYYY)';
    final y = int.tryParse(v);
    final currentYear = DateTime.now().year;
    if (y == null || y < 1900 || y > currentYear) {
      return 'Invalid year';
    }
    final month = _dobMonthCtl.text.trim();
    final day = _dobDayCtl.text.trim();
    if (month.isNotEmpty && day.isNotEmpty) {
      if (!_isValidDob(month, day, v)) return 'Invalid date';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appOffWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingXLarge,
                  vertical: AppDimensions.paddingLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BACK BUTTON AND LOGO ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const ResqBackButton(),
                        const ResqLogo(fontSize: 48),
                        const SizedBox(width: 44), // Balance the row
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingSmall),

                    Center(
                      child: Text(
                        'REGISTER',
                        style: AppTextStyles.authPageTitle,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingXLarge),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // FIRST NAME AND LAST NAME INLINE
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: AuthTextField(
                                  controller: _firstNameCtl,
                                  label: 'FIRST NAME',
                                  hintText: 'e.g. Juan',
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r"[a-zA-Z .'-]"),
                                    ),
                                  ],
                                  validator: _validateFirstName,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                ),
                              ),
                              const SizedBox(width: AppDimensions.paddingSmall),
                              Expanded(
                                child: AuthTextField(
                                  controller: _lastNameCtl,
                                  label: 'LAST NAME',
                                  hintText: 'e.g. Dela Cruz',
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r"[a-zA-Z .'-]"),
                                    ),
                                  ],
                                  validator: _validateLastName,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          AuthTextField(
                            controller: _usernameCtl,
                            label: 'USERNAME',
                            hintText: 'e.g. juan_delacruz',
                            validator: _validateUsername,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          AuthTextField(
                            controller: _passwordCtl,
                            label: 'PASSWORD',
                            hintText: 'e.g. Resq@123',
                            obscureText: _obscurePassword,
                            validator: _validatePassword,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: AppTheme.appBlack,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          AuthTextField(
                            controller: _emailCtl,
                            label: 'EMAIL ADDRESS',
                            hintText: 'e.g. juan@email.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          // PHONE INPUT WITH +63 PREFIX
                          PhoneInputField(
                            controller: _contactCtl,
                            validator: validatePhilippinePhone,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          AuthTextField(
                            controller: _addressCtl,
                            label: 'HOME ADDRESS',
                            hintText: 'e.g. Blk 3 Lot 2, Brgy. Mabini, QC',
                            validator: _validateAddress,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: AppDimensions.paddingMedium),

                          DateOfBirthInput(
                            monthController: _dobMonthCtl,
                            dayController: _dobDayCtl,
                            yearController: _dobYearCtl,
                            monthValidator: _validateDobMonth,
                            dayValidator: _validateDobDay,
                            yearValidator: _validateDobYear,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                          const SizedBox(height: AppDimensions.paddingLarge),

                          // ID VERIFICATION WIDGET (FRONT ONLY)
                          IdVerificationWidget(
                            onUploadComplete: _onIdUploadComplete,
                            initialFrontUrl: _frontIdUrl,
                            usernameForPath: _usernameCtl.text,
                          ),
                          if (_idPhotoError != null) ...[
                            const SizedBox(height: AppDimensions.paddingSmall),
                            Text(
                              _idPhotoError!,
                              style: AppTextStyles.authError,
                            ),
                          ],
                          const SizedBox(height: AppDimensions.paddingLarge),

                          // TERMS CHECKBOX (DISPLAY-ONLY, CLICK LINK TO AGREE)
                          TermsCheckbox(
                            agreed: _agree,
                            onTermsTap: _showTermsAndConditions,
                          ),
                          if (_termsError != null) ...[
                            const SizedBox(height: AppDimensions.paddingSmall),
                            Text(_termsError!, style: AppTextStyles.authError),
                          ],
                          const SizedBox(height: AppDimensions.paddingLarge),

                          ResqPillButton(
                            label: 'CREATE ACCOUNT',
                            loading: _loading,
                            onPressed:
                                (_loading || _frontIdUrl == null)
                                ? null
                                : _submit,
                            height: 48,
                            radius: 30,
                            backgroundColor: AppTheme.appRed,
                            textStyle: AppTextStyles.authButton,
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
