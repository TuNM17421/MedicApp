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
  static const mic = LucideIcons.mic;
  static const micOff = LucideIcons.micOff;
  static const send = LucideIcons.sendHorizontal;
  static const smart = LucideIcons.sparkles;
  static const undo = LucideIcons.undo2;
  static const stop = LucideIcons.square;
  static const phone = LucideIcons.phone;
  static const qr = LucideIcons.qrCode;
  static const family = LucideIcons.usersRound;
  static const lock = LucideIcons.lockKeyhole;
  static const image = LucideIcons.image;
  static const flashlight = LucideIcons.flashlight;
  static const signOut = LucideIcons.logOut;
  static const edit = LucideIcons.pencil;
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
