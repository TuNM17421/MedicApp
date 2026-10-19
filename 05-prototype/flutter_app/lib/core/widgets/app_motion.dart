import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A single policy for optional motion; never scales or limits user text.
abstract final class AppMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context) =>
      reduced(context) ? Duration.zero : const Duration(milliseconds: 180);
}

extension AppEntrance on Widget {
  /// Fades and lifts a block in when the screen opens; later [order]s come a
  /// little after, so the eye follows the page from top to bottom.
  Widget entrance(BuildContext context, {int order = 0}) =>
      AppMotion.reduced(context)
      ? this
      : animate(delay: Duration(milliseconds: 60 * order))
            .fadeIn(duration: 260.ms, curve: Curves.easeOut)
            .slideY(
              begin: 0.06,
              end: 0,
              duration: 260.ms,
              curve: Curves.easeOutCubic,
            );
}

/// New pages slide in from the side and fade (Material shared axis), so it is
/// clear the user went one step deeper. No motion when reduced motion is on.
class AppPageTransitions extends PageTransitionsBuilder {
  const AppPageTransitions();

  static const _sharedAxis = SharedAxisPageTransitionsBuilder(
    transitionType: SharedAxisTransitionType.horizontal,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppMotion.reduced(context)
      ? child
      : _sharedAxis.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

/// Fades the new tab in (Material fade through) when [index] changes.
class AppTabFade extends StatefulWidget {
  const AppTabFade({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<AppTabFade> createState() => _AppTabFadeState();
}

class _AppTabFadeState extends State<AppTabFade>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(AppTabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !AppMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeThroughTransition(
    animation: _controller,
    secondaryAnimation: kAlwaysDismissedAnimation,
    fillColor: Colors.transparent,
    child: widget.child,
  );
}
