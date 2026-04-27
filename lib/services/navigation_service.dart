import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '/flutter_flow/nav/nav.dart';
import '/index.dart';
import 'package:go_router/go_router.dart';

/// NavigationService (GoRouter-first)
///
/// This service serializes navigation calls to avoid navigator locked
/// assertions and prefers declarative routing via GoRouter when a
/// page-based Navigator is in use. It keeps widget-based fallbacks
/// for code paths that still pass Widgets directly.
class NavigationService with WidgetsBindingObserver {
  NavigationService._() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  static final NavigationService instance = NavigationService._();

  // Serializes navigation operations using a future chain.
  Future<void> _chain = Future<void>.value();

  /// Minimum delay between operations (base) in milliseconds.
  Duration minDelay = const Duration(milliseconds: 30);

  /// Poll interval while waiting for navigator unlock.
  Duration _pollInterval = const Duration(milliseconds: 20);

  /// How many consecutive unlocked checks we need before proceeding.
  int consecutiveUnlockChecks = 2;

  bool _isPaused = false;

  void _log(String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('NavigationService[$ts] $msg');
  }

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
    final maxAttempts = 40;
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

  bool isUsingPagesAPI(BuildContext context) {
    try {
      final navigator = Navigator.of(context);
      final widget = navigator.widget;
      if (widget is Navigator) {
        return widget.pages.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  bool _navigatorUsesPages(NavigatorState? ns) {
    if (ns == null) return false;
    try {
      final navWidget = ns.widget;
      if (navWidget is Navigator) return navWidget.pages.isNotEmpty;
    } catch (_) {}
    return false;
  }

  Future<T?> _imperativeRetry<T>(Future<T?> Function() fn, {int retries = 3, Duration backoff = const Duration(milliseconds: 50)}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await fn();
      } catch (e) {
        final msg = e.toString();
        if ((msg.contains('_debugLocked') || msg.contains('page-based route')) && attempt <= retries) {
          _log('Navigator locked/page-based error, retrying attempt $attempt: $e');
          await Future.delayed(backoff * attempt);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<T?> _enqueue<T>(Future<T?> Function() op) {
    final completer = Completer<T?>();

    _chain = _chain.then((_) {
      final inner = Completer<void>();

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
          _log('Navigation operation failed: $e');
          _chain = Future<void>.value();
          completer.completeError(e, st);
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
    }, onError: (e) {
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

  // ------------------------------------------------------------------
  // Helper: map a Widget instance to a GoRouter path when possible.
  // This avoids attempting pushAndRemoveUntil on page-based Navigators.
  String? _mapWidgetToPath(Widget page) {
    try {
      // Special-case NavBarPage which contains an initialPage key.
      if (page is NavBarPage) {
        final initial = page.initialPage ?? 'homePage';
        final mapping = <String, String>{
          'homepage': HomePageWidget.routePath,
          'discoverpage': DiscoverPageWidget.routePath,
          'jobpostpage': JobPostPageWidget.routePath,
          'bookingpage': BookingPageWidget.routePath,
          'profile': ProfileWidget.routePath,
        };
        return mapping[initial.toLowerCase()] ?? HomePageWidget.routePath;
      }

      // Map by runtime type name for common pages. Add entries as needed.
      final name = page.runtimeType.toString();
      final mapByName = <String, String>{
        'HomePageWidget': HomePageWidget.routePath,
        'DiscoverPageWidget': DiscoverPageWidget.routePath,
        'JobPostPageWidget': JobPostPageWidget.routePath,
        'BookingPageWidget': BookingPageWidget.routePath,
        'ProfileWidget': ProfileWidget.routePath,
        'WelcomeAfterSignupWidget': WelcomeAfterSignupWidget.routePath,
        'VerificationPageWidget': VerificationPageWidget.routePath,
        'LoginAccountWidget': LoginAccountWidget.routePath,
        'CreateAccount2Widget': CreateAccount2Widget.routePath,
        'JobDetailsPageWidget': JobDetailsPageWidget.routePath,
        // Add other common pages here if you use them with replace-all.
      };
      if (mapByName.containsKey(name)) return mapByName[name];
    } catch (e) {
      _log('mapWidgetToPath failed: $e');
    }
    return null;
  }

  // Helper: build path with query parameters
  String _buildPathWithQuery(String path, Map<String, String>? queryParams) {
    if (queryParams == null || queryParams.isEmpty) return path;
    final uri = Uri(path: path, queryParameters: queryParams);
    return uri.toString();
  }

  // ---------------- Public API (GoRouter-first) -----------------------

  /// Go (replace current location) using GoRouter. Accepts a raw path
  /// or path built from routePath constants. Query params may be provided.
  Future<void> go(BuildContext context, String path, {Map<String, String>? queryParams, Object? extra}) {
    return _enqueue<void>(() async {
      if (!context.mounted) return null;
      final full = _buildPathWithQuery(path, queryParams);
      try {
        GoRouter.of(context).go(full, extra: extra);
      } catch (e) {
        _log('GoRouter.go failed for $full: $e — attempting imperative fallback');
        // Imperative fallback: use root navigator to pushReplacementNamed if available
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            // Fire-and-forget: future resolves on pop, must not be awaited
            // inside _enqueue or the chain locks for the page lifetime.
            root.pushNamedAndRemoveUntil(path, (r) => false);
            return null;
          }
        } catch (e2) {
          _log('Imperative fallback for go() failed: $e2');
        }
        rethrow;
      }
      return null;
    });
  }

  /// Push a route path (adds to stack). Uses GoRouter.push when available.
  Future<void> pushRoute(BuildContext context, String path, {Map<String, String>? queryParams, Object? extra}) {
    return _enqueue<void>(() async {
      if (!context.mounted) return null;
      final full = _buildPathWithQuery(path, queryParams);
      try {
        GoRouter.of(context).push(full, extra: extra);
        return null;
      } catch (e) {
        _log('GoRouter.push failed for $full: $e — falling back to imperative Navigator');
        final ns = _navigatorForContext(context);
        await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
        try {
          // Fire-and-forget: ns.push's future resolves on pop, must not be
          // awaited inside _enqueue or the chain locks for the page lifetime.
          ns!.push(MaterialPageRoute(builder: (_) => _fakeWidgetForPath(path, extra)));
          return null;
        } catch (e2) {
          _log('pushRoute imperative fallback also failed: $e2');
          rethrow;
        }
      }
    });
  }

  /// Replace current route with the provided widget (widget fallback).
  ///
  /// IMPORTANT: `Navigator.pushReplacement` returns a Future that only
  /// completes when the new route is itself popped. We must NOT await that
  /// future inside `_enqueue`, or the navigation chain would be blocked for
  /// the entire lifetime of the pushed page, deadlocking every subsequent
  /// navigation call. We capture the future and return it to the caller.
  Future<T?> pushReplacementWidget<T extends Object?, TO extends Object?>(BuildContext context, Widget page, {TO? result}) async {
    Future<T?>? popResult;
    await _enqueue<void>(() async {
      if (!context.mounted) return;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        popResult = ns!.pushReplacement<T, TO>(MaterialPageRoute(builder: (_) => page), result: result);
      } catch (e) {
        _log('pushReplacementWidget failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            popResult = root.pushReplacement<T, TO>(MaterialPageRoute(builder: (_) => page), result: result);
            return;
          }
        } catch (e2) {
          _log('pushReplacementWidget fallback failed: $e2');
        }
        rethrow;
      }
    });
    return popResult;
  }

  /// Push a widget onto the stack (kept for backward-compat).
  ///
  /// IMPORTANT: see comment on `pushReplacementWidget`. `Navigator.push`
  /// returns a Future that only completes when the pushed route is popped.
  /// Awaiting it inside `_enqueue` would lock the navigation chain for the
  /// entire page lifetime — every later push would queue behind it and
  /// silently hang. We capture the popped-result future here and return it
  /// to the caller without blocking the queue.
  Future<T?> pushWidget<T extends Object?>(BuildContext context, Widget page, {bool waitForSettlement = true}) async {
    Future<T?>? popResult;
    await _enqueue<void>(() async {
      if (!context.mounted) return;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        final route = MaterialPageRoute<T>(builder: (_) => page);
        popResult = ns!.push<T>(route);
        if (waitForSettlement) await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        _log('pushWidget failed: $e — attempting GoRouter fallback if mapped');
        if (_navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          final path = _mapWidgetToPath(page);
          if (path != null) {
            try {
              GoRouter.of(context).go(path);
              popResult = Future<T?>.value(null);
              return;
            } catch (e2) {
              _log('GoRouter.go fallback in pushWidget failed: $e2');
            }
          }
        }
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            popResult = root.push<T>(MaterialPageRoute<T>(builder: (_) => page));
            return;
          }
        } catch (e2) {
          _log('pushWidget root fallback failed: $e2');
        }
        rethrow;
      }
    });
    return popResult;
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
        _log('pop failed: $e — trying root fallback');
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

  /// Push and remove until predicate — widget-aware and GoRouter-friendly.
  ///
  /// Like `pushWidget`, the imperative `pushAndRemoveUntil` call returns a
  /// Future that only completes when the new route pops. We must not await
  /// that future inside `_enqueue` or the queue stays locked for the page's
  /// lifetime. We fire the call and let the queue advance immediately.
  Future<void> pushAndRemoveWidgetUntil(BuildContext context, Widget page, RoutePredicate predicate) async {
    await _enqueue<void>(() async {
      if (!context.mounted) return;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);

      try {
        // If the navigator is page-based, prefer declarative routing.
        if (_navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          _log('Navigator uses pages API — using declarative fallback for pushAndRemoveWidgetUntil');

          // Try special mapping to route path.
          final mapped = _mapWidgetToPath(page);
          if (mapped != null) {
            try {
              _log('Declarative fallback: going to $mapped');
              GoRouter.of(context).go(mapped);
              return;
            } catch (e) {
              _log('GoRouter.go fallback for mapped widget failed: $e');
              try {
                final root = appNavigatorKey.currentState;
                if (root != null) {
                  _log('Attempting root.pushNamedAndRemoveUntil for $mapped');
                  // Fire-and-forget: don't await pop lifetime.
                  root.pushNamedAndRemoveUntil(mapped, predicate);
                  return;
                }
              } catch (e2) {
                _log('Root pushNamedAndRemoveUntil fallback failed: $e2');
              }
            }
          }

          try {
            final root = appNavigatorKey.currentState;
            if (root != null) {
              root.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate);
              return;
            }
          } catch (e) {
            _log('Root navigator pushAndRemoveUntil fallback failed: $e');
          }

          final err = Exception('Cannot perform pushAndRemoveUntil on a page-based Navigator; provide a router path or use a mapped route.');
          _log(err.toString());
          throw err;
        }

        // Non page-based navigator: safe to call imperative API. Fire-and-forget.
        ns!.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate);
      } catch (e) {
        _log('pushAndRemoveWidgetUntil failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            root.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate);
            return;
          }
        } catch (e2) {
          _log('pushAndRemoveWidgetUntil fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// pushNamedAndRemoveUntil — uses Navigator if possible (kept for compatibility)
  ///
  /// Same caveat as the other push helpers: the returned future from
  /// `Navigator.pushNamedAndRemoveUntil` only completes when the new route
  /// pops. We capture it and return without blocking the chain.
  Future<T?> pushNamedAndRemoveUntil<T extends Object?>(BuildContext context, String newRouteName, RoutePredicate predicate, {Object? arguments}) async {
    Future<T?>? popResult;
    await _enqueue<void>(() async {
      if (!context.mounted) return;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        popResult = ns!.pushNamedAndRemoveUntil<T>(newRouteName, predicate, arguments: arguments);
      } catch (e) {
        _log('pushNamedAndRemoveUntil failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) {
            popResult = root.pushNamedAndRemoveUntil<T>(newRouteName, predicate, arguments: arguments);
            return;
          }
        } catch (e2) {
          _log('pushNamedAndRemoveUntil fallback failed: $e2');
        }
        rethrow;
      }
    });
    return popResult;
  }

  /// Clear internal queue to recover from catastrophic errors.
  void clearQueueForRecovery([String? reason]) {
    _log('Clearing navigation queue for recovery${reason != null ? ': $reason' : ''}');
    _chain = Future<void>.value();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isPaused = (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached);
    _log('AppLifecycle changed: $state — paused=$_isPaused');
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Small helper used by a fallback when we have a path but need to build
  // a widget (best-effort; returns a placeholder that'll be replaced by
  // the router if you use GoRouter). This avoids compile errors in
  // imperative fallback code paths that still push widgets.
  Widget _fakeWidgetForPath(String path, Object? extra) {
    try {
      if (path == '/verificationPage') return VerificationPageWidget();
      if (path == HomePageWidget.routePath) return HomePageWidget();
      if (path == DiscoverPageWidget.routePath) return DiscoverPageWidget();
      if (path == JobPostPageWidget.routePath) return JobPostPageWidget();
      if (path == BookingPageWidget.routePath) return BookingPageWidget();
      if (path == ProfileWidget.routePath) return ProfileWidget();
      return Scaffold(body: Center(child: Text('Navigating...')));
    } catch (_) {
      return Scaffold(body: Center(child: Text('Navigating...')));
    }
  }
}

