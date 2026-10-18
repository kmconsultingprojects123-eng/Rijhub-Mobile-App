import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/session.dart';
import '../../data/models/models.dart';
import '../artisan/work_screens.dart';
import '../explore/explore_screen.dart';

/// The second tab: Explore (finding artisans) for clients, Jobs for
/// artisans. Follows the session, so switching sides switches the tab.
class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key, this.categoryId, this.map = false});

  final String? categoryId;
  final bool map;

  @override
  Widget build(BuildContext context) {
    final artisan = context
        .select<SessionController, bool>((s) => s.role == UserRole.artisan);
    return artisan
        ? JobsBoard(key: ValueKey('jobs$map'), startOnMap: map)
        : ExploreScreen(
            key: ValueKey('explore$map$categoryId'),
            categoryId: categoryId,
            startOnMap: map);
  }
}
