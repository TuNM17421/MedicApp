import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../core/widgets/app_widgets.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(profileCatalogProvider).first;
    return AppPageBody(
      title: 'Tài khoản',
      children: [
        AppReviewSection(
          title: 'Thông tin tài khoản',
          items: [(label: 'Họ và tên', value: account.name)],
        ),
        AppLinkCard(
          title: 'Trợ giúp',
          icon: AppIcons.help,
          onTap: () => context.push(AppRoutes.help),
        ),
      ],
    );
  }
}
