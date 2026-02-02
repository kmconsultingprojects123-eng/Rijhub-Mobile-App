import 'package:flutter/material.dart';
import '/services/token_storage.dart';
import 'artisan_kyc_page_widget.dart';

class ArtisanKycGuard extends StatefulWidget {
  const ArtisanKycGuard({super.key});

  @override
  State<ArtisanKycGuard> createState() => _ArtisanKycGuardState();
}

class _ArtisanKycGuardState extends State<ArtisanKycGuard> {
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await TokenStorage.getKycStatus();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
    // If status is 'pending', show dialog and pop this route after brief delay.
    if (_status == 'pending') {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Awaiting KYC approval'),
            content: const Text('Your KYC request has been submitted and is awaiting approval from an administrator.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              )
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_status == 'pending') {
      // Show an informative placeholder while dialog informs the user
      return Scaffold(
        appBar: AppBar(title: const Text('KYC Pending')),
        body: const Center(child: Text('Your KYC request is pending approval.')),
      );
    }
    // No pending status -> show actual KYC page
    return const ArtisanKycPageWidget();
  }
}
