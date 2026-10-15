import 'package:flutter/widgets.dart';

/// A single policy for optional motion; never scales or limits user text.
abstract final class AppMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context) =>
      reduced(context) ? Duration.zero : const Duration(milliseconds: 180);
}
