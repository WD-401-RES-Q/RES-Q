import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../common/constants/app_dimensions.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/auth_widgets.dart';

const TextStyle _recoveryValidationErrorTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: Colors.red,
);
const TextStyle _recoveryFieldLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w900,
  color: Color(0xFF212121),
  fontFamily: 'Roboto',
);
const TextStyle _recoveryFieldInputTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  color: Color(0xFF212121),
  fontFamily: 'RobotoCondensed',
);
const TextStyle _recoveryFieldHintTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  color: Color(0x80212121),
  fontFamily: 'RobotoCondensed',
);

class AccountRecoveryEmailStep extends StatelessWidget {
  const AccountRecoveryEmailStep({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.loading,
    required this.onContinue,
    required this.emailValidator,
  });

  static const Color _appBlue = Color(0xFFAC1B22);

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool loading;
  final VoidCallback onContinue;
  final String? Function(String?) emailValidator;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: emailController,
            label: 'EMAIL ADDRESS',
            hintText: 'Enter your registered email',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: emailValidator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            labelTextStyle: _recoveryFieldLabelTextStyle,
            textStyle: _recoveryFieldInputTextStyle,
            hintTextStyle: _recoveryFieldHintTextStyle,
            reserveErrorSpace: true,
            reservedErrorHeight: 16,
            errorTextStyle: _recoveryValidationErrorTextStyle,
          ),
          const SizedBox(height: 20),
          ResqPillButton(
            label: 'CONTINUE',
            onPressed: loading ? null : onContinue,
            loading: loading,
            backgroundColor: _appBlue,
            shadowColor: _appBlue.withValues(alpha: 0.3),
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
}

class AccountRecoveryOtpStep extends StatefulWidget {
  const AccountRecoveryOtpStep({
    super.key,
    required this.otpController,
    required this.otpError,
    required this.loading,
    required this.isOtpComplete,
    required this.onVerify,
    required this.onResend,
  });

  final TextEditingController otpController;
  final String otpError;
  final bool loading;
  final bool isOtpComplete;
  final VoidCallback onVerify;
  final VoidCallback onResend;

  @override
  State<AccountRecoveryOtpStep> createState() => _AccountRecoveryOtpStepState();
}

class _AccountRecoveryOtpStepState extends State<AccountRecoveryOtpStep> {
  static const Color _appBlue = Color(0xFFAC1B22);
  static const Color _appBlack = Color(0xFF212121);
  static const int _otpLength = 6;
  static const double _otpBoxSpacing = 8;
  static const double _errorSlotHeight = 34;

