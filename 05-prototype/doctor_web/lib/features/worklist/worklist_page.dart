import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

enum WorklistFilter {
  all('Tất cả'),
  waiting('Chờ khám'),
  notArrived('Chưa đến'),
  sent('Đã gửi kết quả');

  const WorklistFilter(this.label);
  final String label;

  bool matches(WorklistItem i) => switch (this) {
    all => true,
    waiting =>
      i.resultStatus != ResultStatus.sent &&
          (i.status == VisitStatus.arrived ||
              i.status == VisitStatus.inProgress),
    notArrived => i.status == VisitStatus.booked,
    sent => i.resultStatus == ResultStatus.sent,
  };
}

final worklistFilterProvider = NotifierProvider<_Filter, WorklistFilter>(
  _Filter.new,
);

class _Filter extends Notifier<WorklistFilter> {
  @override
  WorklistFilter build() => WorklistFilter.all;
  void set(WorklistFilter value) => state = value;
}

/// 30-day adherence across a patient's courses, computed here with
/// medic_core from the raw log (the server does not compute it).
int? worklistAdherence(WorklistItem item, DateTime now) {
  if (item.consent != ConsentState.shared || item.meds.courses.isEmpty) {
    return null;
  }
  final from = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 30));
  return overallPercent([
    for (final course in item.meds.courses)
      adherenceOf(course, item.meds.log, from: from, days: 30, now: now),
  ]);
}

class WorklistPage extends ConsumerStatefulWidget {
  const WorklistPage({super.key});

  @override
  ConsumerState<WorklistPage> createState() => _WorklistPageState();
}

