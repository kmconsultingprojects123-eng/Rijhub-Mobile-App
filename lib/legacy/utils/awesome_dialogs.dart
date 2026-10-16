import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Reusable dialog widget with adaptive light/dark theme support
class _AppDialog extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final Color iconColor;
  final List<Widget> actions;
  final Color? backgroundColor;

  const _AppDialog({
    Key? key,
    required this.title,
    required this.desc,
    required this.icon,
    required this.iconColor,
    required this.actions,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final w = MediaQuery.of(context).size.width;
    final dialogWidth = min(w * 0.92, 520.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: backgroundColor ?? theme.primaryBackground,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha((0.12 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(desc, style: theme.bodyMedium.copyWith(color: theme.secondaryText)),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Global dialog helpers with consistent, adaptive styling

Future<void> showAppSuccessDialog(
    BuildContext context, {
      required String title,
      required String desc,
      String okText = 'Continue',
      VoidCallback? onOk,
    }) async {
  final theme = FlutterFlowTheme.of(context);
  final completer = Completer<void>();

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      return _AppDialog(
        title: title,
        desc: desc,
        icon: Icons.check_circle_rounded,
        iconColor: theme.success,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete();
            },
            child: Text(
              okText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  await completer.future;
  if (onOk != null) onOk();
}

Future<void> showAppErrorDialog(
    BuildContext context, {
      required String title,
      required String desc,
      String okText = 'Okay',
      VoidCallback? onOk,
    }) async {
  final theme = FlutterFlowTheme.of(context);
  final completer = Completer<void>();

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      return _AppDialog(
        title: title,
        desc: desc,
        icon: Icons.error_outline_rounded,
        iconColor: theme.error,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? theme.error.withAlpha((0.05 * 255).round()) : null,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete();
            },
            child: Text(
              okText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  await completer.future;
  if (onOk != null) onOk();
}

Future<void> showAppInfoDialog(
    BuildContext context, {
      required String title,
      required String desc,
      String okText = 'Got it',
      VoidCallback? onOk,
    }) async {
  final theme = FlutterFlowTheme.of(context);
  final completer = Completer<void>();

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      return _AppDialog(
        title: title,
        desc: desc,
        icon: Icons.info_outline_rounded,
        iconColor: theme.primary,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? theme.primary.withAlpha((0.05 * 255).round()) : null,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete();
            },
            child: Text(
              okText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  await completer.future;
  if (onOk != null) onOk();
}

Future<void> showAppSnackDialog(BuildContext context, String message) async {
  final overlay = Overlay.of(context);
  final theme = FlutterFlowTheme.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final entry = OverlayEntry(
    builder: (ctx) {
      final w = MediaQuery.of(ctx).size.width;
      final leftRight = w < 600 ? 20.0 : 120.0;

      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(left: leftRight, right: leftRight, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade700,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.2 * 255).round()),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  await Future.delayed(const Duration(seconds: 3));
  entry.remove();
}

Future<bool> showAppConfirmDialog(
    BuildContext context, {
      required String title,
      required String desc,
      String okText = 'Confirm',
      String cancelText = 'Cancel',
      bool destructive = false,
      VoidCallback? onOk,
      VoidCallback? onCancel,
    }) async {
  final theme = FlutterFlowTheme.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final completer = Completer<bool>();

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      return _AppDialog(
        title: title,
        desc: desc,
        icon: destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
        iconColor: destructive ? theme.error : theme.primary,
        backgroundColor: destructive && isDark ? theme.error.withAlpha((0.05 * 255).round()) : null,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              side: BorderSide(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                width: 1.5,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete(false);
            },
            child: Text(
              cancelText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: destructive ? theme.error : theme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!completer.isCompleted) completer.complete(true);
            },
            child: Text(
              okText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );

  final res = await completer.future;
  if (res == true) {
    if (onOk != null) onOk();
  } else {
    if (onCancel != null) onCancel();
  }
  return res;
}

/// Shows a centered loading dialog with an indeterminate progress indicator.
/// Caller should dismiss with `Navigator.of(context, rootNavigator: true).pop();` when done.
void showAppLoadingDialog(BuildContext context, {String? message}) {
  final theme = FlutterFlowTheme.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((0.4 * 255).round()),
    builder: (ctx) {
      final w = MediaQuery.of(ctx).size.width;
      final width = min(w * 0.7, 360.0);

      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(((isDark ? 0.3 : 0.1) * 255).round()),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: theme.primary.withAlpha((0.1 * 255).round()),
                          shape: BoxShape.circle,
                        ),
                      ),
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
                      ),
                    ],
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    message,
                    style: theme.bodyLarge.copyWith(
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Quick toast-style notification
void showQuickToast(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.of(context);
  final theme = FlutterFlowTheme.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final entry = OverlayEntry(
    builder: (ctx) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isError
                    ? (isDark ? theme.error.withAlpha((0.9 * 255).round()) : theme.error)
                    : (isDark ? Colors.grey.shade900 : Colors.grey.shade800),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isError
                      ? theme.error.withAlpha((0.3 * 255).round())
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade700),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((0.2 * 255).round()),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    message,
                    style: theme.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), () => entry.remove());
}