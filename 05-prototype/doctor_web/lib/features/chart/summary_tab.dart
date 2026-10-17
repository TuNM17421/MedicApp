import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/charts/adherence_charts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'chart_page.dart' show chartAdherence;

/// "Tóm tắt trước khám". Text the AI shortened always has its source
/// sentences one tap away; medicine figures come from the app's dose log,
/// computed by medic_core.
class SummaryTab extends StatelessWidget {
  const SummaryTab(this.d, {super.key});
  final ChartData d;

  @override
  Widget build(BuildContext context) {
    final summary = d.summary;
    if (!d.shared || summary == null) {
      final declined = d.consent.state == ConsentState.declined;
      return Panel(
        child: EmptyState(
          icon: declined ? LucideIcons.eyeOff : LucideIcons.hourglass,
          title: declined
              ? 'Người bệnh không chia sẻ tóm tắt'
              : 'Chưa có tóm tắt trước khám',
          text: declined
              ? 'Bạn chỉ thấy thông tin lịch hẹn. Hỏi bệnh như bình thường.'
              : 'Người bệnh chưa trả lời câu hỏi trước khám. Tóm tắt sẽ hiện '
                    'ở đây nếu họ trả lời và đồng ý chia sẻ trước giờ khám.',
        ),
      );
    }
    final c = DwColors.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    Widget pair(Widget a, Widget b) => wide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: a),
                const SizedBox(width: 16),
                Expanded(child: b),
              ],
            ),
          )
        : Column(children: [a, const SizedBox(height: 16), b]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Dw.radius),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(LucideIcons.info, size: 16, color: c.fg2),
              Text(
                'Thông tin người bệnh tự cung cấp qua MedicApp, không phải bệnh án.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SourceTag(Source.ai),
              const SourceTag(Source.app),
              const SourceTag(Source.patient),
            ],
          ),
        ),
        for (final flag in summary.flags) ...[
          const SizedBox(height: 12),
          _FlagCallout(flag, d),
        ],
        const SizedBox(height: 16),
        pair(
          _SectionCard(
            title: 'Lý do khám',
            section: summary.section('chief'),
            d: d,
            lead: true,
          ),
          _SectionCard(
            title: 'Người bệnh muốn hỏi',
            section: summary.section('questions'),
            d: d,
            lead: true,
          ),
        ),
        const SizedBox(height: 16),
        pair(
          _SectionCard(
            title: 'Diễn biến, đã tự xử lý',
            section: summary.section('course'),
            d: d,
          ),
          _LastVisitCard(d),
        ),
        const SizedBox(height: 16),
        AdherenceCard(d),
        const SizedBox(height: 16),
        _Feedback(d),
      ],
    );
  }
}

class _Quotes extends StatelessWidget {
  const _Quotes(this.sources, this.d);
  final List<String> sources;
  final ChartData d;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in sources)
          if (d.answer(id) case final a?)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: c.ptSoft,
                border: Border(left: BorderSide(color: c.pt, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      '${a.channelLabel}, ${fmtShort(a.answeredAt.toIso8601String())}',
                      if (a.question.isNotEmpty) a.question,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: c.pt,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('“${a.answer}”', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
      ],
    );
  }
}

class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.title,
    required this.section,
    required this.d,
    this.lead = false,
  });
  final String title;
  final SummarySection? section;
  final ChartData d;
  final bool lead;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    return Panel(
      title: widget.title,
      trailing: const [SourceTag(Source.ai)],
      child: s == null
          ? Text(
              'Người bệnh không nhắc tới.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.text,
                  style: widget.lead
                      ? Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500)
                      : Theme.of(context).textTheme.bodyMedium,
                ),
                if (s.sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(
                      _open ? LucideIcons.chevronUp : LucideIcons.quote,
                      size: 15,
                    ),
                    label: Text(_open ? 'Ẩn câu gốc' : 'Xem câu gốc'),
                  ),
                  if (_open) _Quotes(s.sources, widget.d),
                ],
              ],
            ),
    );
  }
}

