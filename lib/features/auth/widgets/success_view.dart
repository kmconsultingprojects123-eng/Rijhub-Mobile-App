import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../../core/theme/theme.dart';

/// "You're all set": a tick that pops in and a welcome by first name, shown
/// for a moment before the sheet closes by itself.
class AuthSuccessView extends StatelessWidget {
  const AuthSuccessView({
    super.key,
    required this.firstName,
    required this.returning,
  });

  final String? firstName;

  /// Signed in to an existing account, rather than a new one.
  final bool returning;

  /// "Welcome back, Chidinma." Also read out by screen readers.
  static String welcome(String? firstName, {required bool returning}) {
    final greeting = returning ? 'Welcome back' : 'Welcome';
    return firstName == null ? '$greeting.' : '$greeting, $firstName.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.only(top: AppSpace.s16, bottom: AppSpace.s24),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: reduceMotion ? Duration.zero : AppMotion.slow,
            builder: (context, t, child) => Opacity(
              opacity: Curves.easeOut.transform(t),
              child: Transform.scale(
                scale: 0.6 + 0.4 * Curves.easeOutBack.transform(t),
                child: child,
              ),
            ),
            child: Container(
              width: 88.w,
              height: 88.w,
              decoration: BoxDecoration(
                color: c.successSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(
                IconsaxPlusBold.tick_circle,
                size: 56.w,
                color: c.success,
              ),
            ),
          ),
          SizedBox(height: AppSpace.s20),
          Semantics(
            header: true,
            child: Text(
              "You're all set",
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: c.textPrimary),
            ),
          ),
          SizedBox(height: AppSpace.s6),
          Text(
            welcome(firstName, returning: returning),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
