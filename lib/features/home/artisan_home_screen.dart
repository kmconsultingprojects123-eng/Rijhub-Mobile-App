import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import 'widgets/artisan_availability_sheet.dart';
import 'widgets/artisan_format.dart';
import 'widgets/artisan_home_rows.dart';
import 'widgets/artisan_job_row.dart';
import 'widgets/artisan_job_sheet.dart';
import 'widgets/artisan_request_card.dart';
import 'widgets/artisan_section_label.dart';
import 'widgets/artisan_today_card.dart';
import 'widgets/artisan_top_bar.dart';
import 'widgets/artisan_trade_chips.dart';

/// RijHub is live in Abuja. Until someone picks a neighbourhood, jobs come
/// from the whole city.
const _city = 'Abuja';

/// Space between sections, and from a section's label to its content.
double get _sectionGap => AppSpace.s24;
double get _labelGap => AppSpace.s8;

/// Home for artisans. Work comes first: guests see open jobs and how much
/// work there is; signed-in artisans see today's jobs, clients waiting for
/// an answer and new jobs in their trades, with their availability and
/// earnings as two pills at the top.
class ArtisanHomeScreen extends StatelessWidget {
  const ArtisanHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select<SessionController, AppUser?>((s) => s.user);
    final area = context.select<SessionController, String?>((s) => s.area);
    // Home stays alive behind the other tabs. Signing in turns the guest
    // view into the dashboard by itself, and a new person starts afresh, so
    // nothing loaded for the old one is shown under the new. A new area
    // reloads only what depends on it.
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.base),
      child: user == null
          ? _GuestHome(key: const ValueKey('guest'), area: area)
          : _Dashboard(key: ValueKey(user.id), user: user, area: area),
    );
  }
}

/// What an artisan sees before signing in: open jobs near them and how
/// much work there is, with one invitation to quote on them for free.
class _GuestHome extends StatefulWidget {
  const _GuestHome({super.key, required this.area});

  /// The neighbourhood jobs are for, or null for the whole city.
  final String? area;

  @override
  State<_GuestHome> createState() => _GuestHomeState();
}

class _GuestHomeState extends State<_GuestHome>
    with _Clock<_GuestHome>, _JobFeed<_GuestHome> {
  /// How much work there is, for each filter that has been shown.
  final _demand = <ArtisanJobFilter, _Load<JobDemand>>{};
  final _demandRequests = <ArtisanJobFilter, int>{};

  @override
  String? get area => widget.area;

  @override
  int get jobsShown => 10;

  @override
  Set<String> get myTrades => const {};

  @override
  void initState() {
    super.initState();
    filter = ArtisanJobFilter.all;
    loadTrades();
    loadJobs(filter);
    _loadDemand(filter);
  }

  @override
  void didUpdateWidget(_GuestHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.area == oldWidget.area) return;
    // The old area's jobs and numbers would sit under the new one, so
    // skeletons show until the new ones arrive.
    forgetJobs();
    _forgetDemand();
    loadJobs(filter);
    _loadDemand(filter);
  }

  Future<Object?> _loadDemand(ArtisanJobFilter which) async {
    final request = (_demandRequests[which] ?? 0) + 1;
    _demandRequests[which] = request;
    final repository = context.read<JobRepository>();
    final result = await _fetch(
      () => repository.demand(area: place, categoryId: which.tradeId),
    );
    if (!mounted || _demandRequests[which] != request) return null;
    // A failed refresh keeps the numbers already showing.
    if (result is _Failed && _demand[which] is _Ready) return null;
    setState(() => _demand[which] = result);
    return null;
  }

  void _forgetDemand() {
    for (final key in _demand.keys) {
      _demandRequests[key] = (_demandRequests[key] ?? 0) + 1;
    }
    _demand.clear();
  }

  void _select(ArtisanJobFilter which) {
    selectFilter(which);
    if (_demand[which] is! _Ready) _loadDemand(which);
  }

  @override
  void retryFailed() {
    super.retryFailed();
    if (_demand[filter] is! _Failed) return;
    setState(() => _demand.remove(filter));
    _loadDemand(filter);
  }

  Future<void> _refresh() {
    _demand.removeWhere((key, _) => key != filter);
    return _refreshSections(
      context,
      [loadTrades(), refreshJobs(), _loadDemand(filter)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gate = context.read<AuthGate>();
    final demand = switch (_demand[filter]) {
      _Ready(value: final demand) => demand,
      _ => null,
    };

    return _HomeScaffold(
      onRefresh: _refresh,
      children: [
        ArtisanGuestTopBar(
          onSignIn: () => gate.ensureSignedIn(context, AuthPrompt.signIn),
        ),
        SizedBox(height: AppSpace.s8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Jobs near you',
                  style: AppText.headline.copyWith(color: c.textPrimary),
                ),
              ),
              SizedBox(height: AppSpace.s4),
              _DemandLines(
                state: _demand[filter],
                place: place,
                nearby: nearby,
                trade: tradeFor(filter),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpace.s4),
        _TradesRow(
          state: chipTrades,
          selected: filter,
          showMyTrades: false,
          onSelected: _select,
          onRetry: retryFailed,
          foldError: jobs[filter] is _Failed,
        ),
        jobsList(
          weekCount: demand?.openThisWeek,
          invitation: ArtisanJoinRow(
            onJoin: () =>
                gate.ensureSignedIn(context, AuthPrompt.joinAsArtisan),
          ),
        ),
        SizedBox(height: AppSpace.s16),
        const ArtisanTrustLine(),
        SizedBox(height: AppSpace.s32),
      ],
    );
  }
}

/// How much work there is, in two steady lines under the title: how many
/// jobs this week, then what most budgets are. Two lines whichever trade is
/// chosen, so the chips below never move under a finger.
class _DemandLines extends StatelessWidget {
  const _DemandLines({
    required this.state,
    required this.place,
    required this.nearby,
    required this.trade,
  });

  final _Load<JobDemand>? state;
  final String place;
  final bool nearby;
  final ServiceCategory? trade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppText.bodySmall.copyWith(color: c.textSecondary);
    // Text rounds each line's height up to a whole point.
    final lineHeight =
        (MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height!)
            .ceilToDouble();
    final demand = switch (state) {
      _Ready(value: final demand) => demand,
      _ => null,
    };

