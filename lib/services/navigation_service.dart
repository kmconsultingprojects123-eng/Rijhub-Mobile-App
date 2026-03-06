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
            // try named route (strip query)
            final name = path;
            await _imperativeRetry(() async => root.pushNamedAndRemoveUntil(name, (r) => false));
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
          await _imperativeRetry(() async => ns!.push(MaterialPageRoute(builder: (_) => _fakeWidgetForPath(path, extra))));
          return null;
        } catch (e2) {
          _log('pushRoute imperative fallback also failed: $e2');
          rethrow;
        }
      }
    });
  }

  /// Replace current route with the provided widget (widget fallback).
  Future<T?> pushReplacementWidget<T extends Object?, TO extends Object?>(BuildContext context, Widget page, {TO? result}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        final res = await _imperativeRetry(() async => ns!.pushReplacement<T, TO>(MaterialPageRoute(builder: (_) => page), result: result));
        return res;
      } catch (e) {
        _log('pushReplacementWidget failed: $e');
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) return await _imperativeRetry(() async => root.pushReplacement<T, TO>(MaterialPageRoute(builder: (_) => page), result: result));
        } catch (e2) {
          _log('pushReplacementWidget fallback failed: $e2');
        }
        rethrow;
      }
    });
  }

  /// Push a widget onto the stack (kept for backward-compat).
  Future<T?> pushWidget<T extends Object?>(BuildContext context, Widget page, {bool waitForSettlement = true}) {
    return _enqueue<T?>(() async {
      if (!context.mounted) return null;
      final ns = _navigatorForContext(context);
      await _waitForNavigatorUnlocked(ns, consecutiveChecks: consecutiveUnlockChecks);
      try {
        final route = MaterialPageRoute<T>(builder: (_) => page);
        final res = await _imperativeRetry(() async => ns!.push<T>(route));
        if (waitForSettlement) await Future.delayed(const Duration(milliseconds: 250));
        return res;
      } catch (e) {
        _log('pushWidget failed: $e — attempting GoRouter fallback if mapped');
        if (_navigatorUsesPages(ns) || isUsingPagesAPI(context)) {
          final path = _mapWidgetToPath(page);
          if (path != null) {
            try {
              GoRouter.of(context).go(path);
              return null;
            } catch (e2) {
              _log('GoRouter.go fallback in pushWidget failed: $e2');
            }
          }
        }
        try {
          final root = appNavigatorKey.currentState;
          if (root != null) return await _imperativeRetry(() async => root.push<T>(MaterialPageRoute<T>(builder: (_) => page)));
        } catch (e2) {
          _log('pushWidget root fallback failed: $e2');
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
  Future<void> pushAndRemoveWidgetUntil(BuildContext context, Widget page, RoutePredicate predicate) {
    return _enqueue<void>(() async {
      if (!context.mounted) return null;
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
              return null;
            } catch (e) {
              _log('GoRouter.go fallback for mapped widget failed: $e');
              // Try named-route imperative fallback using the mapped path/name.
              try {
                final root = appNavigatorKey.currentState;
                if (root != null) {
                  _log('Attempting root.pushNamedAndRemoveUntil for $mapped');
                  await _imperativeRetry(() async => root.pushNamedAndRemoveUntil(mapped, predicate));
                  return null;
                }
              } catch (e2) {
                _log('Root pushNamedAndRemoveUntil fallback failed: $e2');
              }
            }
          }

          // If we couldn't map (or named fallback failed), attempt root imperative fallback
          // using a widget route. Note: this will fail on page-based Navigators and is
          // therefore a last-resort path; keep the informative error if it does fail.
          try {
            final root = appNavigatorKey.currentState;
            if (root != null) {
              await _imperativeRetry(() async => root.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), predicate));
              return null;
            }
          } catch (e) {
            _log('Root navigator pushAndRemoveUntil fallback failed: $e');
          }

          // Final: raise informative error to encourage using a route path.
          final err = Exception('Cannot perform pushAndRemoveUntil on a page-based Navigator; provide a router path or use a mapped route.');
          _log(err.toString());
          throw err;
        }

        // Non page-based navigator: safe to call imperative API.
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

  /// pushNamedAndRemoveUntil — uses Navigator if possible (kept for compatibility)
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

