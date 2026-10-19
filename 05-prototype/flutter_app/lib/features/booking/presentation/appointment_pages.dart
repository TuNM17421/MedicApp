import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/booking_providers.dart';
import '../domain/booking_models.dart';
import 'booking_format.dart';
import '../../visit_prep/visit_prep.dart' show visitStart;
import '../../visit_prep/visit_prep_widgets.dart';
import '../../records/presentation/visit_result_pages.dart';
import '../../sharing/application/sharing_providers.dart';
import '../../sharing/domain/sharing_models.dart';
import '../../sharing/presentation/clinic_sharing_pages.dart';
import '../../visit_prep/previsit_questions.dart';

class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  /// Only appointments on this day are listed; null lists them all.
  DateTime? _day;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(appointmentsProvider).records;
    final clinic = ref.watch(serverAppointmentsProvider);
    final now = ref.watch(sharingClockProvider)();
    final records = [
      for (final record in all)
        if (_day == null || isSameDay(record.visit.date, _day)) record,
    ]..sort((a, b) => visitStart(a.visit).compareTo(visitStart(b.visit)));
    return AppPageBody(
      title: 'Lịch hẹn',
      onBack: () => AppRoutes.backOrHome(context),
      children: [
        if (all.isNotEmpty)
          AppointmentsCalendar(
            today: ref.watch(bookingTodayProvider),
            selected: _day,
            visitDays: [
              for (final record in all)
                if (record.receipt.status != PaymentStatus.failed)
                  record.visit.date,
            ],
            onSelected: (day) => setState(
              () => _day = _day != null && isSameDay(_day, day) ? null : day,
            ),
          ),
        if (_day case final day?)
          Row(
            children: [
              Expanded(
                child: Text(
                  records.isEmpty
                      ? 'Không có lịch hẹn ngày ${bookingDate(day)}'
                      : 'Lịch hẹn ngày ${bookingDate(day)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                key: const Key('appointments-show-all'),
                onPressed: () => setState(() => _day = null),
                child: const Text('Xem tất cả'),
              ),
            ],
          ),
        if (clinic.error case final error?)
          AppStatusBanner(status: AppStatus.warning, message: error),
        if (all.isEmpty)
          const AppEmptyState(
            title: 'Chưa có lịch hẹn',
            message: 'Các lịch khám của bạn sẽ xuất hiện tại đây.',
            art: AppArt.emptyCalendar,
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
                subtitle: switch (clinic.byId(record.visit.id)) {
                  final ServerAppointment item =>
                    '${item.clinic.name}\n${bookingDate(record.visit.date)} · ${record.visit.time}\n${sharingLabel(item.consent, now)}',
                  null =>
                    '${record.receipt.status.label}\n${bookingDate(record.visit.date)} · ${record.visit.time}',
                },
                icon: AppIcons.calendar,
                onTap: () =>
                    context.push(AppRoutes.appointment(record.visit.id)),
              ),
          ],
      ],
    );
  }
}

/// Month view with a dot under each day that has an appointment.
class AppointmentsCalendar extends StatefulWidget {
  const AppointmentsCalendar({
    super.key,
    required this.today,
    required this.visitDays,
    required this.selected,
    required this.onSelected,
  });
  final DateTime today;
  final List<DateTime> visitDays;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  State<AppointmentsCalendar> createState() => _AppointmentsCalendarState();
}

class _AppointmentsCalendarState extends State<AppointmentsCalendar> {
  late DateTime _focused = widget.selected ?? _firstUpcoming();

