import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/app_widgets.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppPageBody(
      title: 'Trợ giúp',
      onBack: () => AppRoutes.backOrHome(context),
      children: [
        if (kDebugMode)
          AppLinkCard(
            title: 'Kịch bản thử đặt lịch',
            icon: AppIcons.info,
            onTap: () => context.push(AppRoutes.bookingDemo),
          ),
        const AppReviewSection(
          title: 'Sử dụng các mục chính',
          items: [
            (label: 'Hồ sơ', value: 'Chọn và xem thông tin người thân.'),
            (
              label: 'Thông báo',
              value: 'Mở thông báo để xem nội dung; số chưa đọc được cập nhật tự động.',
            ),
            (label: 'Tài khoản', value: 'Xem thông tin tài khoản của bạn.'),
          ],
        ),
      ],
    ),
  );
}

class RouteNotFoundPage extends StatelessWidget {
  const RouteNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppPageBody(
      title: 'Không tìm thấy trang',
      children: [
        AppEmptyState(
          title: 'Đường dẫn không còn phù hợp',
          message: 'Bạn có thể quay về trang chủ để tiếp tục.',
          actionLabel: 'Về trang chủ',
          onAction: () => context.go(AppRoutes.home),
        ),
      ],
    ),
  );
}
