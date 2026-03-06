import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

class PrivacyPageWidget extends StatelessWidget {
  const PrivacyPageWidget({super.key});

  static String routeName = 'PrivacyPage';
  static String routePath = '/privacyPage';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: appBarBackgroundColor(context),
        foregroundColor: appBarForegroundColor(context),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Privacy Policy', style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Your privacy is our priority. Here is how we handle your data:', style: theme.bodyMedium),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Data Collection: We collect your name, contact details, and location to facilitate service bookings. Artisans must also provide government ID for our mandatory verification process.', style: theme.bodySmall),
              const SizedBox(height: 8),
              Text('Data Usage: Your information is used to match you with the right users, process secure payments, and improve platform safety.', style: theme.bodySmall),
              const SizedBox(height: 8),
              Text('Sharing: We only share your contact details with the other party once a quote is accepted and a deposit is paid. We never sell your personal data to third parties.', style: theme.bodySmall),
              const SizedBox(height: 8),
              Text('Security: We use industry-standard encryption to protect your financial information and personal documents.', style: theme.bodySmall),
              const SizedBox(height: 8),
              Text('Your Rights: You can request to view, edit, or delete your account data at any time through the app settings.', style: theme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