  final List<TextEditingController> _digitControllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );
  bool _isProgrammaticUpdate = false;

  @override
  void initState() {
    super.initState();
    widget.otpController.addListener(_syncFromExternalController);
    _applyDigits(widget.otpController.text);
  }

  @override
  void didUpdateWidget(covariant AccountRecoveryOtpStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.otpController == widget.otpController) return;

    oldWidget.otpController.removeListener(_syncFromExternalController);
    widget.otpController.addListener(_syncFromExternalController);
    _applyDigits(widget.otpController.text);
  }

  @override
  void dispose() {
    widget.otpController.removeListener(_syncFromExternalController);
    for (final controller in _digitControllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String _sanitizeDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  void _syncFromExternalController() {
    if (_isProgrammaticUpdate) return;

    final external = _sanitizeDigits(widget.otpController.text);
    final current = _digitControllers
        .map((controller) => controller.text)
        .join();
    if (external == current) return;

    _applyDigits(external);
  }

  void _applyDigits(String rawDigits) {
    final digits = _sanitizeDigits(rawDigits);

    _isProgrammaticUpdate = true;
    for (int i = 0; i < _otpLength; i++) {
      final value = i < digits.length ? digits[i] : '';
      _digitControllers[i].text = value;
      _digitControllers[i].selection = TextSelection.collapsed(
        offset: value.length,
      );
    }
    _isProgrammaticUpdate = false;

    if (mounted) {
      setState(() {});
    }
  }

  void _syncToExternalController() {
    final code = _digitControllers.map((controller) => controller.text).join();
    if (widget.otpController.text == code) return;

    _isProgrammaticUpdate = true;
    widget.otpController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    _isProgrammaticUpdate = false;
  }

  void _fillDigitsFromIndex(int startIndex, String rawDigits) {
    final digits = _sanitizeDigits(rawDigits);
    if (digits.isEmpty) return;

    _isProgrammaticUpdate = true;
    int nextFocus = startIndex;
    for (
      int i = 0;
      i < digits.length && nextFocus < _otpLength;
      i++, nextFocus++
    ) {
      _digitControllers[nextFocus].text = digits[i];
      _digitControllers[nextFocus].selection = const TextSelection.collapsed(
        offset: 1,
      );
    }
    _isProgrammaticUpdate = false;

    _syncToExternalController();
    if (!mounted) return;
    setState(() {});

    if (nextFocus >= _otpLength) {
      _focusNodes[_otpLength - 1].unfocus();
    } else {
      _focusNodes[nextFocus].requestFocus();
    }
  }

  void _onDigitChanged(int index, String value) {
    if (_isProgrammaticUpdate) return;

    final digits = _sanitizeDigits(value);
    if (digits.isEmpty) {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
        final previous = _digitControllers[index - 1];
        previous.selection = TextSelection.collapsed(
          offset: previous.text.length,
        );
      }
      _syncToExternalController();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (digits.length > 1) {
      _fillDigitsFromIndex(index, digits);
      return;
    }

    _isProgrammaticUpdate = true;
    _digitControllers[index].text = digits;
    _digitControllers[index].selection = const TextSelection.collapsed(
      offset: 1,
    );
    _isProgrammaticUpdate = false;

    _syncToExternalController();
    if (index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }

    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleDigitKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _digitControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      final previous = _digitControllers[index - 1];
      previous.selection = TextSelection.collapsed(
        offset: previous.text.length,
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildOtpDigitField({required int index, required double boxWidth}) {
    return SizedBox(
      width: boxWidth,
      child: Focus(
        onKeyEvent: (_, event) => _handleDigitKeyEvent(index, event),
        child: TextField(
          controller: _digitControllers[index],
          focusNode: _focusNodes[index],
          autofocus: index == 0,
          enabled: !widget.loading,
          keyboardType: TextInputType.number,
          textInputAction: index == _otpLength - 1
              ? TextInputAction.done
              : TextInputAction.next,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _appBlack,
            fontFamily: 'Roboto',
          ),
          cursorColor: _appBlue,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF7F8F3),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: BorderSide(
                color: _appBlack.withValues(alpha: 0.35),
                width: 1.4,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: BorderSide(
                color: _appBlack.withValues(alpha: 0.35),
                width: 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              borderSide: const BorderSide(color: _appBlue, width: 1.8),
            ),
          ),
          onChanged: (value) => _onDigitChanged(index, value),
          onTap: () {
            _digitControllers[index].selection = TextSelection.collapsed(
              offset: _digitControllers[index].text.length,
            );
          },
        ),
      ),
    );
  }

  Widget _buildOtpInputRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawBoxWidth =
            (constraints.maxWidth - (_otpBoxSpacing * (_otpLength - 1))) /
            _otpLength;
        final boxWidth = rawBoxWidth.clamp(42.0, 50.0).toDouble();
        final rowWidth =
            (boxWidth * _otpLength) + (_otpBoxSpacing * (_otpLength - 1));

        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: rowWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_otpLength, (index) {
                final rightPadding = index == _otpLength - 1
                    ? 0.0
                    : _otpBoxSpacing;
                return Padding(
                  padding: EdgeInsets.only(right: rightPadding),
                  child: _buildOtpDigitField(index: index, boxWidth: boxWidth),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Enter the 6-digit code sent to your email.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: _appBlack.withValues(alpha: 0.75),
            fontFamily: 'RobotoCondensed',
          ),
        ),
        const SizedBox(height: 18),
        _buildOtpInputRow(),
        const SizedBox(height: 10),
        SizedBox(
          height: _errorSlotHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              widget.otpError.isNotEmpty ? widget.otpError : ' ',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.otpError.isNotEmpty
                    ? Colors.red
                    : Colors.transparent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ResqPillButton(
          label: 'VERIFY CODE',
          onPressed: (widget.loading || !widget.isOtpComplete)
              ? null
              : widget.onVerify,
          loading: widget.loading,
          backgroundColor: _appBlue,
          shadowColor: _appBlue.withValues(alpha: 0.3),
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
          onPressed: widget.loading ? null : widget.onResend,
          child: const Text(
            'Resend code',
            style: TextStyle(
              fontSize: 13,
              color: _appBlue,
              fontWeight: FontWeight.w700,
              fontFamily: 'RobotoCondensed',
            ),
          ),
        ),
      ],
    );
  }
}

