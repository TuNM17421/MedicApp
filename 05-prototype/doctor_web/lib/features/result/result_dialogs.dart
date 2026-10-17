import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import 'rx_pdf.dart';
import 'rx_sheet.dart';

/// Print and download, shared by the preview and the sent view.
class RxPrintButtons extends StatefulWidget {
  const RxPrintButtons(this.sheet, {super.key});
  final RxSheet sheet;

  @override
  State<RxPrintButtons> createState() => _RxPrintButtonsState();
}

class _RxPrintButtonsState extends State<RxPrintButtons> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(RxSheet) action) async {
    setState(() => _busy = true);
    try {
      await action(widget.sheet);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa tạo được bản PDF. Thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.tonalIcon(
        onPressed: _busy ? null : () => _run(printRx),
        icon: const Icon(LucideIcons.printer, size: 16),
        label: const Text('In đơn thuốc'),
      ),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(downloadRx),
        icon: const Icon(LucideIcons.download, size: 16),
        label: const Text('Tải PDF'),
      ),
    ],
  );
}

/// The sheet on a grey "desk", at most A4 width.
class RxPaper extends StatelessWidget {
  const RxPaper(this.sheet, {super.key});
  final RxSheet sheet;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Container(
      color: c.surface3,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 794),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: RxSheetView(sheet),
        ),
      ),
    );
  }
}

/// "Xem đơn theo mẫu": the form exactly as it prints.
Future<void> showRxPreview(BuildContext context, RxSheet sheet) => showDialog(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Đơn thuốc theo mẫu',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RxPrintButtons(sheet),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(child: SingleChildScrollView(child: RxPaper(sheet))),
        ],
      ),
    ),
  ),
);

/// Confirms signing and sending. True when the doctor confirmed.
Future<bool> showSendDialog(
  BuildContext context, {
  required RxSheet sheet,
  required bool amendment,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _SendDialog(sheet: sheet, amendment: amendment),
    ) ??
    false;

class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.sheet, required this.amendment});
  final RxSheet sheet;
  final bool amendment;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.sheet;
    final c = DwColors.of(context);
    Widget fact(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.fg2),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(
        widget.amendment ? 'Gửi bản sửa kết quả' : 'Ký và gửi kết quả',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fact(LucideIcons.user, '${s.patientName}, ${s.age} tuổi'),
            fact(LucideIcons.stethoscope, s.diagnosis),
            fact(
              LucideIcons.pill,
              s.items.isEmpty
                  ? 'Không kê thuốc'
                  : s.items.map((i) => i.title.trim()).join(', '),
            ),
            fact(
              LucideIcons.smartphone,
              widget.amendment
                  ? 'Người bệnh nhận bản sửa bằng mã đã in trên đơn trước.'
                  : 'Sau khi gửi, web hiện mã nhận kết quả và in mã đó trên '
                        'đơn. Người bệnh nhập mã trong app MedicApp để nhận.',
            ),
            fact(
              LucideIcons.lock,
              'Kết quả được ký tên bạn và khóa lại. Muốn đổi thì dùng '
              '“Sửa kết quả”, có ghi lý do.',
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: const Text('Tôi đã kiểm tra chẩn đoán và đơn thuốc.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Quay lại'),
        ),
        FilledButton.icon(
          onPressed: _checked ? () => Navigator.pop(context, true) : null,
          icon: const Icon(LucideIcons.send, size: 16),
          label: const Text('Gửi'),
        ),
      ],
    );
  }
}

/// Asks why a sent result is being changed. Null when cancelled.
Future<String?> showAmendDialog(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _AmendDialog(),
);

class _AmendDialog extends StatefulWidget {
  const _AmendDialog();

  @override
  State<_AmendDialog> createState() => _AmendDialogState();
}

class _AmendDialogState extends State<_AmendDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sửa kết quả đã gửi'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Bản đã gửi được giữ nguyên. Bạn sửa trên một bản mới; người bệnh '
            'thấy bản mới sau khi bạn gửi lại.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Lý do sửa',
              hintText: 'Ví dụ: Đổi liều Colchicin',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Mở bản sửa'),
      ),
    ],
  );
}
