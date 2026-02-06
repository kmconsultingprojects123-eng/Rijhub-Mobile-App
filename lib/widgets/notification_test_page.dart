import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_controller.dart';

/// A utility widget to test notifications
/// Add this to your app for testing purposes
class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({Key? key}) : super(key: key);

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  String? _fcmToken;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    setState(() => _isLoading = true);
    final token = await NotificationController.loadFcmToken();
    setState(() {
      _fcmToken = token;
      _isLoading = false;
    });
  }

  Future<void> _refreshToken() async {
    setState(() => _isLoading = true);
    final token = await NotificationController.requestFirebaseToken();
    setState(() {
      _fcmToken = token;
      _isLoading = false;
    });
  }

  void _copyToken() {
    if (_fcmToken != null) {
      Clipboard.setData(ClipboardData(text: _fcmToken!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token copied to clipboard!')),
      );
    }
  }

  Future<void> _sendTestNotification() async {
    await NotificationController.showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Test Notification',
      body: 'This is a test notification from Rijhub!',
      summary: 'Test',
      payload: {'type': 'test', 'screen': 'home'},
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test notification sent!')),
      );
    }
  }

  Future<void> _requestPermissions() async {
    final granted =
        await NotificationController.requestNotificationPermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(granted ? 'Permissions granted!' : 'Permissions denied'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Tester'),
        backgroundColor: const Color(0xFF9D50DD),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // FCM Token Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FCM Token',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_fcmToken != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                _fcmToken!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _copyToken,
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copy Token'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _refreshToken,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Refresh'),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const Text('No token available'),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _refreshToken,
                              child: const Text('Request Token'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Test Actions Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Test Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _sendTestNotification,
                            icon: const Icon(Icons.notifications_active),
                            label: const Text('Send Test Notification'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _requestPermissions,
                            icon: const Icon(Icons.security),
                            label: const Text('Request Permissions'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await NotificationController.subscribeToTopic(
                                  'all_users');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Subscribed to "all_users" topic'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.subscriptions),
                            label: const Text('Subscribe to "all_users"'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Info Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'How to Test',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '1. Copy the FCM token above\n'
                            '2. Go to Firebase Console → Cloud Messaging\n'
                            '3. Click "Send your first message"\n'
                            '4. Paste the token and send a test notification\n'
                            '\n'
                            'Or use the "Send Test Notification" button above to test local notifications.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
