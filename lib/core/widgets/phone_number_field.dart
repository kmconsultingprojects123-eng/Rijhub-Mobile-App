import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/formatters.dart';
import 'app_text_field.dart';

/// Phone input fixed to Nigeria (+234). Accepts "0803…" and pasted
/// "+234…" numbers and formats them as "803 123 4567".
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.label = 'Phone number',
    this.errorText,
    this.helperText,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;

  /// A quiet line under the field, for example what happens next.
  final String? helperText;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// Blocks edits, for example while a code is being sent.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      // The prefix is part of the number, so it is part of the name.
      semanticLabel: '$label, Nigeria ${NigerianPhone.countryCode}',
      controller: controller,
      focusNode: focusNode,
      hint: '803 123 4567',
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [NigerianPhoneInputFormatter()],
      errorText: errorText,
      helperText: helperText,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      readOnly: readOnly,
      autocorrect: false,
      enableSuggestions: false,
      prefix: const ExcludeSemantics(child: _CountryPrefix()),
    );
  }
}

class _CountryPrefix extends StatelessWidget {
  const _CountryPrefix();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: AppSpace.s16, right: AppSpace.s12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NigeriaFlag(),
          SizedBox(width: AppSpace.s8),
          Text(
            NigerianPhone.countryCode,
            style: AppText.bodyLarge.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: AppSpace.s12),
          SizedBox(height: 24, child: VerticalDivider(color: c.borderStrong)),
        ],
      ),
    );
  }
}

/// The Nigerian flag, drawn rather than shown as an emoji so it renders the
/// same on every device.
class NigeriaFlag extends StatelessWidget {
  const NigeriaFlag({super.key, this.width = 22});

  final double width;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF008751);
    return Semantics(
      label: 'Nigeria',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: width,
          height: width * 2 / 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x14000000)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ColoredBox(color: green)),
                Expanded(child: ColoredBox(color: Colors.white)),
                Expanded(child: ColoredBox(color: green)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
