import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/location.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/widgets/auth_sheet_bar.dart';

/// Opens the area picker. Resolves to the area the person chose, or null
/// if they closed it.
///
/// People pick their neighbourhood from a list, or tap "Use my location",
/// which is the only time the phone asks to share it; Abuja addresses are
/// given by district anyway.
Future<String?> showAreaPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The sheet's top row draws the handle, beside close.
    showDragHandle: false,
    // What screen readers call the dimmed page above the sheet.
    barrierLabel: 'Close',
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => DoubleTapGuard(child: AreaPickerSheet(current: current)),
  );
}

/// A searchable list of the areas RijHub serves, with [current] ticked.
class AreaPickerSheet extends StatefulWidget {
  const AreaPickerSheet({super.key, this.current});

  final String? current;

  @override
  State<AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<AreaPickerSheet> {
  /// How long typing pauses before screen readers hear what matched, so
  /// it doesn't talk over the letters being read back.
  static const _announceAfter = Duration(milliseconds: 700);

  final _search = TextEditingController();
  late Future<List<String>> _areas;
  String _query = '';
  Timer? _announcement;

  /// Finding the phone's location.
  bool _locating = false;

  /// Why "Use my location" didn't work, if it didn't.
  String? _locateProblem;

  @override
  void initState() {
    super.initState();
    _areas = context.read<CatalogRepository>().areas();
  }

  @override
  void dispose() {
    _announcement?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() => _areas = context.read<CatalogRepository>().areas());
  }

  void _queryChanged(String value) {
    setState(() => _query = value);
    _announcement?.cancel();
    if (value.trim().isNotEmpty) {
      _announcement = Timer(_announceAfter, _announceMatches);
    }
  }

  /// The listed area nearest the phone, if the phone is in Abuja.
  Future<void> _useLocation(List<String> areas) async {
    setState(() {
      _locating = true;
      _locateProblem = null;
    });
    final point = await context.read<LocationService>().current();
    if (!mounted) return;
    if (point == null) {
      setState(() {
        _locating = false;
        _locateProblem =
            'Location is off or not allowed. Pick your area below.';
      });
      return;
    }
    // Further than this from the city centre is outside Abuja.
    if (point.kmTo(AbujaPlaces.city) > 60) {
      setState(() {
        _locating = false;
        _locateProblem =
            'You seem to be outside Abuja. RijHub serves Abuja for now, so pick an area below.';
      });
      return;
    }
    final nearest = (areas.toList()
          ..sort((a, b) => AbujaPlaces.centreOf(a)
              .kmTo(point)
              .compareTo(AbujaPlaces.centreOf(b).kmTo(point))))
        .first;
    Navigator.pop(context, nearest);
  }

  void _clear() {
    _announcement?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  /// Tells screen readers what the list now shows everyone else.
  Future<void> _announceMatches() async {
    final List<String> areas;
    try {
      areas = await _areas;
    } on Object {
      // The list's place says it couldn't load, and that is read out.
      return;
    }
    // Not once an area is chosen and the sheet is on its way out.
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    final count = _matches(areas).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      switch (count) {
        0 => 'No areas match "${_query.trim()}"',
        1 => '1 area matches',
        _ => '$count areas match',
      },
      Directionality.of(context),
    );
  }

  /// Areas that start with the query come first, then any that contain it.
  /// "cbd" finds Central Business District by its initials.
  List<String> _matches(List<String> areas) {
    final query = _plain(_query);
    if (query.isEmpty) return areas;
    final starts = <String>[];
    final contains = <String>[];
    for (final area in areas) {
      final name = _plain(area);
      if (name.startsWith(query)) {
        starts.add(area);
      } else if (name.contains(query) || _initials(area) == query) {
        contains.add(area);
      }
    }
    return [...starts, ...contains];
  }

