import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/media.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../booking/booking_sheets.dart';
import '../bookings/bookings_tab.dart';
import '../location/area_picker_sheet.dart';
import '../shared/cards.dart';
import '../shared/page.dart';

// ---------------------------------------------------------------- edit profile

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final AppUser _user = context.read<SessionController>().user!;
  late final _first = TextEditingController(text: _user.firstName);
  late final _last = TextEditingController(text: _user.lastName);
  late final _email = TextEditingController(text: _user.email ?? '');
  final _about = TextEditingController();
  final _years = TextEditingController();
  final _business = TextEditingController();
  var _certificates = <String>[];
  late String? _photo = _user.photo;
  bool _saving = false;
  bool _loadedAbout = false;

  bool get _artisan => _user.role == UserRole.artisan;

  @override
  void initState() {
    super.initState();
    if (_artisan) {
      context.read<ArtisanSetupRepository>().myProfile().then((p) {
        if (!mounted) return;
        setState(() {
          _about.text = p.about;
          _years.text = p.experienceYears == 0 ? '' : '${p.experienceYears}';
          _business.text = p.businessName ?? '';
          _certificates = [...p.certifications];
          _loadedAbout = true;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _about, _years, _business]) {
      c.dispose();
    }
    super.dispose();
  }

  // Certificates are hidden for now (see the note in build).
  // Future<void> _addCertificate() async {
  //   final controller = TextEditingController();
  //   final name = await showModalBottomSheet<String>(
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
  //           Text('Add a certificate', style: AppText.headline),
  //           SizedBox(height: 12.w),
  //           AppTextField(
  //             controller: controller,
  //             label: 'Certificate',
  //             hint: 'For example, NABTEB Plumbing',
  //             autofocus: true,
  //             textCapitalization: TextCapitalization.words,
  //           ),
  //           SizedBox(height: 14.w),
  //           AppButton(
  //             label: 'Add',
  //             onPressed: () =>
  //                 Navigator.of(context).pop(controller.text.trim()),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  //   controller.dispose();
  //   if (name == null || name.isEmpty || !mounted) return;
  //   setState(() => _certificates.add(name));
  // }

  /// The photo itself opens the photos; its camera badge, the camera.
  Future<void> _pickPhoto({bool camera = false}) async {
    final path = await context.read<MediaService>().pickPhoto(camera: camera);
    if (path != null && mounted) setState(() => _photo = path);
  }

  String? get _emailError {
    final e = _email.text.trim();
    if (e.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)
        ? null
        : 'That email doesn\'t look right.';
  }

  Future<void> _save() async {
    // Some people go by one name, so the last name can stay empty.
    if (_first.text.trim().isEmpty || _emailError != null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final session = context.read<SessionController>();
    final account = context.read<AccountRepository>();
    final setup = context.read<ArtisanSetupRepository>();
    final updated = await runAction(context, () async {
      final u = await account.updateProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        photo: _photo,
      );
      if (_artisan && _loadedAbout) {
        await setup.saveAbout(
          about: _about.text.trim(),
          experienceYears: int.tryParse(_years.text) ?? 0,
          businessName: _business.text.trim(),
          certifications: _certificates,
        );
      }
      return u;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (updated == null) return;
    await session.signIn(updated);
    if (!mounted) return;
    showToast(context, 'Profile saved');
    goBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // final area = context.select<SessionController, String?>((s) => s.area);
    return PageScaffold(
      title: 'Edit profile',
      bottom: AppButton(
          label: 'Save', isLoading: _saving, onPressed: _saving ? null : _save),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 8.w, AppSpace.gutter, 24.w),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: 'Change photo',
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    AppAvatar(
                        name: _user.fullName,
                        image: imageFor(_photo),
                        size: 96.w),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Semantics(
                        button: true,
                        label: 'Take a photo',
                        child: GestureDetector(
                          onTap: () => _pickPhoto(camera: true),
                          child: Container(
                            width: 34.w,
                            height: 34.w,
                            decoration: BoxDecoration(
                                color: c.brand,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: c.surface, width: 3)),
                            child: Icon(IconsaxPlusLinear.camera,
                                size: 16.w, color: c.onBrand),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 20.w),
          AppTextField(
            controller: _first,
            label: 'First name',
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            errorText:
                _first.text.trim().isEmpty ? 'Add your first name.' : null,
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 14.w),
          AppTextField(
            controller: _last,
            label: 'Last name',
            optional: true,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
          ),
          SizedBox(height: 14.w),
          AppTextField(
            controller: _email,
            label: 'Email',
            optional: true,
            hint: 'For receipts',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            errorText: _emailError,
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 14.w),
          AppTextField(
            controller: TextEditingController(
                text: NigerianPhone.display(
                    _user.phone.replaceFirst('+234', ''))),
            label: 'Phone number',
            readOnly: true,
            enabled: false,
            helperText:
                'To change your number, contact us from the Help centre.',
          ),
          // Your area: the area pill sets the same value, which never leaves the
          // phone, so it went (2026-10-23: never ask for what isn't needed).
          // SizedBox(height: 14.w),
          // Text('Your area', style: AppText.labelSmall),
          // SizedBox(height: 6.w),
          // Pressable(
          //   onTap: () async {
          //     final session = context.read<SessionController>();
          //     final picked =
          //         await showAreaPicker(context, current: session.area);
          //     if (picked != null) await session.setArea(picked);
          //   },
          //   semanticLabel: 'Area, ${area ?? 'all of Abuja'}. Change',
          //   child: Container(
          //     height: AppSize.input,
          //     padding: EdgeInsets.symmetric(horizontal: 14.w),
          //     decoration: BoxDecoration(
          //         color: c.surfaceMuted,
          //         borderRadius: AppRadius.mdAll,
          //         border: Border.all(color: c.inputBorder)),
          //     child: Row(
          //       children: [
          //         Icon(IconsaxPlusBold.location,
          //             size: 18.w, color: c.brandText),
          //         SizedBox(width: 10.w),
          //         Expanded(
          //             child: Text(area ?? 'All of Abuja',
          //                 style: AppText.bodyLarge)),
          //         Icon(IconsaxPlusLinear.arrow_down,
          //             size: 16.w, color: c.textSecondary),
          //       ],
          //     ),
          //   ),
          // ),
          if (_artisan) ...[
            SizedBox(height: 24.w),
            Text('About you', style: AppText.title),
            SizedBox(height: 4.w),
            Text('Clients read this on your profile.',
                style: AppText.bodySmall.copyWith(color: c.textSecondary)),
            SizedBox(height: 12.w),
            AppTextField(
              controller: _about,
              label: 'Your work in a few lines',
              hint: 'What you do, what you bring, how you work',
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 8,
              helperText: '${_about.text.length}/500',
              onChanged: (v) {
                if (v.length > 500) _about.text = v.substring(0, 500);
                setState(() {});
              },
            ),
            SizedBox(height: 14.w),
            AppTextField(
              controller: _years,
              label: 'Years of experience',
              keyboardType: TextInputType.number,
              hint: 'For example, 6',
            ),
            // Business name and free-text certificates went (2026-10-23): nobody
            // checks the certificates, yet clients would read them as credentials,
            // and a business name isn't needed to book. Saved values are kept.
            // SizedBox(height: 14.w),
            // AppTextField(
            //   controller: _business,
            //   label: 'Business name',
            //   optional: true,
            //   hint: 'For example, Smart Hands Plumbing',
            //   textCapitalization: TextCapitalization.words,
            // ),
            // SizedBox(height: 18.w),
            // Text('Certificates', style: AppText.labelSmall),
            // SizedBox(height: 2.w),
            // Text('Trade certificates clients can trust, by name.',
            //     style: AppText.bodySmall.copyWith(color: c.textSecondary)),
            // SizedBox(height: 6.w),
            // Wrap(
            //   spacing: 8.w,
            //   children: [
            //     for (final cert in _certificates)
            //       InputChip(
            //         label: Text(cert, style: AppText.labelSmall),
            //         onDeleted: () => setState(() => _certificates.remove(cert)),
            //         deleteButtonTooltipMessage: 'Remove $cert',
            //         backgroundColor: c.surfaceMuted,
            //         side: BorderSide.none,
            //         shape:
            //             RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
            //       ),
            //     PromptChip(
            //       label: 'Add a certificate',
            //       icon: IconsaxPlusLinear.add,
            //       onTap: _addCertificate,
            //     ),
            //   ],
            // ),
          ],
        ],
      ),
    );
  }
}

// Photos used to start with a camera-or-library sheet. Each place now goes
// straight to the likelier one and keeps the other one tap away
// (2026-10-23, fewer taps). Kept for if a chooser is ever wanted again.
//
// Future<bool?> _photoSource(BuildContext context) => showModalBottomSheet<bool>(
//       context: context,
//       useRootNavigator: true,
//       showDragHandle: true,
//       backgroundColor: context.colors.surface,
//       builder: (context) => SafeArea(
//         child: Padding(
//           padding: EdgeInsets.fromLTRB(
//               AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               SelectionCard(
//                 icon: IconsaxPlusLinear.camera,
//                 title: 'Take a photo',
//                 subtitle: 'Use the camera',
//                 selected: false,
//                 onTap: () => Navigator.of(context).pop(true),
//               ),
//               SizedBox(height: 8.w),
//               SelectionCard(
//                 icon: IconsaxPlusLinear.gallery,
//                 title: 'Choose a photo',
//                 subtitle: 'From your photos',
//                 selected: false,
//                 onTap: () => Navigator.of(context).pop(false),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//
// /// Where a photo comes from: true for the camera.
// Future<bool?> pickPhotoSource(BuildContext context) => _photoSource(context);

// ---------------------------------------------------------------- saved

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final area = context.read<SessionController>().area;
    return PageScaffold(
      title: 'Saved artisans',
      body: Loader<List<Artisan>>(
        load: () => context.read<DirectoryRepository>().saved(area: area),
        builder: (context, list, reload) => list.isEmpty
            ? Center(
                child: EmptyState(
                  icon: IconsaxPlusLinear.heart,
                  title: 'No one saved yet',
                  message:
                      'Tap the heart on an artisan to keep them here for next time.',
                  action: AppButton(
                      label: 'Explore artisans',
                      expand: false,
                      onPressed: () => context.go(Routes.explore)),
                ),
              )
            : ListView(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                children: [
                  for (final (i, a) in list.indexed)
                    ArtisanRow(
                      artisan: a,
                      hasArea: area != null,
                      divider: i < list.length - 1,
                      onTap: () => context.push(Routes.artisan(a.id)),
                      trailing: AppIconButton(
                        icon: IconsaxPlusBold.heart,
                        iconColor: context.colors.brand,
                        semanticLabel: 'Remove ${a.firstName} from saved',
                        onPressed: () async {
                          await context
                              .read<DirectoryRepository>()
                              .toggleSaved(a.id);
                          await reload();
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- my jobs

class MyJobsScreen extends StatelessWidget {
  const MyJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Your jobs and quotes',
      actions: [
        AppButton(
          label: 'Post a job',
          variant: AppButtonVariant.tertiary,
          size: AppButtonSize.small,
          expand: false,
          onPressed: () => context.push(Routes.postJob),
        ),
      ],
      body: Loader<List<ClientJob>>(
        load: () => context.read<ClientJobRepository>().mine(),
        builder: (context, jobs, reload) => jobs.isEmpty
            ? Center(
                child: EmptyState(
                  icon: IconsaxPlusLinear.receipt_2,
                  title: 'No jobs yet',
                  message:
                      'Post a job and artisans near you send quotes. Compare, then pick one.',
                  action: AppButton(
                      label: 'Post a job',
                      expand: false,
                      onPressed: () => context.push(Routes.postJob)),
                ),
              )
            : ListView(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                children: [
                  for (final (i, j) in jobs.indexed)
                    ClientJobRow(
                      job: j,
                      divider: i < jobs.length - 1,
                      onTap: () async {
                        await context.push(Routes.clientJob(j.id));
                        await reload();
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- places

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  /// With no places yet, the page opens on adding one, the first time.
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    return Loader<List<SavedPlace>>(
      load: () => context.read<AccountRepository>().places(),
      loading: const PageScaffold(title: 'Places', body: ListSkeleton()),
      builder: (context, places, reload) {
        Future<void> add() async {
          final saved = await _editPlace(context, null);
          if (saved) await reload();
        }

        if (places.isEmpty && !_opened) {
          _opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) add();
          });
        }
        return _places(context, places, reload, add);
      },
    );
  }

  Widget _places(BuildContext context, List<SavedPlace> places,
          Future<void> Function() reload, Future<void> Function() add) =>
      PageScaffold(
        title: 'Places',
        subtitle: 'Book faster at the addresses you use',
        bottom: AppButton(
          label: 'Add a place',
          variant: AppButtonVariant.secondary,
          leading: const Icon(IconsaxPlusLinear.location_add),
          onPressed: add,
        ),
        body: places.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: IconsaxPlusLinear.location,
                  title: 'No places yet',
                  message:
                      'Add your home or office once, and pick it in one tap when you book.',
                ),
              )
            : ListView(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                children: [
                  for (final p in places)
                    Pressable(
                      onTap: () async {
                        if (await _editPlace(context, p)) await reload();
                      },
                      pressedScale: 0.99,
                      focusOffset: 0,
                      semanticLabel:
                          '${p.label}, ${p.address}, ${p.area}. Edit',
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 14.w),
                        decoration: BoxDecoration(
                            border: Border(
                                bottom:
                                    BorderSide(color: context.colors.border))),
                        child: Row(
                          children: [
                            Container(
                              width: 44.w,
                              height: 44.w,
                              decoration: BoxDecoration(
                                  color: context.colors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(14.w)),
                              child: Icon(
                                p.label == 'Home'
                                    ? IconsaxPlusLinear.home_2
                                    : p.label == 'Office'
                                        ? IconsaxPlusLinear.briefcase
                                        : IconsaxPlusLinear.location,
                                size: 20.w,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.label, style: AppText.titleSmall),
                                  Text('${p.address}, ${p.area}',
                                      style: AppText.bodySmall.copyWith(
                                          color: context.colors.textSecondary)),
                                ],
                              ),
                            ),
                            Icon(IconsaxPlusLinear.edit_2,
                                size: 18.w, color: context.colors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      );

  /// Adds or edits a place; true when something was saved or deleted.
  static Future<bool> _editPlace(
      BuildContext context, SavedPlace? place) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _PlaceSheet(place: place),
    );
    return result ?? false;
  }
}

class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({this.place});

  final SavedPlace? place;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  late String _label = widget.place?.label ?? 'Home';
  late String? _area =
      widget.place?.area ?? context.read<SessionController>().area;
  late final _address =
      TextEditingController(text: widget.place?.address ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_area == null || _address.text.trim().length < 4) return;
    setState(() => _saving = true);
    final repo = context.read<AccountRepository>();
    await runAction(
        context,
        () => repo.savePlace(SavedPlace(
              id: widget.place?.id ??
                  'p_${DateTime.now().millisecondsSinceEpoch}',
              label: _label,
              area: _area!,
              address: _address.text.trim(),
            )));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DoubleTapGuard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter,
            AppSpace.gutter + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.place == null ? 'Add a place' : 'Edit place',
                style: AppText.headline),
            SizedBox(height: 14.w),
            Wrap(
              spacing: 8.w,
              children: [
                for (final l in const ['Home', 'Office', 'Other'])
                  PromptChip(
                      label: l,
                      selected: _label == l,
                      onTap: () => setState(() => _label = l)),
              ],
            ),
            SizedBox(height: 12.w),
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
                    border: Border.all(color: c.inputBorder)),
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
            SizedBox(height: 12.w),
            AppTextField(
              controller: _address,
              label: 'Street, house and a landmark',
              hint: '12 Aminu Kano Crescent, near Banex Plaza',
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 18.w),
            AppButton(
              label: 'Save place',
              isLoading: _saving,
              onPressed:
                  _area == null || _address.text.trim().length < 4 || _saving
                      ? null
                      : _save,
            ),
            if (widget.place != null)
              AppButton(
                label: 'Delete place',
                variant: AppButtonVariant.tertiary,
                onPressed: () async {
                  await context
                      .read<AccountRepository>()
                      .deletePlace(widget.place!.id);
                  if (context.mounted) Navigator.of(context).pop(true);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- payments

/// What a client has paid, what RijHub is holding, and every receipt.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: 'Payments and receipts',
      body: Loader<(WalletSummary, List<WalletTx>)>(
        load: () async {
          final w = context.read<WalletRepository>();
          final r = await Future.wait<Object>([w.summary(), w.transactions()]);
          return (r[0] as WalletSummary, r[1] as List<WalletTx>);
        },
        builder: (context, data, reload) {
          final (summary, tx) = data;
          final shown = switch (_tab) {
            1 => tx.where((t) => t.status == TxStatus.pending).toList(),
            2 => tx.where((t) => t.status != TxStatus.pending).toList(),
            _ => tx,
          };
          return RefreshIndicator(
            color: c.brandStroke,
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, 4.w, AppSpace.gutter, 24.w),
              children: [
                Container(
                  padding: EdgeInsets.all(18.w),
                  decoration: BoxDecoration(
                      color: c.surfaceStrong,
                      borderRadius: BorderRadius.circular(22.w)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Held safely now',
                                style: AppText.bodySmall.copyWith(
                                    color: c.onSurfaceStrong
                                        .withValues(alpha: 0.7))),
                            SizedBox(height: 4.w),
                            Text(Naira.format(summary.held),
                                style: AppText.display.copyWith(
                                    color: c.onSurfaceStrong,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 4.w),
                            Text('Released when you confirm a job is done',
                                style: AppText.caption.copyWith(
                                    color: c.onSurfaceStrong
                                        .withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Paid in total',
                              style: AppText.caption.copyWith(
                                  color: c.onSurfaceStrong
                                      .withValues(alpha: 0.6))),
                          Text(Naira.format(summary.paidTotal),
                              style: AppText.titleSmall
                                  .copyWith(color: c.onSurfaceStrong)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18.w),
                SegmentedTabs(
                    labels: const ['All', 'Pending', 'Completed'],
                    selected: _tab,
                    onChanged: (i) => setState(() => _tab = i)),
                SizedBox(height: 6.w),
                if (shown.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 40.w),
                    child: const EmptyState(
                        icon: IconsaxPlusLinear.receipt_2,
                        title: 'Nothing here',
                        message: 'Your payments and refunds show here.'),
                  ),
                for (final t in shown) TxRow(tx: t),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A payment, refund, earning or payout as a row; tapping shows the
/// receipt.
class TxRow extends StatelessWidget {
  const TxRow({super.key, required this.tx});

  final WalletTx tx;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, label) = switch (tx.kind) {
      TxKind.payment => (IconsaxPlusLinear.card, 'Payment'),
      TxKind.refund => (IconsaxPlusLinear.refresh, 'Refund'),
      TxKind.earning => (IconsaxPlusLinear.money_recive, 'Earning'),
      TxKind.payout => (IconsaxPlusLinear.money_send, 'Payout'),
    };
    final (statusLabel, tone) = switch (tx.status) {
      TxStatus.pending => (
          tx.kind == TxKind.payment ? 'Held' : 'Pending',
          TagTone.warning
        ),
      TxStatus.successful => ('Done', TagTone.success),
      TxStatus.failed => ('Failed', TagTone.neutral),
    };
    return Pressable(
      onTap: () => _receipt(context, label, statusLabel),
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '$label, ${tx.title}, ${Naira.format(tx.amount)}, $statusLabel',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.w),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(14.w)),
              child: Icon(icon, size: 20.w),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelSmall),
                  SizedBox(height: 2.w),
                  Text('${Schedule.dayLabel(tx.at)} · $label',
                      style: AppText.caption.copyWith(color: c.textTertiary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${tx.isIn ? '+' : '−'}${Naira.format(tx.amount)}',
                  style: AppText.labelSmall
                      .copyWith(color: tx.isIn ? c.success : c.textPrimary),
                ),
                // Done is the norm; only the exceptions get a tag.
                if (tx.status != TxStatus.successful) ...[
                  SizedBox(height: 4.w),
                  StatusTag(label: statusLabel, tone: tone),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _receipt(BuildContext context, String label, String status) {
    final c = context.colors;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, 0, AppSpace.gutter, AppSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tx.isIn ? '+' : '−'}${Naira.format(tx.amount)}',
                  style: AppText.display.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: 4.w),
              Text(tx.title,
                  style: AppText.body.copyWith(color: c.textSecondary)),
              SizedBox(height: 16.w),
              InfoLine(label: 'Type', value: label),
              InfoLine(label: 'Status', value: status),
              InfoLine(label: 'Date', value: Schedule.dayAndTime(tx.at)),
              if (tx.reference != null)
                InfoLine(label: 'Reference', value: tx.reference!),
              SizedBox(height: 16.w),
              AppButton(
                  label: 'Done',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- settings

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = context.watch<SessionController>();
    const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    return PageScaffold(
      title: 'Settings',
      body: ListView(
        padding: EdgeInsets.only(top: 4.w, bottom: 24.w),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance',
                    style: AppText.labelSmall.copyWith(color: c.textSecondary)),
                SizedBox(height: 8.w),
                SegmentedTabs(
                  labels: const ['Auto', 'Light', 'Dark'],
                  selected: modes.indexOf(session.themeMode),
                  onChanged: (i) => session.setThemeMode(modes[i]),
                ),
                SizedBox(height: 6.w),
                Text('Auto follows your phone.',
                    style: AppText.caption.copyWith(color: c.textTertiary)),
                SizedBox(height: 20.w),
              ],
            ),
          ),
          SettingsGroup(
            children: [
              if (session.isSignedIn)
                SettingsRow(
                    icon: IconsaxPlusLinear.notification,
                    label: 'Notifications',
                    onTap: () => context.push(Routes.notificationSettings)),
              SettingsRow(
                  icon: IconsaxPlusLinear.information,
                  label: 'About Employi',
                  onTap: () => context.push(Routes.about)),
              SettingsRow(
                  icon: IconsaxPlusLinear.document_text,
                  label: 'Terms of use',
                  onTap: () => context.push(Routes.terms)),
              SettingsRow(
                  icon: IconsaxPlusLinear.security_user,
                  label: 'Privacy policy',
                  onTap: () => context.push(Routes.privacy)),
            ],
          ),
          if (session.isSignedIn)
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: IconsaxPlusLinear.trash,
                  label: 'Delete account',
                  danger: true,
                  onTap: () => context.push(Routes.deleteAccount),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// What RijHub is and how it keeps people safe.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'About Employi',
        body: ListView(
          padding: EdgeInsets.only(top: 8.w, bottom: 24.w),
          children: const [_About()],
        ),
      );
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget point(IconData icon, String title, String body) => Padding(
          padding: EdgeInsets.only(bottom: 14.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                    color: c.brandSubtle,
                    borderRadius: BorderRadius.circular(12.w)),
                child: Icon(icon, size: 20.w, color: c.brandText),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.titleSmall),
                    SizedBox(height: 2.w),
                    Text(body,
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RijHubLogo(height: 32),
          SizedBox(height: 12.w),
          Text(
            'Employi connects people in Abuja with skilled, ID-checked artisans: AC technicians, electricians, plumbers, '
            'generator and solar technicians, cleaners and more. Our mission is simple: getting things fixed should be '
            'easy, fair and safe, for clients and for the artisans who do the work.',
            style: AppText.body,
          ),
          SizedBox(height: 20.w),
          point(IconsaxPlusLinear.verify, 'Trust through verification',
              'Artisans match their NIN to a live selfie before they can be booked.'),
          point(IconsaxPlusLinear.shield_tick, 'Your money, held safely',
              'You pay when you book; the artisan is paid when you say the job is done.'),
          point(IconsaxPlusLinear.radar_2, 'The right person, nearby',
              'We match you with top-rated artisans near you, with prices up front.'),
          point(IconsaxPlusLinear.messages_2, 'Easy to work together',
              'Chat, photos, voice notes and calls in one place.'),
          SizedBox(height: 4.w),
          Text('Your craft. Your needs. Our platform.',
              style: AppText.labelSmall.copyWith(color: c.textSecondary)),
          SizedBox(height: 4.w),
          Text('Version 2.0.0',
              style: AppText.caption.copyWith(color: c.textTertiary)),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Notifications',
      subtitle: 'Choose what we tell you about',
      body: Loader<NotificationPrefs>(
        load: () => context.read<NoticeRepository>().prefs(),
        builder: (context, prefs, reload) => _PrefsList(initial: prefs),
      ),
    );
  }
}

class _PrefsList extends StatefulWidget {
  const _PrefsList({required this.initial});

  final NotificationPrefs initial;

  @override
  State<_PrefsList> createState() => _PrefsListState();
}

class _PrefsListState extends State<_PrefsList> {
  late NotificationPrefs _p = widget.initial;

  void _set(NotificationPrefs p) {
    setState(() => _p = p);
    context.read<NoticeRepository>().savePrefs(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(IconData icon, String label, String sub, bool on,
            ValueChanged<bool> change) =>
        SettingsRow(
          icon: icon,
          label: label,
          subtitle: sub,
          trailing: Switch.adaptive(
              value: on, activeTrackColor: c.success, onChanged: change),
        );
    return ListView(
      padding: EdgeInsets.only(top: 8.w),
      children: [
        SettingsGroup(
          children: [
            row(
                IconsaxPlusLinear.calendar_tick,
                'Bookings',
                'Confirmed, on the way, done',
                _p.bookings,
                (v) => _set(_p.copyWith(bookings: v))),
            row(
                IconsaxPlusLinear.message,
                'Messages',
                'When someone writes to you',
                _p.messages,
                (v) => _set(_p.copyWith(messages: v))),
            row(
                IconsaxPlusLinear.receipt_2,
                'Quotes and requests',
                'New quotes, new jobs for you',
                _p.quotes,
                (v) => _set(_p.copyWith(quotes: v))),
            row(
                IconsaxPlusLinear.wallet_2,
                'Payments',
                'Held, released, refunded, paid out',
                _p.payments,
                (v) => _set(_p.copyWith(payments: v))),
            row(
                IconsaxPlusLinear.notification,
                'Tips and offers',
                'Now and then, never spam',
                _p.tips,
                (v) => _set(_p.copyWith(tips: v))),
          ],
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Text(
            'We always tell you about payments that need you, whatever you choose here.',
            style: AppText.bodySmall.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- delete

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  // String? _reason; // see the note above the build's last section
  bool _busy = false;

  Future<void> _delete() async {
    final ok = await confirmSheet(
      context,
      title: 'Delete your account for good?',
      message:
          'This can\'t be undone. Bookings in progress are cancelled and refunded.',
      confirm: 'Delete my account',
      cancel: 'Keep my account',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final session = context.read<SessionController>();
    final app = appContext(context);
    final done = await runAction(context, () async {
      await context.read<AccountRepository>().deleteAccount();
      return true;
    });
    if (done != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await session.signOut();
    if (!app.mounted) return;
    app.go(Routes.home);
    showToast(app, 'Your account has been deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bullet(String text) => Padding(
          padding: EdgeInsets.only(bottom: 8.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(IconsaxPlusLinear.minus_cirlce,
                  size: 18.w, color: c.textSecondary),
              SizedBox(width: 10.w),
              Expanded(child: Text(text, style: AppText.body)),
            ],
          ),
        );
    return PageScaffold(
      title: 'Delete account',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
              label: 'Delete my account',
              isLoading: _busy,
              onPressed: _busy ? null : _delete),
          AppButton(
              label: 'Keep my account',
              variant: AppButtonVariant.tertiary,
              onPressed: () => goBack(context)),
        ],
      ),
      body: ListView(
        padding:
            EdgeInsets.fromLTRB(AppSpace.gutter, 8.w, AppSpace.gutter, 24.w),
        children: [
          Text('We\'re sorry to see you go', style: AppText.headline),
          SizedBox(height: 8.w),
          Text('Deleting your account removes:',
              style: AppText.body.copyWith(color: c.textSecondary)),
          SizedBox(height: 12.w),
          bullet('Your profile, photo and phone number'),
          bullet('Your saved artisans and places'),
          bullet('Your messages and booking history'),
          bullet('Money waiting in your wallet: send it to your bank first'),
          SizedBox(height: 8.w),
          Text(
            'Receipts we must keep by law stay on our systems, without your name.',
            style: AppText.bodySmall.copyWith(color: c.textSecondary),
          ),
          // A reason to leave was asked for but never sent, so it went
          // (2026-10-23: never collect what isn't used).
          // SizedBox(height: 24.w),
          // Text('Why are you leaving? (optional)', style: AppText.labelSmall),
          // SizedBox(height: 8.w),
          // Wrap(
          //   spacing: 8.w,
          //   children: [
          //     for (final r in const [
          //       'I don\'t need it now',
          //       'Too expensive',
          //       'Had a bad experience',
          //       'Privacy worries',
          //       'Something else'
          //     ])
          //       PromptChip(
          //           label: r,
          //           selected: _reason == r,
          //           onTap: () => setState(() => _reason = r)),
          //   ],
          // ),
        ],
      ),
    );
  }
}
