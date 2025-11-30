import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  // Brand colors
  static const appBlue = Color(0xFF004FC6);
  static const appRed = Color(0xFFD60000);
  static const appGreen = Color(0xFF00A458);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();

  final _fullNameCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _contactCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _dobDayCtl = TextEditingController();
  final _dobMonthCtl = TextEditingController();
  final _dobYearCtl = TextEditingController();

  bool _loading = false;
  bool _agree = false;
  String? _idPhotoPath;

  @override
  void dispose() {
    _fullNameCtl.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    _emailCtl.dispose();
    _contactCtl.dispose();
    _addressCtl.dispose();
    _dobDayCtl.dispose();
    _dobMonthCtl.dispose();
    _dobYearCtl.dispose();
    super.dispose();
  }

  Widget _logo() {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700),
        children: const [
          TextSpan(
            text: 'RES',
            style: TextStyle(color: appBlue),
          ),
          TextSpan(
            text: 'Q',
            style: TextStyle(color: appRed),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 12, color: appBlack),
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

  Future<void> _uploadPhoto() async {
    setState(() => _idPhotoPath = 'dummy.png');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo selected (mock)')));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agree) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must agree to terms')));
      return;
    }

    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() => _loading = false);

    if (!mounted) return;

    // After registration, open OTP verification
    Navigator.pushReplacementNamed(context, '/otp');
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // BLUE BACK BUTTON
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: appBlue,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Center(child: _logo()),
                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'REGISTER',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: appBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _fullNameCtl,
                            decoration: _fieldDecoration('FULL NAME'),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _usernameCtl,
                            decoration: _fieldDecoration('USERNAME'),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _passwordCtl,
                            obscureText: true,
                            decoration: _fieldDecoration('PASSWORD'),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Min 6 chars'
                                : null,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _emailCtl,
                            decoration: _fieldDecoration('EMAIL ADDRESS'),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _contactCtl,
                            decoration: _fieldDecoration('CONTACT NUMBER'),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: _addressCtl,
                            decoration: _fieldDecoration('HOME ADDRESS'),
                          ),
                          const SizedBox(height: 12),

                          // DOB
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'DATE OF BIRTH',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _dobMonthCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('MM'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _dobDayCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('DD'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _dobYearCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: _fieldDecoration('YY'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'SUBMIT PHOTO OF VALID ID',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: appBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          SizedBox(
                            height: 40,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _uploadPhoto,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appGreen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                _idPhotoPath == null
                                    ? 'UPLOAD PHOTO'
                                    : 'CHANGE PHOTO',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Checkbox(
                                value: _agree,
                                onChanged: (v) =>
                                    setState(() => _agree = v ?? false),
                                activeColor: appBlue,
                              ),
                              Expanded(
                                child: Text(
                                  'AGREE TO TERMS AND CONDITIONS',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: appBlack,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          SizedBox(
                            height: 42,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: appBlue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      'CREATE ACCOUNT',
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
