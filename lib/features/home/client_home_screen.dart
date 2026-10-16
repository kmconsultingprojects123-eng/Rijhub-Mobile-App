import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../location/area_picker_sheet.dart';
import '../location/area_pill.dart';
import 'widgets/client_artisan_row.dart';
import 'widgets/client_booking_card.dart';
import 'widgets/client_filter_chips.dart';
import 'widgets/client_home_rows.dart';
import 'widgets/client_price_guide.dart';
import 'widgets/client_search_bar.dart';

/// RijHub is live in Abuja. Until someone picks a neighbourhood, results
/// cover the whole city.
const _city = AreaPill.city;

/// Artisans listed on Home. "See all" has the rest.
const _listLength = 5;

/// One row of the list: an artisan, and the last time the client hired
/// them, if they have.
typedef _Entry = ({Artisan artisan, HiredArtisan? hired});

/// The client's Home tab. The first screen is the people who can fix
/// things, best rated first, with what makes them trustworthy (rating,
/// jobs done, verified) and what makes them useful now (free now, how
/// near, how fast they reply). Search and filters sit above them; prices
/// and the payment promise below. Guests see all of it; an account is only
/// asked for when they post a job, book or choose to sign in.
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  late final SessionController _session;
  late final _Section<List<Booking>> _bookings;
  late final _Section<List<HiredArtisan>> _hired;
  late final _Section<List<ServiceCategory>> _categories;
  late final _Section<List<Artisan>> _artisans;
  late final _Section<List<PriceGuideItem>> _prices;
  late final Listenable _changes;
  final _refresher = GlobalKey<RefreshIndicatorState>();

  /// The list's filters: one trade (null for all) and "Free now".
  String? _categoryId;
  bool _freeNow = false;

  /// Who and where the sections last loaded for. Home stays alive behind
  /// the other tabs, so signing in or out, or picking an area, over there
  /// must reload what depends on them.
  String? _loadedUserId;
  String? _loadedArea;

  /// The list's area or filters changed since Home was last on screen, so
  /// screen readers are told what it shows once it loads.
  bool _listChanged = false;

  @override
  void initState() {
    super.initState();
    _session = context.read<SessionController>();
    final bookings = context.read<BookingRepository>();
    final catalog = context.read<CatalogRepository>();
    final artisans = context.read<ArtisanRepository>();

    _bookings = _Section(() => bookings.upcoming(as: UserRole.client));
    _hired = _Section(artisans.hiredBefore);
    _categories = _Section(catalog.categories);
    _artisans = _Section(
      () => artisans.topRatedNearby(
        area: _session.area ?? _city,
        categoryId: _categoryId,
        freeNow: _freeNow,
        // One spare, so a past hire at the top can be left out further
        // down without the list coming up short.
        limit: _listLength + 1,
      ),
    );
    _prices = _Section(catalog.priceGuide);
    _changes = Listenable.merge(
      [_bookings, _hired, _categories, _artisans, _prices],
    );
    _loadedUserId = _session.user?.id;
    _loadedArea = _session.area;
    _session.addListener(_onSessionChanged);
    unawaited(_loadAll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab or page covers Home, which leaves the semantics tree. The
    // news has been told, and must not be told again on coming back.
    if (!TickerMode.of(context)) _listChanged = false;
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _bookings.dispose();
    _hired.dispose();
    _categories.dispose();
    _artisans.dispose();
    _prices.dispose();
    super.dispose();
  }

  /// The sections on screen. Guests have no bookings or past hires.
  List<_Section<Object>> get _shown => [
        if (_session.isSignedIn) ...[_bookings, _hired],
        _categories,
        _artisans,
        _prices,
      ];

  Future<void> _loadAll() =>
      Future.wait([for (final section in _shown) section.load()]);

  void _onSessionChanged() {
    final userId = _session.user?.id;
    if (userId != _loadedUserId) {
      _loadedUserId = userId;
      // Never show one person's bookings or hires to the next.
      _bookings.clear();
      _hired.clear();
      if (userId != null) {
        unawaited(_bookings.load());
        unawaited(_hired.load());
      }
    }
    final area = _session.area;
    if (area != _loadedArea) {
      _loadedArea = area;
      _reloadList();
    }
  }

  /// The old list would sit under the new area or filters, so show the
  /// skeleton until the new one arrives.
  void _reloadList() {
    _listChanged = true;
    _artisans.clear();
    unawaited(_artisans.load());
  }

  void _setCategory(String? categoryId) {
    if (categoryId == _categoryId) return;
    setState(() => _categoryId = categoryId);
    _reloadList();
  }

  void _setFreeNow(bool freeNow) {
    setState(() => _freeNow = freeNow);
    _reloadList();
  }

  /// A price row shows who does that job: its trade's chip turns on, and
  /// the page goes back up to the list.
  void _showTradeFor(PriceGuideItem item) {
    _setCategory(item.categoryId);
    // The page scrolls with the route's primary controller, which is also
    // what iOS scrolls up when the status bar is tapped.
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll == null || !scroll.hasClients) return;
    final duration = context.motion(AppMotion.slow);
    if (duration == Duration.zero) {
      scroll.jumpTo(0);
    } else {
      unawaited(
        scroll.animateTo(0, duration: duration, curve: AppMotion.standard),
      );
    }
  }

  Future<void> _refresh() async {
    await _loadAll();
    if (!mounted) return;
    // A section that fails to reload keeps what it showed, so say that it
    // may be out of date, with a way to retry that needs no gesture.
    if (_shown.any((section) => section.value.isStale)) {
      _showNote(
        context,
        "We couldn't refresh everything.",
        action: SnackBarAction(
          label: 'Try again',
          onPressed: () => _refresher.currentState?.show(),
        ),
      );
    }
  }

  /// Whether [artisan] belongs in the list with the filters as they are.
  bool _fits(Artisan artisan) =>
      (_categoryId == null || artisan.categoryId == _categoryId) &&
      (!_freeNow || artisan.isAvailableToday);

  /// The list's rows, once it has loaded (and, for a signed-in client,
  /// their past hires too, so the list doesn't shift when they arrive).
  /// The latest past hire that fits the filters leads, and isn't repeated
  /// below.
  List<_Entry>? get _entries {
    final artisans = _artisans.value.data;
    if (artisans == null) return null;
    HiredArtisan? hired;
    if (_session.isSignedIn) {
      final pastHires = _hired.value;
      if (pastHires.data == null && pastHires.isLoading) return null;
      // A failed load only costs the shortcut; the list still shows.
      hired = pastHires.data?.where((h) => _fits(h.artisan)).firstOrNull;
    }
    final hiredId = hired?.artisan.id;
    final entries = <_Entry>[
      if (hired != null)
        (
          // As listed for this area, so distances and "Free now" are
          // current; else as last hired.
          artisan: artisans.where((a) => a.id == hiredId).firstOrNull ??
              hired.artisan,
          hired: hired,
        ),
      for (final artisan in artisans)
        if (artisan.id != hiredId) (artisan: artisan, hired: null),
    ];
    return entries.take(_listLength).toList();
  }

  ServiceCategory? get _category => _categoryId == null
      ? null
      : _categories.value.data?.where((c) => c.id == _categoryId).firstOrNull;

  /// Who the list is of, in a sentence: "AC technicians", or "artisans".
  String get _who {
    final plural = _category?.artisanPlural;
    return plural == null ? 'artisans' : TextCase.midSentence(plural);
  }

  /// What an empty list says, and the one step most likely to fill it
  /// (posting a job is the row below). [where] is "near you" or "in
  /// Abuja".
  ({String title, String message, String? action, VoidCallback? onAction})
      _emptyNote(String where, {required bool nearby}) {
    if (_freeNow) {
      return (
        title: 'No $_who free right now',
        message:
            "Turn off Free now, or post your job and we'll find\u00A0someone.",
        action: 'Turn off Free now',
        onAction: () => _setFreeNow(false),
      );
    }
    return (
      title: 'No $_who listed $where yet',
      message: nearby
          ? "Try another area, or post your job and we'll find\u00A0someone."
          : "Post your job and we'll find someone for\u00A0you.",
      action: nearby
          ? 'Change area'
          : _categoryId != null
              ? 'Show all trades'
              : null,
      onAction: nearby
          ? _pickArea
          : _categoryId != null
              ? () => _setCategory(null)
              : null,
    );
  }

  Future<void> _pickArea() async {
    final area = await showAreaPicker(context, current: _session.area);
    if (area != null) await _session.setArea(area);
  }

  /// What the list shows, told to screen readers once a new area's or new
  /// filters' results are in, since the list changes away from their
  /// focus. Null until then, and while loading or failed (an error says so
  /// itself).
  String? _listSummary(String? area, List<_Entry>? entries) {
    if (!_listChanged || entries == null) return null;
    final where = area == null ? 'in $_city' : 'near $area';
    if (entries.isEmpty) return _emptyNote(where, nearby: area != null).title;
    final count = entries.length;
    final category = _category;
    if (category == null && !_freeNow) {
      return 'Showing $count top-rated '
          '${count == 1 ? 'artisan' : 'artisans'} $where';
    }
    return [
      'Showing $count ${count == 1 ? 'artisan' : 'artisans'}',
      if (category != null) 'for ${TextCase.midSentence(category.name)}',
      if (_freeNow) 'free now',
      where,
    ].join(' ');
  }

  void _openExplore() => context.go(Routes.explore);

  /// The header's "Sign in", which new people use too.
  Future<void> _signIn() =>
      context.read<AuthGate>().ensureSignedIn(context, AuthPrompt.join);

  Future<void> _postJob() async {
    final signedIn = await context
        .read<AuthGate>()
        .ensureSignedIn(context, AuthPrompt.postJob);
    if (!signedIn || !mounted) return;
    _showNote(context, 'Posting a job is next in the redesign.');
  }

  Future<void> _bookAgain(Artisan artisan) async {
    final signedIn = await context
        .read<AuthGate>()
        .ensureSignedIn(context, AuthPrompt.book(artisan.name));
    if (!signedIn || !mounted) return;
    _showNote(
      context,
      'Booking ${artisan.firstName} again is next in the redesign.',
    );
  }

  void _openArtisan(Artisan artisan) =>
      _showNote(context, 'Artisan profiles are next in the redesign.');

  void _message(Booking booking) =>
      _showNote(context, 'Chat is next in the redesign.');

  /// Calls the artisan through the number the booking gives, which the
  /// backend relays, so neither side sees the other's own.
  Future<void> _call(Booking booking) async {
    final phone = booking.counterpartPhone;
    if (phone == null) {
      // Not the device's fault, so don't say it is.
      final name = booking.counterpartName.split(' ').first;
      _showNote(context, "There's no number to call $name on yet.");
      return;
    }
    var called = false;
    try {
      called = await launchUrl(Uri(scheme: 'tel', path: phone));
    } on Exception {
      // No phone app (a tablet, a simulator): said below.
    }
    if (!called && mounted) {
      _showNote(context, "Calls can't be made from this device.");
    }
  }

  /// Guests who came to work rather than hire: the artisan side.
  Future<void> _findWork() => _session.continueAsGuest(UserRole.artisan);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = context.select<SessionController, AppUser?>((s) => s.user);
    final area = context.select<SessionController, String?>((s) => s.area);
    // "Near you" and distances need a place to measure from. Without one,
    // results cover the city and rows say where each artisan is based.
    final nearby = area != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          key: _refresher,
          color: c.brandStroke,
          backgroundColor: c.surface,
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: _changes,
            builder: (context, _) {
              final entries = _entries;
              final noArtisans = entries?.isEmpty ?? false;
              final tradesFailed = _categories.value.data == null &&
                  !_categories.value.isLoading;
              final gutter = EdgeInsets.symmetric(horizontal: AppSpace.gutter);
              // A chip looks 32pt tall in its 48pt touch area, so the
              // gaps around the row are measured from what shows.
              final chipInset = (AppSize.minTapTarget - AppChip.height) / 2;
              return CustomScrollView(
                primary: true,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          signedIn: user != null,
                          onSignIn: _signIn,
                          onNotifications: () => _showNote(
                            context,
                            'Notifications are next in the redesign.',
                          ),
                        ),
                        _UpcomingBooking(
                          visible: user != null,
                          snapshot: _bookings.value,
                          onRetry: _bookings.load,
                          builder: (booking) => ClientBookingCard(
                            booking: booking,
                            onTap: () => context.go(Routes.bookings),
                            onMessage: () => _message(booking),
                            onCall: () => _call(booking),
                          ),
                        ),
                        SizedBox(height: AppSpace.s8),
                        Padding(
                          padding: gutter,
                          child: ClientSearchBar(
                            onTap: _openExplore,
                            onVoiceTap: () => _showNote(
                              context,
                              'Voice search is coming soon.',
                            ),
                          ),
                        ),
                        SizedBox(height: AppSpace.s12 - chipInset),
                        ClientFilterChips(
                          categories: _categories.value.data,
                          loading: _categories.value.isLoading,
                          categoryId: _categoryId,
                          freeNow: _freeNow,
                          onFreeNowChanged: _setFreeNow,
                          onCategoryChanged: _setCategory,
                        ),
                        // The trades didn't load: "Free now" and "All"
                        // still work, and this says what's missing.
                        if (tradesFailed) ...[
                          SizedBox(height: AppSpace.s12 - chipInset),
                          Padding(
                            padding: gutter,
                            child: InlineError(
                              message: "We couldn't load services.",
                              onRetry: _categories.load,
                            ),
                          ),
                        ],
                        // The gaps sit in the column with the title, so
                        // "See all" takes taps in its 48pt band around the
                        // row; padding around the title alone would cut
                        // the band back to the row. The band reaches 12
                        // past the 24pt row on each side, hence 12 (not 8)
                        // down to the list.
                        Padding(
                          padding: gutter,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: tradesFailed
                                    ? AppSpace.s20
                                    : AppSpace.s20 - chipInset,
                              ),
                              SectionHeader(
                                title: nearby
                                    ? 'Top-rated near you'
                                    : 'Top-rated in $_city',
                                actionLabel: noArtisans ? null : 'See all',
                                onAction: _openExplore,
                              ),
                              SizedBox(height: AppSpace.s12),
                            ],
                          ),
                        ),
                        _LiveSummary(
                          summary: _listSummary(area, entries),
                          child: _list(entries, nearby: nearby),
                        ),
                        SizedBox(height: AppSpace.s16),
                        Padding(
                          padding: gutter,
                          child: ClientPostJobRow(onTap: _postJob),
                        ),
                        // No guide yet: no section, rather than a title
                        // over nothing.
                        if (_prices.value.data?.isNotEmpty ?? true) ...[
                          SizedBox(height: AppSpace.s24),
                          Padding(
                            padding: gutter,
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Typical prices in $_city',
                                style: AppText.title.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          _SectionBody<List<PriceGuideItem>>(
                            snapshot: _prices.value,
                            skeleton: const ClientPriceGuideSkeleton(),
                            errorMessage: "We couldn't load prices.",
                            errorPadding: EdgeInsets.fromLTRB(
                              AppSpace.gutter,
                              AppSpace.s8,
                              AppSpace.gutter,
                              0,
                            ),
                            onRetry: _prices.load,
                            builder: (items) => ClientPriceGuide(
                              items: items,
                              onTap: _showTradeFor,
                              tradeNames: {
                                for (final category
                                    in _categories.value.data ?? const [])
                                  if (category.artisanPlural != null)
                                    category.id: TextCase.midSentence(
                                      category.artisanPlural!,
                                    ),
                              },
                            ),
                          ),
                        ],
                        SizedBox(height: AppSpace.s24),
                        Padding(
                          padding: gutter,
                          child: const ClientTrustStrip(),
                        ),
                        if (user == null) ...[
                          SizedBox(height: AppSpace.s12),
                          ClientRoleLink(onTap: _findWork),
                        ],
                        SizedBox(height: AppSpace.s24),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The artisans, their skeleton while they load, an error with a retry,
  /// or a note when nobody fits.
  Widget _list(List<_Entry>? entries, {required bool nearby}) {
    final gutter = EdgeInsets.symmetric(horizontal: AppSpace.gutter);
    if (entries == null) {
      final snapshot = _artisans.value;
      if (snapshot.error != null && !snapshot.isLoading) {
        return Padding(
          padding: gutter,
          child: InlineError(
            message: "We couldn't load artisans.",
            onRetry: _artisans.load,
          ),
        );
      }
      return SkeletonPulse(
        child: Column(
          children: [
            for (var i = 0; i < _listLength; i++)
              ClientArtisanRowSkeleton(divider: i < _listLength - 1),
          ],
        ),
      );
    }
    if (entries.isEmpty) {
      final note = _emptyNote(
        nearby ? 'near you' : 'in $_city',
        nearby: nearby,
      );
      // Never a dead end: the note's own step, and posting a job right
      // below.
      return Padding(
        padding: gutter,
        child: ClientEmptyNote(
          title: note.title,
          message: note.message,
          actionLabel: note.action,
          onAction: note.onAction,
        ),
      );
    }
    return Column(
      children: [
        for (final (i, entry) in entries.indexed)
          ClientArtisanRow(
            artisan: entry.artisan,
            hired: entry.hired,
            showDistance: nearby,
            divider: i < entries.length - 1,
            onTap: () => _openArtisan(entry.artisan),
            onBookAgain: () => _bookAgain(entry.artisan),
          ),
      ],
    );
  }
}

