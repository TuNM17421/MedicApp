import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin_models.dart';
import '../../data/providers.dart';
import 'admin_scaffold.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "3 giờ 5 phút", "45 phút", "—".
String fmtMinutes(int? m) {
  if (m == null) return '—';
  if (m < 60) return '$m phút';
  final h = m ~/ 60, r = m % 60;
  if (h >= 48) return '${(m / 1440).round()} ngày';
  return r == 0 ? '$h giờ' : '$h giờ $r phút';
}

String _pct(int part, int whole) =>
    whole == 0 ? '—' : '${(100 * part / whole).round()}%';

final _daysProvider = NotifierProvider<_Days, int>(_Days.new);

class _Days extends Notifier<int> {
  @override
  int build() => 30;
  void set(int days) => state = days;
}

/// "Số liệu chạy thử": the four pilot numbers of the plan and a table per
/// day. The server counts; definitions are in CLINIC-API.md (bước 18).
class MetricsPage extends ConsumerWidget {
  const MetricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_daysProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = (
      from: _iso(today.subtract(Duration(days: days - 1))),
      to: _iso(today),
    );
    final async = ref.watch(pilotMetricsProvider(range));
    return AdminScaffold(
      title: 'Số liệu chạy thử',
      subtitle: 'Từ ${fmtDate(range.from)} đến ${fmtDate(range.to)}',
      actions: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 7, label: Text('7 ngày')),
            ButtonSegment(value: 30, label: Text('30 ngày')),
            ButtonSegment(value: 90, label: Text('90 ngày')),
          ],
          selected: {days},
          onSelectionChanged: (v) =>
              ref.read(_daysProvider.notifier).set(v.first),
        ),
      ],
      children: [
        async.when(
          skipLoadingOnRefresh: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => LoadError(
            e,
            onRetry: () => ref.invalidate(pilotMetricsProvider(range)),
          ),
          data: (m) => _Body(m),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.m);
  final PilotMetrics m;

  @override
  Widget build(BuildContext context) {
    final t = m.totals;
    final rated = t.feedbackUp + t.feedbackDown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 900
                ? 4
                : (box.maxWidth >= 480 ? 2 : 1);
            final w = (box.maxWidth - 12 * (cols - 1)) / cols;
            final tiles = [
              _Tile(
                label: 'Lượt khám có tóm tắt',
                value: '${t.withSummary}/${t.visits}',
                note: t.visits == 0
                    ? 'Chưa có lượt khám'
                    : '${_pct(t.withSummary, t.visits)} số lượt khám',
              ),
              _Tile(
                label: 'Bác sĩ bấm “Đúng”',
                value: t.upRate == null ? '—' : '${(t.upRate! * 100).round()}%',
                note: rated == 0
                    ? 'Chưa có đánh giá'
                    : '${t.feedbackUp} Đúng · ${t.feedbackDown} Chưa đúng',
              ),
              _Tile(
                label: 'Từ lúc gửi kết quả đến lúc người bệnh nhận',
                value: fmtMinutes(t.medianMinutes),
                note: t.sent == 0
                    ? 'Chưa gửi kết quả nào'
                    : 'Trung vị · ${t.received}/${t.sent} kết quả đã nhận'
                          '${t.p90Minutes == null ? '' : ' · 90% trong ${fmtMinutes(t.p90Minutes)}'}',
              ),
              _Tile(
                label: 'Đơn phải sửa sau khi gửi',
                value: '${t.amended}',
                note: t.sent == 0
                    ? 'Chưa gửi kết quả nào'
                    : '${_pct(t.amended, t.sent)} của ${t.sent} kết quả đã gửi',
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final tile in tiles) SizedBox(width: w, child: tile),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Theo ngày',
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: m.days.isEmpty
              ? const EmptyState(
                  icon: Icons.calendar_today_outlined,
                  title: 'Chưa có lượt khám',
                  text: 'Không có lượt khám nào trong khoảng ngày này.',
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 44,
                    columns: const [
                      DataColumn(label: Text('Ngày')),
                      DataColumn(label: Text('Lượt khám'), numeric: true),
                      DataColumn(label: Text('Có tóm tắt'), numeric: true),
                      DataColumn(
                        label: Text('Đúng / Chưa đúng'),
                        numeric: true,
                      ),
                      DataColumn(label: Text('Đã gửi'), numeric: true),
                      DataColumn(label: Text('Đã nhận'), numeric: true),
                      DataColumn(label: Text('Trung vị chờ'), numeric: true),
                      DataColumn(label: Text('Đơn sửa'), numeric: true),
                    ],
                    rows: [
                      for (final d in m.days.reversed)
                        DataRow(
                          cells: [
                            DataCell(Text(fmtDate(d.date!))),
                            DataCell(Text('${d.visits}')),
                            DataCell(Text('${d.withSummary}')),
                            DataCell(
                              Text('${d.feedbackUp} / ${d.feedbackDown}'),
                            ),
                            DataCell(Text('${d.sent}')),
                            DataCell(Text('${d.received}')),
                            DataCell(Text(fmtMinutes(d.medianMinutes))),
                            DataCell(Text('${d.amended}')),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Text(
          'Cách tính: lượt khám không tính lượt đã hủy. “Có tóm tắt” là lượt '
          'có ít nhất một bản tóm tắt trước khám. Tỷ lệ “Đúng” tính trên các '
          'bản tóm tắt bác sĩ đã đánh giá. Thời gian chờ tính từ lần ký gửi '
          'kết quả đầu tiên (lúc khám xong) đến lần đầu người bệnh mở kết '
          'quả bằng mã hoặc trong app. “Đơn sửa” là lượt có bản sửa đã gửi.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.note});
  final String label, value, note;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Dw.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall),
          const SizedBox(height: 8),
          Text(
            value,
            style: text.headlineSmall?.copyWith(fontFeatures: tabular),
          ),
          const SizedBox(height: 4),
          Text(note, style: text.bodySmall?.copyWith(fontFeatures: tabular)),
        ],
      ),
    );
  }
}
