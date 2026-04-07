import 'package:flutter/material.dart';

// Removed: the artisan respond placeholder was a temporary UI for testing.
// The actual respond-to-request form will be integrated when provided by the user.

class ArtisanRespondPlaceholderWidget extends StatelessWidget {
  const ArtisanRespondPlaceholderWidget({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Removed')),
      body: const Center(child: Text('Respond-to-request form has been removed.')),
    );
  }
}