class AccountRecoveryPhoneStep extends StatelessWidget {
  const AccountRecoveryPhoneStep({
    super.key,
    required this.formKey,
    required this.newPhoneController,
    required this.confirmPhoneController,
    required this.phoneError,
    required this.loading,
    required this.canContinue,
    required this.onContinue,
  });

  static const Color _appBlue = Color(0xFFAC1B22);
  static const double _errorSlotHeight = 16;

  final GlobalKey<FormState> formKey;
  final TextEditingController newPhoneController;
  final TextEditingController confirmPhoneController;
  final String phoneError;
  final bool loading;
  final bool canContinue;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final newDigits = newPhoneController.text.replaceAll(RegExp(r'\D'), '');
    final confirmDigits = confirmPhoneController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );
    final mismatchMessage =
        newDigits.length == 10 &&
            confirmDigits.length == 10 &&
            newDigits != confirmDigits
        ? 'Phone numbers do not match. Please try again.'
        : '';
    final effectivePhoneError = phoneError.isNotEmpty
        ? phoneError
        : mismatchMessage;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneInputField(
            controller: newPhoneController,
            label: 'NEW PHONE NUMBER',
            validator: validatePhilippinePhone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            autofillHints: const [AutofillHints.telephoneNumber],
            labelTextStyle: _recoveryFieldLabelTextStyle,
            textStyle: _recoveryFieldInputTextStyle,
            hintTextStyle: _recoveryFieldHintTextStyle,
            reserveErrorSpace: true,
            reservedErrorHeight: 16,
            errorTextStyle: _recoveryValidationErrorTextStyle,
          ),
          const SizedBox(height: 10),
          PhoneInputField(
            controller: confirmPhoneController,
            label: 'CONFIRM PHONE NUMBER',
            validator: validatePhilippinePhone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            labelTextStyle: _recoveryFieldLabelTextStyle,
            textStyle: _recoveryFieldInputTextStyle,
            hintTextStyle: _recoveryFieldHintTextStyle,
            reserveErrorSpace: true,
            reservedErrorHeight: 16,
            errorTextStyle: _recoveryValidationErrorTextStyle,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _errorSlotHeight,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                effectivePhoneError.isNotEmpty ? effectivePhoneError : ' ',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: effectivePhoneError.isNotEmpty
                      ? Colors.red
                      : Colors.transparent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ResqPillButton(
            label: 'CONTINUE',
            onPressed: (loading || !canContinue) ? null : onContinue,
            loading: loading,
            backgroundColor: _appBlue,
            shadowColor: _appBlue.withValues(alpha: 0.3),
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
}

class AccountRecoveryPinStep extends StatelessWidget {
  const AccountRecoveryPinStep({
    super.key,
    required this.isConfirmStep,
    required this.pinLength,
    required this.pinError,
    required this.loading,
    required this.shakeAnimation,
    required this.shakeController,
    required this.onKeyTap,
  });

  static const Color _appBlack = Color(0xFF212121);
  static const Color _appOffWhite = Color(0xFFF7F8F3);

  final bool isConfirmStep;
  final int pinLength;
  final String pinError;
  final bool loading;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final ValueChanged<String> onKeyTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isConfirmStep
              ? 'Confirm your new 4-digit PIN'
              : 'Create your new 4-digit PIN',
          style: TextStyle(
            fontSize: 14,
            color: _appBlack.withValues(alpha: 0.75),
            fontFamily: 'RobotoCondensed',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _RecoveryPinDots(
          pinLength: pinLength,
          hasError: pinError.isNotEmpty,
          shakeAnimation: shakeAnimation,
          shakeController: shakeController,
        ),
        if (pinError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            pinError,
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
          enabled: !loading,
          onKeyTap: onKeyTap,
          actionBackgroundColor: _appOffWhite,
          textColor: _appBlack,
        ),
      ],
    );
  }
}

class _RecoveryPinDots extends StatelessWidget {
  const _RecoveryPinDots({
    required this.pinLength,
    required this.hasError,
    required this.shakeAnimation,
    required this.shakeController,
  });

  static const Color _appBlue = Color(0xFFAC1B22);
  static const Color _appBlack = Color(0xFF212121);

  final int pinLength;
  final bool hasError;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shakeAnimation,
      builder: (context, child) {
        final offset =
            shakeAnimation.value *
            10 *
            (1 - shakeAnimation.value) *
            ((shakeController.value * 8).floor() % 2 == 0 ? 1 : -1);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final filled = pinLength > index;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (hasError ? Colors.red : _appBlue)
                  : Colors.transparent,
              border: Border.all(
                color: hasError ? Colors.red : _appBlack,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }
}
