import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../models/auth_models.dart';
import '../password_reset/models/password_reset_models.dart';

class PhoneTextField extends StatelessWidget {
  const PhoneTextField({
    required this.controller,
    required this.validator,
    required this.country,
    required this.onCountryChanged,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final String? Function(String?) validator;
  final PhoneCountry country;
  final ValueChanged<PhoneCountry> onCountryChanged;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) => AppTextField(
        controller: controller,
        hint: 'phone_number'.tr,
        validator: validator,
        keyboardType: TextInputType.phone,
        textInputAction: textInputAction,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9\s-]')),
          LengthLimitingTextInputFormatter(15),
        ],
        prefixIcon: SizedBox(
          width: 112,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: InkWell(
              onTap: () => showCountryPicker(
                context: context,
                showPhoneCode: true,
                favorite: const <String>['YE'],
                onSelect: (Country value) => onCountryChanged(
                  PhoneCountry(
                    countryCode: value.countryCode,
                    phoneCode: value.phoneCode,
                    flagEmoji: value.flagEmoji,
                    name: value.name,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(country.flagEmoji),
                  const SizedBox(width: 4),
                  Text('+${country.phoneCode}'),
                  const Icon(Icons.arrow_drop_down, size: 18),
                  Container(
                    width: 1,
                    height: 22,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class AuthDropdownField extends StatelessWidget {
  const AuthDropdownField({
    required this.hint,
    required this.items,
    required this.value,
    required this.onChanged,
    this.validator,
    super.key,
  });

  final String hint;
  final List<String> items;
  final String value;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value.isEmpty ? null : value,
        decoration: InputDecoration(hintText: hint),
        isExpanded: true,
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(growable: false),
        onChanged: onChanged,
        validator: validator,
      );
}

class PasswordTextField extends StatelessWidget {
  const PasswordTextField({
    required this.controller,
    required this.hint,
    required this.obscureText,
    required this.onToggleVisibility,
    required this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => AppTextField(
        controller: controller,
        hint: hint,
        validator: validator,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofillHints: const <String>[AutofillHints.password],
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          icon: Icon(obscureText
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
        ),
      );
}

class RecoveryMethodCard extends StatelessWidget {
  const RecoveryMethodCard({
    required this.channel,
    required this.selected,
    required this.maskedValue,
    required this.onTap,
    super.key,
  });

  final RecoveryChannel channel;
  final bool selected;
  final String maskedValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AppCard(
      onTap: onTap,
      color: selected ? primary.withValues(alpha: .15) : null,
      borderColor: selected
          ? primary
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: .14),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: primary,
            child: const Icon(Icons.sms_outlined, color: Colors.black),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('via_sms'.tr,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    maskedValue,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Radio<RecoveryChannel>(
            value: channel,
            groupValue: selected ? channel : null,
            onChanged: (_) => onTap(),
          ),
        ],
      ),
    );
  }
}