class _FlagCallout extends StatelessWidget {
  const _FlagCallout(this.flag, this.d);
  final SummarySection flag;
  final ChartData d;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Semantics(
      container: true,
      label: 'Cần chú ý',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.missSoft,
          border: Border.all(color: c.miss.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(Dw.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.triangleAlert, size: 18, color: c.missInk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Người bệnh có nhắc tới',
                    style: TextStyle(
                      color: c.missInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(flag.text),
                  const SizedBox(height: 4),
                  Text(
                    'Câu nguyên văn của người bệnh. Hệ thống không đánh giá mức độ.',
                    style: TextStyle(fontSize: 12, color: c.fg2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastVisitCard extends StatelessWidget {
  const _LastVisitCard(this.d);
  final ChartData d;

  @override
  Widget build(BuildContext context) {
    final last = d.lastVisit;
    return Panel(
      title: 'Lần khám trước',
      trailing: const [SourceTag(Source.app)],
      child: last == null
          ? Text(
              'Lần đầu khám tại phòng khám qua MedicApp.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyValue(
                  'Ngày',
                  Text(
                    fmtDate(last.date),
                    style: const TextStyle(fontFeatures: tabular),
                  ),
                ),
                KeyValue('Nơi khám', Text(last.clinicName)),
                KeyValue('Chẩn đoán', Text(last.diagnosisText)),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () =>
                      context.go(Routes.visit(d.appointmentId, tab: 'history')),
                  icon: const Icon(LucideIcons.history, size: 15),
                  label: const Text('Xem đơn thuốc lần trước'),
                ),
              ],
            ),
    );
  }
}

/// Medicines from the app's "Thuốc hôm nay": a 30-day strip per course
/// with plain facts, skipped doses by reason, and a table view of the same
/// data for anyone who cannot use the chart.
class AdherenceCard extends StatefulWidget {
  const AdherenceCard(this.d, {super.key});
  final ChartData d;

  @override
  State<AdherenceCard> createState() => _AdherenceCardState();
}

class _AdherenceCardState extends State<AdherenceCard> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final c = DwColors.of(context);
    final courses = chartAdherence(d);
    if (courses.isEmpty && d.selfMeds.isEmpty) return const SizedBox.shrink();
    final first = courses.isEmpty ? null : courses.first.days;
    final anyMissed = courses.any((a) => a.missedDoses > 0);

    return Panel(
      title: 'Tuân thủ thuốc',
      trailing: [
        if (first != null && first.isNotEmpty)
          Text(
            '${first.length} ngày, ${fmtShort(first.first.day)} đến '
            '${fmtShort(first.last.day)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontFeatures: tabular),
          ),
        const SourceTag(Source.app),
        if (courses.isNotEmpty)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(LucideIcons.chartNoAxesColumn, size: 15),
                label: Text('Biểu đồ'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(LucideIcons.table, size: 15),
                label: Text('Bảng'),
              ),
            ],
            selected: {_table},
            onSelectionChanged: (s) => setState(() => _table = s.first),
          ),
      ],
      footer: d.selfMeds.isEmpty
          ? null
          : Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'NGƯỜI BỆNH TỰ KHAI THÊM',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SourceTag(Source.patient),
                for (final (name, how) in d.selfMeds)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' · $how'),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
      child: courses.isEmpty
          ? Text(
              'Người bệnh chưa có thuốc nào trong mục Thuốc hôm nay.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : _table
          ? _AdherenceTable(courses)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StripLegend(
                  showPartial: courses.any(
                    (a) => a.days.any((x) => x.status == DayStatus.partial),
                  ),
                ),
                for (final a in courses) ...[
                  const SizedBox(height: 14),
                  Divider(color: c.line),
                  const SizedBox(height: 14),
                  _CourseRow(a),
                ],
                if (anyMissed) ...[
                  const SizedBox(height: 14),
                  Divider(color: c.line),
                  const SizedBox(height: 14),
                  Text(
                    'Lý do bỏ liều',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Người bệnh chọn mỗi lần bấm “Bỏ liều” trên app. Liều quá '
                    'giờ mà không ghi gì được tính là “$unrecordedLabel”.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  ReasonBars(courses),
                ],
              ],
            ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow(this.a);
  final CourseAdherence a;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final level = a.level;
    final (ink, tone) = switch (level) {
      AdherenceLevel.good => (c.okInk, Tone.ok),
      AdherenceLevel.fair => (c.partInk, Tone.warn),
      AdherenceLevel.low => (c.missInk, Tone.danger),
      null => (c.muted, Tone.neutral),
    };
    final head = Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          a.course.item.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          a.course.item.schedule,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
    final number = Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          a.percent == null ? '—' : '${a.percent}%',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ink,
            fontFeatures: tabular,
          ),
        ),
        Text(
          '${a.takenDoses}/${a.dueDoses} liều',
          style: TextStyle(fontSize: 13, color: c.fg2, fontFeatures: tabular),
        ),
        if (level != null) Tag(level.label, tone: tone),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        const SizedBox(height: 4),
        number,
        const SizedBox(height: 10),
        DoseStrip(a),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 15, color: c.fg2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.facts.join(' '),
                style: TextStyle(fontSize: 13, color: c.fg2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdherenceTable extends StatelessWidget {
  const _AdherenceTable(this.courses);
  final List<CourseAdherence> courses;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final days = courses.first.days;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        headingTextStyle: Theme.of(context).textTheme.labelSmall,
        columns: [
          const DataColumn(label: Text('NGÀY')),
          for (final a in courses) DataColumn(label: Text(a.course.item.title)),
        ],
        rows: [
          for (final (i, day) in days.indexed)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    fmtDate(day.day),
                    style: const TextStyle(fontFeatures: tabular),
                  ),
                ),
                for (final a in courses)
                  DataCell(() {
                    final x = a.days[i];
                    final s = dayStyle(c, x.status);
                    final reasons = {
                      for (final r in x.missedReasons)
                        r?.label ?? unrecordedLabel,
                    }.join(', ');
                    return Text(
                      [
                        '${s.glyph} ${s.label}'.trim(),
                        if (x.due > 0) '${x.taken}/${x.due}',
                        if (reasons.isNotEmpty) reasons,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        fontFeatures: tabular,
                      ),
                    );
                  }()),
              ],
            ),
        ],
      ),
    );
  }
}

