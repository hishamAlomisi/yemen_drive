import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/otp_sms_service.dart';

class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    required this.onChanged,
    this.initialCode = '',
    this.autofocus = true,
    super.key,
  });

  final String initialCode;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  static const int _length = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    final digits = OtpSmsService.normalizeDigits(widget.initialCode);
    _controllers = List<TextEditingController>.generate(
      _length,
      (int index) => TextEditingController(
        text: index < digits.length ? digits[index] : '',
      ),
    );
    _focusNodes = List<FocusNode>.generate(_length, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitCode();
      unawaited(OtpSmsService.attach((code) {
        if (mounted) _applyCode(code);
      }),);
    });
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCode != widget.initialCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyCode(widget.initialCode);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AutofillGroup(child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final cellWidth = ((constraints.maxWidth - 40) / _length)
                .clamp(40.0, 56.0)
                .toDouble();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(
                _length,
                (int index) => SizedBox(
                  width: cellWidth,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    autofocus: widget.autofocus &&
                        index ==
                            widget.initialCode.length.clamp(0, _length - 1),
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    autofillHints: index == 0
                        ? const <String>[AutofillHints.oneTimeCode]
                        : null,
                    textInputAction: index == _length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                    inputFormatters: <TextInputFormatter>[
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final digits =
                            OtpSmsService.normalizeDigits(newValue.text);
                        return TextEditingValue(
                          text: digits,
                          selection:
                              TextSelection.collapsed(offset: digits.length),
                        );
                      }),
                      LengthLimitingTextInputFormatter(_length),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    onChanged: (String value) {
                      if (value.length > 1) {
                        _applyCode(value,
                            startIndex: value.length == _length ? 0 : index,);
                        return;
                      }
                      if (value.isNotEmpty && index < _length - 1) {
                        _focusNodes[index + 1].requestFocus();
                      } else if (value.isEmpty && index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                      _emitCode();
                    },
                  ),
                ),
              ),
            );
          },
        ),),
      );

  void _applyCode(String value, {int startIndex = 0}) {
    final digits = OtpSmsService.normalizeDigits(value);
    for (var index = startIndex; index < _length; index++) {
      final offset = index - startIndex;
      _controllers[index].text = offset < digits.length ? digits[offset] : '';
    }
    final nextIndex = (startIndex + digits.length).clamp(0, _length - 1);
    if (widget.autofocus) _focusNodes[nextIndex].requestFocus();
    _emitCode();
  }

  void _emitCode() {
    widget.onChanged(
      _controllers.map((TextEditingController item) => item.text).join(),
    );
  }

  @override
  void dispose() {
    unawaited(OtpSmsService.detach());
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }
}
