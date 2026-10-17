import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/api.dart';
import '../../data/providers.dart';

/// Same rule as the server: at least 10 characters (bước 18). The server
/// also refuses the email and the current password.
const minPassword = 10;

/// Change own password. Forced after signing in with a one-time password
/// (new or reset account): then it is the only screen until it is done.
class PasswordPage extends ConsumerStatefulWidget {
  const PasswordPage({super.key});

  @override
  ConsumerState<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends ConsumerState<PasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã đổi mật khẩu.')));
      final staff = ref.read(sessionProvider).value?.staff;
      if (staff != null) context.go(homeOf(staff));
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final staff = ref.watch(sessionProvider).value?.staff;
    final forced = staff?.mustChangePassword ?? false;
    final eye = IconButton(
      tooltip: _hide ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
      onPressed: () => setState(() => _hide = !_hide),
      icon: Icon(_hide ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
    );
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(Dw.radiusLg),
              ),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          forced ? 'Đặt mật khẩu mới' : 'Đổi mật khẩu',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        forced
                            ? 'Bạn đang dùng mật khẩu tạm do quản trị phòng '
                                  'khám cấp. Hãy đặt mật khẩu của riêng bạn '
                                  'trước khi tiếp tục.'
                            : 'Đổi xong, các phiên đăng nhập khác của bạn '
                                  'sẽ kết thúc.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _current,
                        obscureText: _hide,
                        autofocus: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: forced
                              ? 'Mật khẩu tạm'
                              : 'Mật khẩu hiện tại',
                          suffixIcon: eye,
                        ),
                        validator: (v) => (v ?? '').isEmpty
                            ? 'Nhập mật khẩu hiện tại.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _next,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu mới',
                          helperText:
                              'Ít nhất $minPassword ký tự, không trùng email.',
                        ),
                        validator: (v) => (v ?? '').length < minPassword
                            ? 'Mật khẩu cần ít nhất $minPassword ký tự.'
                            : v == _current.text
                            ? 'Mật khẩu mới cần khác mật khẩu hiện tại.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _again,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.newPassword],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Nhập lại mật khẩu mới',
                        ),
                        validator: (v) =>
                            v != _next.text ? 'Hai mật khẩu chưa khớp.' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                LucideIcons.circleAlert,
                                size: 16,
                                color: c.missInk,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: c.missInk,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Lưu mật khẩu mới'),
                      ),
                      const SizedBox(height: 8),
                      if (forced)
                        TextButton(
                          onPressed: () =>
                              ref.read(sessionProvider.notifier).logout(),
                          child: const Text('Đăng xuất'),
                        )
                      else if (staff != null)
                        TextButton(
                          onPressed: () => context.go(homeOf(staff)),
                          child: const Text('Quay lại'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
