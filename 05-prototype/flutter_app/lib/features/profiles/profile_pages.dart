import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../visit_prep/visit_prep_widgets.dart';
import 'cccd_qr.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profileCatalogProvider);
    final active = ref.watch(activeProfileProvider);
    return AppPageBody(
      title: 'Hồ sơ',
      onHelp: () => context.push(AppRoutes.help),
      children: [
        Text('Hồ sơ gia đình', style: Theme.of(context).textTheme.titleLarge),
        for (final profile in profiles)
          AppChoiceCard(
            key: ValueKey('profile-${profile.id}'),
            title: profile.name,
            description:
                '${profile.relationship} · Sinh năm ${profile.birthYear}',
            icon: AppIcons.person,
            tone: AppTone.lavender,
            selected: active.id == profile.id,
            onTap: () =>
                ref.read(activeProfileIdProvider.notifier).select(profile.id),
          ),
        if (profiles.length < 2)
          const AppSurface(
            key: Key('profiles-family-hint'),
            child: Column(
              children: [
                AppIllustration(AppArt.family, height: 110),
                SizedBox(height: 12),
                Text(
                  'Thêm bố mẹ, vợ chồng hoặc con để đặt khám và nhận nhắc lịch '
                  'giúp cả nhà.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        AppLinkCard(
          key: const Key('profiles-add'),
          title: 'Thêm hồ sơ người thân',
          subtitle: 'Quét mã QR trên CCCD để điền nhanh',
          icon: AppIcons.qr,
          tone: AppTone.peach,
          onTap: () => context.push(AppRoutes.addProfile(self: false)),
        ),
        AppLinkCard(
          title: 'Xem hồ sơ đang chọn',
          subtitle: active.name,
          icon: AppIcons.profile,
          onTap: () => context.push(AppRoutes.profile(active.id)),
        ),
      ],
    );
  }
}

class ProfileDetailPage extends ConsumerWidget {
  const ProfileDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref
        .watch(profileCatalogProvider)
        .where((profile) => profile.id == id);
    return AppPageBody(
      title: 'Chi tiết hồ sơ',
      onBack: () => AppRoutes.backOrHome(context),
      children: [
        if (matches.isEmpty)
          const AppEmptyState(
            title: 'Không tìm thấy hồ sơ',
            message: 'Vui lòng quay lại danh sách hồ sơ.',
          )
        else
          AppReviewSection(
            title: matches.first.name,
            items: [
              if (matches.first.birthDate case final date?)
                (
                  label: 'Ngày sinh',
                  value:
                      '${date.day.toString().padLeft(2, '0')}/'
                      '${date.month.toString().padLeft(2, '0')}/${date.year}',
                )
              else
                (label: 'Năm sinh', value: '${matches.first.birthYear}'),
              if (matches.first.gender case final gender?)
                (label: 'Giới tính', value: gender),
              (label: 'Quan hệ', value: matches.first.relationship),
              if (matches.first.idNumber case final id?)
                (label: 'Số CCCD', value: maskIdNumber(id)),
              if (matches.first.address case final address?)
                (label: 'Địa chỉ', value: address),
            ],
          ),
        if (matches.isNotEmpty)
          ProfileConditionsEditor(
            key: const Key('profile-conditions'),
            selected: matches.first.conditions,
            onChanged: (value) => ref
                .read(profileCatalogProvider.notifier)
                .setConditions(id, value),
          ),
      ],
    );
  }
}