class _WorklistPageState extends ConsumerState<WorklistPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(worklistProvider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          LoadError(e, onRetry: () => ref.invalidate(worklistProvider)),
      data: (list) => _body(context, list),
    );
  }

  Widget _body(BuildContext context, Worklist list) {
    final c = DwColors.of(context);
    final filter = ref.watch(worklistFilterProvider);
    final q = _query.text.trim().toLowerCase();
    final rows = list.items
        .where(
          (i) =>
              q.isEmpty ||
              i.patient.name.toLowerCase().contains(q) ||
              i.patient.code.contains(q),
        )
        .where(filter.matches)
        .toList();
    int count(WorklistFilter f) => list.items.where(f.matches).length;
    final cards = MediaQuery.sizeOf(context).width < Dw.cardsBelow;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(worklistProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    runSpacing: 12,
                    spacing: 16,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              filter == WorklistFilter.sent
                                  ? 'Kết quả đã gửi'
                                  : 'Hàng chờ ${fmtDate(list.date)}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${list.items.length} lịch hẹn · '
                            '${count(WorklistFilter.waiting)} người đang chờ khám · '
                            '${count(WorklistFilter.sent)} đã gửi kết quả',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontFeatures: tabular),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _query,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Tìm tên hoặc mã',
                            prefixIcon: Icon(LucideIcons.search, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<WorklistFilter>(
                        showSelectedIcon: false,
                        segments: [
                          for (final f in WorklistFilter.values)
                            ButtonSegment(
                              value: f,
                              label: Text('${f.label}  ${count(f)}'),
                            ),
                        ],
                        selected: {filter},
                        onSelectionChanged: (s) => ref
                            .read(worklistFilterProvider.notifier)
                            .set(s.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(Dw.radiusLg),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: rows.isEmpty
                        ? const EmptyState(
                            icon: LucideIcons.searchX,
                            title: 'Không có lịch hẹn nào',
                            text: 'Thử bỏ bộ lọc hoặc xóa ô tìm kiếm.',
                          )
                        : cards
                        ? Column(
                            children: [
                              for (final (i, item) in rows.indexed) ...[
                                if (i > 0) const Divider(),
                                _Card(item, now: list.now),
                              ],
                            ],
                          )
                        : _Table(rows, now: list.now),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _open(BuildContext context, WorklistItem item) =>
    context.go(Routes.visit(item.appointmentId));

Widget _reason(BuildContext context, WorklistItem item) {
  final muted = TextStyle(color: DwColors.of(context).muted, fontSize: 13);
  if (item.consent == ConsentState.shared && item.chiefComplaint != null) {
    return Text(
      item.chiefComplaint!,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
    );
  }
  if (item.consent == ConsentState.declined) {
    return Text('Người bệnh không chia sẻ tóm tắt', style: muted);
  }
  return Text('Chưa trả lời câu hỏi trước khám', style: muted);
}

class AdherenceMeter extends StatelessWidget {
  const AdherenceMeter(this.percent, {super.key});
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final p = percent;
    if (p == null) return Text('—', style: TextStyle(color: c.muted));
    final level = AdherenceLevel.of(p);
    final (fill, ink) = switch (level) {
      AdherenceLevel.good => (c.ok, c.okInk),
      AdherenceLevel.fair => (c.part, c.partInk),
      AdherenceLevel.low => (c.miss, c.missInk),
    };
    return Tooltip(
      message: 'Tỷ lệ liều đã uống trong 30 ngày: ${level.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$p%',
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontFeatures: tabular,
              ),
            ),
          ),
          Container(
            width: 56,
            height: 6,
            decoration: BoxDecoration(
              color: c.surface3,
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: p / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table(this.rows, {required this.now});
  final List<WorklistItem> rows;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final head = Theme.of(context).textTheme.labelSmall;
    Widget cell(Widget child, {int flex = 1}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );
    return Column(
      children: [
        Container(
          color: c.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              cell(Text('GIỜ', style: head), flex: 6),
              cell(Text('NGƯỜI BỆNH', style: head), flex: 22),
              cell(Text('HÌNH THỨC', style: head), flex: 12),
              cell(Text('LÝ DO KHÁM', style: head), flex: 26),
              cell(Text('TÓM TẮT', style: head), flex: 15),
              cell(Text('TUÂN THỦ 30 NGÀY', style: head), flex: 14),
              cell(Text('TRẠNG THÁI', style: head), flex: 14),
              const SizedBox(width: 28),
            ],
          ),
        ),
        for (final item in rows) ...[
          const Divider(),
          Semantics(
            button: true,
            label: 'Mở hồ sơ ${item.patient.name}, ${item.time}',
            child: InkWell(
              onTap: () => _open(context, item),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    cell(
                      Text(
                        item.time,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabular,
                        ),
                      ),
                      flex: 6,
                    ),
                    cell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.patient.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${item.patient.age} tuổi · ${item.patient.gender} · '
                            'Mã ${item.patient.code}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.muted,
                              fontFeatures: tabular,
                            ),
                          ),
                        ],
                      ),
                      flex: 22,
                    ),
                    cell(
                      Text(item.kind, style: const TextStyle(fontSize: 13)),
                      flex: 12,
                    ),
                    cell(_reason(context, item), flex: 26),
                    cell(
                      Align(
                        alignment: Alignment.centerLeft,
                        child: summaryTag(
                          item.consent,
                          has: item.hasSummary,
                          flagged: item.flagged,
                        ),
                      ),
                      flex: 15,
                    ),
                    cell(
                      AdherenceMeter(worklistAdherence(item, now)),
                      flex: 14,
                    ),
                    cell(
                      Align(
                        alignment: Alignment.centerLeft,
                        child: statusTag(
                          item.status,
                          result: item.resultStatus,
                        ),
                      ),
                      flex: 14,
                    ),
                    Icon(LucideIcons.chevronRight, size: 18, color: c.muted),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.item, {required this.now});
  final WorklistItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return InkWell(
      onTap: () => _open(context, item),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                item.time,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: item.patient.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text:
                              '  ${item.patient.age}t · ${item.patient.gender}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _reason(context, item),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusTag(item.status, result: item.resultStatus),
                      summaryTag(
                        item.consent,
                        has: item.hasSummary,
                        flagged: item.flagged,
                      ),
                      if (worklistAdherence(item, now) case final int p)
                        AdherenceMeter(p),
                    ],
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
