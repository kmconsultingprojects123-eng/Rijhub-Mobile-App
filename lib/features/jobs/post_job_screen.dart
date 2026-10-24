import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/media.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/catalog/trades.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../location/area_picker_sheet.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

/// Posting a job for quotes, as a form, for people who prefer one to the
/// conversation. Artisans near the place send quotes.
class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key, this.editing});

  /// The job being changed; a new job when null.
  final ClientJob? editing;

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

enum _When { asap, week } // flexible went: it was stored just like week

class _PostJobScreenState extends State<PostJobScreen> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _landmark = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  String? _trade;

  /// The trade guessed from the title, if any.
  String? _suggested;
  late String? _area = context.read<SessionController>().area;
  _When _when = _When.week;
  final _photos = <String>[];
  bool _posting = false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final job = widget.editing;
    if (job == null) return;
    _title.text = job.title;
    _details.text = job.description ?? '';
    _landmark.text = job.landmark ?? '';
    _min.text = job.budgetMin?.toString() ?? '';
    _max.text = job.budgetMax?.toString() ?? '';
    _trade = _suggested = job.categoryId;
    _area = job.area;
    _when = job.isUrgent ? _When.asap : _When.week;
    _photos.addAll(job.photos);
  }

  @override
  void dispose() {
    for (final c in [_title, _details, _landmark, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Straight to the photos (several at once), or the camera.
  Future<void> _addPhotos({bool camera = false}) async {
    final media = context.read<MediaService>();
    final List<String> picked;
    if (camera) {
      final path = await media.pickPhoto(camera: true);
      picked = [if (path != null) path];
    } else {
      picked = await media.pickPhotos();
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _photos.addAll(picked.take(5 - _photos.length)));
  }

  Future<void> _suggestTrade(String title) async {
    if (_trade != null || title.trim().length < 6) return;
    final t = await context.read<AskRepository>().triage(AskInput(text: title));
    if (mounted && t.confident && _trade == null) {
      setState(() => _trade = _suggested = t.categoryId);
    }
  }

  bool get _valid =>
      _title.text.trim().length >= 4 && _trade != null && _area != null;

  Future<void> _post() async {
    setState(() => _tried = true);
    if (!_valid) return;
    final ok = await context
        .read<AuthGate>()
        .ensureSignedIn(context, AuthPrompt.postJob);
    if (!ok || !mounted) return;
    setState(() => _posting = true);
    final repo = context.read<ClientJobRepository>();
    final draft = JobDraft(
      title: _title.text.trim(),
      categoryId: _trade!,
      area: _area!,
      landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      description: _details.text.trim().isEmpty ? null : _details.text.trim(),
      photos: List.unmodifiable(_photos),
      budgetMin: int.tryParse(_min.text.replaceAll(',', '')),
      budgetMax: int.tryParse(_max.text.replaceAll(',', '')),
      isUrgent: _when == _When.asap,
    );
    final editing = widget.editing;
    final job = await runAction(
      context,
      () => editing == null ? repo.post(draft) : repo.update(editing.id, draft),
    );
    if (!mounted) return;
    setState(() => _posting = false);
    if (job == null) return;
    if (editing != null) {
      showToast(context, 'Job updated. Artisans see the changes.');
      goBack(context, true);
      return;
    }
    showToast(context, 'Job posted. Quotes usually come within 30 minutes.');
    context.pushReplacement(Routes.clientJob(job.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter;
    final editing = widget.editing != null;
    return PageScaffold(
      title: editing ? 'Edit job' : 'Post a job',
      subtitle:
          editing ? 'Quotes already in stay' : 'Artisans near you send quotes',
      bottom: AppButton(
          label: editing ? 'Save changes' : 'Post job',
          isLoading: _posting,
          onPressed: _posting ? null : _post),
      body: ListView(
        padding: EdgeInsets.fromLTRB(g, 8.w, g, 28.w),
        children: [
          AppTextField(
            controller: _title,
            label: 'What do you need done?',
            hint: 'Fix two sparking sockets in the kitchen',
            textCapitalization: TextCapitalization.sentences,
            errorText: _tried && _title.text.trim().length < 4
                ? 'Say what you need in a few words.'
                : null,
            onChanged: (v) {
              setState(() {});
              _suggestTrade(v);
            },
          ),
          SizedBox(height: 18.w),
          Text('Trade', style: AppText.labelSmall),
          if (_tried && _trade == null)
            Text('Pick the closest one.',
                style: AppText.bodySmall.copyWith(color: c.error)),
          SizedBox(height: 4.w),
          // One row: the trade guessed from the title comes first, so it
          // shows picked without a scroll.
          Bleed(
            child: ChipRow(
              children: [
                for (final t in [
                  if (_suggested != null) Trades.byId(_suggested!),
                  ...Trades.all.where((t) => t.id != _suggested),
                ])
                  PromptChip(
                    label: t.name,
                    icon: CategoryIcons.of(t.iconKey),
                    selected: _trade == t.id,
                    onTap: () => setState(() => _trade = t.id),
                  ),
              ],
            ),
          ),
          SizedBox(height: 18.w),
          AppTextField(
            controller: _details,
            label: 'Tell artisans more',
            optional: true,
            hint: 'Sizes, brands, what you tried, how to reach it',
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 6,
          ),
          SizedBox(height: 12.w),
          Text('Photos', style: AppText.labelSmall),
          SizedBox(height: 6.w),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.w,
            children: [
              for (final (i, p) in _photos.indexed)
                Stack(
                  children: [
                    PhotoThumb(image: p, size: 76),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Semantics(
                        button: true,
                        label: 'Remove photo ${i + 1}',
                        child: GestureDetector(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: Container(
                            width: 26.w,
                            height: 26.w,
                            decoration: const BoxDecoration(
                                color: Color(0xCC000000),
                                shape: BoxShape.circle),
                            child: Icon(IconsaxPlusLinear.close_circle,
                                size: 16.w, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_photos.length < 5)
                for (final (label, icon, camera) in [
                  ('Add photos', IconsaxPlusLinear.gallery_add, false),
                  ('Take a photo', IconsaxPlusLinear.camera, true),
                ])
                  Semantics(
                    button: true,
                    label: label,
                    child: GestureDetector(
                      onTap: () => _addPhotos(camera: camera),
                      child: Container(
                        width: 76.w,
                        height: 76.w,
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: BorderRadius.circular(20.w),
                          border: Border.all(color: c.border),
                        ),
                        child: Icon(icon, size: 24.w, color: c.textSecondary),
                      ),
                    ),
                  ),
            ],
          ),
          SizedBox(height: 4.w),
          Text('Photos get you better, faster quotes.',
              style: AppText.caption.copyWith(color: c.textTertiary)),
          SizedBox(height: 18.w),
          Text('Where', style: AppText.labelSmall),
          SizedBox(height: 6.w),
          Pressable(
            onTap: () async {
              final picked = await showAreaPicker(context, current: _area);
              if (picked != null) setState(() => _area = picked);
            },
            semanticLabel: 'Area, ${_area ?? 'not picked'}. Change',
            child: Container(
              height: AppSize.input,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                    color: _tried && _area == null ? c.error : c.inputBorder),
              ),
              child: Row(
                children: [
                  Icon(IconsaxPlusBold.location,
                      size: 18.w, color: c.brandText),
                  SizedBox(width: 10.w),
                  Expanded(
                      child: Text(_area ?? 'Pick the area',
                          style: AppText.bodyLarge.copyWith(
                              color: _area == null
                                  ? c.textTertiary
                                  : c.textPrimary))),
                  Icon(IconsaxPlusLinear.arrow_down,
                      size: 16.w, color: c.textSecondary),
                ],
              ),
            ),
          ),
          SizedBox(height: 10.w),
          AppTextField(
            controller: _landmark,
            label: 'Landmark',
            optional: true,
            hint:
                'Near Banex Plaza (the full address goes only to who you book)',
          ),
          SizedBox(height: 18.w),
          Text('When', style: AppText.labelSmall),
          SizedBox(height: 4.w),
          Wrap(
            spacing: 8.w,
            children: [
              for (final (w, label) in const [
                (_When.asap, 'As soon as possible'),
                (_When.week, 'This week'),
                // "I'm flexible" was stored just like "This week" (2026-10-23).
                // (_When.flexible, "I'm flexible"),
              ])
                PromptChip(
                    label: label,
                    selected: _when == w,
                    onTap: () => setState(() => _when = w)),
            ],
          ),
          // The budget went (2026-10-23): it was optional, and its own hint said
          // to leave it empty to hear what artisans charge. A job being edited
          // keeps the budget it has.
          // SizedBox(height: 18.w),
          // Text('Budget', style: AppText.labelSmall),
          // SizedBox(height: 2.w),
          // Text(
          //   _trade == null
          //       ? 'Optional. Leave it empty to hear what artisans charge.'
          //       : 'Optional. Most ${TextCase.midSentence(Trades.byId(_trade!).name)} jobs cost what artisans quote; leave it empty to see.',
          //   style: AppText.bodySmall.copyWith(color: c.textSecondary),
          // ),
          // SizedBox(height: 8.w),
          // Row(
          //   children: [
          //     Expanded(
          //         child: AppTextField(
          //             controller: _min,
          //             label: 'From',
          //             hint: '₦5,000',
          //             keyboardType: TextInputType.number)),
          //     SizedBox(width: 10.w),
          //     Expanded(
          //         child: AppTextField(
          //             controller: _max,
          //             label: 'To',
          //             hint: '₦12,000',
          //             keyboardType: TextInputType.number)),
          //   ],
          // ),
          SizedBox(height: 18.w),
          InlineNote(
            icon: IconsaxPlusLinear.shield_tick,
            title: 'You pay only when you accept a quote',
            message:
                'And Employi holds it until the job is done. Quotes are free.',
            iconColor: c.success,
          ),
          if (_trade != null) ...[
            SizedBox(height: 12.w),
            Center(
              child: Text(
                'We\'ll send it to ${TextCase.midSentence(Trades.byId(_trade!).artisanPlural ?? 'artisans')} near ${_area ?? 'you'}.',
                style: AppText.caption.copyWith(color: c.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
