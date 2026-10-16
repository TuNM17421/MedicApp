import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// "Kết quả & đơn thuốc". Prescribing, the printed form and sending to the
/// app arrive in step 15; until then the tab says so.
class ResultTab extends StatelessWidget {
  const ResultTab(this.d, {super.key});
  final ChartData d;

  @override
  Widget build(BuildContext context) => const Panel(
    child: EmptyState(
      icon: LucideIcons.filePenLine,
      title: 'Kê đơn và gửi kết quả đang được làm',
      text:
          'Phần này có ở bước 15. Hiện web bác sĩ chỉ xem hàng chờ, '
          'tóm tắt trước khám và lịch sử khám.',
    ),
  );
}
