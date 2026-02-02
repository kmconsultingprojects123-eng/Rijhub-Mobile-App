import 'package:flutter/material.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

class TermsPageWidget extends StatelessWidget {
  const TermsPageWidget({super.key});

  static String routeName = 'TermsPage';
  static String routePath = '/termsPage';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Terms of Service', style: theme.titleMedium),
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Terms of Service', style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.secondaryBackground, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Platform Role: Rijhub is a platform that connects users. We do not provide the artisan services ourselves; the contract is between the Customer and the Artisan.', style: theme.bodyMedium),
              SizedBox(height: 8),
              Text('User Conduct: Users must provide accurate information. Any fraudulent activity or harassment will result in immediate account suspension.', style: theme.bodyMedium),
              SizedBox(height: 8),
              Text('Payments & Escrow: All payments for jobs booked on Rijhub must be made through the platform. We hold deposits in a secure escrow account until the job is confirmed complete by the customer.', style: theme.bodyMedium),
              SizedBox(height: 8),
              Text('Cancellations: Deposits may be non-refundable if a cancellation occurs after an artisan has traveled to a site, subject to our cancellation policy.', style: theme.bodyMedium),
              SizedBox(height: 8),
              Text('Disputes: In the event of a disagreement, Rijhub provides a mediation service to help both parties reach a fair resolution.', style: theme.bodyMedium),
            ]),
          ),
        ]),
      ),
    );
  }
}
