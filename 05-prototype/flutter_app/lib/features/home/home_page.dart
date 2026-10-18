import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_widgets.dart';
import '../booking/application/booking_providers.dart';
import '../booking/presentation/booking_format.dart';
import '../consent/health_consent_page.dart';
import '../meds/presentation/today_meds_page.dart';
import '../booking/domain/booking_models.dart';
import '../visit_prep/visit_prep_widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref
        .watch(appointmentsProvider)
        .records
        .where((record) => record.receipt.status != PaymentStatus.failed)
        .toList();
    final account = ref.watch(profileCatalogProvider).first;
    return SingleChildScrollView(
      key: const PageStorageKey('home-scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBrandHeader(
            title: 'MedicApp',
            subtitle: 'Đặt khám dễ dàng cho cả nhà',
            onHelp: () => context.push(AppRoutes.help),
            child: Text(
              'Xin chào,\n${account.name}',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
          Stack(
            children: [
              Container(
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: AppSurface(
                  key: const Key('home-booking-card'),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppIconTile(icon: AppIcons.calendar),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Đặt lịch khám',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppPrimaryButton(
                        label: 'Bắt đầu',
                        onPressed: () => context.push(AppRoutes.booking),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('home-smart'),
                        onPressed: () => context.push(AppRoutes.smart),
                        icon: const AppIcon(AppIcons.smart),
                        label: const Text('Đặt lịch thông minh'),
                      ),
                    ],
                  ),
                ).entrance(context),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HealthConsentPrompt(),
                const HomePrepBanner(),
                const HomeMedsCard(),
                Semantics(
                  header: true,
                  child: Text(
                    'Lịch hẹn sắp tới',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                if (records.isEmpty)
                  const AppEmptyState(
                    title: 'Chưa có lịch hẹn',
                    message: 'Bấm “Bắt đầu” ở trên để đặt lịch khám đầu tiên.',
                    art: AppArt.emptyCalendar,
                  ).entrance(context, order: 1)
                else
                  for (final (index, record) in records.take(2).indexed)
                    AppLinkCard(
                      title: record.visit.patientName,
                      subtitle:
                          '${bookingDate(record.visit.date)} · ${record.visit.time} · ${record.receipt.unresolved ? 'Chờ xác nhận' : 'Đã đặt lịch'}',
                      icon: AppIcons.calendar,
                      onTap: () =>
                          context.push(AppRoutes.appointment(record.visit.id)),
                    ).entrance(context, order: 1 + index),
                const SizedBox(height: 16),
                AppLinkCard(
                  title: 'Lịch hẹn',
                  icon: AppIcons.calendar,
                  tone: AppTone.lavender,
                  onTap: () => context.push(AppRoutes.appointments),
                ),
                const SizedBox(height: 12),
                AppLinkCard(
                  key: const Key('home-facility-map'),
                  title: 'Cơ sở khám gần bạn',
                  subtitle: 'Xem bệnh viện, phòng khám trên bản đồ',
                  icon: AppIcons.map,
                  tone: AppTone.sky,
                  onTap: () => context.push(AppRoutes.facilityMap),
                ),
                const SizedBox(height: 12),
                AppLinkCard(
                  title: 'Trợ giúp',
                  icon: AppIcons.help,
                  tone: AppTone.peach,
                  onTap: () => context.push(AppRoutes.help),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
