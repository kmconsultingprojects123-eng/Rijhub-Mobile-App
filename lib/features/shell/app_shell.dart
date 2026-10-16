import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../onboarding/welcome_sheet.dart';

/// The app's frame, for guests and signed-in people alike: five tabs,
/// labelled for the side of the app they're using.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final role = context.select<SessionController, UserRole>((s) => s.role);
    final tabs = role == UserRole.artisan ? _artisanTabs : _clientTabs;
    return _FirstLaunchWelcome(
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: _BottomBar(
          tabs: tabs,
          currentIndex: navigationShell.currentIndex,
          onSelect: (index) {
            if (index != navigationShell.currentIndex) {
              HapticFeedback.selectionClick();
            }
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
        ),
      ),
    );
  }
}

/// On the very first launch, opens the welcome sheet over the guest home,
/// which is already loaded behind it.
class _FirstLaunchWelcome extends StatefulWidget {
  const _FirstLaunchWelcome({required this.child});

  final Widget child;

  @override
  State<_FirstLaunchWelcome> createState() => _FirstLaunchWelcomeState();
}

class _FirstLaunchWelcomeState extends State<_FirstLaunchWelcome> {
  @override
  void initState() {
    super.initState();
    if (context.read<SessionController>().hasOnboarded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWelcomeSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _clientTabs = [
  _Tab('Home', IconsaxPlusLinear.home_2, IconsaxPlusBold.home_2),
  // Iconsax's bold magnifier is a solid disc, so Explore keeps the outline
  // and shows it is active by its colour and label.
  _Tab(
    'Explore',
    IconsaxPlusLinear.search_normal_1,
    IconsaxPlusLinear.search_normal_1,
  ),
  _Tab('Bookings', IconsaxPlusLinear.calendar_tick,
      IconsaxPlusBold.calendar_tick),
  _Tab('Messages', IconsaxPlusLinear.message, IconsaxPlusBold.message),
  _Tab('Profile', IconsaxPlusLinear.profile_circle,
      IconsaxPlusBold.profile_circle),
];

const _artisanTabs = [
  _Tab('Home', IconsaxPlusLinear.home_2, IconsaxPlusBold.home_2),
  _Tab('Jobs', IconsaxPlusLinear.briefcase, IconsaxPlusBold.briefcase),
  _Tab('Schedule', IconsaxPlusLinear.calendar_tick,
      IconsaxPlusBold.calendar_tick),
  _Tab('Messages', IconsaxPlusLinear.message, IconsaxPlusBold.message),
  _Tab('Profile', IconsaxPlusLinear.profile_circle,
      IconsaxPlusBold.profile_circle),
];

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// The bar's height on the design frame. Smaller phones keep it.
  static const _height = 60.0;

  /// Labels stop growing at this text size, as tab labels do on iOS, so
  /// all five stay on one line, well apart, on a 360-wide phone.
  static const _maxTextScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final localizations = MaterialLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _maxTextScale,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            role: SemanticsRole.tabBar,
            child: SizedBox(
              height: math.max(_height, _height.w),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _NavItem(
                        tab: tabs[i],
                        active: i == currentIndex,
                        position: localizations.tabLabel(
                          tabIndex: i + 1,
                          tabCount: tabs.length,
                        ),
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: its icon over a one-line label. Screen readers hear its name,
/// whether it's selected and where it sits ("Tab 2 of 5").
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.position,
    required this.onTap,
  });

  final _Tab tab;
  final bool active;
  final String position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.brandText : c.textTertiary;
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: active,
        hint: position,
        child: Pressable(
          onTap: onTap,
          semanticLabel: tab.label,
          pressedScale: 0.92,
          // The tabs sit edge to edge, so the ring stays inside this one.
          focusOffset: 0,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.s4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? tab.activeIcon : tab.icon,
                  size: AppSize.iconLarge,
                  color: color,
                ),
                SizedBox(height: AppSpace.s4),
                // A label too long for its tab shrinks rather than wraps.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    softWrap: false,
                    style: AppText.caption.copyWith(
                      color: color,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Unread counts are off until messaging exists, so no tab claims messages
// nobody sent. To bring them back: read the count from the inbox in
// AppShell (signed-in people only; guests have no messages), pass it to the
// Messages tab's _NavItem, put its icon in a Stack(clipBehavior: Clip.none)
// with `if (count > 0) _UnreadBadge(count: count)`, and add
// ', $count unread' to its semantic label.
//
// class _UnreadBadge extends StatelessWidget {
//   const _UnreadBadge({required this.count});
//
//   final int count;
//
//   @override
//   Widget build(BuildContext context) {
//     final c = context.colors;
//     return Positioned(
//       top: -4,
//       right: -9,
//       child: Container(
//         constraints: const BoxConstraints(minWidth: 18),
//         height: 18,
//         padding: const EdgeInsets.symmetric(horizontal: 5),
//         alignment: Alignment.center,
//         decoration: BoxDecoration(
//           color: c.brand,
//           borderRadius: AppRadius.pillAll,
//           border: Border.all(color: c.surface, width: 2),
//         ),
//         child: Text(
//           '$count',
//           style: AppText.caption.copyWith(
//             fontSize: 10,
//             height: 1,
//             fontWeight: FontWeight.w700,
//             color: c.onBrand,
//           ),
//         ),
//       ),
//     );
//   }
// }
