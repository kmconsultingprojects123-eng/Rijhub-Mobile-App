import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../ask/ask_launch.dart';
import '../bookings/bookings_tab.dart';
import '../location/area_pill.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// Finding artisans: search by name, trade or problem, filter, sort, and
/// switch between a list and a map.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen(
      {super.key,
      this.categoryId,
      this.startOnMap = false,
      this.standalone = false});

  final String? categoryId;
  final bool startOnMap;

  /// Pushed over the tabs (the home's map), with a back button.
  final bool standalone;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  late String? _category = widget.categoryId;
  bool _freeNow = false;
  ArtisanSort _sort = ArtisanSort.recommended;
  late bool _map = widget.startOnMap;
  Artisan? _selected;
  List<Artisan>? _results;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen old) {
    super.didUpdateWidget(old);
    if (old.categoryId != widget.categoryId && widget.categoryId != null) {
      _category = widget.categoryId;
      _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = ++_request;
    final area = context.read<SessionController>().area ?? AreaPill.city;
    setState(() => _error = null);
    try {
      final results = await context.read<DirectoryRepository>().search(
            area: area,
            query: _query.text,
            categoryId: _category,
            freeNow: _freeNow,
            sort: _sort,
          );
      if (!mounted || id != _request) return;
      setState(() {
        _results = results;
        if (_selected != null && !results.any((a) => a.id == _selected!.id)) {
          _selected = null;
        }
      });
    } on Object catch (e) {
      if (mounted && id == _request) setState(() => _error = e);
    }
  }

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
    setState(() {});
  }

  Future<void> _pickSort() async {
    final picked = await showChoiceSheet<ArtisanSort>(
      context,
      title: 'Sort by',
      selected: _sort,
      options: const [
        (ArtisanSort.recommended, 'Recommended'),
        (ArtisanSort.nearest, 'Nearest'),
        (ArtisanSort.rating, 'Top rated'),
        (ArtisanSort.price, 'Lowest price'),
      ],
    );
    if (picked != null && picked != _sort) {
      setState(() => _sort = picked);
      await _search();
    }
  }

  String get _sortLabel => switch (_sort) {
        ArtisanSort.recommended => 'Recommended',
        ArtisanSort.nearest => 'Nearest',
        ArtisanSort.rating => 'Top rated',
        ArtisanSort.price => 'Lowest price',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final area = context.select<SessionController, String?>((s) => s.area);
    final results = _results;
    final plural = _category == null
        ? 'artisans'
        : TextCase.midSentence(
            Trades.byId(_category!).artisanPlural ?? 'artisans');
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.standalone)
          TopBar(
              title: 'Map',
              subtitle: area == null ? 'All of Abuja' : 'Near $area')
        else
          TabTitle(
            'Explore',
            // Where, and list or map: the same pair the artisan's Jobs tab has.
            trailing: Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AreaPill(),
                  SizedBox(width: 6.w),
                  AppIconButton(
                    icon:
                        _map ? IconsaxPlusLinear.menu_1 : IconsaxPlusLinear.map,
                    filled: true,
                    semanticLabel: _map ? 'Show as a list' : 'Show on a map',
                    onPressed: () => setState(() => _map = !_map),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: _SearchField(
              controller: _query,
              onChanged: _typed,
              onClear: () {
                _query.clear();
                _search();
                setState(() {});
              }),
        ),
        SizedBox(height: 4.w),
        ChipRow(children: [
          PromptChip(
              label: 'All',
              solid: _category == null,
              onTap: () {
                setState(() => _category = null);
                _search();
              }),
          for (final t in Trades.all)
            PromptChip(
              label: t.name,
              icon: CategoryIcons.of(t.iconKey),
              solid: _category == t.id,
              onTap: () {
                setState(() => _category = t.id);
                _search();
              },
            ),
        ]),
        // How many, then the two ways to narrow them. Everyone listed is
        // ID-checked, so there's no "verified" filter.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  results == null
                      ? ''
                      : '${results.length} ${results.length == 1 ? plural.replaceAll(RegExp(r's$'), '') : plural}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(color: c.textSecondary),
                ),
              ),
              PromptChip(
                label: 'Free now',
                selected: _freeNow,
                onTap: () {
                  setState(() => _freeNow = !_freeNow);
                  _search();
                },
              ),
              SizedBox(width: 6.w),
              PromptChip(
                label: _sort == ArtisanSort.recommended ? 'Sort' : _sortLabel,
                icon: IconsaxPlusLinear.sort,
                onTap: _pickSort,
              ),
            ],
          ),
        ),
      ],
    );

    final Widget body;
    if (_error != null && results == null) {
      body = Center(
          child: InlineError(
              message: "We couldn't load artisans. Check your connection.",
              onRetry: _search));
    } else if (results == null) {
      body = const ListSkeleton();
    } else if (results.isEmpty) {
      body = ListView(
        children: [
          SizedBox(height: 40.w),
          EmptyState(
            icon: IconsaxPlusLinear.search_normal_1,
            title: 'No one matches that',
            message: _query.text.isEmpty
                ? 'Try another trade, or turn off a filter.'
                : 'Tell Employi what you need instead, and we will find the right person.',
            action: AppButton(
              label: _query.text.isEmpty ? 'Clear filters' : 'Ask Employi',
              expand: false,
              onPressed: _query.text.isEmpty
                  ? () {
                      setState(() {
                        _freeNow = false;
                        _category = null;
                      });
                      _search();
                    }
                  : () => openAsk(context, text: _query.text, typed: true),
            ),
          ),
        ],
      );
    } else if (_map) {
      body = _MapResults(
        results: results,
        area: area,
        selected: _selected,
        onSelect: (a) => setState(() => _selected = a),
      );
    } else {
      body = RefreshIndicator(
        color: c.brandStroke,
        onRefresh: _search,
        child: ListView(
          padding: EdgeInsets.fromLTRB(g, 4.w, g, 24.w),
          children: [
            for (final (i, a) in results.indexed)
              ArtisanRow(
                artisan: a,
                hasArea: area != null,
                divider: i < results.length - 1,
                onTap: () => context.push(Routes.artisan(a.id)),
              ),
            SizedBox(height: 16.w),
            Pressable(
              onTap: () => openAsk(context,
                  text: _query.text.isEmpty ? null : _query.text, typed: true),
              semanticLabel: 'Not sure who you need? Ask Employi',
              child: Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(16.w)),
                child: Row(
                  children: [
                    const RijHubAvatar(size: 36),
                    SizedBox(width: 12.w),
                    Expanded(
                        child: Text(
                            'Not sure who you need? Describe it and Employi will match you.',
                            style: AppText.bodySmall)),
                    Icon(IconsaxPlusLinear.arrow_right_3,
                        size: 16.w, color: c.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: widget.standalone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, SizedBox(height: 4.w), Expanded(child: body)],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller,
      required this.onChanged,
      required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 52.w,
      padding: EdgeInsets.only(left: 16.w, right: 4.w),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(IconsaxPlusLinear.search_normal_1,
              size: 20.w, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: AppText.body,
              cursorColor: c.brandStroke,
              decoration: InputDecoration(
                hintText: 'Search a name, trade or problem',
                hintStyle: AppText.body.copyWith(color: c.textTertiary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            AppIconButton(
                icon: IconsaxPlusLinear.close_circle,
                semanticLabel: 'Clear search',
                onPressed: onClear),
        ],
      ),
    );
  }
}

class _MapResults extends StatelessWidget {
  const _MapResults(
      {required this.results,
      required this.area,
      required this.selected,
      required this.onSelect});

  final List<Artisan> results;
  final String? area;
  final Artisan? selected;
  final ValueChanged<Artisan?> onSelect;

  @override
  Widget build(BuildContext context) {
    final centre = AbujaPlaces.centreOf(area);
    final shown =
        (area == null ? results : results.where((a) => a.distanceKm <= 4))
            .take(16)
            .toList();
    return Stack(
      children: [
        Positioned.fill(
          child: RijMap(
            lat: centre.lat,
            lng: centre.lng,
            kmAcross: area == null ? 14 : 6.5,
            fit: area == null,
            showMe: area != null,
            semanticLabel: 'Map of ${shown.length} artisans',
            markers: [
              for (final a in shown)
                if (a.location != null)
                  MapMarker(
                    key: ValueKey(a.id),
                    lat: a.location!.lat,
                    lng: a.location!.lng,
                    child: Semantics(
                      button: true,
                      label: '${a.name}, from ${Naira.format(a.startingPrice)}',
                      child: GestureDetector(
                        onTap: () => onSelect(a),
                        child: FacePin(
                          name: a.name,
                          photo: a.photo,
                          size: selected?.id == a.id ? 40 : 34,
                          selected: selected?.id == a.id,
                          free: a.isAvailableToday,
                          label: selected?.id == a.id
                              ? Naira.format(a.startingPrice)
                              : null,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (selected != null)
          Positioned(
            left: AppSpace.gutter,
            right: AppSpace.gutter,
            bottom: 16.w,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20.w),
                boxShadow: AppShadows.floating,
              ),
              child: ArtisanRow(
                artisan: selected!,
                hasArea: area != null,
                divider: false,
                onTap: () => context.push(Routes.artisan(selected!.id)),
              ),
            ),
          )
        else
          Positioned(
            left: 0,
            right: 0,
            bottom: 16.w,
            child: Center(
              child: MapPill(
                  label: 'Tap a face to see who it is',
                  icon: IconsaxPlusLinear.finger_cricle),
            ),
          ),
      ],
    );
  }
}
