import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/auth_controller.dart';
import '../consent/health_consent.dart';
import '../family/presentation/family_pages.dart';

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
        if (phone != null) const _HealthDataSection(),
        if (phone != null && familyLinkingOn(ref)) const MemberLinksSection(),
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
    if (confirmed != true || !context.mounted) return;
    // Messages for the old session must not cover the welcome buttons.
    ScaffoldMessenger.of(context).clearSnackBars();
    ref.read(authSessionProvider.notifier).signOut();
  }
}

class _HealthDataSection extends ConsumerWidget {
  const _HealthDataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(healthConsentProvider);
    final text = Theme.of(context).textTheme;
    return AppSurface(
      key: const Key('account-health-data'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dữ liệu sức khỏe', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            consent == null
                ? 'Chưa lưu trên máy này. Hồ sơ sẽ mất khi đóng app.'
                : 'Đang lưu trên máy này (đã mã hóa) từ ${DateFormat('dd/MM/yyyy').format(consent.acceptedAt)}.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 12),
          if (consent == null)
            FilledButton.icon(
              key: const Key('account-consent-open'),
              onPressed: () => context.push(AppRoutes.healthConsent),
              icon: const AppIcon(AppIcons.lock, color: Colors.white),
              label: const Text('Lưu trên máy này'),
            )
          else
            OutlinedButton(
              key: const Key('account-consent-withdraw'),
              onPressed: () => _confirmWithdraw(context, ref),
              child: const Text('Ngừng lưu và xóa khỏi máy'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmWithdraw(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngừng lưu dữ liệu sức khỏe?'),
        content: const Text(
          'Hồ sơ trên máy này sẽ bị xóa. Bạn vẫn dùng được app cho đến khi đóng app.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngừng lưu'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(authSessionProvider.notifier).setConsent(null);
  }
}
