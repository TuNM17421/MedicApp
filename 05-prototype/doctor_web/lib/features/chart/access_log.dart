import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin_models.dart';
import '../../data/api.dart';
import '../../data/providers.dart';

/// Who opened or changed a patient's record, newest first (bước 18). The
/// first page comes in; "Tải thêm" asks [more] for the next one.
class AccessLogList extends StatefulWidget {
  const AccessLogList(this.first, {super.key, required this.more});
  final AccessLogPage first;
  final Future<AccessLogPage> Function(int offset) more;

  @override
  State<AccessLogList> createState() => _AccessLogListState();
}

class _AccessLogListState extends State<AccessLogList> {
  late final _items = [...widget.first.items];
  late int? _next = widget.first.nextOffset;
  bool _busy = false;
  String? _error;

  Future<void> _loadMore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.more(_next!);
      setState(() {
        _items.addAll(page.items);
        _next = page.nextOffset;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    if (_items.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.scrollText,
        title: 'Chưa có lượt truy cập nào',
        text: 'Chưa ai mở hay thay đổi hồ sơ này.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, e) in _items.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    '${fmtClock(e.at)}\n${fmtDay(e.at)}',
                    style: text.bodySmall?.copyWith(fontFeatures: tabular),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          e.actorName,
                          if (e.visitDate != null)
                            'Lượt khám ${fmtDate(e.visitDate!)}',
                        ].join(' · '),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tag(switch (e.actorKind) {
                  'patient' => 'Người bệnh',
                  'system' => 'Hệ thống',
                  _ => 'Phòng khám',
                }, tone: e.actorKind == 'patient' ? Tone.pt : Tone.neutral),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: c.missInk)),
          ),
        if (_next != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy ? null : _loadMore,
                child: Text(_busy ? 'Đang tải…' : 'Tải thêm'),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showAccessLogDialog(BuildContext context, String patientId) =>
    showDialog<void>(
      context: context,
      builder: (context) => _AccessLogDialog(patientId),
    );

class _AccessLogDialog extends ConsumerWidget {
  const _AccessLogDialog(this.patientId);
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(accessLogProvider(patientId));
    return AlertDialog(
      title: const Text('Nhật ký truy cập'),
      content: SizedBox(
        width: 560,
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => LoadError(
            e,
            onRetry: () => ref.invalidate(accessLogProvider(patientId)),
          ),
          data: (page) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ai đã mở hoặc thay đổi hồ sơ của ${page.patientName}, '
                  'mới nhất trước. Lần xem này cũng được ghi lại.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                AccessLogList(
                  page,
                  more: (offset) => ref
                      .read(apiProvider)
                      .accessLog(patientId: patientId, offset: offset),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