    final where = '${nearby ? 'near' : 'in'} $place';
    final Widget lines;
    if (state is _Failed) {
      // Without the count, still say what the list is, so the space
      // reads as meant; pulling down or any "Try again" counts again.
      lines = Text(
        trade == null
            ? 'Open jobs $where, newest first'
            : 'Open ${TextCase.midSentence(trade!.name)} jobs $where, '
                'newest first',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    } else if (demand == null) {
      lines = SkeletonPulse(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final width in [200.0, 150.0])
              SizedBox(
                height: lineHeight,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SkeletonBox(
                    width: width * lineHeight / 18,
                    height: lineHeight * 0.55,
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      final count = demand.openThisWeek;
      final jobs = count == 1 ? 'job' : 'jobs';
      final first = trade == null
          ? '$count open $jobs $where this week'
          : '$count ${TextCase.midSentence(trade!.name)} $jobs this week';
      final min = demand.typicalBudgetMin;
      final max = demand.typicalBudgetMax;
      final second = min == null || max == null
          ? null
          : 'Most budgets ${ArtisanFormat.budget(min, max)}';
      lines = Semantics(
        label: [
          first,
          if (min != null && max != null)
            'Most budgets ${Naira.format(min)} to ${Naira.format(max)}',
        ].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (second != null) Text(second, maxLines: 1, style: style),
          ],
        ),
      );
    }
    return SizedBox(
      height: lineHeight * 2,
      child: Align(alignment: AlignmentDirectional.topStart, child: lines),
    );
  }
}

/// A signed-in artisan's Home: the work first (today's jobs, clients
/// waiting for an answer, new jobs in their trades), under a top bar with
/// their availability and the week's earnings; then the week in one row
/// and the next setup step.
class _Dashboard extends StatefulWidget {
  const _Dashboard({super.key, required this.user, required this.area});

  final AppUser user;

  /// The neighbourhood jobs are for, or null for the whole city.
  final String? area;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard>
    with _Clock<_Dashboard>, _JobFeed<_Dashboard> {
  /// Where the choice to hide earnings is kept on this device.
  static const _hideEarningsKey = 'dashboard.hideEarnings';

  _Load<ArtisanDashboard> _dashboard = const _Loading();
  _Load<List<Booking>> _upcoming = const _Loading();
  _Load<List<DirectRequest>> _requests = const _Loading();

  /// How many jobs there are this week for each filter shown, for "See
  /// all". Missing until counted.
  final _counts = <ArtisanJobFilter, int>{};

  /// Today's demand in the artisan's main trade, for the availability
  /// sheet. Null until it loads, or if it fails.
  JobDemand? _todayDemand;

  /// Whether earnings show as dots. Null until it is read from the device;
  /// the wallet stays a skeleton until then, so amounts never flash up.
  bool? _hideEarnings;

  /// Requests whose answer is on its way.
  final _answering = <String, RequestAnswer>{};

  // The latest request for each section. A reply to an older one, sent
  // before a retry, a refresh or a change of area, is dropped.
  int _dashboardRequest = 0;
  int _upcomingRequest = 0;
  int _requestsRequest = 0;
  int _countRequest = 0;
  int _demandRequest = 0;

  /// Availability as the server last confirmed it, for undoing a failed
  /// save.
  ArtisanAvailability? _savedAvailability;

  /// Whether availability is being saved. Saves go one at a time.
  bool _savingAvailability = false;

  /// Counts changes of availability, so a dashboard requested before one
  /// can't undo it when it arrives.
  int _availabilityChanges = 0;

  @override
  String? get area => widget.area;

  @override
  int get jobsShown => 6;

  @override
  Set<String> get myTrades => widget.user.tradeIds.toSet();

  @override
  void initState() {
    super.initState();
    // A session saved before trades were stored has none: every trade,
    // until the next sign-in brings them.
    filter =
        myTrades.isEmpty ? ArtisanJobFilter.all : ArtisanJobFilter.myTrades;
    _loadHideEarnings();
    _loadDashboard();
    _loadUpcoming();
    _loadRequests();
    loadTrades();
    loadJobs(filter);
    _loadCount(filter);
    _loadTodayDemand();
  }

  @override
  void didUpdateWidget(_Dashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.area == oldWidget.area) return;
    // Jobs, their counts and distances depend on the area.
    forgetJobs();
    _counts.clear();
    _countRequest++;
    loadJobs(filter);
    _loadCount(filter);
    _loadTodayDemand();
  }

  @override
  void onTick() {
    // A request that has run out of time can no longer be answered, and a
    // busy spell that has ended is over: the server has moved on too.
    if (_requests case _Ready(value: final requests)) {
      final open = [
        for (final request in requests)
          if (request.expiresAt.isAfter(now)) request,
      ];
      if (open.length != requests.length) _requests = _Ready(open);
    }
    if (_dashboard case _Ready(value: final dashboard)) {
      final until = dashboard.busyUntil;
      if (until != null && !until.isAfter(now)) {
        _dashboard = _Ready(dashboard.withAvailability(true));
        _savedAvailability = (available: true, busyUntil: null);
      }
    }
  }

