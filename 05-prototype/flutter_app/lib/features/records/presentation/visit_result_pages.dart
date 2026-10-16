import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/auth_controller.dart';
import '../application/records_providers.dart';

import 'package:medic_core/medic_core.dart';

final _date = DateFormat('dd/MM/yyyy');

/// On a confirmed appointment: a link to the doctor's result, or, before one
/// arrives, a button that asks the mock doctor system to send it.
class VisitResultSection extends ConsumerWidget {
  const VisitResultSection({super.key, required this.visitId});
  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitResultsProvider);
    final result = state.forVisit(visitId);
    if (result != null) {
      final follow = result.followUpDate;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppLinkCard(
          key: const Key('visit-result-open'),
          title: 'Kết quả khám và đơn thuốc',
          subtitle: [
            result.items.isEmpty
                ? 'Không kê thuốc'
                : '${result.items.length} loại thuốc',
            if (follow != null) 'Tái khám ${_date.format(follow)}',
          ].join(' · '),
          icon: AppIcons.result,
          tone: AppTone.success,
          onTap: () => context.push(AppRoutes.visitResult(visitId)),
        ),
      );
    }
    final fetching = state.fetching.contains(visitId);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconTile(icon: AppIcons.result, tone: AppTone.success),
                const SizedBox(width: 12),
                Expanded(child: Text('Kết quả khám', style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sau buổi khám, bác sĩ sẽ gửi chẩn đoán và đơn thuốc vào đây.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('visit-result-simulate'),
              onPressed: fetching
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final result = await ref
                          .read(visitResultsProvider.notifier)
                          .fetch(visitId);
                      if (result == null) return;
                      messenger
                        ..clearSnackBars()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Đã nhận kết quả khám.'),
                          ),
                        );
                    },
              child: Text(
                fetching
                    ? 'Đang nhận kết quả…'
                    : 'Mô phỏng: bác sĩ gửi kết quả',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bản thử: chưa nối với web của bác sĩ.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class VisitResultPage extends ConsumerStatefulWidget {
  const VisitResultPage({super.key, required this.visitId});
  final String visitId;

  @override
  ConsumerState<VisitResultPage> createState() => _VisitResultPageState();
}

class _VisitResultPageState extends ConsumerState<VisitResultPage> {
  bool _paper = false;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(visitResultsProvider).forVisit(widget.visitId);
    return Scaffold(
      body: AppPageBody(
        title: 'Kết quả khám',
        onBack: () =>
            AppRoutes.backOr(context, AppRoutes.appointment(widget.visitId)),
        children: [
          if (result == null)
            const AppEmptyState(
              title: 'Chưa có kết quả',
              message: 'Bác sĩ chưa gửi kết quả cho lượt khám này.',
            )
          else ...[
            SegmentedButton<bool>(
              key: const Key('visit-result-view'),
              segments: const [
                ButtonSegment(value: false, label: Text('Dễ đọc')),
                ButtonSegment(value: true, label: Text('Bản đơn thuốc')),
              ],
              selected: {_paper},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _paper = value.single),
            ),
            if (_paper)
              PrescriptionPaper(result: result)
            else
              ..._readable(context, result),
          ],
        ],
      ),
    );
  }

  List<Widget> _readable(BuildContext context, VisitResult result) {
    final text = Theme.of(context).textTheme;
    final follow = result.followUpDate;
    return [
      AppReviewSection(
        title: result.patientName,
        items: [
          (
            label: 'Ngày khám',
            value: DateFormat('HH:mm, dd/MM/yyyy').format(result.issuedAt),
          ),
          (label: 'Nơi khám', value: result.facilityName),
          (label: 'Bác sĩ', value: result.doctorName),
          (label: 'Chẩn đoán', value: result.diagnosis),
        ],
      ),
      Semantics(
        header: true,
        child: Text(
          result.items.isEmpty
              ? 'Đơn thuốc'
              : 'Đơn thuốc (${result.items.length} loại)',
          style: text.titleLarge,
        ),
      ),
      if (result.items.isEmpty)
        const AppStatusBanner(message: 'Lần khám này bác sĩ không kê thuốc.')
      else
        for (final (index, item) in result.items.indexed)
          MedicineCard(number: index + 1, item: item),
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lời dặn của bác sĩ', style: text.titleLarge),
            const Divider(),
            for (final line in result.advice)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: text.bodyLarge),
                    Expanded(child: Text(line, style: text.bodyLarge)),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (follow != null)
        AppStatusBanner(
          status: AppStatus.info,
          title: 'Hẹn tái khám ${_date.format(follow)}',
          message: 'Khám lại xin mang theo đơn này.',
        ),
    ];
  }
}

class MedicineCard extends StatelessWidget {
  const MedicineCard({super.key, required this.number, required this.item});
  final int number;
  final PrescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppTokens.of(context).tone(AppTone.teal);
    return AppSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.background,
            child: Text(
              '$number',
              style: text.titleMedium?.copyWith(color: colors.foreground),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: text.titleLarge),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: AppIcon(AppIcons.clock, size: 22),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _capitalized(item.schedule),
                        style: text.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.quantity} ${item.form} · dùng ${item.days} ngày',
                  style: text.bodyLarge,
                ),
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.note, style: text.bodyLarge),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalized(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// The same result laid out like the Bộ Y tế prescription form
/// (Thông tư 18/2018/TT-BYT), so it looks like the paper people know.
class PrescriptionPaper extends ConsumerWidget {
  const PrescriptionPaper({super.key, required this.result});
  final VisitResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: Colors.black, height: 1.5);
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    Widget field(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: base),
          TextSpan(text: value.isEmpty ? '…' : value, style: bold),
        ],
      ),
    );
    final issued = result.issuedAt;
    return Container(
      key: const Key('prescription-paper'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          field('Tên đơn vị', result.facilityName),
          field('Điện thoại', formatPhone(result.facilityPhone)),
          const SizedBox(height: 16),
          Center(child: Text('ĐƠN THUỐC', style: bold.copyWith(fontSize: 22))),
          const SizedBox(height: 16),
          field('Họ tên', result.patientName),
          Wrap(
            spacing: 16,
            children: [
              field(
                'Tuổi',
                result.patientAge == 0 ? '' : '${result.patientAge}',
              ),
              field(
                'Cân nặng',
                result.weightKg == null ? '' : '${result.weightKg} kg',
              ),
              field('Nam/nữ', result.patientGender),
            ],
          ),
          field('Mã số thẻ bảo hiểm y tế (nếu có)', result.insuranceCode),
          field('Địa chỉ liên hệ', result.address),
          field('Chẩn đoán', result.diagnosis),
          const SizedBox(height: 8),
          Text('Thuốc điều trị:', style: bold),
          if (result.items.isEmpty) Text('Không kê thuốc.', style: base),
          for (final (index, item) in result.items.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${index + 1}. ${item.title}', style: bold),
                      ),
                      Text('${item.quantity} ${item.form}', style: bold),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      [
                        item.usageLine,
                        if (item.note.isNotEmpty) item.note,
                      ].join('. '),
                      style: base,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text('Lời dặn:', style: bold),
          for (final line in result.advice) Text('- $line', style: base),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              children: [
                Text(
                  'Ngày ${issued.day} tháng ${issued.month} năm ${issued.year}',
                  style: base.copyWith(fontStyle: FontStyle.italic),
                ),
                Text('Bác sĩ/Y sĩ khám bệnh', style: bold),
                const SizedBox(height: 24),
                Text(result.doctorName, style: bold),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('- Khám lại xin mang theo đơn này.', style: base),
        ],
      ),
    );
  }
}
