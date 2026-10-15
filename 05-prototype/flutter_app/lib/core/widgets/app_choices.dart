import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_icons.dart';
import 'app_motion.dart';
import 'app_primitives.dart';

class AppChoiceCard extends StatelessWidget {
  const AppChoiceCard({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.tone = AppTone.teal,
    this.selected = false,
    this.enabled = true,
    this.unavailableReason,
    this.onTap,
  });
  final String title;
  final String? description;
  final IconData? icon;
  final AppTone tone;
  final bool selected;
  final bool enabled;
  final String? unavailableReason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final action = enabled ? onTap : null;
    final radius = BorderRadius.circular(AppTokens.of(context).cardRadius);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (!enabled && unavailableReason != null) ...[
          const SizedBox(height: 8),
          Text(
            unavailableReason!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
    final mark = AppIcon(
      selected ? AppIcons.success : AppIcons.unselected,
      color: selected ? AppColors.primary : AppColors.secondaryInk,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: action != null,
      onTap: action,
      label: [
        title,
        ?description,
        if (!enabled && unavailableReason != null) unavailableReason!,
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        animationDuration: AppMotion.duration(context),
        color: selected
            ? AppColors.selected
            : enabled
            ? Colors.white
            : const Color(0xFFF1F4F3),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.outline,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: InkWell(
          onTap: action,
          excludeFromSemantics: true,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final large = MediaQuery.textScalerOf(context).scale(18) > 27;
                if (large) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (icon != null) AppIconTile(icon: icon, tone: tone),
                          const Spacer(),
                          mark,
                        ],
                      ),
                      const SizedBox(height: 12),
                      content,
                    ],
                  );
                }
                return Row(
                  children: [
                    if (icon != null) ...[
                      AppIconTile(icon: icon, tone: tone),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: content),
                    const SizedBox(width: 12),
                    mark,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class AppSelectionChip extends StatelessWidget {
  const AppSelectionChip({
    super.key,
    required this.label,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.pill = false,
    this.onTap,
  });
  final String label;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final bool pill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final action = enabled ? onTap : null;
    final radius = BorderRadius.circular(pill && !selected ? 40 : 14);
    final color = selected
        ? Colors.white
        : enabled
        ? AppColors.ink
        : AppColors.secondaryInk;
    return Semantics(
      button: true,
      selected: selected,
      enabled: action != null,
      onTap: action,
      label: [label, ?subtitle, if (!enabled) 'Hết chỗ'].join('. '),
      excludeSemantics: true,
      child: Material(
        animationDuration: AppMotion.duration(context),
        color: selected
            ? AppColors.primary
            : enabled
            ? Colors.white
            : const Color(0xFFEEF1F0),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.outline,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: action,
          excludeFromSemantics: true,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              decoration: enabled
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: color),
                        ),
                      if (!enabled)
                        Text(
                          'Hết chỗ',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 20,
                  child: selected
                      ? AppIcon(AppIcons.check, size: 20, color: color)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