  Future<void> _loadHideEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Anything but a saved true shows them, even a value left by another
    // version of the app.
    setState(() => _hideEarnings = prefs.get(_hideEarningsKey) == true);
  }

  /// Hides or shows earnings, and remembers the choice on this device.
  Future<void> _toggleEarnings() async {
    final hide = !(_hideEarnings ?? false);
    HapticFeedback.selectionClick();
    setState(() => _hideEarnings = hide);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideEarningsKey, hide);
  }

  // Each loader returns the error of a refresh that failed while older
  // content was on screen. That content stays, and the refresh mentions it.

  Future<Object?> _loadDashboard() async {
    final request = ++_dashboardRequest;
    final repository = context.read<ArtisanDashboardRepository>();
    final changesBefore = _availabilityChanges;
    final savingBefore = _savingAvailability;
    final result = await _fetch(repository.dashboard);
    if (!mounted || request != _dashboardRequest) return null;
    if (result case _Failed(:final error) when _dashboard is _Ready) {
      return error;
    }
    if (result case _Ready(value: final dashboard)) {
      final shown = _shownAvailability;
      final overlapsChange = savingBefore ||
          _savingAvailability ||
          changesBefore != _availabilityChanges;
      if (shown != null && overlapsChange) {
        // This request overlapped a change of availability, so its own
        // may be out of date. Availability stays as the artisan set it.
        setState(() {
          _dashboard = _Ready(
            dashboard.withAvailability(
              shown.available,
              busyUntil: shown.busyUntil,
            ),
          );
        });
      } else {
        _savedAvailability = (
          available: dashboard.isAvailable,
          busyUntil: dashboard.busyUntil,
        );
        setState(() => _dashboard = result);
      }
      return null;
    }
    setState(() => _dashboard = result);
    return null;
  }

  Future<Object?> _loadUpcoming() async {
    final request = ++_upcomingRequest;
    final repository = context.read<BookingRepository>();
    final result = await _fetch(
      () => repository.upcoming(as: UserRole.artisan),
    );
    if (!mounted || request != _upcomingRequest) return null;
    if (result case _Failed(:final error) when _upcoming is _Ready) {
      return error;
    }
    setState(() => _upcoming = result);
    return null;
  }

  Future<Object?> _loadRequests() async {
    final request = ++_requestsRequest;
    final repository = context.read<ArtisanDashboardRepository>();
    final result = await _fetch(repository.requests);
    if (!mounted || request != _requestsRequest) return null;
    if (result case _Failed(:final error) when _requests is _Ready) {
      return error;
    }
    setState(() => _requests = result);
    return null;
  }

  /// Counts this week's jobs for [which], adding up the artisan's trades
  /// for "My trades". A failure leaves "See all" without a number.
  Future<Object?> _loadCount(ArtisanJobFilter which) async {
    final request = ++_countRequest;
    final repository = context.read<JobRepository>();
    final ids = which.isMine ? myTrades.toList() : [which.tradeId];
    try {
      final counts = await Future.wait([
        for (final id in ids)
          repository.openJobsThisWeek(area: place, categoryId: id),
      ]);
      if (!mounted || request != _countRequest) return null;
      setState(() => _counts[which] = counts.fold(0, (sum, n) => sum + n));
    } on Object catch (error, stackTrace) {
      _reportBug(error, stackTrace);
    }
    return null;
  }

  Future<Object?> _loadTodayDemand() async {
    final request = ++_demandRequest;
    final repository = context.read<JobRepository>();
    try {
      final demand = await repository.demand(
        area: place,
        categoryId: widget.user.tradeIds.firstOrNull,
      );
      if (!mounted || request != _demandRequest) return null;
      setState(() => _todayDemand = demand);
    } on Object catch (error, stackTrace) {
      // The sheet works without it.
      _reportBug(error, stackTrace);
    }
    return null;
  }

  Future<void> _refresh() => _refreshSections(context, [
        _loadDashboard(),
        _loadUpcoming(),
        _loadRequests(),
        refreshJobs(),
        _loadCount(filter),
        _loadTodayDemand(),
      ]);

  @override
  void retryFailed() {
    super.retryFailed();
    final dashboard = _dashboard is _Failed;
    final upcoming = _upcoming is _Failed;
    final requests = _requests is _Failed;
    if (!dashboard && !upcoming && !requests) return;
    setState(() {
      if (dashboard) _dashboard = const _Loading();
      if (upcoming) _upcoming = const _Loading();
      if (requests) _requests = const _Loading();
    });
    if (dashboard) _loadDashboard();
    if (upcoming) _loadUpcoming();
    if (requests) _loadRequests();
  }

  void _select(ArtisanJobFilter which) {
    selectFilter(which);
    if (!_counts.containsKey(which)) _loadCount(which);
  }

  // Availability.

  /// Availability as shown, or null while the dashboard isn't on screen.
  ArtisanAvailability? get _shownAvailability => switch (_dashboard) {
        _Ready(value: final dashboard) => (
            available: dashboard.isAvailable,
            busyUntil: dashboard.busyUntil,
          ),
        _ => null,
      };

  /// Shows [availability]. False when there is no dashboard to show it on.
  bool _showAvailability(ArtisanAvailability availability) {
    if (_dashboard case _Ready(value: final dashboard)) {
      setState(() {
        _dashboard = _Ready(
          dashboard.withAvailability(
            availability.available,
            busyUntil: availability.busyUntil,
          ),
        );
      });
      return true;
    }
    return false;
  }

  /// Shows the choice at once, then saves. Saves go one at a time until
  /// the server matches what shows, so quick changes end where the artisan
  /// left them. If a save fails, availability goes back to what the server
  /// last confirmed.
  Future<void> _setAvailability(ArtisanAvailability wanted) async {
    if (!_showAvailability(wanted)) return;
    _availabilityChanges++;
    // A save already running sends this one once it finishes.
    if (_savingAvailability) return;
    _savingAvailability = true;
    final repository = context.read<ArtisanDashboardRepository>();
    try {
      var next = _shownAvailability;
      while (mounted && next != null && next != _savedAvailability) {
        await repository.setAvailability(
          next.available,
          busyUntil: next.busyUntil,
        );
        _savedAvailability = next;
        next = _shownAvailability;
      }
    } on Object catch (error, stackTrace) {
      _reportBug(error, stackTrace);
      if (!mounted) return;
      if (_savedAvailability case final saved?) _showAvailability(saved);
      _showMessage(
        _messageFor(error, "We couldn't update your availability. Try again."),
      );
    } finally {
      _savingAvailability = false;
    }
  }

  Future<void> _openAvailability(ArtisanDashboard dashboard) async {
    final choice = await showArtisanAvailabilitySheet(
      context,
      status: dashboard.availability,
      busyUntil: dashboard.busyUntil,
      demand: _demandLine(),
      blockingStep: _blockingStep(dashboard),
      onStartSetup: _startSetup,
    );
    if (choice == null || !mounted) return;
    _setAvailability(choice);
  }

  /// "5 AC repair jobs posted today near Wuse 2".
  String? _demandLine() {
    final demand = _todayDemand;
    if (demand == null) return null;
    final tradeId = widget.user.tradeIds.firstOrNull;
    final trade = tradeId == null ? null : tradeOf(tradeId);
    final kind = trade == null ? '' : '${TextCase.midSentence(trade.name)} ';
    final where = nearby ? 'near $place' : 'in $place';
    final count = demand.postedToday;
    if (count == 0) return 'No new ${kind}jobs $where yet today';
    return '$count $kind${count == 1 ? 'job' : 'jobs'} posted today $where';
  }

  // Requests.

  Future<void> _answer(DirectRequest request, {required bool accept}) async {
    if (_answering.containsKey(request.id)) return;
    final repository = context.read<ArtisanDashboardRepository>();
    final messenger = ScaffoldMessenger.of(context);
    // Turning one down takes it away at once; accepting waits for the
    // booking, so "Booked" is never said too early.
    final removed = accept ? null : _takeRequest(request.id);
    setState(() {
      _answering[request.id] =
          accept ? RequestAnswer.accepting : RequestAnswer.declining;
    });
    try {
      final booking = await repository.respond(request.id, accept: accept);
      if (!mounted) return;
      setState(() => _answering.remove(request.id));
      _takeRequest(request.id);
      if (!accept) return;
      if (booking == null) {
        _say(messenger, 'This request was already answered.');
        return;
      }
      HapticFeedback.mediumImpact();
      _say(messenger, "Booked. It's in your schedule.");
      _loadUpcoming();
    } on RequestExpiredException catch (error) {
      if (!mounted) return;
      setState(() => _answering.remove(request.id));
      _takeRequest(request.id);
      _say(messenger, error.message);
    } on Object catch (error, stackTrace) {
      _reportBug(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _answering.remove(request.id);
        if (removed case (final index, final request)) {
          _putRequestBack(index, request);
        }
      });
      _say(
        messenger,
        _messageFor(error, "We couldn't send your answer. Try again."),
      );
    }
  }

  /// Takes request [id] off the list, returning where it was.
  (int, DirectRequest)? _takeRequest(String id) {
    if (_requests case _Ready(value: final requests)) {
      final index = requests.indexWhere((r) => r.id == id);
      if (index < 0) return null;
      final request = requests[index];
      setState(() => _requests = _Ready([...requests]..removeAt(index)));
      return (index, request);
    }
    return null;
  }

  void _putRequestBack(int index, DirectRequest request) {
    if (_requests case _Ready(value: final requests)) {
      final at = index.clamp(0, requests.length);
      _requests = _Ready([...requests]..insert(at, request));
    }
  }

  // Bookings.

  Future<void> _call(Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = booking.counterpartPhone;
    var started = false;
    if (phone != null) {
      try {
        started = await launchUrl(Uri(scheme: 'tel', path: phone));
      } on Object {
        started = false;
      }
    }
    if (started) return;
    final shown = phone == null
        ? null
        : NigerianPhone.display(NigerianPhone.normalize(phone));
    _say(
      messenger,
      shown == null
          ? "We couldn't start the call. Try from your schedule."
          : "We couldn't start the call. Dial $shown.",
    );
  }

  void _startSetup() => _showMessage('ID checks are next in the redesign.');

  void _showMessage(String message) =>
      _say(ScaffoldMessenger.of(context), message);

  /// The step that stops clients booking the artisan, while it's undone.
  static SetupStep? _blockingStep(ArtisanDashboard dashboard) =>
      dashboard.setupSteps
          .where((step) => step.blocksBookings && !step.done)
          .firstOrNull;

  /// Whether the artisan has worked through RijHub, so an empty day or
  /// week is worth saying.
  static bool _hasHistory(ArtisanDashboard dashboard) =>
      dashboard.earnedToDate > 0 ||
      dashboard.reviewCount > 0 ||
      dashboard.jobsThisWeek > 0;

  @override
  Widget build(BuildContext context) {
    final dashboard = switch (_dashboard) {
      _Ready(value: final dashboard) => dashboard,
      _ => null,
    };
    // When the connection drops, every part fails at once. Then one error,
    // at the first part that failed, says what didn't load, and the other
    // failed parts fold away; its "Try again" reloads them all.
    final failed = _failedParts;
    final shared = failed.length > 1 ? _sharedFailure(failed) : null;
    final folded = shared == null ? const <_Part>{} : failed.skip(1).toSet();
    // The sections that show, in order, each built with the space above
    // it: the first sits closer to the top bar than the rest to each other.
    final sections = <Widget Function(double gap)>[
      if (_noticeSection(shared) case final notice?) notice,
      if (!folded.contains(_Part.today))
        if (_todaySection(dashboard, shared) case final today?) today,
      (gap) => _requestsSection(
            gap,
            folded: folded.contains(_Part.requests),
            shared: shared,
          ),
      if (!folded.contains(_Part.jobs)) _jobsSection,
    ];

    return _HomeScaffold(
      onRefresh: _refresh,
      children: [
        _topBar(dashboard),
        for (final (i, section) in sections.indexed)
          section(i == 0 ? AppSpace.s4 : _sectionGap),
        if (dashboard != null) ..._footer(dashboard),
        SizedBox(height: AppSpace.s32),
      ],
    );
  }

  /// The parts that failed to load, in the order they show.
  List<_Part> get _failedParts => [
        if (_dashboard is _Failed) _Part.dashboard,
        if (_upcoming is _Failed) _Part.today,
        if (_requests is _Failed) _Part.requests,
        if (jobs[filter] is _Failed || trades is _Failed) _Part.jobs,
      ];

  /// One message for several parts that failed: what didn't load, or a
  /// message written for people that one of them carries.
  String _sharedFailure(List<_Part> failed) {
    final errors = [
      for (final load in <Object?>[_dashboard, _upcoming, _requests])
        if (load case _Failed(:final error)) error,
      if (jobs[filter] case _Failed(:final error)) error,
      if (trades case _Failed(:final error)) error,
    ];
    if (errors.whereType<AuthException>().firstOrNull case final error?) {
      return error.message;
    }
    if (failed.length == _Part.values.length) {
      return "We couldn't load your Home. Check your connection, then try "
          'again.';
    }
    final names = [
      for (final part in failed)
        switch (part) {
          _Part.dashboard => 'your availability',
          _Part.today => "today's schedule",
          _Part.requests => 'requests for you',
          _Part.jobs => 'new jobs',
        },
    ];
    final last = names.removeLast();
    return "We couldn't load ${names.join(', ')} or $last.";
  }

  Widget _topBar(ArtisanDashboard? dashboard) {
    final hidden = _hideEarnings;
    return ArtisanTopBar(
      availability: switch (_dashboard) {
        _Loading() => const SkeletonPulse(
            child: ArtisanPillSkeleton(width: 116),
          ),
        _Failed() => null,
        _Ready(value: final dashboard) => ArtisanAvailabilityPill(
            status: dashboard.availability,
            busyUntil: dashboard.busyUntil,
            onTap: () => _openAvailability(dashboard),
          ),
      },
      // Money stays out of sight until there is some.
      wallet: switch (_dashboard) {
        _Loading() => const SkeletonPulse(
            child: ArtisanPillSkeleton(width: 104),
          ),
        _Ready(value: final dashboard) when dashboard.earnedToDate > 0 =>
          hidden == null
              ? const SkeletonPulse(child: ArtisanPillSkeleton(width: 104))
              : ArtisanWalletPill(
                  amount: dashboard.earningsThisWeek,
                  hidden: hidden,
                  onToggle: _toggleEarnings,
                ),
        _ => null,
      },
      onNotifications: () =>
          _showMessage('Notifications are next in the redesign.'),
    );
  }

  /// A dashboard that failed to load (with [shared], the message for
  /// everything that failed), or the setup step that stops clients booking
  /// a new artisan.
  Widget Function(double gap)? _noticeSection(String? shared) {
    final Widget notice;
    switch (_dashboard) {
      case _Failed(:final error):
        notice = InlineError(
          message: shared ??
              _messageFor(
                error,
                "We couldn't load your availability and earnings.",
              ),
          onRetry: retryFailed,
        );
      case _Ready(value: final dashboard) when _blockingStep(dashboard) != null:
        notice = ArtisanSetupBanner(
          step: _blockingStep(dashboard)!,
          onStart: _startSetup,
        );
      default:
        return null;
    }
    return (gap) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            gap,
            AppSpace.gutter,
            0,
          ),
          child: notice,
        );
  }

  /// Today's bookings, or the next day's when they start within hours, as
  /// an agenda card. An artisan with no bookings and no history sees no
  /// section at all.
  Widget Function(double gap)? _todaySection(
    ArtisanDashboard? dashboard,
    String? shared,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    ArtisanSectionLabel label(DateTime day) {
      final isToday = day == today;
      final name = isToday ? 'Today' : 'Tomorrow';
      return ArtisanSectionLabel(
        text: '$name · ${DateFormat('EEE d MMM').format(day)}',
        semanticLabel: '$name, ${DateFormat('EEEE d MMMM').format(day)}',
        actionLabel: 'Schedule',
        actionSemanticLabel: 'Open your schedule',
        onAction: () => context.go(Routes.bookings),
      );
    }

    Widget section(double gap, DateTime day, Widget content) => Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: gap),
              label(day),
              SizedBox(height: _labelGap),
              _Grow(child: content),
            ],
          ),
        );

    switch (_upcoming) {
      case _Loading():
        return (gap) => section(
              gap,
              today,
              const SkeletonPulse(child: ArtisanTodayCardSkeleton()),
            );
      case _Failed(:final error):
        return (gap) => section(
              gap,
              today,
              InlineError(
                message: shared ??
                    _messageFor(error, "We couldn't load today's jobs."),
                onRetry: retryFailed,
              ),
            );
      case _Ready(value: final bookings):
        DateTime dayOf(Booking b) => DateTime(
              b.scheduledAt.year,
              b.scheduledAt.month,
              b.scheduledAt.day,
            );
        final todays = bookings.where((b) => dayOf(b) == today).toList();
        if (todays.isNotEmpty) {
          return (gap) => section(gap, today, _todayCard(todays));
        }
        // Late at night, the first job may be just after midnight.
        final first = bookings.firstOrNull;
        if (first != null &&
            first.scheduledAt.difference(now) < const Duration(hours: 12)) {
          final day = dayOf(first);
          final those = bookings.where((b) => dayOf(b) == day).toList();
          return (gap) => section(gap, day, _todayCard(those));
        }
        if (first == null && (dashboard == null || !_hasHistory(dashboard))) {
          return null;
        }
        return (gap) => section(gap, today, ArtisanNothingToday(next: first));
    }
  }

  Widget _todayCard(List<Booking> bookings) => ArtisanTodayCard(
        bookings: bookings,
        now: now,
        showDistance: nearby,
        onOpen: () => context.go(Routes.bookings),
        onMessage: (_) => context.go(Routes.messages),
        onCall: _call,
      );

  /// Clients who picked this artisan and are waiting for an answer. Folds
  /// away when there are none, and when it failed along with a part above
  /// whose error says so ([folded]).
  Widget _requestsSection(
    double gap, {
    required bool folded,
    required String? shared,
  }) {
    final open = switch (_requests) {
      _Ready(value: final requests) => [
          for (final request in requests)
            if (request.expiresAt.isAfter(now)) request,
        ],
      _ => const <DirectRequest>[],
    };
    // A booking already starting inside the time a client asks for, so
    // the artisan sees the clash before accepting.
    final booked = switch (_upcoming) {
      _Ready(value: final bookings) => [
          for (final booking in bookings) booking.scheduledAt,
        ],
      _ => const <DateTime>[],
    };
    DateTime? clashFor(DirectRequest request) => booked
        .where(
          (at) =>
              !at.isBefore(request.window.start) &&
              at.isBefore(request.window.end),
        )
        .firstOrNull;
    final Widget content;
    if (_requests case _Failed(:final error) when !folded) {
      content = Column(
        key: const ValueKey('failed'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: gap),
          const ArtisanSectionLabel(
            text: 'Requests for you',
            semanticLabel: 'Requests for you',
          ),
          SizedBox(height: _labelGap),
          InlineError(
            message:
                shared ?? _messageFor(error, "We couldn't check for requests."),
            onRetry: retryFailed,
          ),
        ],
      );
    } else if (open.isNotEmpty) {
      final count = open.length;
      content = Column(
        key: const ValueKey('requests'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: gap),
          ArtisanSectionLabel(
            text: 'Requests for you · $count',
            semanticLabel: count == 1
                ? 'Requests for you, 1 waiting'
                : 'Requests for you, $count waiting',
          ),
          SizedBox(height: _labelGap),
          for (final (i, request) in open.indexed) ...[
            if (i > 0) SizedBox(height: AppSpace.s8),
            ArtisanRequestCard(
              key: ValueKey(request.id),
              request: request,
              now: now,
              answering: _answering[request.id],
              clashesWith: clashFor(request),
              onAccept: () => _answer(request, accept: true),
              onDecline: () => _answer(request, accept: false),
            ),
          ],
        ],
      );
    } else {
      content = const SizedBox(key: ValueKey('none'), width: double.infinity);
    }
    return _CollapseSwitcher(
      child: Padding(
        key: content.key,
        padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        child: content,
      ),
    );
  }

  /// New jobs: the artisan's trades first, filtered by the chips.
  Widget _jobsSection(double gap) {
    final hasNoJobs = switch (jobs[filter]) {
      _Ready(value: final list) => list.isEmpty,
      _ => false,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          // The gap shares a parent with the header, so taps in it can
          // reach "See all": the chips start right under the title, so its
          // extra taps come from the space above.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: gap),
              ArtisanSectionHeader(
                title: 'New jobs for you',
                reachAbove: gap,
                actionLabel: hasNoJobs ? null : 'See all',
                onAction: () => context.go(Routes.explore),
              ),
            ],
          ),
        ),
        _TradesRow(
          state: chipTrades,
          selected: filter,
          showMyTrades: myTrades.isNotEmpty,
          onSelected: _select,
          onRetry: retryFailed,
          foldError: jobs[filter] is _Failed,
        ),
        jobsList(weekCount: _counts[filter]),
      ],
    );
  }

  /// The week in one row, then the next setup step: a short flat list
  /// below the work, set off from the jobs by a hairline.
  List<Widget> _footer(ArtisanDashboard dashboard) {
    final week = _hasHistory(dashboard);
    final next = dashboard.setupSteps
        .where((step) => !step.done && !step.blocksBookings)
        .firstOrNull;
    if (!week && next == null) return const [];
    return [
      SizedBox(height: AppSpace.s8),
      ArtisanRowDivider(indent: AppSpace.gutter),
      if (week)
        ArtisanWeekRow(
          dashboard: dashboard,
          onTap: () =>
              _showMessage('Earnings and stats are next in the redesign.'),
        ),
      if (week && next != null) const ArtisanRowDivider(),
      if (next != null)
        ArtisanSetupRow(
          step: next,
          done: dashboard.setupDone,
          total: dashboard.setupSteps.length,
          onTap: () => _showMessage('Profile setup is next in the redesign.'),
        ),
    ];
  }
}

