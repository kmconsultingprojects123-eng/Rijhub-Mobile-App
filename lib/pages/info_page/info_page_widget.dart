import 'package:flutter/material.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/app_notification.dart';

class InfoPageWidget extends StatefulWidget {
  const InfoPageWidget({super.key});

  static String routeName = 'InfoPage';
  static String routePath = '/infoPage';

  @override
  State<InfoPageWidget> createState() => _InfoPageWidgetState();
}

class _InfoPageWidgetState extends State<InfoPageWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // URLs for external links
  static const _termsUrl = 'https://example.com/terms';
  static const _supportEmail = 'support@rijhub.com';
  // Updated support phone per project contact
  static const _contactPhone = '08053466666';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      AppNotification.showError(context, 'Could not open link');
    }
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (!await launchUrl(uri)) {
      AppNotification.showError(context, 'Could not open email client');
    }
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
                    'About & Info',
                    style: theme.titleLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 48), // For balance
                ],
              ),
            ),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: theme.primary,
                unselectedLabelColor: theme.secondaryText,
                indicatorColor: theme.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'About Us'),
                  Tab(text: 'Terms & Privacy'),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // About Us Tab
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // About Rijhub (replaced per user content)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About Rijhub',
                                style: theme.headlineSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 28,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Our Story
                              Text(
                                'Our Story',
                                style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Rijhub was born out of a simple observation: there is an abundance of incredible skill in our communities, yet finding a reliable, verified professional often feels like a game of chance. Meanwhile, talented artisans frequently struggle to reach the customers who need them most.',
                                style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'We built Rijhub to bridge that gap. We are more than just an app; we are a digital ecosystem designed to foster trust, celebrate craftsmanship, and drive economic growth for local service providers.',
                                style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                              ),

                              const SizedBox(height: 16),
                              // Our Mission
                              Text(
                                'Our Mission',
                                style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'To empower artisans by providing them with the digital tools to build empires, and to provide customers with a seamless, secure, and stress-free way to access expert services.',
                                style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                              ),

                              const SizedBox(height: 16),
                              // The Rijhub Difference
                              Text(
                                'The Rijhub Difference',
                                style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),

                              // Difference items
                              _buildBulletItem(context, '1. Trust Through Verification',
                                  'We believe that safety is the foundation of any great service. That is why every artisan on Rijhub undergoes a rigorous KYC (Know Your Customer) verification process. When you see the "Verified Professional" badge, you know you are working with the best.'),
                              const SizedBox(height: 10),
                              _buildBulletItem(context, '2. The Power of Escrow',
                                  'Financial security shouldn\'t be a worry. Our unique Escrow Payment System protects both parties. Customers know their money is safe until the job is done, and Artisans know that their payment is secured before they even pick up their tools.'),
                              const SizedBox(height: 10),
                              _buildBulletItem(context, '3. Precision Matching',
                                  'Rijhub doesn\'t just give you a list of names. Our platform uses smart matching to connect you with professionals based on their specific expertise, real-time availability, and proximity to your location.'),
                              const SizedBox(height: 10),
                              _buildBulletItem(context, '4. Seamless Collaboration',
                                  'From the first inquiry to the final handshake, our integrated chat and booking tools keep the conversation organized and professional. No more missed calls or lost messages.'),

                              const SizedBox(height: 16),
                              // Commitment
                              Text(
                                'Our Commitment to You',
                                style: theme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Whether you are a homeowner looking for an emergency repair, a business owner planning a renovation, or a master of your craft looking to scale your business—Rijhub is here to power that journey.',
                                style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Rijhub: Your Craft. Your Needs. Our Platform.',
                                style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // Contact Information
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0, bottom: 12),
                            child: Text(
                              'CONTACT INFORMATION',
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
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(26),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.email_outlined,
                                          color: primaryColor,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      'Email Support',
                                      style: theme.titleSmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _supportEmail,
                                      style: theme.bodyMedium.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(26),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Contact',
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    onTap: () => _launchEmail(_supportEmail),
                                  ),
                                  const SizedBox(height: 16),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(26),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.phone_outlined,
                                          color: primaryColor,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      'Phone Support',
                                      style: theme.titleSmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _contactPhone,
                                      style: theme.bodyMedium.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(26),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Call',
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    onTap: () => _launchUrl('tel:$_contactPhone'),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // App Version
                          Center(
                            child: Text(
                              'Version 1.0.0',
                              style: theme.bodySmall.copyWith(
                                color: theme.secondaryText,
                              ),
                            ),
                          ),

                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),

                  // Terms & Privacy Tab
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rijhub: Terms of Service & Privacy Policy',
                            style: theme.headlineSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Last Updated: November 2025',
                            style: theme.bodyMedium.copyWith(
                              color: theme.secondaryText,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Intro paragraph
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              'This document governs the relationship between you ("User," "Artisan," or "Customer") and Rijhub ("the Platform"). By accessing or using our services, you agree to be bound by these unified terms.',
                              style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                            ),
                          ),

                          const SizedBox(height: 20),

                          Text('PART 1: TERMS AND CONDITIONS', style: theme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),

                          Text('1. The Nature of the Platform', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Rijhub is a digital marketplace technology that facilitates connections between independent service providers ("Artisans") and individuals or businesses seeking those services ("Customers").\n\nLegal Relationship: Rijhub is a facilitator only. We do not provide artisan services, and we do not employ Artisans. Every booking creates a direct legal contract between the Customer and the Artisan. Rijhub is not a party to that contract.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('2. User Accounts & Eligibility', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Registration: You must provide accurate and complete information during registration.\n\nVerification (KYC): Artisans must undergo a mandatory identity and business verification process to receive a "Verified Professional" badge.\n\nAge Requirement: Users must be at least 18 years of age to create an account or book services.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('3. The Secure Booking & Escrow Flow', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'To protect both parties, Rijhub operates a mandatory Escrow Payment System:\n\nQuoting: Artisans provide custom, itemized quotes based on job requests.\n\nSecure Deposit: Upon acceptance of a quote, the Customer pays the total amount (or a mandatory deposit). This money is held securely by Rijhub in an Escrow account.\n\nWork Authorization: Artisans are notified only when payment is secured. Work should never begin until the Platform confirms "Payment Secured."\n\nPayout: Funds are released to the Artisan only after the Customer confirms "Job Completed" or after a 48-hour window following the Artisan’s completion notification (provided no dispute is active).',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('4. Fees and Financial Conduct', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Platform Commission: Rijhub deducts a service fee from the Artisan\'s total earnings to cover platform maintenance, marketing, and secure payment processing.\n\nAnti-Circumvention: All communication and payments for jobs initiated on Rijhub must remain on the Platform. Attempting to pay an Artisan directly (offline) to avoid fees is a violation of these terms and will result in permanent account termination.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('5. Cancellations & Disputes', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Refund Policy: If an Artisan fails to appear, the Customer receives a 100% refund of the Escrowed amount. If a Customer cancels last minute, a "Site Visit Fee" may be deducted from the deposit to compensate the Artisan for travel.\n\nMediation: If a dispute arises regarding work quality, Rijhub’s mediation team will review in-app chat logs and photos to determine the fair distribution of Escrowed funds.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 24),

                          Text('PART 2: PRIVACY POLICY', style: theme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),

                          Text('6. Information We Collect', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'We collect information necessary to operate a safe marketplace:\n\nIdentification: Name, email, phone number, and government-issued ID (for Artisans).\n\nLocation: Real-time GPS data to match Customers with nearby Artisans.\n\nProfessional Data: Trade licenses, portfolios, and certification documents.\n\nFinancial Data: Payout bank details (Artisans) and encrypted payment tokens (Customers).',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('7. How We Use Your Data', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Service Fulfillment: To enable chat, booking, and navigation between parties.\n\nSafety & Security: To prevent fraud through identity verification and monitoring of suspicious activity.\n\nImprovements: To analyze user behavior and optimize the search and booking experience.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('8. Data Sharing & Disclosure', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Between Users: We only share contact details (phone/location) once a quote is accepted and payment is secured.\n\nThird Parties: We do not sell your data. We only share data with verified payment processors and cloud storage providers necessary for app functionality.\n\nLegal Compliance: We may disclose information if required by law to protect the safety of our community.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('9. Your Privacy Rights', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'You have the right to:\n\nAccess: Request a copy of the data we hold about you.\n\nRectification: Update your profile information at any time.\n\nErasure: Request account deletion (subject to completion of any active bookings/payments).',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 24),

                          Text('PART 3: GENERAL PROVISIONS', style: theme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),

                          Text('10. Limitation of Liability', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'Rijhub is not liable for personal injury, property damage, or any other loss resulting from the services performed by Artisans. Our maximum liability is limited to the service fee collected for the specific booking in question.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5),
                          ),

                          const SizedBox(height: 16),

                          Text('11. Acceptance', style: theme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(
                            'By clicking "Create Account," you acknowledge that you have read, understood, and agreed to these Terms and Conditions and the Privacy Policy.',
                            style: theme.bodyMedium.copyWith(color: theme.secondaryText, height: 1.5, fontWeight: FontWeight.w600),
                          ),

                          const SizedBox(height: 40),

                          // Keep external links section but update label to point to full docs if present
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
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withAlpha(26),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.link_outlined,
                                          color: theme.primary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      'Full Terms & Privacy',
                                      style: theme.titleSmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Read the complete unified terms and privacy document',
                                      style: theme.bodyMedium.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    trailing: const Icon(Icons.open_in_new, size: 20),
                                    onTap: () => _launchUrl(_termsUrl),
                                  ),
                                  const SizedBox(height: 16),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withAlpha(26),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.link_outlined,
                                          color: theme.primary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      'Contact Support',
                                      style: theme.titleSmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'For privacy or terms inquiries, reach out to our support team',
                                      style: theme.bodyMedium.copyWith(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    trailing: const Icon(Icons.open_in_new, size: 20),
                                    onTap: () => _launchEmail(_supportEmail),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletItem(BuildContext context, String title, String description) {
    final theme = FlutterFlowTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4, right: 12),
          decoration: BoxDecoration(
            color: theme.primary,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.bodyMedium.copyWith(
                  color: theme.secondaryText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