/// The top row: the area results are for, and a way to sign in (or
/// notifications, once signed in).
class _Header extends StatelessWidget {
  const _Header({
    required this.signedIn,
    required this.onSignIn,
    required this.onNotifications,
  });

  final bool signedIn;
  final VoidCallback onSignIn;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    // Both trailing controls pad their touch areas past what they show;
    // these line what shows up with the gutter.
    final reach = signedIn ? 13.0 : 14.0;
    return SizedBox(
      height: math.max(AppSize.minTapTarget, 48.w),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: AppSpace.gutter,
          end: math.max(0, AppSpace.gutter - reach),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AreaPill(),
              ),
            ),
            SizedBox(width: AppSpace.s12),
            if (signedIn)
              AppIconButton(
                icon: IconsaxPlusLinear.notification,
                // Off until notifications exist: a dot that never clears
                // means nothing. Drive it from their unread count then.
                // showBadge: true,
                semanticLabel: 'Notifications',
                onPressed: onNotifications,
              )
            else
              // A quiet link: guests are welcome as they are.
              AppButton(
                label: 'Sign in',
                variant: AppButtonVariant.tertiary,
                size: AppButtonSize.small,
                expand: false,
                onPressed: onSignIn,
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a short message, replacing any that is already showing.
void _showNote(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        // Like Android's own: one with an action waits for screen reader
        // users to reach it, and goes after a few seconds for everyone
        // else rather than following them to other tabs.
        persist: action != null && MediaQuery.accessibleNavigationOf(context),
      ),
    );
}

