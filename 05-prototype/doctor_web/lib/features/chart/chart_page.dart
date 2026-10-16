import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../worklist/worklist_page.dart' show AdherenceMeter;
import 'history_tab.dart';
import 'result_tab.dart';
import 'summary_tab.dart';

/// Adherence of each shared course over the chart's period.
List<CourseAdherence> chartAdherence(ChartData d) => [
  for (final course in d.meds.courses)
    adherenceOf(
      course,
      d.meds.log,
      from: d.periodFrom,
      days: d.periodDays,
      now: d.now,
    ),
];

enum ChartTab {
  summary('Tóm tắt trước khám', LucideIcons.fileText),
  result('Kết quả & đơn thuốc', LucideIcons.pill),
  history('Lịch sử khám', LucideIcons.history);

  const ChartTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// One visit: the patient column on the left, tabs on the right; the
/// column stacks on top on narrow screens.
class ChartPage extends ConsumerWidget {
  const ChartPage({super.key, required this.appointmentId, required this.tab});
  final String appointmentId;
  final String tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chartProvider(appointmentId));
    final current = ChartTab.values.firstWhere(
      (t) => t.name == tab,
      orElse: () => ChartTab.summary,
    );
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LoadError(
        e,
        onRetry: () => ref.invalidate(chartProvider(appointmentId)),
      ),
      data: (data) {
        final stacked = MediaQuery.sizeOf(context).width < Dw.stackBelow;
        final banner = PatientBanner(data, stacked: stacked);
        final tabs = _Tabs(data: data, current: current);
        if (stacked) {
          return ListView(children: [banner, tabs]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: Dw.banner,
              child: SingleChildScrollView(child: banner),
            ),
            Expanded(child: SingleChildScrollView(child: tabs)),
          ],
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.data, required this.current});
  final ChartData data;
  final ChartTab current;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final body = switch (current) {
      ChartTab.summary => SummaryTab(data),
      ChartTab.result => ResultTab(data),
      ChartTab.history => HistoryTab(data.patient.brief.id),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in ChartTab.values)
                  _TabButton(
                    tab: t,
                    selected: t == current,
                    badge:
                        t == ChartTab.result &&
                            data.resultStatus == ResultStatus.sent
                        ? const Tag('Đã gửi', tone: Tone.ok)
                        : null,
                    onTap: () => context.go(
                      Routes.visit(data.appointmentId, tab: t.name),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final ChartTab tab;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final color = selected ? c.brandInk : c.fg2;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? c.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(tab.icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                tab.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
            ],
          ),
        ),
      ),
    );
  }
}

class PatientBanner extends ConsumerStatefulWidget {
  const PatientBanner(this.data, {super.key, required this.stacked});
  final ChartData data;
  final bool stacked;

  @override
  ConsumerState<PatientBanner> createState() => _PatientBannerState();
}

class _PatientBannerState extends ConsumerState<PatientBanner> {
  bool _busy = false;