  DateTime _firstUpcoming() {
    final upcoming = [
      for (final day in widget.visitDays)
        if (!day.isBefore(widget.today)) day,
    ]..sort();
    return upcoming.firstOrNull ?? widget.today;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rowHeight = MediaQuery.textScalerOf(context)
        .scale(48)
        .clamp(48.0, 96.0);
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return AppSurface(
      key: const Key('appointments-calendar'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TableCalendar<DateTime>(
        locale: 'vi',
        firstDay: DateTime(widget.today.year - 1, widget.today.month),
        lastDay: DateTime(widget.today.year + 1, widget.today.month, 28),
        focusedDay: _focused,
        currentDay: widget.today,
        startingDayOfWeek: StartingDayOfWeek.monday,
        rowHeight: rowHeight,
        daysOfWeekHeight: rowHeight * 0.6,
        availableGestures: AvailableGestures.horizontalSwipe,
        pageAnimationEnabled: !AppMotion.reduced(context),
        selectedDayPredicate: (day) => isSameDay(day, widget.selected),
        eventLoader: (day) => [
          for (final visit in widget.visitDays)
            if (isSameDay(visit, day)) visit,
        ],
        onDaySelected: (day, focused) {
          setState(() => _focused = focused);
          widget.onSelected(DateTime(day.year, day.month, day.day));
        },
        onPageChanged: (focused) => _focused = focused,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: text.titleMedium!,
          titleTextFormatter: (date, _) => 'Tháng ${date.month}, ${date.year}',
          leftChevronIcon: const AppIcon(AppIcons.back, label: 'Tháng trước'),
          rightChevronIcon: const AppIcon(AppIcons.forward, label: 'Tháng sau'),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          dowTextFormatter: (date, _) => weekdays[date.weekday - 1],
          weekdayStyle: text.bodySmall!,
          weekendStyle: text.bodySmall!,
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          cellMargin: const EdgeInsets.all(9),
          defaultTextStyle: text.bodyLarge!,
          weekendTextStyle: text.bodyLarge!,
          todayTextStyle: text.bodyLarge!.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
          todayDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          selectedTextStyle: text.bodyLarge!.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          markersMaxCount: 1,
          markersAutoAligned: false,
          markersAlignment: Alignment.bottomCenter,
          markersOffset: const PositionedOffset(bottom: 1),
          markerSize: 7,
          markerDecoration: const BoxDecoration(
            color: Color(0xFFE07A4F),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Celebrates a confirmed booking with a check that pops in once.
class BookingSuccessMark extends ConsumerWidget {
  const BookingSuccessMark({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmed = ref
        .watch(appointmentsProvider)
        .records
        .any(
          (record) =>
              record.visit.id == id &&
              record.receipt.status == PaymentStatus.confirmed,
        );
    if (!confirmed) return const SizedBox.shrink();
    Widget mark = Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.selected,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
      ),
    );
    if (!AppMotion.reduced(context)) {
      mark = mark
          .animate()
          .scale(
            begin: const Offset(0.6, 0.6),
            duration: 420.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 200.ms);
    }
    return Padding(
      key: const Key('booking-success-mark'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ExcludeSemantics(child: mark),
          const SizedBox(height: 12),
          Text(
            'Đã đặt lịch xong',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'MedicApp sẽ nhắc trên điện thoại trước buổi khám.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
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
    children: [AppointmentRecordView(id: id, showResult: true)],
  );
}

class AppointmentRecordView extends ConsumerWidget {
  const AppointmentRecordView({
    super.key,
    required this.id,
    this.onRetry,
    this.showResult = false,
  });
  final String id;
  final VoidCallback? onRetry;

  /// The doctor's result only makes sense on the saved appointment, not on
  /// the booking confirmation.
  final bool showResult;
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
    final clinic = ref.watch(serverAppointmentProvider(id));
    if (clinic != null) {
      return _ClinicAppointmentView(record: record, appointment: clinic);
    }
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
        if (receipt.status != PaymentStatus.failed) ...[
          if (showResult && receipt.status == PaymentStatus.confirmed)
            VisitResultSection(visitId: visit.id),
          VisitPrepSection(visitId: visit.id),
          VisitRemindersSection(visitId: visit.id),
        ],
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

/// An appointment the clinic holds for the signed-in phone (bước 16): no
/// payment, a result fetched without a code, questions before the visit and
/// the per-visit sharing consent.
class _ClinicAppointmentView extends StatelessWidget {
  const _ClinicAppointmentView({
    required this.record,
    required this.appointment,
  });
  final AppointmentRecord record;
  final ServerAppointment appointment;

  static const _status = {
    'booked': 'Đã đặt lịch',
    'arrived': 'Đã đến phòng khám',
    'in_progress': 'Đang khám',
    'done': 'Đã khám xong',
    'cancelled': 'Đã hủy',
  };

  @override
  Widget build(BuildContext context) {
    final visit = record.visit;
    final cancelled = appointment.cancelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTicketCard(
          title: _status[appointment.status] ?? 'Lịch khám',
          status: cancelled ? AppStatus.error : AppStatus.success,
          reference: appointment.clinic.name,
          details: [
            if (visit.patientName.isNotEmpty)
              (label: 'Người khám', value: visit.patientName),
            if (appointment.kind.isNotEmpty)
              (label: 'Hình thức', value: appointment.kind),
            (
              label: 'Ngày và giờ hẹn',
              value: '${bookingDate(visit.date)} · ${visit.time}',
            ),
            (
              label: 'Nơi khám',
              value: appointment.clinic.phone.isEmpty
                  ? appointment.clinic.name
                  : '${appointment.clinic.name}\nĐiện thoại ${appointment.clinic.phone}',
            ),
            if (appointment.specialty.isNotEmpty)
              (label: 'Chuyên khoa', value: appointment.specialty),
          ],
        ),
        const SizedBox(height: 16),
        if (!cancelled) ...[
          VisitResultSection(visitId: visit.id),
          PreVisitQuestionsSection(visitId: visit.id),
          ClinicSharingSection(appointmentId: visit.id),
          VisitRemindersSection(visitId: visit.id),
        ] else
          const AppStatusBanner(
            status: AppStatus.error,
            message:
                'Lịch khám này đã hủy. Liên hệ phòng khám nếu cần đặt lại.',
          ),
      ],
    );
  }
}
