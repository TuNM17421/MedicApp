import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/notifications.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/notifications/notification_hub.dart';
import '../auth/auth_controller.dart';
import '../booking/application/booking_providers.dart';
import '../booking/domain/booking_models.dart';
import 'reminder_planner.dart';
import 'visit_prep.dart';

/// Reminders for every upcoming appointment of the signed-in account,
/// soonest first.
final reminderPlanProvider = Provider<List<PlannedReminder>>((ref) {
  if (ref.watch(authSessionProvider) == null) return const [];
  final profiles = ref.watch(profileCatalogProvider);
  final notes = ref.watch(visitPrepNotesProvider);
  final now = ref.watch(prepClockProvider)();
  final plan = [
    for (final record in ref.watch(appointmentsProvider).records)
      if (record.receipt.status != PaymentStatus.failed)
        ...planReminders(
          visit: record.visit,
          patient: profiles
              .where((profile) => profile.id == record.visit.patientId)
              .firstOrNull,
          notes: [
            for (final note in notes)
              if (note.visitId == record.visit.id) note,
          ],
          now: now,
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return List.unmodifiable(plan);
});

/// Puts the plan on the phone's notification schedule.
abstract interface class ReminderScheduler {
  /// Replaces every scheduled reminder. Returns false when the user has not
  /// allowed notifications.
  Future<bool> replaceAll(List<PlannedReminder> reminders);
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalReminderScheduler(ref.watch(notificationHubProvider)),
);

/// Whether the phone allows our notifications; null until first asked.
final notificationsAllowedProvider =
    NotifierProvider<NotificationsAllowed, bool?>(NotificationsAllowed.new);

class NotificationsAllowed extends Notifier<bool?> {
  @override
  bool? build() => null;

  void set(bool value) => state = value;
}

/// Keeps the phone's schedule equal to [reminderPlanProvider]. Watched once
/// near the app root.
final reminderSyncProvider = Provider<void>((ref) {
  ref.listen(reminderPlanProvider, (previous, next) async {
    if (listEquals(previous, next)) return;
    if (next.isEmpty && (previous == null || previous.isEmpty)) return;
    final allowed = await ref.read(reminderSchedulerProvider).replaceAll(next);
    if (ref.mounted) {
      ref.read(notificationsAllowedProvider.notifier).set(allowed);
    }
  }, fireImmediately: true);
});

/// Local notifications scheduled on the phone itself: no push server, nothing
/// leaves the device. Taps are routed by [NotificationHub]; the payload is
/// `visit:<visit id>`.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler(this.hub);
  final NotificationHub hub;

  static const openAction = 'open';
  static const dismissAction = 'dismiss';
  static const payloadPrefix = 'visit:';

  /// The visit a notification is about, or null when it is not a visit
  /// reminder. Payloads without a prefix come from before medication
  /// reminders existed.
  static String? visitIdOf(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith(payloadPrefix)) {
      return payload.substring(payloadPrefix.length);
    }
    return payload.contains(':') ? null : payload;
  }

  static AndroidNotificationDetails _details(PlannedReminder reminder) =>
      AndroidNotificationDetails(
        'visit_reminders',
        'Nhắc lịch khám',
        channelDescription: 'Nhắc chuẩn bị trước khi khám và giờ đi khám',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        // Health details stay hidden on the lock screen until unlocked.
        visibility: NotificationVisibility.private,
        icon: 'ic_stat_medic',
        color: AppColors.primary,
        subText: reminder.header,
        styleInformation: BigTextStyleInformation(
          reminder.html,
          htmlFormatBigText: true,
          contentTitle: reminder.title,
        ),
        // Gone from the shade an hour after the visit starts.
        timeoutAfter: reminder.visitAt
            .add(const Duration(hours: 1))
            .difference(reminder.at)
            .inMilliseconds,
        actions: const [
          AndroidNotificationAction(
            openAction,
            'Xem hướng dẫn',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(dismissAction, 'Đã hiểu'),
        ],
      );

  @override
  Future<bool> replaceAll(List<PlannedReminder> reminders) async {
    try {
      await hub.ready();
      var allowed = true;
      if (reminders.isNotEmpty) allowed = await hub.requestPermission();
      await hub.cancelRange(
        NotificationIds.visitStart,
        NotificationIds.visitEnd,
      );
      final mode = await hub.scheduleMode();
      final count = NotificationIds.visitEnd - NotificationIds.visitStart;
      for (final (index, reminder) in reminders.take(count).indexed) {
        await hub.plugin.zonedSchedule(
          id: NotificationIds.visitStart + index,
          scheduledDate: NotificationHub.inVietnam(reminder.at),
          title: reminder.title,
          body: reminder.summary,
          payload: '$payloadPrefix${reminder.visitId}',
          androidScheduleMode: mode,
          notificationDetails: NotificationDetails(android: _details(reminder)),
        );
      }
      return allowed;
    } on MissingPluginException {
      // Widget tests and unsupported platforms: the plan still shows in-app.
      return true;
    }
  }
}
