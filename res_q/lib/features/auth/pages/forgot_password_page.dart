import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../common/widgets/app_snackbar.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // Brand colors
  static const appBlue = Color(0xFFAC1B22);
  static const appRed = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);

  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _newPassCtl = TextEditingController();
  final _confirmCtl = TextEditingController();

  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailCtl.dispose();
    _newPassCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: appBlack),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: appBlue, width: 1.5),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPassCtl.text != _confirmCtl.text) {
      AppSnackBar.show(
        context,
        'Passwords do not match',
        type: AppSnackBarType.error,
      );
      return;
    }

    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() => _loading = false);

    if (!mounted) return;

    AppSnackBar.show(
      context,
      'Password updated (mock).',
      type: AppSnackBarType.success,
    );
    Navigator.pop(context);
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
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Back button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: appBlue,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Logo at the top
                      SvgPicture.asset(
                        'assets/icons/RESQ-LOGO.svg',
                        height: 70,
                        width: 200,
                      ),
                      const SizedBox(height: 40),

                      // Title
                      const Text(
                        'FORGOT PASSWORD',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: appBlack,
                        ),
                      ),

                      const SizedBox(height: 40),

                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email Address Label
                            const Text(
                              'EMAIL ADDRESS',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailCtl,
                              style: const TextStyle(
                                fontSize: 15,
                                color: appBlack,
                                fontFamily: 'RobotoCondensed',
                              ),
                              decoration: _inputDecoration(''),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 24),

                            // New Password Label
                            const Text(
                              'NEW PASSWORD',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _newPassCtl,
                              obscureText: _obscureNew,
                              style: const TextStyle(
                                fontSize: 15,
                                color: appBlack,
                                fontFamily: 'RobotoCondensed',
                              ),
                              decoration: _inputDecoration('').copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureNew
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureNew = !_obscureNew,
                                  ),
                                ),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Min 6 chars'
                                  : null,
                            ),
                            const SizedBox(height: 24),

                            // Confirm New Password Label
                            const Text(
                              'CONFIRM NEW PASSWORD',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: appBlack,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _confirmCtl,
                              obscureText: _obscureConfirm,
                              style: const TextStyle(
                                fontSize: 15,
                                color: appBlack,
                                fontFamily: 'RobotoCondensed',
                              ),
                              decoration: _inputDecoration('').copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Required' : null,
                            ),

                            const SizedBox(height: 40),

                            // Button with shadow
                            Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  elevation: 0,
                                ),
                                child: _loading
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        'UPDATE AND PROCEED TO LOGIN',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w200,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                          fontFamily: 'RobotoCondensed',
                                        ),
                                        textAlign: TextAlign.center,
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
      ),
    );
  }
}