/// The parts of a signed-in artisan's Home that load on their own, in the
/// order they show.
enum _Part { dashboard, today, requests, jobs }

/// Open jobs for the area, one list per filter, loaded when a filter is
/// first chosen and kept while the person flips between them.
mixin _JobFeed<T extends StatefulWidget> on State<T>, _Clock<T> {
  /// The neighbourhood jobs are for, or null for the whole city.
  String? get area;

  /// How many jobs Home lists; "See all" opens the rest.
  int get jobsShown;

  /// The signed-in artisan's trades; empty for guests.
  Set<String> get myTrades;

  /// The jobs showing.
  late ArtisanJobFilter filter;

  _Load<List<ServiceCategory>> trades = const _Loading();
  final jobs = <ArtisanJobFilter, _Load<List<JobPost>>>{};

  // The latest request for each list. A reply to an older one, sent
  // before a retry, a refresh or a change of area, is dropped.
  final _jobRequests = <ArtisanJobFilter, int>{};
  int _tradesRequest = 0;

  /// The filter whose jobs screen readers hear about once they load.
  ArtisanJobFilter? _announce;

  /// Jobs are for a neighbourhood, so "near" and distances mean something.
  bool get nearby => area != null;

  /// Where jobs are for: the neighbourhood, or the city.
  String get place => area ?? _city;

  Future<Object?> loadTrades() async {
    final request = ++_tradesRequest;
    final repository = context.read<CatalogRepository>();
    final result = await _fetch(repository.categories);
    if (!mounted || request != _tradesRequest) return null;
    if (result case _Failed(:final error) when trades is _Ready) return error;
    setState(() {
      trades = result;
      // A trade that is no longer listed stops filtering.
      final id = filter.tradeId;
      if (result case _Ready(value: final list)
          when id != null && !list.any((t) => t.id == id)) {
        filter =
            myTrades.isEmpty ? ArtisanJobFilter.all : ArtisanJobFilter.myTrades;
        if (jobs[filter] == null) loadJobs(filter);
      }
    });
    return null;
  }

  Future<Object?> loadJobs(ArtisanJobFilter which) async {
    final request = (_jobRequests[which] ?? 0) + 1;
    _jobRequests[which] = request;
    final repository = context.read<JobRepository>();
    final result = await _fetch(
      () => repository.openJobsNearby(
        area: place,
        categoryIds: _tradesFor(which),
        limit: jobsShown,
      ),
    );
    if (!mounted || _jobRequests[which] != request) return null;
    if (result case _Failed(:final error) when jobs[which] is _Ready) {
      return error;
    }
    setState(() => jobs[which] = result);
    if (_announce == which && which == filter) _announceJobs(which);
    return null;
  }

  Set<String>? _tradesFor(ArtisanJobFilter which) => which.isMine
      ? myTrades
      : switch (which.tradeId) {
          final id? => {id},
          null => null,
        };

  /// Shows [which]'s jobs, loading them the first time.
  void selectFilter(ArtisanJobFilter which) {
    if (which == filter) return;
    HapticFeedback.selectionClick();
    setState(() => filter = which);
    _announce = which;
    switch (jobs[which]) {
      case _Ready():
        _announceJobs(which);
      case _Loading():
        break;
      case _Failed() || null:
        setState(() => jobs[which] = const _Loading());
        loadJobs(which);
    }
  }

  /// Drops every list, as for a new area, so late replies are dropped too.
  void forgetJobs() {
    for (final key in jobs.keys) {
      _jobRequests[key] = (_jobRequests[key] ?? 0) + 1;
    }
    jobs.clear();
  }

  /// Reloads the jobs showing; other filters load afresh when chosen.
  Future<Object?> refreshJobs() {
    jobs.removeWhere((key, _) => key != filter);
    return loadJobs(filter);
  }

  /// Tries every part of Home that failed to load again, from any "Try
  /// again": when the connection drops they fail together, and one tap
  /// should bring them all back.
  @mustCallSuper
  void retryFailed() {
    final jobsFailed = jobs[filter] is _Failed;
    final tradesFailed = trades is _Failed;
    if (!jobsFailed && !tradesFailed) return;
    setState(() {
      if (jobsFailed) jobs[filter] = const _Loading();
      if (tradesFailed) trades = const _Loading();
    });
    if (jobsFailed) loadJobs(filter);
    if (tradesFailed) loadTrades();
  }

  /// The trade [id], once trades have loaded.
  ServiceCategory? tradeOf(String id) => switch (trades) {
        _Ready(value: final list) => list.where((t) => t.id == id).firstOrNull,
        _ => null,
      };

  /// The one trade [which] shows, if it shows one.
  ServiceCategory? tradeFor(ArtisanJobFilter which) =>
      which.tradeId == null ? null : tradeOf(which.tradeId!);

  /// Trades for the chips: the artisan's own first, in their account's
  /// order, then the rest as the catalog lists them.
  _Load<List<ServiceCategory>> get chipTrades => switch (trades) {
        _Ready(value: final list) when myTrades.isNotEmpty => _Ready([
            for (final id in myTrades) ...list.where((t) => t.id == id),
            ...list.where((t) => !myTrades.contains(t.id)),
          ]),
        final state => state,
      };

  /// The icon for jobs in [categoryId], through its trade's icon key once
  /// trades load. Until then the id itself is tried, and an unknown key
  /// gets a general icon.
  IconData iconFor(String categoryId) =>
      CategoryIcons.of(tradeOf(categoryId)?.iconKey ?? categoryId);

  /// The chosen filter's jobs as flat rows, then "See all", which counts
  /// [weekCount] jobs when known. An [invitation] (the guest's join row)
  /// sits after the first few jobs.
  Widget jobsList({required int? weekCount, Widget? invitation}) {
    const invitationAfter = 3;
    final gap = SizedBox(height: AppSpace.s8);
    return _SectionSwitcher(
      child: switch (jobs[filter]) {
        null || _Loading() => const _JobsSkeleton(key: ValueKey('loading')),
        _Failed(:final error) => _ListMessage(
            key: const ValueKey('failed'),
            child: InlineError(
              message: _messageFor(error, "We couldn't load jobs."),
              onRetry: retryFailed,
            ),
          ),
        _Ready(value: []) => _ListMessage(
            key: ValueKey(('empty', filter)),
            child: _noJobsNote(filter),
          ),
        // A different set of jobs, from a new trade or a refresh, fades in.
        _Ready(value: final list) => Column(
            key: ValueKey((filter, list.map((job) => job.id).join(','))),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, job) in list.indexed) ...[
                if (invitation != null && i == invitationAfter) ...[
                  gap,
                  invitation,
                  gap
                ] else if (i > 0)
                  const ArtisanRowDivider(),
                jobRow(job),
              ],
              // A short list still ends with the invitation.
              if (invitation != null && list.length <= invitationAfter) ...[
                gap,
                invitation,
              ],
              ArtisanSeeAllRow(
                label: _seeAllLabel(weekCount),
                onTap: () => context.go(Routes.explore),
              ),
            ],
          ),
      },
    );
  }

  /// "See all 126 jobs", "See all 46 AC repair jobs", or without a number
  /// until it is known.
  String _seeAllLabel(int? count) {
    final trade = tradeFor(filter);
    final kind = trade == null ? '' : '${TextCase.midSentence(trade.name)} ';
    if (count == null || count == 0) return 'See all ${kind}jobs';
    return 'See all $count $kind${count == 1 ? 'job' : 'jobs'}';
  }

  /// A job in the list; it opens the job sheet.
  Widget jobRow(JobPost job) => ArtisanJobRow(
        key: ValueKey(job.id),
        job: job,
        icon: iconFor(job.categoryId),
        showDistance: nearby,
        now: now,
        onTap: () => _openJob(job),
      );

  Future<void> _openJob(JobPost job) => showArtisanJobSheet(
        context,
        job: job,
        icon: iconFor(job.categoryId),
        tradeName: tradeOf(job.categoryId)?.name,
        showDistance: nearby,
        isGuest: context.read<SessionController>().isGuest,
        onSendQuote: _sendQuote,
      );

  /// Quoting needs an artisan account, so a guest is asked to sign in over
  /// the job sheet first. The sheet closes after; quoting itself comes
  /// next.
  Future<void> _sendQuote(BuildContext sheetContext) async {
    // Signing in swaps the guest view for the dashboard, so what's needed
    // afterwards is found before asking.
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<SessionController>();
    final gate = context.read<AuthGate>();
    final navigator = Navigator.of(sheetContext);
    final sheet = ModalRoute.of(sheetContext);
    final signedIn = await gate.ensureSignedIn(
      sheetContext,
      AuthPrompt.sendQuote,
    );
    if (!signedIn) return;
    if (sheet != null && sheet.isActive) {
      if (sheet.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(sheet);
      }
    }
    // A client's number signs in to the client side, which has nothing to
    // quote on.
    if (session.role == UserRole.artisan) {
      _say(messenger, 'Quoting is next in the redesign.');
    }
  }

  /// Says what the list now shows. It changes below the chips while focus
  /// stays on them, so screen reader users would otherwise not know.
  void _announceJobs(ArtisanJobFilter which) {
    _announce = null;
    if (jobs[which] case _Ready(value: final list)) {
      final trade = tradeFor(which);
      final kind = trade == null ? '' : '${TextCase.midSentence(trade.name)} ';
      final count = list.length;
      SemanticsService.sendAnnouncement(
        View.of(context),
        count == 0
            ? _noJobsTitle(which, trade)
            : '$count $kind${count == 1 ? 'job' : 'jobs'}',
        Directionality.of(context),
      );
    }
  }

  /// What an empty list says.
  Widget _noJobsNote(ArtisanJobFilter which) {
    final trade = tradeFor(which);
    // Never a dead end: say what happens next, and where else to look.
    return InlineNote(
      title: _noJobsTitle(which, trade),
      message: which.isMine
          ? 'New jobs in your trades show up here first. All has the rest.'
          : trade == null
              ? 'New jobs show up here as clients post them.'
              : 'New ones show up here as clients post them. All has other '
                  'trades.',
    );
  }

  String _noJobsTitle(ArtisanJobFilter which, ServiceCategory? trade) {
    final where = nearby ? 'nearby' : 'in $_city';
    if (which.isMine) return 'No new jobs in your trades $where right now';
    if (trade == null) return 'No new jobs $where right now';
    return 'No ${TextCase.midSentence(trade.name)} jobs $where right now';
  }
}

