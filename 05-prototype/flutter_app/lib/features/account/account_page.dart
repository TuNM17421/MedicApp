import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/auth_controller.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(profileCatalogProvider).first;
    final phone = ref.watch(authSessionProvider);
    return AppPageBody(
      title: 'Tài khoản',
      children: [
        AppReviewSection(
          title: 'Thông tin tài khoản',
          items: [
            (label: 'Họ và tên', value: account.name),
            if (phone != null)
              (label: 'Số điện thoại đăng nhập', value: formatPhone(phone)),
          ],
        ),
        AppLinkCard(
          title: 'Trợ giúp',
          icon: AppIcons.help,
          onTap: () => context.push(AppRoutes.help),
        ),
        if (phone != null)
          OutlinedButton.icon(
            key: const Key('account-sign-out'),
            onPressed: () => _confirmSignOut(context, ref),
            icon: const AppIcon(AppIcons.signOut),
            label: const Text('Đăng xuất'),
          ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất khỏi MedicApp?'),
        content: const Text(
          'Bạn cần nhập lại số điện thoại và mật khẩu để vào lại.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(authSessionProvider.notifier).signOut();
  }
}
