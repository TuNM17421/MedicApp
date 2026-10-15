import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One icon vocabulary. Screen code does not depend on individual icon packages.
abstract final class AppIcons {
  static const calendar = LucideIcons.calendarDays;
  static const person = LucideIcons.userRound;
  static const hospital = LucideIcons.hospital;
  static const doctor = LucideIcons.stethoscope;
  static const payment = LucideIcons.creditCard;
  static const help = LucideIcons.circleHelp;
  static const back = LucideIcons.chevronLeft;
  static const next = LucideIcons.arrowRight;
  static const check = LucideIcons.check;
  static const unselected = LucideIcons.circle;
  static const info = LucideIcons.info;
  static const warning = LucideIcons.triangleAlert;
  static const error = LucideIcons.circleAlert;
  static const success = LucideIcons.circleCheck;
  static const home = LucideIcons.house;
  static const profile = LucideIcons.idCard;
  static const notifications = LucideIcons.bell;
  static const clock = LucideIcons.clock;
  static const search = LucideIcons.search;
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.color, this.size = 24, this.label});
  final IconData icon;
  final Color? color;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: color, size: size, semanticLabel: label);
}
