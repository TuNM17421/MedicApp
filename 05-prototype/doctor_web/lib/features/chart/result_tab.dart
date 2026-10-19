import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/result.dart';
import '../result/result_dialogs.dart';
import '../result/rx_editor.dart';
import '../result/rx_sheet.dart';

/// "Kết quả & đơn thuốc": the editor while the result is a draft, the
/// signed form with its claim code once sent.
class ResultTab extends ConsumerWidget {
  const ResultTab(this.d, {super.key});
  final ChartData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resultProvider(d.appointmentId));
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => LoadError(
        e,
        onRetry: () => ref.invalidate(resultProvider(d.appointmentId)),
      ),
      data: (result) => result == null || result.isDraft
          ? RxEditor(
              key: ValueKey(result?.id ?? 'new'),
              chart: d,
              draft: result,
            )
          : SentResult(chart: d, result: result),
    );
  }
}

class SentResult extends ConsumerStatefulWidget {
  const SentResult({super.key, required this.chart, required this.result});
  final ChartData chart;
  final ResultDraft result;

  @override
  ConsumerState<SentResult> createState() => _SentResultState();
}

class _SentResultState extends ConsumerState<SentResult> {
  bool _busy = false;

  Future<void> _amend() async {
    final reason = await showAmendDialog(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final id = widget.chart.appointmentId;
    try {
      await ref.read(apiProvider).amendResult(id, reason);
      ref.invalidate(resultProvider(id));
      ref.invalidate(chartProvider(id));
      ref.invalidate(worklistProvider);
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final session = ref.watch(sessionProvider).value;
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    if (session == null) return const SizedBox.shrink();
    final sheet = RxSheet.of(
      chart: widget.chart,
      session: session,
      diagnosis: r.diagnosis,
      items: r.items,
      advice: r.advice,
      followUpDate: r.followUpDate,
      signedAt: r.signedAt,
      signedBy: r.signedBy,
      claimCode: r.claimCode,
    );
    final signed = r.signedAt == null
        ? ''
        : ' lúc ${fmtClock(r.signedAt!)} ngày ${fmtDay(r.signedAt!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(LucideIcons.circleCheck, size: 20, color: c.ok),
                  Text('Đã gửi kết quả', style: text.titleMedium),
                  if (r.version > 1)
                    Tag('Bản sửa ${r.version}', tone: Tone.warn),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r.signedBy ?? ''}$signed.'
                '${r.amendReason == null ? '' : ' Lý do sửa: ${r.amendReason}.'}',
                style: text.bodySmall,
              ),
              if (r.claimCode != null) ...[
                const SizedBox(height: 14),
                _ClaimCode(r.claimCode!),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  RxPrintButtons(sheet),
                  TextButton.icon(
                    onPressed: _busy ? null : _amend,
                    icon: const Icon(LucideIcons.filePen, size: 16),
                    label: const Text('Sửa kết quả'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (r.internalNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          Panel(title: 'Ghi chú nội bộ', child: Text(r.internalNote)),
        ],
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(Dw.radiusLg),
          child: RxPaper(sheet),
        ),
      ],
    );
  }
}

class _ClaimCode extends StatelessWidget {
  const _ClaimCode(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(Dw.radius),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MÃ NHẬN KẾT QUẢ',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              SelectableText(
                code,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: c.brandInk,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              'Đã in trên đơn. Người bệnh nhập mã này trong app MedicApp để '
              'nhận kết quả và lịch uống thuốc. Mã dùng được 30 ngày.',
              style: TextStyle(color: c.fg2, fontSize: 13),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                copyText(context, code, 'Đã chép mã nhận kết quả.'),
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('Chép mã'),
          ),
        ],
      ),
    );
  }
}
