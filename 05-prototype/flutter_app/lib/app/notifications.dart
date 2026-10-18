import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_hub.dart';
import '../features/meds/application/meds_providers.dart';
import '../features/meds/data/med_reminder_scheduler.dart';
import '../features/visit_prep/reminder_scheduler.dart';
import '../features/visit_prep/visit_prep.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';

/// The app's one notification plugin. Taps on visit reminders open the
/// appointment; taps on medication reminders open Thuốc hôm nay, and their
/// buttons record or snooze the dose.
final notificationHubProvider = Provider<NotificationHub>((ref) {
  late final NotificationHub hub;
  hub = NotificationHub(
    onBackgroundResponse: medBackgroundResponse,
    onResponse: (response) async {
      final router = ref.read(appRouterProvider);
      if (MedPayload.decode(response.payload) case final payload?) {
        final handled = await handleMedAction(
          response,
          plugin: hub.plugin,
          store: ref.read(pendingDoseStoreProvider),
          now: ref.read(prepClockProvider)(),
          mode: await hub.scheduleMode(),
        );
        if (handled) {
          await ref.read(doseLogProvider.notifier).drainPending();
        } else if (payload.ring) {
          // Opened by the alarm itself: on the lock screen, or a tap on it.
          router.go(AppRoutes.medAlarm, extra: payload);
        } else {
          router.go(AppRoutes.meds);
        }
        return;
      }
      final visitId = LocalReminderScheduler.visitIdOf(response.payload);
      if (visitId != null &&
          response.actionId != LocalReminderScheduler.dismissAction) {
        router.go(AppRoutes.appointment(visitId));
      }
    },
  );
  return hub;
});