/// Keeps "12 min ago", countdowns and busy spells current: [now] moves on
/// every [_every], and [onTick] runs first. Behind another tab Home doesn't
/// tick (nothing there is seen), and it catches up as soon as it shows.
mixin _Clock<T extends StatefulWidget> on State<T> {
  static const _every = Duration(seconds: 20);

  DateTime now = DateTime.now();
  Timer? _timer;
  bool _onScreen = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_every, (_) {
      if (!mounted || !_onScreen) return;
      setState(_tick);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell turns tickers off for tabs that are out of sight. A build
    // follows, so catching up needs no setState.
    final onScreen = TickerMode.of(context);
    if (onScreen && !_onScreen) _tick();
    _onScreen = onScreen;
  }

  void _tick() {
    now = DateTime.now();
    onTick();
  }

  /// Called on every tick, inside setState or just before a build, after
  /// [now] moves on.
  void onTick() {}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The page both versions of Home share: one scrolling list under the
/// status bar that refreshes when pulled down.
class _HomeScaffold extends StatelessWidget {
  const _HomeScaffold({required this.onRefresh, required this.children});

  final RefreshCallback onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.brandStroke,
          backgroundColor: c.surface,
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverList.list(
                // Rows and cards group their own semantics. Indexed
                // semantics would merge each whole section into one node.
                addSemanticIndexes: false,
                // A repaint boundary would cut "See all" and "Schedule"
                // back to their rows.
                addRepaintBoundaries: false,
                children: children,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trades to filter jobs by, or their skeleton or error.
class _TradesRow extends StatelessWidget {
  const _TradesRow({
    required this.state,
    required this.selected,
    required this.showMyTrades,
    required this.onSelected,
    required this.onRetry,
    required this.foldError,
  });

  final _Load<List<ServiceCategory>> state;
  final ArtisanJobFilter selected;
  final bool showMyTrades;
  final ValueChanged<ArtisanJobFilter> onSelected;
  final VoidCallback onRetry;

  /// The jobs failed too, so their error below speaks for both and this
  /// row shows nothing rather than a second one.
  final bool foldError;

  @override
  Widget build(BuildContext context) {
    return _SectionSwitcher(
      child: switch (state) {
        _Loading() => const SkeletonPulse(
            key: ValueKey('loading'),
            child: ArtisanTradeChipsSkeleton(),
          ),
        _Failed() when foldError => const SizedBox(
            key: ValueKey('folded'),
            width: double.infinity,
          ),
        _Failed(:final error) => Padding(
            key: const ValueKey('failed'),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.gutter,
              vertical: AppSpace.s8,
            ),
            child: InlineError(
              message: _messageFor(error, "We couldn't load trades."),
              onRetry: onRetry,
            ),
          ),
        _Ready(value: final trades) => ArtisanTradeChips(
            key: const ValueKey('ready'),
            trades: trades,
            selected: selected,
            showMyTrades: showMyTrades,
            onSelected: onSelected,
          ),
      },
    );
  }
}

/// Four job rows' worth of skeleton, with their hairlines.
class _JobsSkeleton extends StatelessWidget {
  const _JobsSkeleton({super.key});

  static const _titles = [0.78, 0.6, 0.7, 0.52];

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, title) in _titles.indexed) ...[
            if (i > 0) const ArtisanRowDivider(),
            ArtisanJobRowSkeleton(titleWidth: title),
          ],
        ],
      ),
    );
  }
}

