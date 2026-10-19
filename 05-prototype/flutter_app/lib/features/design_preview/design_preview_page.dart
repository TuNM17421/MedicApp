import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_choices.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_headers.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_primitives.dart';

/// Component preview only. No booking draft, routes, payment or backend.
class DesignPreviewPage extends StatefulWidget {
  const DesignPreviewPage({super.key});
  @override
  State<DesignPreviewPage> createState() => _DesignPreviewPageState();
}

class _DesignPreviewPageState extends State<DesignPreviewPage> {
  final _componentsKey = GlobalKey();
  String _choice = 'service';
  String _slot = '07:30';
  String _date = '15/10';
  int _navIndex = 0;

  void _help() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bản xem trước giao diện',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Bạn có thể thử chọn thẻ, ô giờ và xem các kiểu thông báo. Chưa có luồng đặt lịch hoặc giao dịch thực tế.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: 'Đã hiểu',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(String title, List<Widget> children, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      key: const Key('design-preview-scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBrandHeader(
            title: 'MedicApp',
            subtitle: 'Xem trước giao diện',
            onHelp: _help,
            child: Text(
              'Rõ ràng hơn.\nDễ thao tác hơn.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
          Stack(
            children: [
              Container(
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: AppSurface(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppIconTile(icon: AppIcons.calendar),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bộ thành phần',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppPrimaryButton(
                        label: 'Xem các thành phần',
                        onPressed: () => Scrollable.ensureVisible(
                          _componentsKey.currentContext!,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _section('Dễ đọc, dễ nhận biết', [
            Text(
              'Be Vietnam Pro · 18 / 16',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Text('Tiếng Việt rõ dấu: đặt khám, người thân, chuyên khoa.'),
            const AppStatusBanner(
              message: 'Đây là bộ mẫu giao diện. Các lựa chọn chỉ dùng để xem trước.',
            ),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppIconTile(icon: AppIcons.calendar),
                AppIconTile(icon: AppIcons.person, tone: AppTone.lavender),
                AppIconTile(icon: AppIcons.hospital, tone: AppTone.sky),
                AppIconTile(icon: AppIcons.payment, tone: AppTone.peach),
              ],
            ),
          ], key: _componentsKey),
          _section('Thẻ lựa chọn', [
            AppChoiceCard(
              key: const Key('service-choice'),
              title: 'Khám dịch vụ',
              description: 'Tự chi trả',
              icon: AppIcons.doctor,
              selected: _choice == 'service',
              onTap: () => setState(() => _choice = 'service'),
            ),
            AppChoiceCard(
              key: const Key('insurance-choice'),
              title: 'Khám BHYT',
              icon: AppIcons.profile,
              tone: AppTone.lavender,
              selected: _choice == 'insurance',
              onTap: () => setState(() => _choice = 'insurance'),
            ),
            const AppChoiceCard(
              title: 'Lựa chọn chưa khả dụng',
              icon: AppIcons.hospital,
              enabled: false,
              unavailableReason: 'Vui lòng chọn một phương án khác.',
            ),
          ]),
          _section('Ô ngày và giờ', [
            AppChoiceGrid(
              children: [
                AppSelectionChip(
                  label: 'Thứ Năm',
                  subtitle: '15/10',
                  selected: _date == '15/10',
                  onTap: () => setState(() => _date = '15/10'),
                ),
                const AppSelectionChip(
                  label: 'Thứ Sáu',
                  subtitle: '16/10',
                  enabled: false,
                ),
                AppSelectionChip(
                  label: 'Thứ Bảy',
                  subtitle: '17/10',
                  selected: _date == '17/10',
                  onTap: () => setState(() => _date = '17/10'),
                ),
              ],
            ),
            AppChoiceGrid(
              children: [
                for (final time in ['07:30', '08:00', '08:30', '09:00'])
                  AppSelectionChip(
                    key: ValueKey('slot-$time'),
                    label: time,
                    pill: true,
                    selected: _slot == time,
                    enabled: time != '09:00',
                    onTap: () => setState(() => _slot = time),
                  ),
              ],
            ),
          ]),
          _section('Nhập thông tin', const [
            AppTextField(label: 'Họ và tên', hint: 'Nhập họ và tên'),
            AppTextField(
              label: 'Số điện thoại',
              errorText: 'Vui lòng kiểm tra lại số điện thoại.',
              keyboardType: TextInputType.phone,
            ),
          ]),
          _section('Thông báo trạng thái', const [
            AppStatusBanner(
              status: AppStatus.warning,
              title: 'Cần kiểm tra lại',
              message: 'Một số lựa chọn đã thay đổi.',
            ),
            AppStatusBanner(
              status: AppStatus.error,
              title: 'Chưa hoàn tất',
              message: 'Thông tin chưa được xác nhận.',
            ),
            AppStatusBanner(
              status: AppStatus.success,
              title: 'Đã cập nhật',
              message: 'Thay đổi đã được ghi nhận.',
            ),
          ]),
          _section('Nhóm thông tin', [
            AppReviewSection(
              title: 'Người khám',
              items: const [(label: 'Họ và tên', value: 'Nguyễn An')],
              onEdit: _help,
            ),
            const AppTicketCard(
              title: 'Vé khám mẫu',
              reference: 'MẪU-001',
              details: [
                (label: 'Nơi khám', value: 'Cơ sở minh họa'),
                (label: 'Ngày và giờ', value: 'Thứ Năm, 15/10 · 07:30'),
              ],
            ),
          ]),
          _section('Trạng thái dữ liệu', [
            const AppEmptyState(
              title: 'Chưa có lịch hẹn',
              message: 'Lịch hẹn sẽ được hiển thị tại đây.',
            ),
            const AppLoadingState(),
            AppErrorState(
              message: 'Vui lòng thử lại khi kết nối ổn định.',
              onRetry: _help,
            ),
          ]),
          _section('Header và thanh hành động', [
            AppPageHeader(title: 'Hồ sơ', onBack: _help, onHelp: _help),
            AppFlowHeader(
              step: 2,
              title: 'Người khám',
              patientName: 'Nguyễn An',
              onBack: _help,
              onHelp: _help,
            ),
            AppPrimaryActionBar(label: 'Nút chính mẫu', onPressed: _help),
            const AppPrimaryButton(
              label: 'Xác nhận',
              onPressed: null,
              isLoading: true,
            ),
          ]),
          _section('Thanh điều hướng mẫu', [
            Text(
              'Chạm để xem trạng thái được chọn. Chưa điều hướng đến màn hình chức năng.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            AppBottomNav(
              selectedIndex: _navIndex,
              onSelected: (i) => setState(() => _navIndex = i),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}