class _Feedback extends ConsumerStatefulWidget {
  const _Feedback(this.d);
  final ChartData d;

  @override
  ConsumerState<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends ConsumerState<_Feedback> {
  bool _busy = false;

  Future<void> _send(String value) async {
    final summary = widget.d.summary!;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).summaryFeedback(summary.id, value);
      ref.invalidate(chartProvider(widget.d.appointmentId));
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
    final c = DwColors.of(context);
    final given = widget.d.summary?.feedback;
    return Panel(
      child: given != null
          ? Row(
              children: [
                Icon(LucideIcons.check, size: 16, color: c.okInk),
                const SizedBox(width: 8),
                Text(
                  given == 'up'
                      ? 'Đã ghi nhận: tóm tắt đúng. Cảm ơn bác sĩ.'
                      : 'Đã ghi nhận: tóm tắt có chỗ sai. Cảm ơn bác sĩ.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Bản tóm tắt này có đúng với những gì người bệnh nói không?',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _send('up'),
                  icon: const Icon(LucideIcons.thumbsUp, size: 15),
                  label: const Text('Đúng, có ích'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _send('down'),
                  icon: const Icon(LucideIcons.flag, size: 15),
                  label: const Text('Có chỗ sai'),
                ),
              ],
            ),
    );
  }
}
