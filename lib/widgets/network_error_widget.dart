import 'package:flutter/material.dart';

/// Simple, reusable network error widget used by HomePage and other screens.
class NetworkErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final bool showOfflineContent;
  final DateTime? lastSuccessfulLoad;

  const NetworkErrorWidget({
    Key? key,
    this.title = 'Connection Lost',
    this.message = 'Unable to reach our services. Please check your internet connection.',
    this.primaryAction,
    this.secondaryAction,
    this.showOfflineContent = false,
    this.lastSuccessfulLoad,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 80,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onBackground.withOpacity(0.8)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (lastSuccessfulLoad != null)
                  Text('Last successful load: ${_formatDate(lastSuccessfulLoad!)}', style: theme.textTheme.bodySmall),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (primaryAction != null) primaryAction!,
                    if (primaryAction != null && secondaryAction != null) const SizedBox(width: 12),
                    if (secondaryAction != null) secondaryAction!,
                  ],
                ),
                if (showOfflineContent)
                  Padding(
                    padding: const EdgeInsets.only(top: 28.0),
                    child: Text(
                      'You are viewing offline content.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onBackground.withOpacity(0.6)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class RetryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  const RetryButton({Key? key, this.onPressed, this.label = 'Retry'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

class SettingsButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  const SettingsButton({Key? key, this.onPressed, this.label = 'Settings'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

