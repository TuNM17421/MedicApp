import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_headers.dart';
import 'app_icons.dart';
import 'app_primitives.dart';

/// Header scrolls with the content, including at large system text sizes.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.title,
    required this.children,
    this.onBack,
    this.onHelp,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: PageStorageKey(title),
    slivers: [
      SliverToBoxAdapter(
        child: ColoredBox(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: AppPageHeader(title: title, onBack: onBack, onHelp: onHelp),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverList.list(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              children[i],
            ],
          ],
        ),
      ),
    ],
  );
}

class AppLinkCard extends StatelessWidget {
  const AppLinkCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon = AppIcons.next,
    this.tone = AppTone.teal,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final AppTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.of(context).cardRadius),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppTokens.of(context).cardRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppIconTile(icon: icon, tone: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const ExcludeSemantics(child: AppIcon(AppIcons.next, size: 20)),
          ],
        ),
      ),
    ),
  );
}
