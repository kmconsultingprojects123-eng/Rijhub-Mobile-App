import 'package:flutter/material.dart';
import 'artisan_profilepage_model.dart';
import '../profile/profile_widget.dart';

export 'artisan_profilepage_model.dart';

class ArtisanProfilepageWidget extends StatelessWidget {
  const ArtisanProfilepageWidget({super.key});

  static String routeName = 'artisanProfilepage';
  static String routePath = '/artisanProfilepage';

  @override
  Widget build(BuildContext context) {
    // Delegate to the shared `ProfileWidget`. NavBarPage composes this when necessary.
    return const ProfileWidget();
  }
}