  Future<void> _advance(Future<void> Function(ClinicApi api) call) async {
    setState(() => _busy = true);
    try {
      await call(ref.read(apiProvider));
      ref.invalidate(chartProvider(widget.data.appointmentId));
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
    final d = widget.data;
    final p = d.patient;
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    final adherence = d.shared ? chartAdherence(d) : const <CourseAdherence>[];
    final id = d.appointmentId;

    final Widget action = switch ((d.status, d.resultStatus)) {
      (_, ResultStatus.sent) => OutlinedButton.icon(
        onPressed: () => context.go(Routes.visit(id, tab: 'result')),
        icon: const Icon(LucideIcons.fileCheck2, size: 16),
        label: const Text('Xem kết quả đã gửi'),
      ),
      (VisitStatus.booked, _) => OutlinedButton.icon(
        onPressed: _busy ? null : () => _advance((api) => api.arrive(id)),
        icon: const Icon(LucideIcons.userCheck, size: 16),
        label: const Text('Đánh dấu đã đến'),
      ),
      (VisitStatus.arrived, _) => FilledButton.icon(
        onPressed: _busy ? null : () => _advance((api) => api.start(id)),
        icon: const Icon(LucideIcons.play, size: 16),
        label: const Text('Bắt đầu khám'),
      ),
      _ => FilledButton.icon(
        onPressed: () => context.go(Routes.visit(id, tab: 'result')),
        icon: const Icon(LucideIcons.filePenLine, size: 16),
        label: const Text('Ghi kết quả'),
      ),
    };

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title.toUpperCase(), style: text.labelSmall),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: widget.stacked
            ? Border(bottom: BorderSide(color: c.line))
            : Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(Routes.worklist),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Hàng chờ'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.brandSoft,
                child: Text(
                  initials(p.brief.name),
                  style: TextStyle(
                    color: c.brandInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(p.brief.name, style: text.titleLarge),
                    ),
                    Text(
                      '${p.brief.age} tuổi · ${p.brief.gender} · Mã ${p.brief.code}',
                      style: text.bodySmall?.copyWith(fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: statusTag(d.status, result: d.resultStatus),
          ),
          section('Lượt khám', [
            KeyValue(
              'Giờ hẹn',
              Text(
                '${d.time}, ${fmtDay(d.startsAt)}',
                style: const TextStyle(fontFeatures: tabular),
              ),
            ),
            KeyValue('Hình thức', Text(d.kind)),
            KeyValue('Chuyên khoa', Text(d.specialty)),
            KeyValue(
              'Thẻ BHYT',
              Text(
                p.insuranceCode.isEmpty ? 'Không dùng' : p.insuranceCode,
                style: const TextStyle(fontFeatures: tabular),
              ),
            ),
          ]),
          section('Cần chú ý', [
            KeyValue(
              'Dị ứng thuốc',
              Text(p.allergy.isEmpty ? 'Chưa có thông tin' : p.allergy),
            ),
            if (d.shared)
              for (final flag in d.summary?.flags ?? const <SummarySection>[])
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.missSoft,
                    borderRadius: BorderRadius.circular(Dw.radius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.triangleAlert,
                        size: 16,
                        color: c.missInk,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Người bệnh nhắc: ${flag.text}',
                          style: TextStyle(color: c.missInk, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
          ]),
          if (p.conditions.isNotEmpty)
            section('Đang theo dõi', [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final cond in p.conditions) Tag(cond)],
              ),
            ]),
          if (adherence.isNotEmpty)
            section('Thuốc đang dùng', [
              for (final a in adherence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.course.item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              a.course.item.schedule,
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      AdherenceMeter(a.percent),
                    ],
                  ),
                ),
            ]),
          section('Chia sẻ dữ liệu', [_ConsentNote(d)]),
          const SizedBox(height: 18),
          action,
        ],
      ),
    );
  }
}

class _ConsentNote extends StatelessWidget {
  const _ConsentNote(this.d);
  final ChartData d;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final shared = d.shared;
    final text = switch (d.consent.state) {
      ConsentState.shared =>
        'Đồng ý chia sẻ lúc ${fmtClock(d.consent.grantedAt!)} '
            '${fmtDay(d.consent.grantedAt!)}. Chỉ phòng khám của lượt khám '
            'này xem được.',
      ConsentState.declined => switch ((
        d.consent.reason,
        d.consent.revokedAt,
      )) {
        ('revoked', final DateTime at) =>
          'Người bệnh đã rút lại đồng ý chia sẻ lúc ${fmtClock(at)} '
              '${fmtDay(at)}. Dữ liệu đã chia sẻ không còn hiện ở đây.',
        ('expired', _) =>
          'Đồng ý chia sẻ đã hết hạn. Dữ liệu đã chia sẻ không còn hiện ở đây.',
        _ => 'Người bệnh không chia sẻ dữ liệu cho lượt khám này.',
      },
      ConsentState.none => 'Người bệnh chưa trả lời câu hỏi trước khám.',
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: shared ? c.okSoft : c.surface3,
        borderRadius: BorderRadius.circular(Dw.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            shared ? LucideIcons.shieldCheck : LucideIcons.shieldOff,
            size: 16,
            color: shared ? c.okInk : c.fg2,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: shared ? c.okInk : c.fg2),
            ),
          ),
        ],
      ),
    );
  }
}
