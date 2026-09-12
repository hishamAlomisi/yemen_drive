import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final digits = widget.initialCode.replaceAll(RegExp(r'\D'), '');
    _controllers = List<TextEditingController>.generate(
      _length,
      (int index) => TextEditingController(
        text: index < digits.length ? digits[index] : '',
      ),
    );
    _focusNodes = List<FocusNode>.generate(_length, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitCode());
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
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
                    textInputAction: index == _length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    onChanged: (String value) {
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
        ),
      );

  void _emitCode() {
    widget.onChanged(
      _controllers.map((TextEditingController item) => item.text).join(),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }
}
