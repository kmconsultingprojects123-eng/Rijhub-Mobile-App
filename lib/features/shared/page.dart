import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/repositories.dart';

/// A screen pushed over the tabs: a back button, a title, and the content.
/// [bottom] pins the screen's main action to the bottom edge.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.bottom,
    this.subtitle,
    this.onBack,
    this.background,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  final VoidCallback? onBack;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: background ?? c.background,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            TopBar(
                title: title,
                subtitle: subtitle,
                actions: actions,
                onBack: onBack),
            Expanded(child: body),
          ],
        ),
      ),
      // In the scaffold's own bottom slot, so toasts float above the main
      // button instead of covering it.
      bottomNavigationBar: bottom == null ? null : BottomBar(child: bottom!),
    );
  }
}

/// Back, a title (and a line under it), and up to two actions.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpace.s8, AppSpace.s4, AppSpace.s8, AppSpace.s4),
      child: SizedBox(
        height: 56.w,
        child: Row(
          children: [
            if (showBack)
              AppIconButton(
                icon: IconsaxPlusLinear.arrow_left,
                onPressed: onBack ?? () => goBack(context),
                semanticLabel: 'Back',
              )
            else
              SizedBox(width: AppSpace.s12),
            SizedBox(width: AppSpace.s4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The main action of a screen, pinned above the home indicator with a
/// hairline over it.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Placed as a scaffold's bottomNavigationBar, which stays under the
    // keyboard, so it rides up on the keyboard's height itself: a form's
    // main button stays in reach while typing.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: AppSpace.s8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.s12, AppSpace.gutter, AppSpace.s4),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Loads [load] and builds what it returns; shows [loading] (a skeleton)
/// while it waits and a calm error with "Try again" if it fails. Call the
/// `reload` the builder gets after a change.
class Loader<T> extends StatefulWidget {
  const Loader({
    super.key,
    required this.load,
    required this.builder,
    this.loading,
    this.reloadOn,
  });

  final Future<T> Function() load;
  final Widget Function(
      BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? loading;

  /// Reloads whenever this changes (the session, an area).
  final Listenable? reloadOn;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();
  T? _last;

  @override
  void initState() {
    super.initState();
    widget.reloadOn?.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadOn != widget.reloadOn) {
      old.reloadOn?.removeListener(_reload);
      widget.reloadOn?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.reloadOn?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final next = widget.load();
    // A block body: setState must not be handed a closure that returns
    // the Future.
    setState(() {
      _future = next;
    });
  }

  Future<void> reload() {
    final next = widget.load();
    setState(() {
      _future = next;
    });
    return next.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          _last = snap.data;
          return widget.builder(context, snap.data as T, reload);
        }
        if (snap.hasError) {
          final last = _last;
          // Keep showing what we had if a refresh failed.
          if (last != null) return widget.builder(context, last, reload);
          final error = Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.gutter),
              child: InlineError(
                message: snap.error is AppException
                    ? snap.error.toString()
                    : "We couldn't load this. Check your connection and try again.",
                onRetry: reload,
              ),
            ),
          );
          // On a page of its own, give it a page and a way back.
          if (Scaffold.maybeOf(context) == null) {
            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const TopBar(title: ''),
                    Expanded(child: error),
                  ],
                ),
              ),
            );
          }
          return error;
        }
        final last = _last;
        if (last != null) return widget.builder(context, last, reload);
        return widget.loading ?? const ListSkeleton();
      },
    );
  }
}

/// Grey rows while a list loads.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 5, this.leading = 52});

  final int rows;
  final double leading;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(AppSpace.gutter),
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpace.s20),
              child: Row(
                children: [
                  SkeletonBox(
                      width: leading.w, height: leading.w, radius: 14.w),
                  SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 180.w, height: 14.w),
                        SizedBox(height: AppSpace.s8),
                        SkeletonBox(width: 120.w, height: 12.w),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Runs [action] with a spinner on the caller's button and turns failures
/// into a short message at the bottom. Returns the result, or null when it
/// failed.
Future<T?> runAction<T>(
    BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on AppException catch (e) {
    if (context.mounted) showToast(context, e.message, error: true);
  } on Object {
    if (context.mounted) {
      showToast(context,
          "That didn't go through. Check your connection and try again.",
          error: true);
    }
  }
  return null;
}

/// A short message at the bottom of the screen.
/// Leaves a page: back to where it was opened from, with [result]. A page
/// opened straight from a link or a notice has nothing under it, so it goes
/// to the page above it in the app (the wallet for "Withdraw", a job for
/// its quote), or home.
void goBack(BuildContext context, [Object? result]) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop(result);
    return;
  }
  final router = GoRouter.of(context);
  final segments = router.routerDelegate.currentConfiguration.uri.pathSegments;
  for (var n = segments.length - 1; n > 0; n--) {
    final parent = Uri(path: '/${segments.take(n).join('/')}');
    if (router.configuration.findMatch(parent).isNotEmpty) {
      router.go(parent.toString());
      return;
    }
  }
  router.go('/home');
}

