import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// A step's title and the line under it that says what to do.
class AuthStepHeader extends StatelessWidget {
  /// With a plain [message]. Its last two words wrap together, so the line
  /// never ends on one word of its own.
  AuthStepHeader({super.key, required this.title, required String message})
      : message = Text(_keepLastWordsTogether(message));

  /// With a [message] that carries a link or emphasis, such as a
  /// [Text.rich].
  const AuthStepHeader.rich({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final Widget message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppText.headline.copyWith(color: c.textPrimary),
          ),
        ),
        SizedBox(height: AppSpace.s8),
        DefaultTextStyle.merge(
          style: AppText.body.copyWith(color: c.textSecondary),
          child: message,
        ),
      ],
    );
  }
}

/// Joins the last two words with a non-breaking space.
String _keepLastWordsTogether(String text) {
  final space = text.lastIndexOf(' ');
  if (space < 0) return text;
  return '${text.substring(0, space)} ${text.substring(space + 1)}';
}