/// A note or error in place of the job rows, inside the gutter.
class _ListMessage extends StatelessWidget {
  const _ListMessage({super.key, required this.child});

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
      child: child,
    );
  }
}

/// Fades a section in as its content or error replaces the skeleton, and
/// switches at once when the system asks for reduced motion.
class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.base),
      switchInCurve: AppMotion.enter,
      // Only the incoming child is laid out, so the outgoing one never
      // overlaps it or holds the section at its old height.
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      child: child,
    );
  }
}

/// Eases its child's height to a new size, as when an accepted request
/// joins today's card, rather than pushing what's below in one jump. At
/// once under reduced motion, where AnimatedSize can't run without a
/// duration.
class _Grow extends StatelessWidget {
  const _Grow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// Folds a section away, or opens it, by its height as well as fading,
/// so what's below moves smoothly. At once under reduced motion.
class _CollapseSwitcher extends StatelessWidget {
  const _CollapseSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.base),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// Where one section's data stands: loading, ready, or failed.
sealed class _Load<T> {
  const _Load();
}

final class _Loading<T> extends _Load<T> {
  const _Loading();
}

final class _Ready<T> extends _Load<T> {
  const _Ready(this.value);

  final T value;
}

final class _Failed<T> extends _Load<T> {
  const _Failed(this.error);

