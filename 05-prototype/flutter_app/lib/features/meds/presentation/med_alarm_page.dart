import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../visit_prep/visit_prep.dart';
import '../application/meds_providers.dart';
import '../data/med_reminder_scheduler.dart';

/// What a ringing medication alarm opens: on the lock screen, or when the
/// alarm is tapped. Both buttons stop the ringing.
class MedAlarmPage extends ConsumerWidget {
  const MedAlarmPage({super.key, required this.payload});
  final MedPayload payload;

  /// "Thuốc của bạn · 07:00" → 07:00.
  String get _time => payload.header.split(' · ').last;

  Future<void> _taken(BuildContext context, WidgetRef ref) async {
    final log = ref.read(doseLogProvider.notifier);
    for (final key in payload.keys) {
      log.taken(key);
    }
    await ref.read(medReminderSchedulerProvider).stopRinging(payload.keys);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Đã ghi: uống thuốc lúc $_time.')));
    context.go(AppRoutes.meds);
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref) async {
    await ref
        .read(medReminderSchedulerProvider)
        .snooze(payload, ref.read(prepClockProvider)());
    await ref.read(medReminderSchedulerProvider).stopRinging(payload.keys);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Sẽ nhắc lại sau 10 phút.')));
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget bell = Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: const Icon(AppIcons.alarm, size: 48, color: Colors.white),
    );
    if (!still) {
      bell = bell
          .animate(onPlay: (controller) => controller.repeat())
          .shake(hz: 4, rotation: 0.08, duration: 900.ms)
          .then(delay: 600.ms);
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: bell),
              const SizedBox(height: 20),
              Text(
                _time,
                textAlign: TextAlign.center,
                style: text.displayMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  payload.title,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: AppSurface(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, line) in payload.lines.indexed) ...[
                          if (index > 0) const Divider(height: 24),
                          Text(line.label, style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text(line.text, style: text.bodyLarge),
                        ],
                        if (payload.lines.isEmpty)
                          Text(payload.summary, style: text.titleMedium),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('med-alarm-taken'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(64),
                  textStyle: text.titleLarge,
                ),
                onPressed: () => _taken(context, ref),
                icon: const Icon(AppIcons.check),
                label: const Text('Đã uống'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('med-alarm-snooze'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => _snooze(context, ref),
                child: const Text('Nhắc lại sau 10 phút'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
