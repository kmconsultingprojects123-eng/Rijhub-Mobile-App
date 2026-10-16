import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';

/// One line under a field: what went wrong, or what just happened. Screen
/// readers announce it as it appears.
class AuthStatusLine extends StatelessWidget {
  const AuthStatusLine({
    super.key,
    required this.message,
    this.isError = true,
  });

  final String message;

  /// False for confirmations, such as a code that was sent again.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? IconsaxPlusBold.info_circle : IconsaxPlusBold.tick_circle,
            size: AppSize.iconSmall,
            color: isError ? c.error : c.success,
          ),
          SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              message,
              style: AppText.caption.copyWith(
                color: isError ? c.error : c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet, centred note, for example why an option isn't available yet.
/// The icon sits in the first line, so a note that wraps stays centred like
/// the legal line beside it.
class AuthNote extends StatelessWidget {
  const AuthNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: AppSpace.s6),
                child: Icon(
                  IconsaxPlusLinear.info_circle,
                  size: AppSize.iconSmall,
                  color: c.textTertiary,
                ),
              ),
            ),
            TextSpan(text: message),
          ],
        ),
        textAlign: TextAlign.center,
        style: AppText.caption.copyWith(color: c.textTertiary),
      ),
    );
  }
}

/// Reports a failure that isn't an `AuthException`, so wasn't expected, and
/// returns a message that is safe to show, so the step can recover.
String reportUnexpectedAuthError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'RijHub sign-in',
      context: ErrorDescription('in the sign-in sheet'),
    ),
  );
  return 'Something went wrong. Please try again.';
}
