import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../utils/app_notification.dart';

class SupportPageWidget extends StatelessWidget {
  const SupportPageWidget({super.key});

  static String routeName = 'SupportPage';
  static String routePath = '/supportPage';

  Future<void> _launchEmail(BuildContext context, String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (!await launchUrl(uri)) AppNotification.showError(context, 'Could not open mail client');
  }

  Future<void> _launchPhone(BuildContext context, String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) AppNotification.showError(context, 'Could not dial');
  }

  Widget _buildContactCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: backgroundColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.bodyMedium?.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: backgroundColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionText,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAQItem({
    required BuildContext context,
    required String question,
    required String answer,
    required int index,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        collapsedIconColor: theme.primary,
        iconColor: theme.primary,
        title: Text(
          question,
          style: theme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(
              answer,
              style: theme.bodyMedium?.copyWith(
                color: theme.secondaryText,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFA20025);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: theme.primary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    'Support',
                    style: theme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 48), // For balance
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Need Help?',
                            style: theme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Our support team is here to help you with any questions or issues you may have.',
                            style: theme.bodyLarge?.copyWith(
                              color: theme.secondaryText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // Contact Methods Section
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 12),
                        child: Text(
                          'CONTACT METHODS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),

                      _buildContactCard(
                        context: context,
                        icon: Icons.email_outlined,
                        title: 'Email Support',
                        subtitle: 'Get help via email',
                        actionText: 'Send Email',
                        onTap: () => _launchEmail(context, 'support@artisanhub.com'),
                        backgroundColor: primaryColor,
                        iconColor: primaryColor,
                      ),

                      const SizedBox(height: 16),

                      _buildContactCard(
                        context: context,
                        icon: Icons.phone_outlined,
                        title: 'Phone Support',
                        subtitle: 'Call our support line',
                        actionText: 'Call Now',
                        onTap: () => _launchPhone(context, '+15555555555'),
                        backgroundColor: Colors.green,
                        iconColor: Colors.green,
                      ),

                      const SizedBox(height: 40),

                      // FAQ Section
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 12),
                        child: Text(
                          'FREQUENTLY ASKED QUESTIONS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),

                      Column(
                        children: [
                          _buildFAQItem(
                            context: context,
                            question: 'How do I verify my account?',
                            answer: 'Go to your profile settings and navigate to the KYC section. Follow the step-by-step instructions to upload required documents for verification.',
                            index: 1,
                          ),
                          const SizedBox(height: 16),
                          _buildFAQItem(
                            context: context,
                            question: 'How do I get paid for my services?',
                            answer: 'Connect your bank account in the Wallet section or use our in-app wallet feature. Payments are processed securely within 1-3 business days.',
                            index: 2,
                          ),
                          const SizedBox(height: 16),
                          _buildFAQItem(
                            context: context,
                            question: 'How can I cancel a booking?',
                            answer: 'Go to My Jobs section, select the booking you want to cancel, and follow the cancellation process. Please note cancellation policies may apply.',
                            index: 3,
                          ),
                          const SizedBox(height: 16),
                          _buildFAQItem(
                            context: context,
                            question: 'What payment methods are accepted?',
                            answer: 'We accept credit/debit cards, mobile money, and bank transfers. All payments are secured with encryption and fraud protection.',
                            index: 4,
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // Additional Help Section
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 12),
                        child: Text(
                          'ADDITIONAL RESOURCES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),

                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.chat_outlined,
                                        color: primaryColor,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Live Chat Support',
                                          style: theme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Available 9AM - 6PM daily',
                                          style: theme.bodyMedium?.copyWith(
                                            color: theme.secondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Coming Soon',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Business Hours',
                                      style: theme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Monday - Friday: 9:00 AM - 6:00 PM\nSaturday: 10:00 AM - 4:00 PM\nSunday: Closed',
                                      style: theme.bodyMedium?.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}