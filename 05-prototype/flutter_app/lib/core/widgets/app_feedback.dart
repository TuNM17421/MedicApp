import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_icons.dart';
import 'app_primitives.dart';

enum AppStatus { info, warning, error, success }

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({
    super.key,
    required this.message,
    this.status = AppStatus.info,
    this.title,
    this.liveRegion = false,
  });
  final String message;
  final String? title;
  final AppStatus status;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status) {
      AppStatus.info => (AppTone.sky, AppIcons.info),
      AppStatus.warning => (AppTone.warning, AppIcons.warning),
      AppStatus.error => (AppTone.error, AppIcons.error),
      AppStatus.success => (AppTone.success, AppIcons.success),
    };
    final colors = AppTokens.of(context).tone(tone);
    return Semantics(
      liveRegion: liveRegion,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: colors.foreground, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: AppIcon(icon, color: colors.foreground)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: colors.foreground),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.foreground),
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

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = AppIcons.calendar,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Column(
      children: [
        AppIconTile(icon: icon),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          AppPrimaryButton(label: actionLabel!, onPressed: onAction),
        ],
      ],
    ),
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppStatusBanner(
        status: AppStatus.error,
        title: 'Chưa tải được thông tin',
        message: message,
        liveRegion: true,
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: onRetry,
        child: const Text('Thử lại', textAlign: TextAlign.center),
      ),
    ],
  );
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = 'Đang tải thông tin…'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    excludeSemantics: true,
    child: AppSurface(
      child: Row(
        children: [
          if (MediaQuery.disableAnimationsOf(context))
            const AppIcon(AppIcons.clock)
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    ),
  );
}

class AppReviewSection extends StatelessWidget {
  const AppReviewSection({
    super.key,
    required this.title,
    required this.items,
    this.onEdit,
  });
  final String title;
  final List<({String label, String value})> items;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (onEdit != null)
              Semantics(
                label: 'Sửa ${title.toLowerCase()}',
                button: true,
                onTap: onEdit,
                excludeSemantics: true,
                child: TextButton(onPressed: onEdit, child: const Text('Sửa')),
              ),
          ],
        ),
        const Divider(),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class AppTicketCard extends StatelessWidget {
  const AppTicketCard({
    super.key,
    required this.title,
    required this.reference,
    required this.details,
    this.status = AppStatus.success,
  });
  final String title;
  final String reference;
  final List<({String label, String value})> details;
  final AppStatus status;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppTokens.of(context).ticketRadius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppTokens.of(context).ticketRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStatusBanner(title: title, message: reference, status: status),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in details)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          item.value,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
