import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import 'package:go_router/go_router.dart';

/// Robust NavigationService
/// - Serializes navigation calls via an internal queue to avoid concurrent
///   Navigator operations and the common '!_debugLocked' assertion.
/// - Detects Navigator that uses the pages API and attempts fallbacks when an
///   imperative navigation fails with page-based errors.
/// - Adds a small delay between rapid navigation calls to reduce races.
/// - Registers as a [WidgetsBindingObserver] to observe lifecycle changes and
///   avoid performing navigation while the app is backgrounded.
/// - Clears the queue on catastrophic errors to avoid stuck state.
class NavigationService with WidgetsBindingObserver {
  NavigationService._() {
    // Register to observe app lifecycle changes.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  static final NavigationService instance = NavigationService._();

  // Internal chain used to serialize operations. We keep a Future chain so
  // each op waits for the previous one.
  Future<void> _chain = Future<void>.value();

  /// Minimal delay between consecutive navigation operations (ms).
  Duration minDelay = const Duration(milliseconds: 30);

  /// How many consecutive "unlocked" checks are required before performing
  /// navigation. Useful to wait until the framework finishes its current
  /// transition.
  int consecutiveUnlockChecks = 2;

  /// Poll interval while waiting for navigator to unlock.
  Duration _pollInterval = const Duration(milliseconds: 20);

  /// Whether the app is currently paused/backgrounded. We avoid performing
  /// navigation while paused.
  bool _isPaused = false;

  /// Simple debug logger (prints only in debug or when kReleaseMode is false)
  void _log(String msg) {
    final ts = DateTime.now().toIso8601String();
    // Use debugPrint to avoid large bursts blocking the UI
    debugPrint('NavigationService[$ts] $msg');
  }

  // Helper to safely access the current navigator state (root navigator if available)
  NavigatorState? _navigatorForContext(BuildContext context) {
    try {
      if (appNavigatorKey.currentState != null) return appNavigatorKey.currentState;
      return Navigator.of(context, rootNavigator: true);
    } catch (e) {
      _log('Failed to get navigator for context: $e');
      try {
        return Navigator.of(context);
      } catch (_) {
        return null;
      }
    }
  }

  bool _isNavigatorDebugLockedDirect(NavigatorState? ns) {
    if (ns == null) return false;
    try {
      final dyn = ns as dynamic;
      final val = dyn._debugLocked;
      return val == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _waitForNavigatorUnlocked(NavigatorState? ns, {int consecutiveChecks = 2}) async {
    if (ns == null) return;
    var ok = 0;
    final maxAttempts = 40; // ~0.8s with _pollInterval 20ms
    var attempts = 0;
    while (ok < consecutiveChecks && attempts < maxAttempts) {
      attempts++;
      try {
        if (!_isNavigatorDebugLockedDirect(ns)) {
          ok++;
        } else {
          ok = 0;
        }
      } catch (_) {
        ok = 0;
      }
      if (ok >= consecutiveChecks) break;
      await Future.delayed(_pollInterval);
    }
  }

  /// Checks whether the navigator in the given [context] is using the
  /// page-based API (i.e. Navigator.pages is non-empty). Useful to detect
  /// mixing of Router/pages API and imperative push/pop APIs.
  bool isUsingPagesAPI(BuildContext context) {
    try {
      final navigator = Navigator.of(context);
      final widget = navigator.widget;
      if (widget is Navigator) {
        // navigator.pages is a List<Page> (may be empty)
        return widget.pages.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  /// Enqueue an operation. This ensures operations run sequentially and we
  /// catch errors to recover the queue in case of a catastrophic failure.
  Future<T?> _enqueue<T>(Future<T?> Function() op) {
    final completer = Completer<T?>();

    // Chain the operation after the previous one.
    _chain = _chain.then((_) {
      final inner = Completer<void>();

      // Run the op after the current frame to avoid navigator locked issues
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_isPaused) {
          _log('App paused; skipping navigation op');
          completer.complete(null);
          inner.complete();
          return;
        }

        try {
          final res = await op();
          completer.complete(res);
        } catch (e, st) {
          // Clear the chain to avoid blocking future navigations
          _log('Navigation operation failed: $e');
          // reset chain so next ops start fresh
          _chain = Future<void>.value();
          completer.completeError(e, st);
        } finally {
          // Small deliberate delay between ops to reduce racing. Add a tiny
          // random jitter (0-20ms) to reduce repeated simultaneous clicks
          // causing thundering herd behaviour in edge cases.
          final jitter = math.Random().nextInt(20);
          final delay = Duration(milliseconds: minDelay.inMilliseconds + jitter);
          try {
            await Future.delayed(delay);
          } catch (_) {}
          inner.complete();
        }
      });

      return inner.future;
    }, onError: (e) {
      // If previous op failed, reset chain and still run the next op.
      _log('Previous navigation op error: $e — resetting chain');
      final inner = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final res = await op();
          completer.complete(res);
        } catch (e2, st2) {
          _log('Navigation op after error also failed: $e2');
          _chain = Future<void>.value();
          completer.completeError(e2, st2);
        } finally {
          final jitter = math.Random().nextInt(20);
          final delay = Duration(milliseconds: minDelay.inMilliseconds + jitter);
          try {
            await Future.delayed(delay);
          } catch (_) {}
          inner.complete();
        }
      });
      return inner.future;
    });

    return completer.future;
  }

