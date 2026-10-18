import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

import '../../app/auth_gate.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/images.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../bookings/bookings_tab.dart';
import '../shared/page.dart';

/// Conversations with artisans (or clients), newest first, with RijHub
/// itself pinned on top.
class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabTitle('Messages'),
            Expanded(
              child: session.isGuest
                  ? Center(
                      child: EmptyState(
                        icon: IconsaxPlusLinear.message,
                        title: 'Chat with your artisans',
                        message:
                            'Once you book, you can message, send photos and voice notes, and call through RijHub.',
                        action: AppButton(
                          label: 'Sign in',
                          expand: false,
                          onPressed: () => context
                              .read<AuthGate>()
                              .ensureSignedIn(context, AuthPrompt.messages),
                        ),
                      ),
                    )
                  : Loader<List<Conversation>>(
                      reloadOn: session,
                      load: () =>
                          context.read<ChatRepository>().conversations(),
                      builder: (context, list, reload) => RefreshIndicator(
                        color: c.brandStroke,
                        onRefresh: reload,
                        child: ListView(
                          padding:
                              EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                          children: [
                            _RijHubRow(
                                artisan: session.role == UserRole.artisan),
                            for (final (i, convo) in list.indexed)
                              ConversationRow(
                                conversation: convo,
                                divider: i < list.length - 1,
                                onTap: () async {
                                  await context.push(Routes.chat(convo.id));
                                  await reload();
                                },
                              ),
                            if (list.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 60.w),
                                child: const EmptyState(
                                  icon: IconsaxPlusLinear.message,
                                  title: 'No messages yet',
                                  message:
                                      'When you book or ask an artisan for a price, your conversation shows here.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RijHubRow extends StatelessWidget {
  const _RijHubRow({required this.artisan});

  final bool artisan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: () => context.push(artisan ? Routes.support : Routes.ask),
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel: artisan ? 'RijHub help' : 'Ask RijHub',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.w),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(
          children: [
            const RijHubAvatar(size: 52),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RijHub',
                      style: AppText.titleSmall
                          .copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2.w),
                  Text(
                    artisan
                        ? 'Help with your jobs, pay and account'
                        : 'Tell me what needs fixing',
                    style: AppText.bodySmall.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_right_3,
                size: 18.w, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class ConversationRow extends StatelessWidget {
  const ConversationRow(
      {super.key,
      required this.conversation,
      required this.onTap,
      this.divider = true});

  final Conversation conversation;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final convo = conversation;
    final last = convo.lastMessage;
    final unread = convo.unread > 0;
    final preview = last == null
        ? (convo.subtitle ?? '')
        // A booking's own notes ("Booking confirmed…") aren't anyone's words.
        : '${last.fromMe && last.kind != MessageKind.system ? 'You: ' : ''}${last.preview}';
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      focusOffset: 0,
      semanticLabel:
          '${convo.title}${unread ? ', ${convo.unread} unread' : ''}. $preview',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.w),
        decoration: BoxDecoration(
            border:
                divider ? Border(bottom: BorderSide(color: c.border)) : null),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(
                    name: convo.title,
                    image: imageFor(convo.photo),
                    size: 52.w),
                if (convo.online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14.w,
                      height: 14.w,
                      decoration: BoxDecoration(
                        color: c.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(convo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.titleSmall
                                .copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        RelativeTime.short(convo.updatedAt),
                        style: AppText.caption.copyWith(
                            color: unread ? c.brandText : c.textTertiary),
                      ),
                    ],
                  ),
                  if (convo.subtitle != null)
                    Text(convo.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: c.textTertiary)),
                  SizedBox(height: 2.w),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: unread ? c.textPrimary : c.textSecondary,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        SizedBox(width: 8.w),
                        CountBadge(convo.unread)
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
