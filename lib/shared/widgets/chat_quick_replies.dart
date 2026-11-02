import 'package:flutter/material.dart';

class ChatQuickReplies extends StatelessWidget {
  const ChatQuickReplies(
      {required this.controller, required this.suggestions, super.key});
  final TextEditingController controller;
  final List<String> suggestions;

  void _insert(String suggestion) {
    final current = controller.text.trimRight();
    final text = current.isEmpty ? suggestion : '$current $suggestion';
    controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          for (final suggestion in suggestions)
            Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ActionChip(
                  label: Text(suggestion),
                  onPressed: () => _insert(suggestion),
                )),
        ]),
      );
}
