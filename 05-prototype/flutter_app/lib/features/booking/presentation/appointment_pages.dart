import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/booking_providers.dart';
import '../domain/booking_models.dart';
import 'booking_format.dart';

class AppointmentsPage extends ConsumerWidget {
  const AppointmentsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(appointmentsProvider).records;
    return AppPageBody(
      title: 'Lịch hẹn',
      onBack: () => AppRoutes.backOrHome(context),
      children: [
        if (records.isEmpty)
          const AppEmptyState(
            title: 'Chưa có lịch hẹn',
            message: 'Các lịch khám của bạn sẽ xuất hiện tại đây.',
          ),
        for (final group in [
          (
            title: 'Đã xác nhận',
            records: records.where(
              (record) => record.receipt.status == PaymentStatus.confirmed,
            ),
          ),
          (
            title: 'Đang xử lý',
            records: records.where((record) => record.receipt.unresolved),
          ),
          (
            title: 'Chưa hoàn tất',
            records: records.where(
              (record) => record.receipt.status == PaymentStatus.failed,
            ),
          ),
        ])
          if (group.records.isNotEmpty) ...[
            Text(group.title, style: Theme.of(context).textTheme.titleLarge),
            for (final record in group.records)
              AppLinkCard(
                title: record.visit.patientName,
                subtitle:
                    '${record.receipt.status.label}\n${bookingDate(record.visit.date)} · ${record.visit.time}',
                icon: AppIcons.calendar,
                onTap: () =>
                    context.push(AppRoutes.appointment(record.visit.id)),
              ),
          ],
      ],
    );
  }
}

class AppointmentDetailPage extends StatelessWidget {
  const AppointmentDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => AppPageBody(
    title: 'Chi tiết lịch hẹn',
    onBack: () => AppRoutes.backOrHome(context),
    children: [AppointmentRecordView(id: id)],
  );
}

class AppointmentRecordView extends ConsumerWidget {
  const AppointmentRecordView({super.key, required this.id, this.onRetry});
  final String id;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(appointmentsProvider);
    final record = ledger.records
        .where((record) => record.visit.id == id)
        .firstOrNull;
    if (record == null) {
      return const AppEmptyState(
        title: 'Không tìm thấy lịch hẹn',
        message: 'Vui lòng quay lại danh sách lịch hẹn.',
      );
    }
    final visit = record.visit;
    final receipt = record.receipt;
    final status = switch (receipt.status) {
      PaymentStatus.confirmed => AppStatus.success,
      PaymentStatus.failed => AppStatus.error,
      _ => AppStatus.warning,
    };
    final paymentLabel = switch (receipt.status) {
      PaymentStatus.failed => 'Bạn chưa bị trừ tiền',
      PaymentStatus.checking => 'Chưa xác định — vui lòng không thanh toán lại',
      _ =>
        receipt.method == PayMethod.atHospital
            ? 'Chưa thanh toán — trả tại viện'
            : 'Đã thanh toán',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTicketCard(
          title: receipt.status.label,
          status: status,
          reference: receipt.appointmentCode != null
              ? 'Mã lịch: ${receipt.appointmentCode}'
              : receipt.transactionCode != null
              ? 'Mã giao dịch: ${receipt.transactionCode}'
              : 'Chưa tạo lịch hẹn',
          details: [
            (label: 'Người khám', value: visit.patientName),
            (label: 'Hình thức', value: visit.type.label),
            (
              label: 'Ngày và giờ hẹn',
              value: '${bookingDate(visit.date)} · ${visit.time}',
            ),
            (
              label: 'Nơi khám',
              value: '${visit.facilityName}\n${visit.address}',
            ),
            (label: 'Chuyên khoa', value: visit.departmentName),
            (label: 'Bác sĩ', value: visit.doctorName),
            (
              label: visit.type == VisitType.insurance
                  ? 'Phí đặt lịch'
                  : 'Phí khám dự kiến',
              value: bookingMoney(visit.fee),
            ),
            (label: 'Thanh toán', value: paymentLabel),
            (
              label: 'Nhận thông báo',
              value: '${visit.contactName} · ${visit.contactPhone}',
            ),
            if (visit.note.isNotEmpty) (label: 'Ghi chú', value: visit.note),
          ],
        ),
        const SizedBox(height: 16),
        if (visit.type == VisitType.insurance)
          const AppStatusBanner(
            message: 'Quyền lợi BHYT và khoản cần thanh toán sẽ được cơ sở xác nhận. Phí đặt lịch 0đ không có nghĩa là miễn toàn bộ chi phí khám.',
          ),
        if (receipt.status == PaymentStatus.confirmed)
          const AppStatusBanner(
            message: 'Mang theo giấy tờ tùy thân và giấy tờ BHYT nếu chọn khám BHYT. Giờ hẹn có thể khác thời điểm thực tế được bác sĩ khám.',
          ),
        if (receipt.unresolved) ...[
          const AppStatusBanner(
            status: AppStatus.warning,
            message: 'Vui lòng không thanh toán lại. Bạn có thể về Lịch hẹn và kiểm tra trạng thái sau.',
          ),
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: 'Kiểm tra trạng thái',
            isLoading: ledger.checking.contains(id),
            onPressed: () => ref.read(appointmentsProvider.notifier).check(id),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.help),
            child: const Text('Trợ giúp'),
          ),
        ],
        if (ledger.errors[id] != null)
          AppStatusBanner(
            status: AppStatus.error,
            message: ledger.errors[id]!,
            liveRegion: true,
          ),
        if (receipt.status == PaymentStatus.failed) ...[
          const AppStatusBanner(
            status: AppStatus.error,
            message: 'Bạn chưa bị trừ tiền và chưa có lịch khám được xác nhận.',
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            AppPrimaryButton(
              label: 'Thử lại hoặc đổi cách thanh toán',
              onPressed: onRetry,
            ),
          ],
        ],
      ],
    );
  }
}
