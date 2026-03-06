import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';

class ArtisanInfoPageWidget extends StatelessWidget {
  const ArtisanInfoPageWidget({super.key});

  static String routeName = 'ArtisanInfoPageWidget';
  static String routePath = '/artisanInfoPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0,
        backgroundColor: FlutterFlowTheme.of(context).primary,
        title: Text('Artisan Info', style: FlutterFlowTheme.of(context).titleMedium.copyWith(color: FlutterFlowTheme.of(context).onPrimary)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This page contains artisan-specific information and settings.', style: FlutterFlowTheme.of(context).bodyMedium),
              SizedBox(height: 12.0),
              Text('You can expand this page to include detailed bio, certifications, contact details, and support links.', style: FlutterFlowTheme.of(context).bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