  final Object error;
}

/// Runs one section's request, keeping a failure for the section to show.
Future<_Load<T>> _fetch<T>(Future<T> Function() request) async {
  try {
    return _Ready(await request());
  } on Object catch (error, stackTrace) {
    _reportBug(error, stackTrace);
    return _Failed(error);
  }
}

/// Waits for every section's reload. A section that failed while older
/// content was on screen keeps that content, and one message says so.
Future<void> _refreshSections(
  BuildContext context,
  List<Future<Object?>> loads,
) async {
  final errors = await Future.wait(loads);
  final error = errors.nonNulls.firstOrNull;
  if (error == null || !context.mounted) return;
  _say(
    ScaffoldMessenger.of(context),
    _messageFor(
      error,
      "We couldn't refresh everything. Pull down to try again.",
    ),
  );
}

/// Shows [message] in a snackbar, replacing any already showing.
void _say(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// What to tell the artisan about [error]. An [AuthException] carries a
/// message written for people; anything else gets [fallback].
String _messageFor(Object error, String fallback) =>
    error is AuthException ? error.message : fallback;

/// Reports [error] when it is a bug rather than a failed request, so the
/// short message shown in its place doesn't hide it.
void _reportBug(Object error, StackTrace stackTrace) {
  if (error is! Error) return;
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'artisan home',
    ),
  );
}
