import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'app_icons.dart';

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    this.icon,
    this.initials,
    this.tone = AppTone.teal,
  });
  final IconData? icon;
  final String? initials;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppTokens.of(context).tone(tone);
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: initials != null
            ? Text(
                initials!,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.foreground),
                textScaler: TextScaler.noScaling,
              )
            : AppIcon(
                icon ?? AppIcons.person,
                color: colors.foreground,
                size: 26,
              ),
      ),
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: AppColors.divider),
        boxShadow: tokens.shadow,
      ),
      child: child,
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: Semantics(
        liveRegion: isLoading,
        child: Text(
          isLoading ? 'Đang xử lý…' : label,
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class AppPrimaryActionBar extends StatelessWidget {
  const AppPrimaryActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.divider)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: AppPrimaryButton(
          label: label,
          onPressed: onPressed,
          isLoading: isLoading,
        ),
      ),
    ),
  );
}

/// Reflows instead of shrinking text when system font size grows.
class AppChoiceGrid extends StatelessWidget {
  const AppChoiceGrid({
    super.key,
    required this.children,
    this.minItemWidth = 140,
  });
  final List<Widget> children;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final count = (constraints.maxWidth / (minItemWidth * scale))
          .floor()
          .clamp(1, 4);
      final width =
          (constraints.maxWidth - AppTokens.gap * (count - 1)) / count;
      return Wrap(
        spacing: AppTokens.gap,
        runSpacing: AppTokens.gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.errorText,
    this.onChanged,
    this.controller,
    this.keyboardType,
  });
  final String label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: keyboardType,
    style: Theme.of(context).textTheme.bodyLarge,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
  );
}