  static String _plain(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static String _initials(String text) => text
      .toLowerCase()
      .split(RegExp(r'[\s-]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0])
      .join();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isArtisan = context.select<SessionController, bool>(
      (s) => s.role == UserRole.artisan,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The sign-in sheet's top row, so every sheet closes from the
            // same place.
            AuthSheetBar(onClose: () => Navigator.pop(context)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.s8,
                AppSpace.gutter,
                AppSpace.s8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Choose your area',
                      style: AppText.headline.copyWith(color: c.textPrimary),
                    ),
                  ),
                  SizedBox(height: AppSpace.s8),
                  Text(
                    isArtisan
                        ? "We'll show you jobs nearby."
                        : "We'll show you artisans nearby.",
                    style: AppText.body.copyWith(color: c.textSecondary),
                  ),
                  SizedBox(height: AppSpace.s16),
                  AppTextField(
                    controller: _search,
                    // Still named once the hint gives way to what's typed.
                    semanticLabel: 'Search areas',
                    hint: 'Search areas in Abuja',
                    prefix: Icon(
                      IconsaxPlusLinear.search_normal_1,
                      size: AppSize.icon,
                      color: c.textTertiary,
                    ),
                    suffix: _query.isEmpty
                        ? null
                        : AppIconButton(
                            icon: IconsaxPlusBold.close_circle,
                            iconColor: c.textTertiary,
                            semanticLabel: 'Clear search',
                            onPressed: _clear,
                          ),
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.words,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: _queryChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _areas,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _Message(
                      child: InlineError(
                        message: "We couldn't load the areas.",
                        onRetry: _retry,
                      ),
                    );
                  }
                  final areas = snapshot.data;
                  if (areas == null) return const _ListSkeleton();
                  final matches = _matches(areas);
                  if (matches.isEmpty) {
                    return _Message(
                      child: InlineNote(
                        icon: IconsaxPlusLinear.location,
                        title: 'No areas match "${_query.trim()}"',
                        message: 'RijHub serves Abuja for now. Check the '
                            'spelling, or pick the area closest to you.',
                      ),
                    );
                  }
                  // "Use my location" leads the full list, not a search.
                  final locate = _query.trim().isEmpty;
                  final offset = locate ? 1 : 0;
                  return ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      bottom:
                          AppSpace.s16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: matches.length + offset,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppSpace.gutter,
                      endIndent: AppSpace.gutter,
                      color: c.border,
                    ),
                    itemBuilder: (context, i) => locate && i == 0
                        ? _LocateRow(
                            busy: _locating,
                            problem: _locateProblem,
                            onTap: _locating ? null : () => _useLocation(areas),
                          )
                        : _AreaRow(
                            name: matches[i - offset],
                            selected: matches[i - offset] == widget.current,
                            onTap: () =>
                                Navigator.pop(context, matches[i - offset]),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One area. Tapping it, or Enter while it has keyboard focus, chooses it
/// and closes the sheet.
class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One node for screen readers: the name, the tap and whether it's the
    // area already chosen.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      // Inset a little, so the focus ring clears the edges of the screen.
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
        child: Pressable(
          onTap: onTap,
          // The list clips, so the ring sits on the row's edges.
          focusOffset: 0,
          child: Container(
            constraints: BoxConstraints(minHeight: AppSize.input),
            // The name still lines up with the gutter.
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.gutter - AppSpace.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: AppText.bodyLarge.copyWith(
                      color: c.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (selected) ...[
                  SizedBox(width: AppSpace.s12),
                  Icon(
                    IconsaxPlusBold.tick_circle,
                    size: AppSize.icon,
                    color: c.brandStroke,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Use my location": finds the nearest area, asking to share location
/// only now.
class _LocateRow extends StatelessWidget {
  const _LocateRow({required this.busy, required this.onTap, this.problem});

  final bool busy;
  final VoidCallback? onTap;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      label: busy ? 'Finding your area' : 'Use my location',
      hint: problem,
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
        child: Pressable(
          onTap: onTap,
          focusOffset: 0,
          child: Container(
            constraints: BoxConstraints(minHeight: AppSize.input),
            padding: EdgeInsets.symmetric(
                horizontal: AppSpace.gutter - AppSpace.s8,
                vertical: AppSpace.s8),
            child: Row(
              children: [
                SizedBox(
                  width: AppSize.icon,
                  height: AppSize.icon,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2, color: c.brandStroke)
                      : Icon(IconsaxPlusLinear.gps,
                          size: AppSize.icon, color: c.brandText),
                ),
                SizedBox(width: AppSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busy ? 'Finding your area…' : 'Use my location',
                        style: AppText.bodyLarge.copyWith(
                            color: c.brandText, fontWeight: FontWeight.w600),
                      ),
                      if (problem != null)
                        Text(problem!,
                            style: AppText.bodySmall
                                .copyWith(color: c.textSecondary)),
                    ],
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

class _Message extends StatelessWidget {
  const _Message({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.s8,
        AppSpace.gutter,
        0,
      ),
      child: Align(alignment: Alignment.topCenter, child: child),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  static const _widths = [0.32, 0.44, 0.26, 0.38, 0.3, 0.48, 0.34, 0.4];

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: LayoutBuilder(
        // A list, not a column, so it clips instead of overflowing when the
        // keyboard leaves little room.
        builder: (context, constraints) => ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final width in _widths)
              Container(
                height: AppSize.input,
                padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: constraints.maxWidth * width,
                  height: AppSpace.s16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
