import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(notificationFeedProvider);
    final unread = ref.watch(unreadCountProvider);
    return AppPageBody(
      title: 'Thông báo',
      children: [
        if (notices.isEmpty)
          const AppEmptyState(
            title: 'Chưa có thông báo',
            message: 'Thông báo mới sẽ được hiển thị tại đây.',
            icon: AppIcons.notifications,
          )
        else ...[
          Text(
            unread == 0
                ? 'Bạn đã đọc tất cả thông báo'
                : '$unread thông báo chưa đọc',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (unread > 0)
            OutlinedButton(
              onPressed: () =>
                  ref.read(notificationFeedProvider.notifier).markAllRead(),
              child: const Text(
                'Đánh dấu tất cả đã đọc',
                textAlign: TextAlign.center,
              ),
            ),
          for (final notice in notices)
            AppLinkCard(
              title: notice.title,
              subtitle: notice.isRead ? 'Đã đọc' : 'Chưa đọc',
              icon: AppIcons.notifications,
              tone: notice.isRead ? AppTone.teal : AppTone.peach,
              onTap: () => context.push(AppRoutes.notice(notice.id)),
            ),
        ],
      ],
    );
  }
}

class NotificationDetailPage extends ConsumerStatefulWidget {
  const NotificationDetailPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<NotificationDetailPage> createState() =>
      _NotificationDetailPageState();
}

class _NotificationDetailPageState
    extends ConsumerState<NotificationDetailPage> {
  @override
  void initState() {
    super.initState();
    _markReadAfterBuild();
  }

  @override
  void didUpdateWidget(covariant NotificationDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _markReadAfterBuild();
  }

  void _markReadAfterBuild() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(notificationFeedProvider.notifier).markRead(widget.id);
        }
      });

  @override
  Widget build(BuildContext context) {
    final matches = ref
        .watch(notificationFeedProvider)
        .where((notice) => notice.id == widget.id);
    return AppPageBody(
      title: 'Chi tiết thông báo',
      onBack: () => AppRoutes.backOrHome(context),
      children: [
        if (matches.isEmpty)
          const AppEmptyState(
            title: 'Không tìm thấy thông báo',
            message: 'Vui lòng quay lại danh sách thông báo.',
          )
        else
          AppReviewSection(
            title: matches.first.title,
            items: [(label: 'Nội dung', value: matches.first.message)],
          ),
      ],
    );
  }
}
