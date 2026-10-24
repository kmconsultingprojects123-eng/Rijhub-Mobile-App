import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/live_updates.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../shared/page.dart';

/// Updates about bookings, quotes, messages and money, newest first. Each
/// one opens what it is about.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NoticeKind? _filter;
  final _readNow = <String>{};

  static const _filters = [
    (null, 'All'),
    (NoticeKind.booking, 'Bookings'),
    (NoticeKind.quote, 'Quotes'),
    (NoticeKind.message, 'Messages'),
    (NoticeKind.payment, 'Payments'),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NoticeRepository>();
    return Loader<List<AppNotice>>(
      reloadOn: context.read<LiveUpdates>(),
      load: repo.notices,
      loading: const PageScaffold(
          title: 'Notifications', body: ListSkeleton(leading: 44)),
      builder: (context, all, reload) {
        final unread =
            all.where((n) => !n.read && !_readNow.contains(n.id)).length;
        final shown =
            all.where((n) => _filter == null || n.kind == _filter).toList();
        final now = DateTime.now();
        final today =
            shown.where((n) => now.difference(n.at).inHours < 24).toList();
        final earlier =
            shown.where((n) => now.difference(n.at).inHours >= 24).toList();
        return PageScaffold(
          title: 'Notifications',
          subtitle: unread == 0 ? "You're all caught up" : '$unread new',
          actions: [
            if (unread > 0)
              AppButton(
                label: 'Mark all read',
                variant: AppButtonVariant.tertiary,
                size: AppButtonSize.small,
                expand: false,
                onPressed: () async {
                  await repo.markAllRead();
                  setState(() => _readNow.addAll(all.map((n) => n.id)));
                },
              ),
          ],
          body: RefreshIndicator(
            color: context.colors.brandStroke,
            onRefresh: reload,
            child: ListView(
              children: [
                ChipRow(children: [
                  for (final (kind, label) in _filters)
                    PromptChip(
                        label: label,
                        solid: _filter == kind,
                        onTap: () => setState(() => _filter = kind)),
                ]),
                if (shown.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 80.w),
                    child: const EmptyState(
                      icon: IconsaxPlusLinear.notification,
                      title: 'Nothing here',
                      message:
                          'Updates about your bookings, quotes and payments show here.',
                    ),
                  ),
                if (today.isNotEmpty)
                  _Group(
                      title: 'Today',
                      notices: today,
                      readNow: _readNow,
                      onOpen: _open),
                if (earlier.isNotEmpty)
                  _Group(
                      title: 'Earlier',
                      notices: earlier,
                      readNow: _readNow,
                      onOpen: _open),
                SizedBox(height: 24.w),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(AppNotice n) async {
    await context.read<NoticeRepository>().markRead(n.id);
    setState(() => _readNow.add(n.id));
    final route = n.route;
    if (route == null || !mounted) return;
    const tabs = ['/home', '/explore', '/bookings', '/messages'];
    if (tabs.any(route.startsWith)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }
}

class _Group extends StatelessWidget {
  const _Group(
      {required this.title,
      required this.notices,
      required this.readNow,
      required this.onOpen});

  final String title;
  final List<AppNotice> notices;
  final Set<String> readNow;
  final ValueChanged<AppNotice> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 12.w, bottom: 4.w),
            child: Text(title,
                style: AppText.labelSmall.copyWith(color: c.textSecondary)),
          ),
          for (final n in notices)
            NoticeRow(
                notice: n,
                unread: !n.read && !readNow.contains(n.id),
                onTap: () => onOpen(n)),
        ],
      ),
    );
  }
}

class NoticeRow extends StatelessWidget {
  const NoticeRow(
      {super.key,
      required this.notice,
      required this.unread,
      required this.onTap});

  final AppNotice notice;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, fg, bg) = switch (notice.kind) {
      NoticeKind.booking => (
          IconsaxPlusLinear.calendar_tick,
          c.info,
          c.infoSubtle
        ),
      NoticeKind.quote => (
          IconsaxPlusLinear.receipt_2,
          c.brandText,
          c.brandSubtle
        ),
      NoticeKind.message => (
          IconsaxPlusLinear.message,
          c.textPrimary,
          c.surfaceMuted
        ),
      NoticeKind.payment => (
          IconsaxPlusLinear.wallet_2,
          c.success,
          c.successSubtle
        ),
      NoticeKind.review => (
          IconsaxPlusLinear.star_1,
          c.warning,
          c.warningSubtle
        ),
      NoticeKind.account => (
          IconsaxPlusLinear.verify,
          c.verified,
          c.verifiedSubtle
        ),
      NoticeKind.news => (
          IconsaxPlusLinear.notification,
          c.textPrimary,
          c.surfaceMuted
        ),
    };
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${unread ? 'New. ' : ''}${notice.title}. ${notice.body}. ${RelativeTime.spoken(notice.at)}',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.w),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(14.w)),
              child: Icon(icon, size: 20.w, color: fg),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notice.title,
                          style: AppText.titleSmall.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w600),
                        ),
                      ),
                      Text(RelativeTime.short(notice.at),
                          style:
                              AppText.caption.copyWith(color: c.textTertiary)),
                    ],
                  ),
                  SizedBox(height: 2.w),
                  Text(
                    notice.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (unread) ...[
              SizedBox(width: 8.w),
              Padding(
                padding: EdgeInsets.only(top: 6.w),
                child: Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                      color: c.brandStroke, shape: BoxShape.circle),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
