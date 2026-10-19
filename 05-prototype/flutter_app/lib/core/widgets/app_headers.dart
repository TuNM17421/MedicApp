import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_icons.dart';

class AppBrandHeader extends StatelessWidget {
  const AppBrandHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onHelp,
    this.child,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onHelp;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.primary,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final brand = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                );
                final help = onHelp == null
                    ? null
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: onHelp,
                        icon: const AppIcon(AppIcons.help, size: 20),
                        label: const Text('Trợ giúp'),
                      );
                if (constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(16) > 21) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brand,
                      if (help != null) ...[const SizedBox(height: 12), help],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: brand),
                    if (help != null) ...[const SizedBox(width: 12), help],
                  ],
                );
              },
            ),
            if (child != null) ...[const SizedBox(height: 24), child!],
          ],
        ),
      ),
    ),
  );
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.onHelp,
  });
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.primary,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              if (onBack != null)
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const AppIcon(AppIcons.back),
                  label: const Text('Quay lại'),
                ),
              if (onHelp != null)
                TextButton.icon(
                  onPressed: onHelp,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const AppIcon(AppIcons.help),
                  label: const Text('Trợ giúp'),
                ),
            ],
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class AppFlowHeader extends StatelessWidget {
  const AppFlowHeader({
    super.key,
    required this.step,
    required this.title,
    this.totalSteps = 6,
    this.patientName,
    this.onBack,
    this.onHelp,
  }) : assert(step >= 1 && step <= totalSteps);
  final int step;
  final int totalSteps;
  final String title;
  final String? patientName;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: 'Bước $step/$totalSteps · $title',
          onBack: onBack,
          onHelp: onHelp,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 1; i <= totalSteps; i++)
                      Expanded(
                        child: Container(
                          height: 6,
                          margin: EdgeInsets.only(
                            right: i < totalSteps ? 4 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: i <= step ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (patientName != null) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Người khám: $patientName',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.unreadCount = 0,
  }) : assert(selectedIndex >= 0 && selectedIndex < 5);

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int unreadCount;
  static const items = [
    (label: 'Trang chủ', icon: AppIcons.home),
    (label: 'Hồ sơ', icon: AppIcons.profile),
    (label: 'Đặt lịch', icon: AppIcons.calendar),
    (label: 'Thông báo', icon: AppIcons.notifications),
    (label: 'Tài khoản', icon: AppIcons.person),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88 + MediaQuery.paddingOf(context).bottom,
    child: Stack(
      children: [
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1016302C),
                  blurRadius: 18,
                  offset: Offset(0, -3),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 8,
          right: 8,
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    key: ValueKey('nav-${items[i].label}'),
                    button: true,
                    selected: i != 2 && selectedIndex == i,
                    label: i == 3 && unreadCount > 0
                        ? '${items[i].label}, $unreadCount chưa đọc'
                        : items[i].label,
                    onTap: () => onSelected(i),
                    excludeSemantics: true,
                    child: Tooltip(
                      message: items[i].label,
                      excludeFromSemantics: true,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          excludeFromSemantics: true,
                          onTap: () => onSelected(i),
                          child: SizedBox(
                            height: 80,
                            child: Align(
                              alignment: i == 2
                                  ? Alignment.topCenter
                                  : const Alignment(0, .3),
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                width: i == 2 ? 64 : 52,
                                height: i == 2 ? 64 : 48,
                                decoration: BoxDecoration(
                                  color: i == 2
                                      ? AppColors.primary
                                      : selectedIndex == i
                                      ? AppColors.selected
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    i == 2 ? 32 : 18,
                                  ),
                                  border: i == 2
                                      ? Border.all(
                                          color: Colors.white,
                                          width: 4,
                                        )
                                      : null,
                                  boxShadow: i == 2
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x260F766E),
                                            blurRadius: 12,
                                            offset: Offset(0, 3),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Badge(
                                  isLabelVisible: i == 3 && unreadCount > 0,
                                  label: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                  ),
                                  child: AppIcon(
                                    items[i].icon,
                                    size: 26,
                                    color: i == 2
                                        ? Colors.white
                                        : selectedIndex == i
                                        ? AppColors.primary
                                        : AppColors.secondaryInk,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
