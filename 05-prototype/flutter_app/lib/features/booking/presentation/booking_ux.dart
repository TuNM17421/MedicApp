import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_widgets.dart';

/// Only the current step enters. No outgoing copy of forms or payment actions.
class BookingStepEntrance extends StatelessWidget {
  const BookingStepEntrance({
    super.key,
    required this.step,
    required this.child,
  });
  final Object step;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return child
        .animate(key: ValueKey(step))
        .fadeIn(
          begin: 0.8,
          duration: AppMotion.duration(context),
          curve: Curves.easeOut,
        )
        .move(
          begin: const Offset(0, 6),
          end: Offset.zero,
          duration: AppMotion.duration(context),
          curve: Curves.easeOut,
        );
  }
}

class BookingSlotsSkeleton extends StatelessWidget {
  const BookingSlotsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Đang tải giờ khám. Vui lòng chờ.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Đang tải giờ khám…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          ExcludeFocus(
            child: Skeletonizer.zone(
              key: const Key('booking-slots-skeleton'),
              effect: AppMotion.reduced(context)
                  ? const SolidColorEffect(color: Color(0xFFE0EAE7))
                  : const PulseEffect(
                      from: Color(0xFFE0EAE7),
                      to: Color(0xFFF0F5F3),
                      duration: Duration(milliseconds: 1200),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final count in [7, 6]) ...[
                    Bone(width: 120, height: scale.scale(22), uniRadius: 8),
                    const SizedBox(height: 12),
                    AppChoiceGrid(
                      minItemWidth: 120,
                      children: [
                        for (var i = 0; i < count; i++)
                          Bone(height: scale.scale(26) + 32, uniRadius: 20),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
