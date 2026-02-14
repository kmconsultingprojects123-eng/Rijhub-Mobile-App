import '../splash_screen_page2/splash_screen_page2_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/pages/create_job_page1/create_job_page1_widget.dart';
import '../job_history_page/job_history_page_widget.dart';
import 'package:flutter/material.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import 'job_post_page_model.dart';
import '../../services/job_service.dart';
import '../../services/user_service.dart';
import '../job_details_page/job_details_page_widget.dart';
import '../artisan_jobs_history/artisan_jobs_history_widget.dart';
import 'dart:async';
import '../../utils/navigation_utils.dart';
import '../../utils/auth_guard.dart';
import '/main.dart';
export 'job_post_page_model.dart';

/// Create a page where list of posted jobs can been seen then artisan can
/// apply for them no images just text
class JobPostPageWidget extends StatefulWidget {
  const JobPostPageWidget({super.key});

  static String routeName = 'JobPostPage';
  static String routePath = '/jobPostPage';

  @override
  State<JobPostPageWidget> createState() => _JobPostPageWidgetState();
}

class _JobPostPageWidgetState extends State<JobPostPageWidget> {
  late JobPostPageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _jobs = [];
  // Cached full job list fetched from server to allow fast client-side filtering
  List<Map<String, dynamic>> _allJobs = [];
  bool _loading = true;
  // pagination / infinite scroll
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  final int _limit = 12;
  bool _hasMore = true;
  bool _loadingMore = false;
  Timer? _debounce;
  bool _isArtisan = false;
  bool _roleLoaded = false;
  VoidCallback? _textListener;

  // New: track current query and seen job ids for deduplication
  String _currentQuery = '';
  final Set<String> _seenJobIds = {};
  bool _lastFetchFailed = false;