/// A context that outlives the page: the app navigator's. For work that
/// ends after the widget that started it is gone (signing in or out swaps
/// the Profile tab under it), to navigate and show a toast from.
BuildContext appContext(BuildContext context) =>
    GoRouter.of(context).routerDelegate.navigatorKey.currentContext ?? context;

void showToast(BuildContext context, String message, {bool error = false}) {
  final c = context.colors;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceStrong,
        margin: EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s16),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(
              error
                  ? IconsaxPlusLinear.info_circle
                  : IconsaxPlusBold.tick_circle,
              size: 20.w,
              color: error ? c.warningOnStrong : c.successOnStrong,
            ),
            SizedBox(width: AppSpace.s12),
            Expanded(
              child: Text(
                message,
                style: AppText.bodySmall.copyWith(color: c.onSurfaceStrong),
              ),
            ),
          ],
        ),
      ),
    );
}

/// A titled group in a settings-style list.
/// A short list to pick one from, in a sheet. Null when dismissed.
/// Options that [enabled] rejects show greyed out.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  T? selected,
  bool Function(T value)? enabled,
}) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: c.surface,
    builder: (context) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, 4.w),
            child: Text(title, style: AppText.headline),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s16),
              children: [
                for (final (value, label) in options)
                  Builder(builder: (context) {
                    final on = enabled?.call(value) ?? true;
                    final picked = value == selected;
                    return Semantics(
                      button: true,
                      enabled: on,
                      selected: picked,
                      label: label,
                      excludeSemantics: true,
                      child: InkWell(
                        onTap:
                            on ? () => Navigator.of(context).pop(value) : null,
                        child: Container(
                          height: 50.w,
                          decoration: BoxDecoration(
                              border:
                                  Border(bottom: BorderSide(color: c.border))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: (picked
                                          ? AppText.titleSmall
                                          : AppText.bodyLarge)
                                      .copyWith(
                                          color: on
                                              ? c.textPrimary
                                              : c.textTertiary),
                                ),
                              ),
                              if (picked)
                                Icon(IconsaxPlusBold.tick_circle,
                                    size: 20.w, color: c.brandStroke),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, 0, AppSpace.gutter, AppSpace.s8),
              child: Text(
                title!,
                style: AppText.labelSmall.copyWith(color: c.textSecondary),
              ),
            ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18.w),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1, thickness: 1, color: c.border, indent: 56.w),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in a [SettingsGroup]: an icon, a label, a value or a switch,
/// and a chevron when it opens something.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? c.error : c.textPrimary;
    final row = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpace.s16, vertical: AppSpace.s12),
      child: Row(
        children: [
          Icon(icon, size: 22.w, color: danger ? c.error : c.textSecondary),
          SizedBox(width: AppSpace.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppText.body
                        .copyWith(color: fg, fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Padding(
                    padding: EdgeInsets.only(top: 2.w),
                    child: Text(subtitle!,
                        style:
                            AppText.bodySmall.copyWith(color: c.textSecondary)),
                  ),
              ],
            ),
          ),
          if (value != null)
            Padding(
              padding: EdgeInsets.only(left: AppSpace.s8),
              child: Text(value!,
                  style: AppText.bodySmall.copyWith(color: c.textSecondary)),
            ),
          if (trailing != null) trailing!,
          if (trailing == null && onTap != null) ...[
            SizedBox(width: AppSpace.s4),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 18.w, color: c.textTertiary),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return ConstrainedBox(
          constraints: BoxConstraints(minHeight: 56.w), child: row);
    }
    return Pressable(
      onTap: onTap,
      pressedScale: 1,
      focusOffset: 0,
      semanticLabel: value == null ? label : '$label, $value',
      child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 56.w), child: row),
    );
  }
}

/// Keeps [child] up to date with a stream of counts (unread messages, new
/// notifications), starting from none.
class CountStream extends StatelessWidget {
  const CountStream({super.key, required this.stream, required this.builder});

  final Stream<int> stream;
  final Widget Function(BuildContext context, int count) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: stream,
        builder: (context, snap) => builder(context, snap.data ?? 0),
      );
}

/// Waits [duration], or not at all when tests run without timers.
Future<void> pause(Duration duration) => Future<void>.delayed(duration);

/// Keeps [future] from being dropped silently.
void unawaitedSafe(Future<void> future) => unawaited(future.catchError((_) {}));
