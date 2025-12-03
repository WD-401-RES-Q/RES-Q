import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OTPPage extends StatefulWidget {
  const OTPPage({super.key});

  @override
  State<OTPPage> createState() => _OTPPageState();
}

class _OTPPageState extends State<OTPPage> {
  // Brand colors
  static const appBlue = Color(0xFF004FC6);
  static const appRed = Color(0xFFD60000);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final TextEditingController _otpCtl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _otpCtl.dispose();
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

  Future<void> _verify() async {
    final code = _otpCtl.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter the OTP code')));
      return;
    }

    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() => _loading = false);

    if (!mounted) return;

    // TODO: replace with real verification
    Navigator.pushReplacementNamed(context, '/main');
  }

  void _resend() {
    // TODO: hook to real resend endpoint
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OTP resent (mock)')));
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
                    // BLUE BACK BUTTON (icon only)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: appBlue,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Logo + title
                    Center(child: _logo()),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'VERIFY OTP',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: appBlack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: Text(
                        'Enter the 6 digit code sent to your\nphone number.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          color: appBlack,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // OTP input
                    Center(
                      child: SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _otpCtl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            letterSpacing: 8,
                          ),
                          maxLength: 6,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '• • • •',
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 22,
                              color: Colors.grey,
                              letterSpacing: 8,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.black87,
                                width: 1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.black87,
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: appBlue,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // VERIFY button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'VERIFY',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Center(
                      child: TextButton(
                        onPressed: _resend,
                        child: Text(
                          'Resend code',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: appBlue,
                          ),
                        ),
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
