import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/booking_providers.dart';
import '../domain/booking_models.dart';

/// A separate reviewer surface. Not part of the patient booking workflow.
class BookingDemoPage extends ConsumerWidget {
  const BookingDemoPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(demoOptionsProvider);
    void update({
      DemoOutcome? outcome,
      bool? networkError,
      bool? slotTaken,
      bool? facilityConfirmed,
    }) => ref
        .read(demoOptionsProvider.notifier)
        .set(
          DemoOptions(
            outcome: outcome ?? options.outcome,
            networkError: networkError ?? options.networkError,
            slotTaken: slotTaken ?? options.slotTaken,
            facilityConfirmed: facilityConfirmed ?? options.facilityConfirmed,
          ),
        );
    return Scaffold(
      body: AppPageBody(
        title: 'Kịch bản thử nghiệm',
        onBack: () => AppRoutes.backOrHome(context),
        children: [
          const AppStatusBanner(
            message: 'Chỉ mô phỏng, không kết nối ngân hàng hay bệnh viện. Chọn kịch bản rồi bắt đầu lượt đặt mới. Kết quả thanh toán áp dụng cho ví/thẻ; trả tại viện xác nhận mà không trừ tiền.',
          ),
          for (final item in [
            (value: DemoOutcome.success, label: 'Thanh toán thành công'),
            (
              value: DemoOutcome.failure,
              label: 'Thất bại lần đầu, thử lại thành công',
            ),
            (
              value: DemoOutcome.unknown,
              label: 'Mất kết nối — kiểm tra hai lần để xác nhận',
            ),
            (
              value: DemoOutcome.paidUnconfirmed,
              label: 'Đã trả tiền, cơ sở chưa xác nhận lịch',
            ),
          ])
            AppChoiceCard(
              title: item.label,
              selected: options.outcome == item.value,
              onTap: () => update(outcome: item.value),
            ),
          SwitchListTile(
            title: const Text('Lỗi tải giờ một lần mỗi lượt đặt'),
            value: options.networkError,
            onChanged: (value) => update(networkError: value),
          ),
          SwitchListTile(
            title: const Text('Giờ vừa hết khi kiểm tra trước thanh toán'),
            value: options.slotTaken,
            onChanged: (value) => update(slotTaken: value),
          ),
          SwitchListTile(
            title: const Text('Cơ sở đã xác nhận các lịch đang chờ'),
            value: options.facilityConfirmed,
            onChanged: (value) => update(facilityConfirmed: value),
          ),
        ],
      ),
    );
  }
}
