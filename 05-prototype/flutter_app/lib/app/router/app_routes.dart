import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const home = '/home';
  static const profiles = '/profiles';
  static const notifications = '/notifications';
  static const account = '/account';
  static const appointments = '/home/appointments';
  static const meds = '/home/meds';
  static const booking = '/booking';
  static const smart = '/smart';
  static const smartFromBooking = '/smart?from=booking';
  static const bookingDemo = '/booking-demo';
  static const facilityMap = '/facility-map';
  static const facilityMapFromBooking = '/facility-map?from=booking';
  static String appointment(String id) =>
      '$appointments/${Uri.encodeComponent(id)}';
  static String visitResult(String id) => '${appointment(id)}/result';
  static String shareWithClinic(String id) => '${appointment(id)}/share';
  static const help = '/help';
  static const healthConsent = '/health-consent';
  static const designPreview = '/design-preview';

  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const authPaths = {welcome, signIn, signUp};

  static const addProfilePath = '/profile-new';
  static const scanCccdPath = '/profile-new/scan';
  static const profileFormPath = '/profile-new/form';
  static const profileSetupPaths = {
    addProfilePath,
    scanCccdPath,
    profileFormPath,
  };
  static String _for(bool self) => self ? '?for=self' : '?for=family';
  static String addProfile({required bool self}) =>
      '$addProfilePath${_for(self)}';
  static String scanCccd({required bool self}) => '$scanCccdPath${_for(self)}';
  static String profileForm({required bool self}) =>
      '$profileFormPath${_for(self)}';

  static String profile(String id) => '$profiles/${Uri.encodeComponent(id)}';
  static String notice(String id) =>
      '$notifications/${Uri.encodeComponent(id)}';

  static void backOrHome(BuildContext context) => backOr(context, home);

  static void backOr(BuildContext context, String fallback) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }
}