  // Detect whether the provided NavigatorState is using the pages API.
  bool _navigatorUsesPages(NavigatorState? ns) {
    if (ns == null) return false;
    try {
      final navWidget = ns.widget;
      if (navWidget is Navigator) {
        return navWidget.pages.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  // Helper retry wrapper to attempt an imperative navigator call a few times
  // if it fails with debug-locked assertion. Returns the result or rethrows.
  Future<T?> _imperativeRetry<T>(Future<T?> Function() fn, {int retries = 3, Duration backoff = const Duration(milliseconds: 50)}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await fn();
      } catch (e) {
        final msg = e.toString();
        // Handle common navigator locked assertion
        if ((msg.contains('_debugLocked') || msg.contains('page-based route')) && attempt <= retries) {
          _log('Navigator locked or page-based error, retrying attempt $attempt: $e');
          await Future.delayed(backoff * attempt);
          continue;
        }
        rethrow;
      }
    }
  }

  // Public API -------------------------------------------------------------

  /// Push a widget-based route (MaterialPageRoute built inside service).
  Future<T?> pushWidget<T extends Object?>(BuildContext context, Widget page, {bool rootNavigator = true, bool waitForSettlement = true}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        if (_navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          _log('Detected page-based Navigator in context; attempting root fallback');
        }
        final route = MaterialPageRoute<T>(builder: (_) => page);
        final res = await _imperativeRetry(() async => ns!.push<T>(route));
        if (waitForSettlement) await Future.delayed(const Duration(milliseconds: 250));
        return res;
      } catch (e) {
        _log('Primary pushWidget failed: $e');
        // If the error indicates a page-based Navigator mismatch, attempt a
        // fallback using appNavigatorKey root navigator push.
        if (e.toString().contains('page-based route') || _navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          try {
            _log('Attempting fallback push via appNavigatorKey');
            final root = appNavigatorKey.currentState;
            if (root != null) return await root.push<T>(MaterialPageRoute<T>(builder: (_) => page));
          } catch (e2) {
            _log('Fallback push failed: $e2');
          }
        }
        rethrow;
      }
    });
  }

  /// Push by route name (uses Navigator.pushNamed) — good when using Router/GoRouter as well.
  Future<T?> pushNamed<T extends Object?>(BuildContext context, String name, {Object? arguments}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        final res = await _imperativeRetry(() async => ns!.pushNamed<T>(name, arguments: arguments));
        return res;
      } catch (e) {
        _log('pushNamed failed: $e');
        // Try root navigator fallback
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) return await _imperativeRetry(() async => root.pushNamed<T>(name, arguments: arguments));
        } catch (e2) {
          _log('pushNamed fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Replace current route with a widget-based route.
  Future<T?> pushReplacementWidget<T extends Object?, TO extends Object?>(BuildContext context, Widget page, {TO? result}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        final route = MaterialPageRoute<T>(builder: (_) => page);
        final res = await _imperativeRetry(() async => ns!.pushReplacement<T, TO>(route, result: result));
        return res;
      } catch (e) {
        _log('pushReplacementWidget failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) return await _imperativeRetry(() async => root.pushReplacement<T, TO>(MaterialPageRoute<T>(builder: (_) => page), result: result));
        } catch (e2) {
          _log('pushReplacementWidget fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Push and remove until predicate, widget variant. This implementation avoids
  /// using imperative pushAndRemoveUntil on a page-based navigator — instead we
  /// route via GoRouter when possible or call root navigator operations.
  Future<void> pushAndRemoveWidgetUntil(BuildContext context, Widget page, RoutePredicate predicate) {
    return _enqueue<void>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        // If the navigator is page-based, avoid imperative pushAndRemoveUntil
        // which triggers the 'page-based route cannot be completed' assertion.
        if (_navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          _log('Navigator uses pages API — using declarative fallback');
          // Log a short stack trace to help identify the caller site that requested
          // a replace-all navigation. This is useful during debugging of unexpected
          // redirects to routes like /homePage.
          try {
            final st = StackTrace.current.toString().split('\n').take(6).join(' | ');
            _log('pushAndRemoveWidgetUntil caller stack (truncated): $st');
          } catch (_) {}

          // NavBarPage special-case mapping to go paths
          if (page is NavBarPage) {
            final initial = (page as NavBarPage).initialPage ?? 'homePage';
            _log('pushAndRemoveWidgetUntil: NavBarPage detected with initialPage="$initial" (runtime: ${page.runtimeType})');
            final mapping = <String, String>{
              'homepage': HomePageWidget.routePath,
              'discoverpage': DiscoverPageWidget.routePath,
              'jobpostpage': JobPostPageWidget.routePath,
              'bookingpage': BookingPageWidget.routePath,
              'profile': ProfileWidget.routePath,
            };
            final target = mapping[initial.toLowerCase()] ?? HomePageWidget.routePath;
            try {
              _log('Declarative fallback: going to $target');
              GoRouter.of(context).go(target);
              return null;
            } catch (e) {
              _log('GoRouter.go fallback for NavBarPage failed: $e');
            }
          }

          // If page has a known static path, prefer GoRouter
          try {
            // Many widgets define `routePath` static String — attempt to reflect by name
            if (page.runtimeType.toString() == 'HomePageWidget') {
              GoRouter.of(context).go(HomePageWidget.routePath);
              return null;
            }
            if (page.runtimeType.toString() == 'DiscoverPageWidget') {
              GoRouter.of(context).go(DiscoverPageWidget.routePath);
              return null;
            }
            if (page.runtimeType.toString() == 'JobPostPageWidget') {
              GoRouter.of(context).go(JobPostPageWidget.routePath);
              return null;
            }
            if (page.runtimeType.toString() == 'BookingPageWidget') {
              GoRouter.of(context).go(BookingPageWidget.routePath);
              return null;
            }
            if (page.runtimeType.toString() == 'ProfileWidget') {
              GoRouter.of(context).go(ProfileWidget.routePath);
              return null;
            }
          } catch (e) {
            _log('GoRouter.go attempt failed: $e');
          }

          // If we couldn't map to a router path, try root navigator imperative
          try {
            final root = appNavigatorKey.currentState;
            if (root != null) {
              await _imperativeRetry(() async => root.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate));
              return null;
            }
          } catch (e) {
            _log('Root navigator pushAndRemoveUntil fallback failed: $e');
          }

          // As a last resort, clear queue and throw a descriptive error so call
          // sites can handle it gracefully.
          final err = Exception('Cannot perform pushAndRemoveUntil on a page-based Navigator; provide a router path or use pushNamedAndRemoveUntil.');
          _log(err.toString());
          throw err;
        }

        // Non page-based navigator: safe to call imperative API with retry
        await _imperativeRetry(() async => ns!.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate));
        return null;
      } catch (e) {
        _log('pushAndRemoveWidgetUntil failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            await _imperativeRetry(() async => root.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate));
            return null;
          }
        } catch (e2) {
          _log('pushAndRemoveWidgetUntil fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Named variant of pushNamedAndRemoveUntil
  Future<T?> pushNamedAndRemoveUntil<T extends Object?>(BuildContext context, String newRouteName, RoutePredicate predicate, {Object? arguments}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        final res = await _imperativeRetry(() async => ns!.pushNamedAndRemoveUntil<T>(newRouteName, predicate, arguments: arguments));
        return res;
      } catch (e) {
        _log('pushNamedAndRemoveUntil failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) return await _imperativeRetry(() async => root.pushNamedAndRemoveUntil<T>(newRouteName, predicate, arguments: arguments));
        } catch (e2) {
          _log('pushNamedAndRemoveUntil fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Pop the current route.
  Future<void> pop<T extends Object?>(BuildContext context, [T? result]) {
    return _enqueue<void>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        await _imperativeRetry(() async => ns!.pop<T>(result));
        return null;
      } catch (e) {
        _log('pop failed: $e — attempting root fallback');
        try {
          final root = appNavigatorKey.currentState;
          await _imperativeRetry(() async => root?.pop<T>(result));
        } catch (e2) {
          _log('pop fallback also failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Clears the internal queue and resets to a healthy state.
  void clearQueueForRecovery([String? reason]) {
    _log('Clearing navigation queue for recovery${reason != null ? ': $reason' : ''}');
    _chain = Future<void>.value();
  }

  // WidgetsBindingObserver overrides -------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isPaused = (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached);
    _log('AppLifecycle changed: $state — paused=$_isPaused');
  }

  // call this to dispose observer when app shuts down (optional)
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }
}

// Removed duplicated NavigationUtils wrapper to avoid naming conflicts with
// the real `lib/utils/navigation_utils.dart`. Call sites should import the
// utils variant. Keeping this file focused on NavigationService only.