  @override
  void initState() {
    super.initState();

    _model = createModel(context, () => JobPostPageModel());

    _model.textController ??= TextEditingController();
    _model.textFieldFocusNode ??= FocusNode();

    // Try to use cached profile from AppStateNotifier to avoid UI flicker
    try {
      final cached = AppStateNotifier.instance.profile;
      if (cached != null) {
        final role = (cached['role'] ?? cached['type'] ?? '')?.toString().toLowerCase() ?? '';
        _isArtisan = role.contains('artisan');
        _roleLoaded = true;
      }
    } catch (_) {}

    // Fetch initial jobs (now paginated)
    _fetchJobs();

    // Debounced search listener + instant UI update for suffix icon
    _textListener = () {
      if (!mounted) return;
      setState(() {}); // so clear icon appears/disappears immediately
      final q = _model.textController!.text.trim();
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _fetchJobs(query: q);
      });
    };
    _model.textController!.addListener(_textListener!);

    // Load stored token first, then fetch profile; determines whether current user is artisan
    () async {
      try {
        await AppStateNotifier.instance.refreshAuth();
        if (!AppStateNotifier.instance.loggedIn) {
          if (!mounted) return;
          try {
            GoRouter.of(context).go(SplashScreenPage2Widget.routePath);
          } catch (_) {
            if (appNavigatorKey.currentState != null) {
              appNavigatorKey.currentState!.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()),
                    (Route<dynamic> route) => false,
              );
            } else {
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()),
                    (Route<dynamic> route) => false,
              );
            }
          }
          return;
        }

        try {
          final profile = await UserService.getProfile();
          final role = (profile?['role'] ?? profile?['type'] ?? '')?.toString().toLowerCase() ?? '';
          if (mounted) setState(() { _isArtisan = role.contains('artisan'); _roleLoaded = true; });
        } catch (_) {
          if (mounted) setState(() { _roleLoaded = true; });
        }
      } catch (_) {
        if (!mounted) return;
        if (appNavigatorKey.currentState != null) {
          appNavigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()),
                (Route<dynamic> route) => false,
          );
        } else {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => SplashScreenPage2Widget()),
                (Route<dynamic> route) => false,
          );
        }
        return;
      }
    }();

    // Infinite scroll listener: load more when near bottom
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_loadingMore && _hasMore && !_loading) {
        _fetchMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // remove controller listener to avoid leaks
    try { if (_textListener != null) _model.textController?.removeListener(_textListener!); } catch (_) {}
    _model.dispose();
    try { _scrollController.dispose(); } catch (_) {}

    super.dispose();
  }

  Future<void> _fetchJobs({String? query}) async {
    // Use server-side pagination: reset page and dedupe tracking
    if (mounted) setState(() {
      _loading = true;
      _lastFetchFailed = false;
    });

    try {
      _currentQuery = (query ?? '').trim();
      _page = 1;
      _jobs = [];
      _seenJobIds.clear();

      // Attempt paginated fetch
      final res = await JobService.getJobs(page: _page, limit: _limit, query: _currentQuery.isEmpty ? null : _currentQuery);

      // Deduplicate and append
      final newItems = <Map<String, dynamic>>[];
      for (final item in res) {
        final id = (item['id'] ?? item['_id'] ?? '').toString();
        if (id.isEmpty || !_seenJobIds.contains(id)) {
          if (id.isNotEmpty) _seenJobIds.add(id);
          newItems.add(item);
        }
      }

      if (mounted) setState(() {
        _jobs = newItems;
        _hasMore = res.length == _limit;
      });
      return;
    } catch (e) {
      // Fallback: try old getAllJobs method and paginate client-side
      if (kDebugMode) debugPrint('Paginated fetch failed, falling back: $e');
      try {
        final resAll = await JobService.getAllJobs();
        if (mounted) setState(() {
          _allJobs = resAll;
          _page = 1;
          _hasMore = _allJobs.length > _limit;
          _jobs = _allJobs.take(_limit).toList();
        });
        return;
      } catch (e2) {
        if (kDebugMode) debugPrint('Fallback getAllJobs failed: $e2');
        if (mounted) setState(() { _jobs = []; _lastFetchFailed = true; });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      // Try server-side next page
      final nextPage = _page + 1;
      try {
        final res = await JobService.getJobs(page: nextPage, limit: _limit, query: _currentQuery.isEmpty ? null : _currentQuery);
        final newItems = <Map<String, dynamic>>[];
        for (final item in res) {
          final id = (item['id'] ?? item['_id'] ?? '').toString();
          if (id.isEmpty || !_seenJobIds.contains(id)) {
            if (id.isNotEmpty) _seenJobIds.add(id);
            newItems.add(item);
          }
        }

        if (newItems.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 120)); // small delay for UX
          setState(() {
            _jobs.addAll(newItems);
            _page = nextPage;
            _hasMore = res.length == _limit;
          });
        } else {
          // server returned empty page; no more
          setState(() { _hasMore = false; });
        }
        return;
      } catch (e) {
        // server pagination failed -> fallback to client-side pagination if we have _allJobs
        if (kDebugMode) debugPrint('Server pagination failed in _fetchMore: $e');
        final start = _page * _limit;
        final next = _allJobs.skip(start).take(_limit).toList();
        if (next.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 250));
          setState(() {
            _jobs.addAll(next.where((item) {
              final id = (item['id'] ?? item['_id'] ?? '').toString();
              if (id.isEmpty) return true;
              if (_seenJobIds.contains(id)) return false;
              _seenJobIds.add(id);
              return true;
            }).toList());
            _page = _page + 1;
            _hasMore = _allJobs.length > _jobs.length;
          });
          return;
        }
        setState(() { _hasMore = false; });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchMore jobs error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _buildSkeletonCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title placeholder
          Container(
            height: 16,
            width: 180,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withAlpha((0.08 * 255).toInt()),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),

          // Posted date placeholder
          Container(
            height: 12,
            width: 100,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withAlpha((0.06 * 255).toInt()),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Description placeholder lines
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withAlpha((0.08 * 255).toInt()),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 280,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withAlpha((0.08 * 255).toInt()),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),

          // Bottom row placeholders
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withAlpha((0.08 * 255).toInt()),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withAlpha((0.06 * 255).toInt()),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              Container(
                height: 36,
                width: 110,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withAlpha((0.08 * 255).toInt()),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If this page isn't inside NavBarPage, redirect so the bottom nav is visible
    final bool _isNestedNavBar = context.findAncestorWidgetOfExactType<NavBarPage>() != null;
    if (!_isNestedNavBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NavigationUtils.safePushReplacement(context, NavBarPage(initialPage: 'JobPostPage'));
        } catch (_) {
          try { Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NavBarPage(initialPage: 'JobPostPage'))); } catch (_) {}
        }
      });
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        // Use surface so the page background follows the theme surface color
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back arrow removed per request; keep spacer so title stays centered
                    const SizedBox(width: 48),
                    Text(
                      'Job Board',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 48), // For balance
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    // Reset query and refresh
                    _model.textController?.clear();
                    _currentQuery = '';
                    await _fetchJobs();
                  },
                  color: colorScheme.primary,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 24.0),
                    physics: const BouncingScrollPhysics(),
                    itemCount: 1 + (_loading ? 3 : (_jobs.isEmpty && !_loading && !_lastFetchFailed ? 1 : _jobs.length + (_hasMore ? 1 : 0))),
                    itemBuilder: (context, index) {
                      // index 0 => static top section (search + header + actions)
                      if (index == 0) {
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 20.0),

                          // Search bar
                          TextFormField(
                            controller: _model.textController,
                            focusNode: _model.textFieldFocusNode,
                            autofocus: false,
                            obscureText: false,
                            decoration: InputDecoration(
                              hintText: 'Search jobs...',
                              hintStyle: TextStyle(
                                color: colorScheme.onSurface.withAlpha((0.4 * 255).toInt()),
                              ),
                              filled: true,
                              fillColor: colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 14.0,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: colorScheme.onSurface.withAlpha((0.4 * 255).toInt()),
                                size: 20.0,
                              ),
                              suffixIcon: _model.textController!.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: colorScheme.onSurface.withAlpha((0.4 * 255).toInt()),
                                        size: 20.0,
                                      ),
                                      onPressed: () {
                                        try { if (_debounce?.isActive ?? false) _debounce?.cancel(); } catch (_) {}
                                        _model.textController!.clear();
                                        FocusScope.of(context).unfocus();
                                        if (_allJobs.isNotEmpty) {
                                          setState(() { _jobs = List<Map<String, dynamic>>.from(_allJobs.take(_limit)); _page = 1; _hasMore = _allJobs.length > _limit; });
                                        } else {
                                          _fetchJobs();
                                        }
                                      },
                                    )
                                  : null,
                            ),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 16,
                            ),
                            validator: _model.textControllerValidator.asValidator(context),
                            onFieldSubmitted: (value) {
                              try { if (_debounce?.isActive ?? false) _debounce?.cancel(); } catch (_) {}
                              FocusScope.of(context).unfocus();
                              _fetchJobs(query: value);
                            },
                          ),

                          const SizedBox(height: 24),

                          // Header with actions
                          Row(
                            children: [
                              Expanded(child: Text('Available Jobs', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
                              Row(children: [
                                OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      if (_isArtisan) {
                                        await NavigationUtils.safePush(context, ArtisanJobsHistoryWidget());
                                      } else {
                                        await NavigationUtils.safePush(context, JobHistoryPageWidget());
                                      }
                                    } catch (_) {
                                      try {
                                        if (_isArtisan) {
                                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtisanJobsHistoryWidget()));
                                        } else {
                                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobHistoryPageWidget()));
                                        }
                                      } catch (_) {}
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colorScheme.primary,
                                    side: BorderSide(color: colorScheme.primary, width: 1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  child: Text(_isArtisan ? 'Jobs Done' : 'My Jobs', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                ),
                                const SizedBox(width: 12),
                                // Show Create Job button only after role is resolved and user is not an artisan
                                if (_roleLoaded && !_isArtisan)
                                  ElevatedButton(
                                    onPressed: () async {
                                      if (!await ensureSignedInForAction(context)) return;
                                      try { await NavigationUtils.safePush(context, CreateJobPage1Widget()); } catch (_) {}
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), elevation: 0),
                                    child: Row(children: const [Icon(Icons.add, size: 18), SizedBox(width: 6), Text('Create', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]),
                                  ),
                              ])
                            ],
                          ),

                          const SizedBox(height: 24),
                        ]);
                      }

                      // Jobs or loaders
                      final dataIndex = index - 1;
                      if (_loading) {
                        // Initial skeleton loaders
                        return Padding(padding: const EdgeInsets.only(bottom: 16.0), child: _buildSkeletonCard());
                      }

                      // Empty state
                      if (_jobs.isEmpty && !_loading && !_lastFetchFailed) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.work_outline, size: 56, color: colorScheme.onSurface.withAlpha((0.4 * 255).toInt())),
                                const SizedBox(height: 12),
                                Text('No jobs found', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text('Try a different search or pull to refresh', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withAlpha((0.6 * 255).toInt()))),
                                const SizedBox(height: 20),
                                if (_hasMore)
                                  ElevatedButton(onPressed: _fetchMore, child: const Text('Load more'))
                              ],
                            ),
                          ),
                        );
                      }

                      // If last fetch failed show retry
                      if (_lastFetchFailed) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.error_outline, size: 56, color: colorScheme.error),
                                const SizedBox(height: 12),
                                Text('Failed to load jobs', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 8),
                                ElevatedButton(onPressed: () { _fetchJobs(query: _currentQuery); }, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        );
                      }

                      // Bottom loader slot or load more button
                      if (dataIndex >= _jobs.length) {
                        if (_loadingMore) return Padding(padding: const EdgeInsets.only(bottom: 16.0), child: _buildSkeletonCard());
                        // show explicit load more button when available to avoid accidental auto-loads
                        if (_hasMore) return Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Center(child: ElevatedButton(onPressed: _fetchMore, child: const Text('Load more'))));
                        return const SizedBox();
                      }

                      final job = _jobs[dataIndex];
                      final title = (job['title'] ?? job['jobTitle'] ?? '').toString();
                      final desc = (job['description'] ?? job['details'] ?? '').toString();
                      final posted = job['createdAt'] ?? job['postedAt'] ?? job['created'];
                      String postedText = 'Posted';
                      try {
                        if (posted != null) {
                          final dt = DateTime.tryParse(posted.toString());
                          if (dt != null) {
                            postedText = dateTimeFormat('relative', dt);
                          }
                        }
                      } catch (_) {}
                      final budget = job['budget'];
                      final location = job['location'] ?? job['address'] ?? '';

                      String _displayBudget(dynamic b) {
                        if (b == null) return '-';
                        try {
                          if (b is num) {
                            return '₦' +
                                NumberFormat('#,##0', 'en_US')
                                    .format(b);
                          }
                          final s = b.toString();
                          if (s.contains('₦')) return s;
                          final numVal = num.tryParse(s.replaceAll(
                              RegExp(r'[^0-9.-]'), ''));
                          if (numVal != null) {
                            return '₦' +
                                NumberFormat('#,##0', 'en_US')
                                    .format(numVal);
                          }
                          return s;
                        } catch (_) {
                          return b.toString();
                        }
                      }

                      final rawStatus =
                          (job['status'] ?? '')?.toString().toLowerCase() ?? '';
                      final statusLabel = (rawStatus == 'closed' ||
                          rawStatus == 'done' ||
                          rawStatus == 'inactive')
                          ? 'Closed'
                          : 'Open';
                      final isOpen = statusLabel == 'Open';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: InkWell(
                          onTap: () async {
                            try {
                              await NavigationUtils.safePush(context, JobDetailsPageWidget(job: job));
                            } catch (_) {
                              try {
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailsPageWidget(job: job)));
                              } catch (_) {}
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.onSurface.withAlpha((0.1 * 255).toInt()),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  // Top row with title and status
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title.isNotEmpty
                                                  ? title
                                                  : 'Untitled Job',
                                              style: theme.textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow:
                                              TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              postedText,
                                              style: theme.textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                color: colorScheme
                                                    .onSurface
                                                    .withAlpha((0.6 * 255).toInt()),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isOpen
                                              ? colorScheme.primary.withAlpha((0.1 * 255).toInt())
                                              : colorScheme.error.withAlpha((0.1 * 255).toInt()),
                                          borderRadius:
                                          BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: isOpen
                                                ? colorScheme.primary
                                                : colorScheme.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Description
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.8 * 255).toInt()),
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  // Bottom row: budget, location, and action
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _displayBudget(budget),
                                            style: theme.textTheme
                                                .titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Location: ${location.toString()}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withAlpha((0.6 * 255).toInt()),
                                            ),
                                          ),
                                        ],
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          try {
                                            await NavigationUtils.safePush(context, JobDetailsPageWidget(job: job));
                                          } catch (_) {}
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                          colorScheme.primary,
                                          foregroundColor:
                                          colorScheme.onPrimary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(8),
                                          ),
                                          padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 10),
                                          elevation: 0,
                                        ),
                                        child: Text(
                                          'View Job',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        );
                      },
                  ),
                  ),
                ),
              ],
          ),
          ),
        ),
    );
  }
}
