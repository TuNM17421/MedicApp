import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin_models.dart';
import '../../data/api.dart';
import '../../data/providers.dart';
import 'admin_scaffold.dart';

/// "Tài khoản": the clinic admin creates doctor and admin accounts, locks
/// and unlocks them, and issues one-time passwords (bước 18).
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffListProvider);
    final session = ref.watch(sessionProvider).value;
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          LoadError(e, onRetry: () => ref.invalidate(staffListProvider)),
      data: (list) => AdminScaffold(
        title: 'Tài khoản',
        subtitle:
            '${list.where((s) => s.active).length} tài khoản đang dùng · '
            '${session?.clinic.name ?? ''}',
        actions: [
          FilledButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(LucideIcons.userPlus, size: 16),
            label: const Text('Thêm tài khoản'),
          ),
        ],
        children: [
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, s) in list.indexed)
                  _AccountRow(
                    s,
                    first: i == 0,
                    self: s.id == session?.staff.id,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Mật khẩu tạm chỉ hiện một lần, ngay sau khi tạo hoặc đặt lại. '
            'Người dùng phải đổi mật khẩu ở lần đăng nhập đầu. Khóa tài khoản '
            'thì phiên đang mở của người đó kết thúc ngay.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final issued = await showDialog<IssuedPassword>(
      context: context,
      builder: (context) => const _CreateDialog(),
    );
    if (issued == null || !context.mounted) return;
    ref.invalidate(staffListProvider);
    await showTemporaryPassword(context, issued);
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow(this.s, {required this.first, required this.self});
  final StaffAccount s;
  final bool first, self;

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final (title, body, ok) = switch (action) {
      'reset' => (
        'Đặt lại mật khẩu?',
        'Mật khẩu hiện tại của ${s.name} hết dùng được và phiên đang mở '
            'kết thúc. Bạn sẽ nhận một mật khẩu tạm mới.',
        'Đặt lại',
      ),
      'deactivate' => (
        'Khóa tài khoản?',
        '${s.name} bị đăng xuất ngay và không đăng nhập được cho tới khi '
            'bạn mở lại.',
        'Khóa tài khoản',
      ),
      _ => (
        'Mở lại tài khoản?',
        '${s.name} đăng nhập lại được bằng mật khẩu đang có.',
        'Mở lại',
      ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ok),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final api = ref.read(apiProvider);
    try {
      if (action == 'reset') {
        final issued = await api.resetStaffPassword(s.id);
        ref.invalidate(staffListProvider);
        if (context.mounted) await showTemporaryPassword(context, issued);
      } else {
        await api.setStaffActive(s.id, active: action == 'reactivate');
        ref.invalidate(staffListProvider);
      }
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    final status = !s.active
        ? const Tag('Đã khóa', icon: LucideIcons.lock, tone: Tone.danger)
        : s.locked
        ? const Tag(
            'Tạm khóa do nhập sai',
            icon: LucideIcons.timer,
            tone: Tone.warn,
          )
        : s.mustChangePassword
        ? const Tag(
            'Chờ đổi mật khẩu',
            icon: LucideIcons.keyRound,
            tone: Tone.warn,
          )
        : const Tag('Đang dùng', icon: LucideIcons.circleCheck, tone: Tone.ok);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: s.active ? c.brandSoft : c.surface3,
            child: Text(
              initials(s.fullName.isEmpty ? s.name : s.fullName),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: s.active ? c.brandInk : c.fg2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      s.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Tag(s.roleLabel, tone: s.isAdmin ? Tone.ai : Tone.brand),
                    status,
                    if (self) const Tag('Bạn'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.email} · ${s.lastLoginAt == null ? 'Chưa đăng nhập' : 'Đăng nhập gần nhất ${fmtClock(s.lastLoginAt!)} ${fmtDay(s.lastLoginAt!)}'}',
                  style: text.bodySmall?.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
          ),
          if (!self)
            PopupMenuButton<String>(
              tooltip: 'Thao tác với ${s.name}',
              icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
              onSelected: (a) => _act(context, ref, a),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Đặt lại mật khẩu'),
                ),
                if (s.active)
                  const PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Khóa tài khoản'),
                  )
                else
                  const PopupMenuItem(
                    value: 'reactivate',
                    child: Text('Mở lại tài khoản'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CreateDialog extends ConsumerStatefulWidget {
  const _CreateDialog();

  @override
  ConsumerState<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends ConsumerState<_CreateDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _title = TextEditingController(text: 'BS.');
  String _role = 'doctor';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await ref
          .read(apiProvider)
          .createStaff(
            email: _email.text.trim(),
            fullName: _name.text.trim(),
            role: _role,
            title: _role == 'doctor' ? _title.text.trim() : '',
          );
      if (mounted) Navigator.of(context).pop(issued);
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm tài khoản'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'doctor', label: Text('Bác sĩ')),
                ButtonSegment(value: 'admin', label: Text('Quản trị')),
              ],
              selected: {_role},
              onSelectionChanged: (v) => setState(() => _role = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              _role == 'doctor'
                  ? 'Bác sĩ xem hàng chờ, hồ sơ và gửi kết quả.'
                  : 'Quản trị quản lý tài khoản, xem số liệu và nhật ký; '
                        'không xem hồ sơ người bệnh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Họ và tên'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nhập họ và tên.' : null,
            ),
            if (_role == 'doctor') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Chức danh (hiện trước tên)',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email đăng nhập'),
              validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(v ?? '')
                  ? null
                  : 'Nhập email hợp lệ.',
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: DwColors.of(context).missInk),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('Tạo tài khoản'),
      ),
    ],
  );
}

/// Shows a one-time password once, with a copy button.
Future<void> showTemporaryPassword(
  BuildContext context,
  IssuedPassword issued,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final c = DwColors.of(context);
    return AlertDialog(
      title: const Text('Mật khẩu tạm'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Đưa trực tiếp cho ${issued.staff.name} (${issued.staff.email}). '
              'Mật khẩu chỉ hiện lần này; lần đăng nhập đầu phải đổi.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface3,
                borderRadius: BorderRadius.circular(Dw.radius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      issued.password,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chép mật khẩu',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: issued.password)),
                    icon: const Icon(LucideIcons.copy, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đã ghi lại'),
        ),
      ],
    );
  },
);
