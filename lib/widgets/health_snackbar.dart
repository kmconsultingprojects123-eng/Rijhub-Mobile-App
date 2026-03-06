// ...new file...
import 'package:flutter/material.dart';

/// Small wrapper to show a concise, styled snackbar for health messages.
void showHealthSnackBar(BuildContext context, String message, {bool isError = true}) {
  final theme = Theme.of(context);
  final bg = isError ? Colors.red.shade600 : theme.primaryColor;
  final textColor = Colors.white;

  final snack = SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
    backgroundColor: bg,
    content: Text(message, style: TextStyle(color: textColor)),
    duration: const Duration(seconds: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
  );

  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(snack);
}

