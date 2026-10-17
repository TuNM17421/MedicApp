import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin_models.dart';
import '../../data/api.dart';
import '../../data/providers.dart';
import '../chart/access_log.dart';
import 'admin_scaffold.dart';

/// "Nhật ký truy cập" for the admin: look a patient up by code (the admin
/// has no worklist) and see who opened or changed the record.
class AccessLogAdminPage extends ConsumerStatefulWidget {
  const AccessLogAdminPage({super.key});

  @override
  ConsumerState<AccessLogAdminPage> createState() => _AccessLogPageState();
}

class _AccessLogPageState extends ConsumerState<AccessLogAdminPage> {
  final _code = TextEditingController();
  AccessLogPage? _page;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiProvider).accessLog(patientCode: code);
      setState(() => _page = page);
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      setState(() {
        _page = null;
        _error = e.status == 404
            ? 'Không có người bệnh mã $code ở phòng khám này.'
            : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return AdminScaffold(
      title: 'Nhật ký truy cập',
      subtitle:
          'Ai đã mở hoặc thay đổi hồ sơ của một người bệnh, mới nhất '
          'trước. Mỗi lần xem nhật ký cũng được ghi lại.',
      children: [
        Panel(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Mã người bệnh',
                    hintText: 'Ví dụ 000482',
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _search,
                icon: const Icon(LucideIcons.search, size: 16),
                label: const Text('Xem nhật ký'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: TextStyle(color: DwColors.of(context).missInk)),
        if (page != null)
          Panel(
            key: ValueKey(page.patientId),
            title: '${page.patientName} · Mã ${page.patientCode}',
            trailing: [Tag('${page.total} lượt')],
            child: AccessLogList(
              page,
              more: (offset) => ref
                  .read(apiProvider)
                  .accessLog(patientCode: page.patientCode, offset: offset),
            ),
          ),
      ],
    );
  }
}
