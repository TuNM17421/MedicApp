import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/auth_controller.dart';
import 'health_consent.dart';

/// Asks the account holder, in plain words, to keep their family's health data
/// on this phone. Nothing is pre-ticked; declining keeps today's behaviour
/// (data lives only until the app closes).
class HealthConsentPage extends ConsumerStatefulWidget {
  const HealthConsentPage({super.key});

  @override
  ConsumerState<HealthConsentPage> createState() => _HealthConsentPageState();
}

class _HealthConsentPageState extends ConsumerState<HealthConsentPage> {
  bool _understood = false;

  void _accept() {
    ref
        .read(authSessionProvider.notifier)
        .setConsent(
          HealthConsent(
            version: healthConsentVersion,
            acceptedAt: DateTime.now(),
          ),
        );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Đã lưu hồ sơ trên máy này.')),
      );
    AppRoutes.backOr(context, AppRoutes.account);
  }

  void _decline() {
    ref.read(consentPromptDismissedProvider.notifier).dismiss();
    AppRoutes.backOr(context, AppRoutes.account);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AppPageBody(
        title: 'Lưu dữ liệu sức khỏe',
        onBack: () => AppRoutes.backOr(context, AppRoutes.account),
        children: [
          Text(
            'Bạn có muốn lưu hồ sơ của gia đình trên điện thoại này không?',
            style: text.titleLarge,
          ),
          const AppReviewSection(
            title: 'Những gì được lưu',
            items: [
              (
                label: 'Hồ sơ',
                value: 'Họ tên, năm sinh, giới tính, số CCCD, địa chỉ.',
              ),
              (
                label: 'Sức khỏe',
                value: 'Các bệnh đang theo dõi của từng người.',
              ),
              (
                label: 'Tài khoản',
                value: 'Số điện thoại và mật khẩu đăng nhập.',
              ),
            ],
          ),
          const AppReviewSection(
            title: 'Lưu như thế nào',
            items: [
              (
                label: 'Ở đâu',
                value: 'Chỉ trên điện thoại này, không gửi đi đâu.',
              ),
              (
                label: 'Bảo vệ',
                value: 'Được mã hóa; chỉ MedicApp trên máy này mở được.',
              ),
              (
                label: 'Rút lại',
                value: 'Vào Tài khoản, chọn "Ngừng lưu" bất kỳ lúc nào. Dữ liệu trên máy sẽ bị xóa.',
              ),
            ],
          ),
          const AppStatusBanner(
            status: AppStatus.warning,
            title: 'Đây là dữ liệu nhạy cảm',
            message: 'Thông tin sức khỏe là dữ liệu cá nhân nhạy cảm theo Nghị định 356/2025/NĐ-CP. Nếu không đồng ý, app vẫn dùng được nhưng hồ sơ sẽ mất khi đóng app.',
          ),
          AppSurface(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const Key('consent-understood'),
                value: _understood,
                onChanged: (value) => setState(() => _understood = value!),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Tôi hiểu đây là dữ liệu sức khỏe nhạy cảm và đồng ý lưu trên máy này.',
                  style: text.bodyLarge,
                ),
              ),
            ),
          ),
          AppPrimaryButton(
            key: const Key('consent-accept'),
            label: 'Đồng ý và lưu',
            onPressed: _understood ? _accept : null,
          ),
          OutlinedButton(
            key: const Key('consent-decline'),
            onPressed: _decline,
            child: const Text('Không lưu'),
          ),
        ],
      ),
    );
  }
}

/// Home-page prompt shown until the signed-in holder decides.
class HealthConsentPrompt extends ConsumerWidget {
  const HealthConsentPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authSessionProvider) != null;
    final undecided = ref.watch(healthConsentProvider) == null;
    final dismissed = ref.watch(consentPromptDismissedProvider);
    if (!signedIn || !undecided || dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AppSurface(
        key: const Key('consent-prompt'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIcon(AppIcons.lock),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Lưu hồ sơ trên máy này?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Hiện tại hồ sơ gia đình sẽ mất khi bạn đóng app.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  key: const Key('consent-prompt-later'),
                  onPressed: () => ref
                      .read(consentPromptDismissedProvider.notifier)
                      .dismiss(),
                  child: const Text('Để sau'),
                ),
                FilledButton(
                  key: const Key('consent-prompt-open'),
                  onPressed: () => context.push(AppRoutes.healthConsent),
                  child: const Text('Xem và đồng ý'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
