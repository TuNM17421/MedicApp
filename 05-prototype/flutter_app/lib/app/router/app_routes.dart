import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const home = '/home';
  static const profiles = '/profiles';
  static const notifications = '/notifications';
  static const account = '/account';
  static const appointments = '/home/appointments';
  static const booking = '/booking';
  static const smart = '/smart';
  static const smartFromBooking = '/smart?from=booking';
  static const bookingDemo = '/booking-demo';
  static String appointment(String id) =>
      '$appointments/${Uri.encodeComponent(id)}';
  static const help = '/help';
  static const designPreview = '/design-preview';

  static String profile(String id) => '$profiles/${Uri.encodeComponent(id)}';
  static String notice(String id) =>
      '$notifications/${Uri.encodeComponent(id)}';

  static void backOrHome(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(home);
    }
  }
}