/// What one section has to show.
@immutable
class _Snapshot<T> {
  const _Snapshot({this.data, this.error, this.isLoading = false});

  /// The last data that loaded. Kept while reloading and after a failed
  /// reload, so a refresh never blanks what the client was looking at.
  final T? data;
  final Object? error;
  final bool isLoading;

  /// A reload failed, so [data] may be out of date.
  bool get isStale => data != null && error != null;
}

/// Loads one part of the screen on its own, so one failure never blanks the
/// rest. Only the latest request's result is kept.
class _Section<T> extends ValueNotifier<_Snapshot<T>> {
  _Section(this._fetch) : super(_Snapshot<T>(isLoading: true));

  final Future<T> Function() _fetch;
  int _request = 0;
  bool _disposed = false;

  Future<void> load() async {
    final request = ++_request;
    if (!value.isLoading) {
      value = _Snapshot(data: value.data, isLoading: true);
    }
    try {
      final data = await _fetch();
      if (_disposed || request != _request) return;
      value = _Snapshot(data: data);
    } catch (error, stackTrace) {
      // A bug rather than a failed request: report it, but still offer a
      // retry instead of loading forever.
      if (error is Error) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      }
      if (_disposed || request != _request) return;
      value = _Snapshot(data: value.data, error: error);
    }
  }

  /// Forgets what loaded and drops any request in flight, until the next
  /// [load].
  void clear() {
    _request++;
    value = _Snapshot<T>(isLoading: true);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A section's content once it has data, its skeleton while it first loads,
/// or a short error with a retry.
class _SectionBody<T> extends StatelessWidget {
  const _SectionBody({
    required this.snapshot,
    required this.skeleton,
    required this.errorMessage,
    required this.onRetry,
    required this.builder,
    this.errorPadding = EdgeInsets.zero,
  });

  final _Snapshot<T> snapshot;
  final Widget skeleton;
  final String errorMessage;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final EdgeInsetsGeometry errorPadding;

  @override
  Widget build(BuildContext context) {
    final data = snapshot.data;
    if (data != null) return builder(data);
    if (snapshot.isLoading) return SkeletonPulse(child: skeleton);
    return Padding(
      padding: errorPadding,
      child: InlineError(message: errorMessage, onRetry: onRetry),
    );
  }
}

/// The next booking, for signed-in clients who have one, 8pt under the
/// header. Guests and people with nothing booked see nothing here rather
/// than an empty card.
class _UpcomingBooking extends StatelessWidget {
  const _UpcomingBooking({
    required this.visible,
    required this.snapshot,
    required this.onRetry,
    required this.builder,
  });

  final bool visible;
  final _Snapshot<List<Booking>> snapshot;
  final VoidCallback onRetry;
  final Widget Function(Booking booking) builder;

  @override
  Widget build(BuildContext context) {
    final nothingBooked = snapshot.data?.isEmpty ?? false;
    final child = !visible || nothingBooked
        ? const SizedBox(width: double.infinity)
        : Padding(
            // With the 8 above the search, 12 between card and search.
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.s8,
              AppSpace.gutter,
              AppSpace.s4,
            ),
            child: _SectionBody<List<Booking>>(
              snapshot: snapshot,
              skeleton: const ClientBookingCardSkeleton(),
              errorMessage: "We couldn't load your bookings.",
              onRetry: onRetry,
              builder: (bookings) => builder(bookings.first),
            ),
          );
    // AnimatedSize fails without a duration, so with reduced motion the
    // card just appears and goes.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// Gives screen readers [summary] of [child]: announced politely when it
/// appears or changes, and read before [child]. Silent while it is null.
class _LiveSummary extends StatelessWidget {
  const _LiveSummary({required this.summary, required this.child});

  final String? summary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: summary != null,
      label: summary,
      child: child,
    );
  }
}
