import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import 'auth_controller.dart';

/// Header, scrolling content and one large action pinned at the bottom.
class FormPageScaffold extends StatelessWidget {
  const FormPageScaffold({
    super.key,
    required this.header,
    required this.children,
    this.actionLabel,
    this.onAction,
    this.scrollKey,
  });
  final Widget header;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      key: scrollKey,
      slivers: [
        SliverToBoxAdapter(
          child: ColoredBox(
            color: AppColors.primary,
            child: SafeArea(bottom: false, child: header),
          ),
        ),
        // Not a lazy list: forms must stay built while scrolled off screen so
        // validation reaches every field.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: actionLabel == null
        ? null
        : AppPrimaryActionBar(label: actionLabel!, onPressed: onAction),
  );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppBrandHeader(
              title: 'MedicApp',
              subtitle: 'Đặt khám dễ dàng cho cả nhà',
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppIllustration(AppArt.welcome, height: 150),
                  const SizedBox(height: 16),
                  Text('Chào mừng bạn', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Tạo tài khoản một lần để đặt khám và theo dõi lịch khám '
                    'cho bạn và người thân.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  const _Benefit(
                    icon: AppIcons.calendar,
                    tone: AppTone.teal,
                    text: 'Đặt lịch khám trong vài bước',
                  ),
                  const _Benefit(
                    icon: AppIcons.qr,
                    tone: AppTone.lavender,
                    text: 'Tạo hồ sơ nhanh bằng mã QR trên thẻ CCCD',
                  ),
                  const _Benefit(
                    icon: AppIcons.family,
                    tone: AppTone.peach,
                    text: 'Quản lý hồ sơ và lịch khám của cả nhà',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('welcome-sign-up'),
                    onPressed: () => context.push(AppRoutes.signUp),
                    child: const Text('Tạo tài khoản mới'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('welcome-sign-in'),
                    onPressed: () => context.push(AppRoutes.signIn),
                    child: const Text('Tôi đã có tài khoản'),
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

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.tone, required this.text});
  final IconData icon;
  final AppTone tone;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        AppIconTile(icon: icon, tone: tone),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  AuthFailure? _failure;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _failure = null);
    if (!_form.currentState!.validate()) return;
    final result = ref
        .read(authSessionProvider.notifier)
        .signIn(_phone.text, _password.text);
    // On success the router leaves this page by itself.
    if (result is AuthFailure) setState(() => _failure = result);
  }

  @override
  Widget build(BuildContext context) => FormPageScaffold(
    header: AppPageHeader(
      title: 'Đăng nhập',
      onBack: () => AppRoutes.backOr(context, AppRoutes.welcome),
    ),
    actionLabel: 'Đăng nhập',
    onAction: _submit,
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            PhoneField(
              controller: _phone,
              errorText: _failure?.field == 'phone' ? _failure!.message : null,
            ),
            const SizedBox(height: 20),
            PasswordField(
              key: const Key('sign-in-password'),
              controller: _password,
              label: 'Mật khẩu',
              errorText: _failure?.field == 'password'
                  ? _failure!.message
                  : null,
              validator: (value) => value == null || value.isEmpty
                  ? 'Vui lòng nhập mật khẩu.'
                  : null,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Chưa có tài khoản?',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          TextButton(
            onPressed: () => context.pushReplacement(AppRoutes.signUp),
            child: const Text('Tạo tài khoản mới'),
          ),
        ],
      ),
      const AppStatusBanner(
        title: 'Bản thử nghiệm',
        message:
            'Tài khoản chỉ lưu trên điện thoại này và mất khi tắt app. '
            'Tài khoản mẫu: 0912 345 678, mật khẩu 123456.',
      ),
      TextButton(
        key: const Key('sign-in-demo'),
        onPressed: () {
          _phone.text = formatPhone(demoPhone);
          _password.text = demoPassword;
          setState(() => _failure = null);
        },
        child: const Text('Điền tài khoản mẫu'),
      ),
    ],
  );
}

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  AuthFailure? _failure;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _failure = null);
    if (!_form.currentState!.validate()) return;
    final result = ref
        .read(authSessionProvider.notifier)
        .signUp(_phone.text, _password.text);
    if (result is AuthFailure) setState(() => _failure = result);
  }

  @override
  Widget build(BuildContext context) => FormPageScaffold(
    header: AppFlowHeader(
      step: 1,
      totalSteps: 2,
      title: 'Tạo tài khoản',
      onBack: () => AppRoutes.backOr(context, AppRoutes.welcome),
    ),
    actionLabel: 'Tiếp tục',
    onAction: _submit,
    children: [
      Text(
        'Bạn sẽ dùng số điện thoại và mật khẩu này để đăng nhập.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      Form(
        key: _form,
        child: Column(
          children: [
            PhoneField(
              controller: _phone,
              errorText: _failure?.field == 'phone' ? _failure!.message : null,
            ),
            const SizedBox(height: 20),
            PasswordField(
              key: const Key('sign-up-password'),
              controller: _password,
              label: 'Mật khẩu',
              helperText: 'Ít nhất 6 ký tự, dễ nhớ với bạn.',
              errorText: _failure?.field == 'password'
                  ? _failure!.message
                  : null,
              validator: validateNewPassword,
            ),
            const SizedBox(height: 20),
            PasswordField(
              key: const Key('sign-up-confirm'),
              controller: _confirm,
              label: 'Nhập lại mật khẩu',
              validator: (value) => value != _password.text
                  ? 'Hai mật khẩu chưa giống nhau.'
                  : null,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Đã có tài khoản?',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          TextButton(
            onPressed: () => context.pushReplacement(AppRoutes.signIn),
            child: const Text('Đăng nhập'),
          ),
        ],
      ),
    ],
  );
}

class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.errorText});
  final TextEditingController controller;
  final String? errorText;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const Key('auth-phone'),
    controller: controller,
    keyboardType: TextInputType.phone,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.telephoneNumber],
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ .]')),
      LengthLimitingTextInputFormatter(16),
    ],
    style: Theme.of(context).textTheme.titleLarge,
    decoration: InputDecoration(
      labelText: 'Số điện thoại',
      hintText: 'Ví dụ: 0912 345 678',
      errorText: errorText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: const AppIcon(AppIcons.phone),
    ),
    validator: validatePhone,
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.errorText,
    this.validator,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  var _visible = false;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: !_visible,
    enableSuggestions: false,
    autocorrect: false,
    style: Theme.of(context).textTheme.titleLarge,
    onFieldSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      helperStyle: Theme.of(context).textTheme.bodySmall,
      helperMaxLines: 3,
      errorText: widget.errorText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: const AppIcon(AppIcons.lock),
      // A word, not just an eye icon, so the action is clear.
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          onPressed: () => setState(() => _visible = !_visible),
          child: Text(_visible ? 'Ẩn' : 'Hiện'),
        ),
      ),
    ),
    validator: widget.validator,
  );
}
