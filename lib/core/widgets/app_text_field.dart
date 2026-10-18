import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../theme/theme.dart';

/// A labelled text input. The label sits above the field so it never
/// collides with what the user types. Errors show below with an icon.
///
/// Screen readers hear the label as the field's own name, so it is never an
/// unnamed edit box, even once something is typed.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.semanticLabel,
    this.optional = false,
    this.hint,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.helperText,
    this.prefix,
    this.suffix,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onEditingComplete,
    this.maxLines = 1,
    this.minLines,
  });

  final String? label;

  /// What screen readers call the field, when it isn't [label] alone: for
  /// a field with no visible label, or one with a fixed prefix.
  final String? semanticLabel;

  /// Adds "(optional)" after the label.
  final bool optional;
  final String? hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final String? helperText;
  final Widget? prefix;
  final Widget? suffix;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;

  /// Turn off for names, emails and codes.
  final bool autocorrect;
  final bool enableSuggestions;
  final VoidCallback? onEditingComplete;

  /// More than 1 for a multi-line field (null to grow without limit).
  final int? maxLines;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = errorText != null;
    final theme = Theme.of(context).inputDecorationTheme;
    final name = semanticLabel ?? label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          // The field says its name itself; read here too, it would be
          // heard twice.
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (optional)
                    TextSpan(
                      text: '  (optional)',
                      style: AppText.bodySmall.copyWith(color: c.textTertiary),
                    ),
                ],
              ),
              style: AppText.labelSmall.copyWith(color: c.textPrimary),
            ),
          ),
          SizedBox(height: AppSpace.s8),
        ],
        Semantics(
          label: name == null || !optional ? name : '$name, optional',
          // Heard again on coming back to the field. The line below
          // announces it as it appears.
          hint: errorText,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            autofocus: autofocus,
            enabled: enabled,
            readOnly: readOnly,
            obscureText: obscureText,
            autocorrect: autocorrect,
            enableSuggestions: enableSuggestions,
            onEditingComplete: onEditingComplete,
            maxLines: maxLines,
            minLines: minLines,
            style: AppText.bodyLarge.copyWith(color: c.textPrimary),
            cursorColor: c.brandStroke,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: prefix,
              suffixIcon: suffix,
              enabledBorder: hasError ? theme.errorBorder : null,
              focusedBorder: hasError ? theme.focusedErrorBorder : null,
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: EdgeInsets.only(top: AppSpace.s8),
            // Announced by screen readers as soon as it appears.
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(IconsaxPlusBold.info_circle, size: 16, color: c.error),
                  SizedBox(width: AppSpace.s6),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: AppText.caption.copyWith(color: c.error),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (helperText != null)
          Padding(
            padding: EdgeInsets.only(top: AppSpace.s8),
            child: Text(
              helperText!,
              style: AppText.caption.copyWith(color: c.textTertiary),
            ),
          ),
      ],
    );
  }
}
