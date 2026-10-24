import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/media.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/geo/places.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../artisan_profile/artisan_profile_screen.dart';
import '../booking/booking_sheets.dart';
import '../location/area_picker_sheet.dart';
import '../shared/page.dart';

// ---------------------------------------------------------------- services

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  /// With no services yet, the page opens on adding one, the first time.
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    return Loader<(ArtisanProfile, List<PriceGuideItem>)>(
      load: () async {
        final r = await Future.wait<Object>([
          context.read<ArtisanSetupRepository>().myProfile(),
          context.read<CatalogRepository>().priceGuide(),
        ]);
        return (r[0] as ArtisanProfile, r[1] as List<PriceGuideItem>);
      },
      loading: const PageScaffold(
          title: 'Services and prices', body: ListSkeleton()),
      builder: (context, data, reload) {
        final (profile, guide) = data;
        final c = context.colors;
        final trades = context.read<SessionController>().user?.tradeIds ??
            [profile.artisan.categoryId];
        Future<void> edit(ServiceOffer? s) async {
          final changed = await showModalBottomSheet<bool>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            backgroundColor: c.surface,
            builder: (_) =>
                _ServiceSheet(service: s, trades: trades, guide: guide),
          );
          if (changed == true) await reload();
        }

        if (profile.services.isEmpty && !_opened) {
          _opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) edit(null);
          });
        }

        return PageScaffold(
          title: 'Services and prices',
          subtitle: 'What clients can book you for',
          bottom: profile.services.isEmpty
              ? null
              : AppButton(
                  label: 'Add a service',
                  leading: const Icon(IconsaxPlusLinear.add),
                  onPressed: () => edit(null)),
          body: profile.services.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: IconsaxPlusLinear.tag,
                    title: 'Add what you do',
                    message:
                        'Clients book faster when they can see your prices. Start with your most common job.',
                    action: AppButton(
                        label: 'Add a service',
                        expand: false,
                        onPressed: () => edit(null)),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                  children: [
                    for (final s in profile.services)
                      Pressable(
                        onTap: () => edit(s),
                        pressedScale: 0.99,
                        focusOffset: 0,
                        semanticLabel:
                            '${s.name}, ${s.priceMax == null ? Naira.format(s.price) : Naira.range(s.price, s.priceMax)}. Edit',
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 14.w),
                          decoration: BoxDecoration(
                              border:
                                  Border(bottom: BorderSide(color: c.border))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: AppText.titleSmall),
                                    Text(
                                      [
                                        Trades.byId(s.categoryId).name,
                                        if (s.unit != null) s.unit!
                                      ].join(' · '),
                                      style: AppText.caption
                                          .copyWith(color: c.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                  s.priceMax == null
                                      ? Naira.format(s.price)
                                      : Naira.range(s.price, s.priceMax),
                                  style: AppText.labelSmall),
                              SizedBox(width: 8.w),
                              Icon(IconsaxPlusLinear.edit_2,
                                  size: 18.w, color: c.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(height: 16.w),
                    Text(
                      'Prices are what clients pay you. Employi adds its small fee on top, so you keep your full price.',
                      style: AppText.bodySmall.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet(
      {required this.service, required this.trades, required this.guide});

  final ServiceOffer? service;
  final List<String> trades;
  final List<PriceGuideItem> guide;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _price = TextEditingController(
      text: widget.service == null ? '' : '${widget.service!.price}');
  late final _max = TextEditingController(
      text: widget.service?.priceMax == null
          ? ''
          : '${widget.service!.priceMax}');
  late String _trade = widget.service?.categoryId ?? widget.trades.first;
  late bool _range = widget.service?.priceMax != null;
  late String? _unit = widget.service?.unit;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _n(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));

  bool get _valid {
    final p = _n(_price);
    if (_name.text.trim().length < 3 || p == null || p < 500) return false;
    if (_range && (_n(_max) == null || _n(_max)! <= p)) return false;
    return true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = context.read<ArtisanSetupRepository>();
    final saved = await runAction(
      context,
      () => repo.saveService(ServiceOffer(
        id: widget.service?.id ?? 's_${DateTime.now().millisecondsSinceEpoch}',
        categoryId: _trade,
        name: _name.text.trim(),
        price: _n(_price)!,
        priceMax: _range ? _n(_max) : null,
        unit: _unit,
      )),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = widget.guide.where((g) => g.categoryId == _trade).firstOrNull;
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter,
            AppSpace.gutter + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.service == null ? 'Add a service' : 'Edit service',
                  style: AppText.headline),
              SizedBox(height: 14.w),
              if (widget.trades.length > 1) ...[
                Wrap(
                  spacing: 8.w,
                  children: [
                    for (final t in widget.trades)
                      PromptChip(
                          label: Trades.byId(t).name,
                          selected: _trade == t,
                          onTap: () => setState(() => _trade = t)),
                  ],
                ),
                SizedBox(height: 10.w),
              ],
              AppTextField(
                controller: _name,
                label: 'Service',
                hint: 'AC servicing',
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 12.w),
              SegmentedTabs(
                  labels: const ['Fixed price', 'Price range'],
                  selected: _range ? 1 : 0,
                  onChanged: (i) => setState(() => _range = i == 1)),
              SizedBox(height: 12.w),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _price,
                      label: _range ? 'From' : 'Price',
                      hint: '₦8,000',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_range) ...[
                    SizedBox(width: 10.w),
                    Expanded(
                      child: AppTextField(
                        controller: _max,
                        label: 'To',
                        hint: '₦12,000',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ],
              ),
              if (hint != null) ...[
                SizedBox(height: 6.w),
                Text(
                  'Typical in Abuja for ${TextCase.midSentence(hint.problem)}: ${Naira.range(hint.minPrice, hint.maxPrice)}',
                  style: AppText.caption.copyWith(color: c.textTertiary),
                ),
              ],
              SizedBox(height: 12.w),
              Text('Price is for', style: AppText.labelSmall),
              SizedBox(height: 4.w),
              Wrap(
                spacing: 8.w,
                children: [
                  for (final (u, label) in const [
                    (null, 'The whole job'),
                    ('per unit', 'Per unit'),
                    ('per hour', 'Per hour'),
                    ('per visit', 'Per visit')
                  ])
                    PromptChip(
                        label: label,
                        selected: _unit == u,
                        onTap: () => setState(() => _unit = u)),
                ],
              ),
              SizedBox(height: 18.w),
              AppButton(
                  label: 'Save',
                  isLoading: _saving,
                  onPressed: !_valid || _saving ? null : _save),
              if (widget.service != null)
                AppButton(
                  label: 'Delete service',
                  variant: AppButtonVariant.tertiary,
                  onPressed: () async {
                    final ok = await confirmSheet(context,
                        title: 'Delete this service?',
                        message:
                            'Clients won\'t see it on your profile any more.',
                        confirm: 'Delete');
                    if (!ok || !context.mounted) return;
                    await context
                        .read<ArtisanSetupRepository>()
                        .deleteService(widget.service!.id);
                    if (context.mounted) Navigator.of(context).pop(true);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- work photos

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  /// An empty page opens the photos at once, the first time only.
  bool _opened = false;
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    return Loader<ArtisanProfile>(
      load: () => context.read<ArtisanSetupRepository>().myProfile(),
      loading: const PageScaffold(title: 'Work photos', body: ListSkeleton()),
      builder: (context, profile, reload) {
        final c = context.colors;
        // Straight from the photos (or the camera) onto the profile: no
        // chooser and no caption to fill in.
        Future<void> add({required bool camera}) async {
          final media = context.read<MediaService>();
          final setup = context.read<ArtisanSetupRepository>();
          final List<String> paths;
          if (camera) {
            final path = await media.pickPhoto(camera: true);
            paths = [if (path != null) path];
          } else {
            paths = await media.pickPhotos();
          }
          if (paths.isEmpty || !context.mounted) return;
          setState(() => _uploading = true);
          var added = 0;
          await runAction(context, () async {
            for (final path in paths) {
              await setup.addWorkPhoto(path);
              added++;
            }
          });
          if (!mounted) return;
          setState(() => _uploading = false);
          await reload();
          if (added > 0 && context.mounted) {
            showToast(
                context,
                added == 1
                    ? 'Photo added to your profile'
                    : '$added photos added to your profile');
          }
        }

        if (profile.work.isEmpty && !_opened) {
          _opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) add(camera: false);
          });
        }

        return PageScaffold(
          title: 'Work photos',
          subtitle: '${profile.work.length} on your profile',
          bottom: Row(
            children: [
              AppButton(
                  label: 'Camera',
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  leading: const Icon(IconsaxPlusLinear.camera),
                  onPressed: _uploading ? null : () => add(camera: true)),
              SizedBox(width: 10.w),
              Expanded(
                child: AppButton(
                    label: _uploading ? 'Adding…' : 'Add photos',
                    isLoading: _uploading,
                    leading: const Icon(IconsaxPlusLinear.gallery_add),
                    onPressed: _uploading ? null : () => add(camera: false)),
              ),
            ],
          ),
          body: profile.work.isEmpty
              ? const Center(
                  child: EmptyState(
                    icon: IconsaxPlusLinear.gallery,
                    title: 'Show your best work',
                    message:
                        'Clients book artisans with photos far more often. Add before-and-after shots of real jobs.',
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    if (profile.work.length < 6)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                            AppSpace.gutter, 4.w, AppSpace.gutter, 0),
                        sliver: SliverToBoxAdapter(
                          child: InlineNote(
                            icon: IconsaxPlusLinear.gallery_favorite,
                            title: 'Add ${6 - profile.work.length} more',
                            message:
                                'Profiles with six or more photos of real jobs get booked far more often.',
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          AppSpace.gutter, 16.w, AppSpace.gutter, 24.w),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16.w,
                          crossAxisSpacing: 12.w,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: profile.work.length,
                        itemBuilder: (context, i) {
                          final w = profile.work[i];
                          return Pressable(
                            pressedScale: 0.98,
                            semanticLabel:
                                '${w.caption ?? 'Work photo ${i + 1}'}. Options',
                            onTap: () async {
                              final delete = await confirmSheet(
                                context,
                                title: w.caption ?? 'Work photo',
                                message: 'Remove this photo from your profile?',
                                confirm: 'Remove photo',
                                cancel: 'Keep it',
                              );
                              if (!delete || !context.mounted) return;
                              await context
                                  .read<ArtisanSetupRepository>()
                                  .deleteWorkPhoto(w.id);
                              await reload();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16.w),
                                    child: Image(
                                        image: imageFor(w.image)!,
                                        fit: BoxFit.cover,
                                        alignment:
                                            Alignment(w.focusX, w.focusY)),
                                  ),
                                ),
                                if (w.caption != null) ...[
                                  SizedBox(height: 6.w),
                                  Text(
                                    w.caption!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.bodySmall
                                        .copyWith(color: c.textPrimary),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  // Captions were asked for after every photo; work photos now go straight
  // onto the profile (2026-10-23, fewer taps). Kept for if they come back.
  //
  // static Future<String?> _askCaption(BuildContext context) async {
  //   final controller = TextEditingController();
  //   final caption = await showModalBottomSheet<String>(
  //     context: context,
  //     useRootNavigator: true,
  //     isScrollControlled: true,
  //     useSafeArea: true,
  //     showDragHandle: true,
  //     backgroundColor: context.colors.surface,
  //     builder: (context) => Padding(
  //       padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter,
  //           AppSpace.gutter + MediaQuery.viewInsetsOf(context).bottom),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         crossAxisAlignment: CrossAxisAlignment.stretch,
  //         children: [
  //           Text('Say what it shows', style: AppText.headline),
  //           SizedBox(height: 12.w),
  //           AppTextField(
  //               controller: controller,
  //               label: 'Caption',
  //               optional: true,
  //               hint: 'Split unit service, Wuse 2',
  //               autofocus: true),
  //           SizedBox(height: 14.w),
  //           AppButton(
  //               label: 'Add photo',
  //               onPressed: () =>
  //                   Navigator.of(context).pop(controller.text.trim())),
  //         ],
  //       ),
  //     ),
  //   );
  //   controller.dispose();
  //   return caption == null || caption.isEmpty ? null : caption;
  // }
}

// ---------------------------------------------------------------- work area

class WorkAreaScreen extends StatefulWidget {
  const WorkAreaScreen({super.key});

  @override
  State<WorkAreaScreen> createState() => _WorkAreaScreenState();
}

class _WorkAreaScreenState extends State<WorkAreaScreen> {
  ServiceArea? _area;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<ArtisanSetupRepository>().myProfile().then((p) {
      if (mounted) setState(() => _area = p.serviceArea);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final area = _area;
    if (area == null) {
      return const PageScaffold(title: 'Work area', body: ListSkeleton());
    }
    final centre = AbujaPlaces.centreOf(area.area);
    final near = AbujaPlaces.near(centre, withinKm: area.radiusKm.toDouble());
    return PageScaffold(
      title: 'Work area',
      subtitle: 'Where you take jobs',
      bottom: AppButton(
        label: 'Save',
        isLoading: _saving,
        onPressed: () async {
          setState(() => _saving = true);
          await context.read<ArtisanSetupRepository>().saveServiceArea(area);
          if (!context.mounted) return;
          showToast(context, 'Work area saved');
          goBack(context);
        },
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20.w),
            child: SizedBox(
              height: 230.w,
              child: LayoutBuilder(
                builder: (context, box) {
                  // Sized so the circle sits inside the map with room
                  // around it; the map is wider than it is tall.
                  final kmAcross = math.max(6.0,
                      area.radiusKm * 2 * box.maxWidth / (box.maxHeight * 0.8));
                  final radiusPx = box.maxWidth / kmAcross * area.radiusKm;
                  // A few names spread around the circle rather than the
                  // nearest handful, which all crowd the middle.
                  final labels = <MapLabel>[];
                  final spacing = kmAcross / 5;
                  for (final (name, p)
                      in AbujaPlaces.near(centre, withinKm: kmAcross / 2)) {
                    if (labels.length == 6) break;
                    final km = p.kmTo(centre);
                    // Not right by the middle dot, nor under the circle's edge.
                    if (name == area.area ||
                        km < spacing / 2 ||
                        (km - area.radiusKm).abs() < kmAcross * 0.05) {
                      continue;
                    }
                    if (labels
                        .any((l) => GeoPoint(l.lat, l.lng).kmTo(p) < spacing)) {
                      continue;
                    }
                    labels.add(MapLabel(name, p.lat, p.lng));
                  }
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: RijMap(
                          lat: centre.lat,
                          lng: centre.lng,
                          kmAcross: kmAcross,
                          showMe: true,
                          labels: labels,
                        ),
                      ),
                      IgnorePointer(
                        child: Container(
                          width: radiusPx * 2,
                          height: radiusPx * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.brand.withValues(alpha: 0.08),
                            border: Border.all(color: c.brandStroke, width: 2),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SizedBox(height: 18.w),
          Text('Based in', style: AppText.labelSmall),
          SizedBox(height: 6.w),
          Pressable(
            onTap: () async {
              final picked = await showAreaPicker(context, current: area.area);
              if (picked != null) {
                setState(() =>
                    _area = ServiceArea(area: picked, radiusKm: area.radiusKm));
              }
            },
            semanticLabel: 'Based in ${area.area}. Change',
            child: Container(
              height: AppSize.input,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: c.inputBorder)),
              child: Row(
                children: [
                  Icon(IconsaxPlusBold.location,
                      size: 18.w, color: c.brandText),
                  SizedBox(width: 10.w),
                  Expanded(child: Text(area.area, style: AppText.bodyLarge)),
                  Icon(IconsaxPlusLinear.arrow_down,
                      size: 16.w, color: c.textSecondary),
                ],
              ),
            ),
          ),
          SizedBox(height: 20.w),
          Row(
            children: [
              Text('How far you travel', style: AppText.labelSmall),
              const Spacer(),
              Text('${area.radiusKm} km', style: AppText.titleSmall),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.w,
              activeTrackColor: c.brandStroke,
              inactiveTrackColor: c.surfaceMuted,
              thumbColor: c.brandStroke,
              overlayColor: c.brand.withValues(alpha: 0.12),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: area.radiusKm.toDouble(),
              min: 3,
              max: 50,
              divisions: 47,
              semanticFormatterCallback: (v) => '${v.round()} kilometres',
              onChanged: (v) => setState(() =>
                  _area = ServiceArea(area: area.area, radiusKm: v.round())),
            ),
          ),
          Text(
            near.length <= 1
                ? 'Covers ${area.area}.'
                : 'Covers ${near.take(5).map((e) => e.$1).join(', ')}${near.length > 5 ? ' and ${near.length - 5} more' : ''}.',
            style: AppText.bodySmall.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- hours

class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key});

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> {
  WorkingHours? _h;
  bool _saving = false;

  static const _presets = [
    (
      'Mon–Fri, 9–5',
      WorkingHours(
          days: {1, 2, 3, 4, 5}, startMinutes: 9 * 60, endMinutes: 17 * 60)
    ),
    ('Mon–Sat, 8–6', WorkingHours.usual),
    (
      'Every day, 7–9',
      WorkingHours(
          days: {1, 2, 3, 4, 5, 6, 7},
          startMinutes: 7 * 60,
          endMinutes: 21 * 60)
    ),
  ];

  @override
  void initState() {
    super.initState();
    context.read<ArtisanSetupRepository>().myProfile().then((p) {
      if (mounted) setState(() => _h = p.hours);
    });
  }

  static bool _same(WorkingHours a, WorkingHours b) =>
      a.days.length == b.days.length &&
      a.days.containsAll(b.days) &&
      a.startMinutes == b.startMinutes &&
      a.endMinutes == b.endMinutes;

  static String _clock(int m) {
    final h = m ~/ 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickTime({required bool start}) async {
    final h = _h!;
    final picked = await showChoiceSheet<int>(
      context,
      title: start ? 'Start at' : 'Finish at',
      options: [
        for (var i = start ? 5 : 10; i <= (start ? 14 : 23); i++)
          (i * 60, _clock(i * 60)),
      ],
      selected: start ? h.startMinutes : h.endMinutes,
      // At least two hours a day, so a client can fit a job in.
      enabled: start ? null : (m) => m >= h.startMinutes + 120,
    );
    if (picked == null || !mounted) return;
    setState(() => _h = start
        ? WorkingHours(
            days: h.days,
            startMinutes: picked,
            endMinutes: math.max(h.endMinutes, picked + 120))
        : WorkingHours(
            days: h.days, startMinutes: h.startMinutes, endMinutes: picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = _h;
    if (h == null) {
      return const PageScaffold(title: 'Working hours', body: ListSkeleton());
    }
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const full = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final allDay = h.startMinutes == 0 && h.endMinutes >= 1439;

    Widget label(String text) => Padding(
          padding: EdgeInsets.only(top: 20.w, bottom: 8.w),
          child: Text(text, style: AppText.labelSmall),
        );
    Widget timeField(String name, int minutes, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: onTap,
            semanticLabel: '$name ${_clock(minutes)}. Change',
            child: Container(
              height: AppSize.input,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: c.inputBorder)),
              child: Row(
                children: [
                  Text(name,
                      style:
                          AppText.bodySmall.copyWith(color: c.textSecondary)),
                  SizedBox(width: 8.w),
                  Expanded(
                      child: Text(_clock(minutes), style: AppText.titleSmall)),
                  Icon(IconsaxPlusLinear.arrow_down,
                      size: 16.w, color: c.textSecondary),
                ],
              ),
            ),
          ),
        );

    return PageScaffold(
      title: 'Working hours',
      subtitle: 'When clients can book you',
      bottom: AppButton(
        label: 'Save',
        isLoading: _saving,
        onPressed: h.days.isEmpty
            ? null
            : () async {
                setState(() => _saving = true);
                await context.read<ArtisanSetupRepository>().saveHours(h);
                if (!context.mounted) return;
                showToast(context, 'Hours saved: ${hoursLabel(h)}');
                goBack(context);
              },
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
        children: [
          InlineNote(
            icon: IconsaxPlusLinear.clock,
            title: h.days.isEmpty ? 'Pick at least one day' : hoursLabel(h),
            message:
                'Requests only come in these hours. Switch to Off any time from your home screen.',
          ),
          label('Quick picks'),
          Wrap(
            spacing: 8.w,
            children: [
              for (final (name, preset) in _presets)
                PromptChip(
                    label: name,
                    selected: _same(h, preset),
                    onTap: () => setState(() => _h = preset)),
            ],
          ),
          label('Days'),
          Row(
            children: [
              for (var d = 1; d <= 7; d++) ...[
                if (d > 1) SizedBox(width: 6.w),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: h.days.contains(d),
                    label: full[d - 1],
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        final days = {...h.days};
                        days.contains(d) ? days.remove(d) : days.add(d);
                        _h = WorkingHours(
                            days: days,
                            startMinutes: h.startMinutes,
                            endMinutes: h.endMinutes);
                      }),
                      child: Container(
                        height: 44.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              h.days.contains(d) ? c.surfaceStrong : c.surface,
                          shape: BoxShape.circle,
                          border: h.days.contains(d)
                              ? null
                              : Border.all(color: c.border),
                        ),
                        child: Text(names[d - 1],
                            style: AppText.labelSmall.copyWith(
                                color: h.days.contains(d)
                                    ? c.onSurfaceStrong
                                    : c.textPrimary)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          label('Hours'),
          if (!allDay)
            Row(
              children: [
                timeField('From', h.startMinutes, () => _pickTime(start: true)),
                SizedBox(width: 10.w),
                timeField('To', h.endMinutes, () => _pickTime(start: false)),
              ],
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: allDay,
            activeTrackColor: c.success,
            title: Text('Any time of day', style: AppText.body),
            subtitle: Text('For emergency call-outs',
                style: AppText.caption.copyWith(color: c.textTertiary)),
            onChanged: (on) => setState(() => _h = WorkingHours(
                  days: h.days,
                  startMinutes: on ? 0 : 8 * 60,
                  endMinutes: on ? 1439 : 18 * 60,
                )),
          ),
        ],
      ),
    );
  }
}
