import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../app/state/app_state.dart';
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
  (ref) => LocalReminderScheduler(),
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
/// leaves the device. Uses inexact alarms, so Android may deliver a reminder
/// a few minutes late to save battery.
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  static const _channel = AndroidNotificationDetails(
    'visit_reminders',
    'Nhắc lịch khám',
    channelDescription: 'Nhắc chuẩn bị trước khi khám và giờ đi khám',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> _init() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  @override
  Future<bool> replaceAll(List<PlannedReminder> reminders) async {
    try {
      await (_ready ??= _init());
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      var allowed = true;
      if (reminders.isNotEmpty) {
        allowed = await android?.requestNotificationsPermission() ?? true;
      }
      await _plugin.cancelAll();
      final vietnam = tz.getLocation('Asia/Ho_Chi_Minh');
      for (final (index, reminder) in reminders.indexed) {
        await _plugin.zonedSchedule(
          id: index,
          scheduledDate: tz.TZDateTime(
            vietnam,
            reminder.at.year,
            reminder.at.month,
            reminder.at.day,
            reminder.at.hour,
            reminder.at.minute,
          ),
          title: reminder.title,
          body: reminder.body,
          payload: reminder.visitId,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.channelId,
              _channel.channelName,
              channelDescription: _channel.channelDescription,
              importance: _channel.importance,
              priority: _channel.priority,
              styleInformation: BigTextStyleInformation(reminder.body),
            ),
          ),
        );
      }
      return allowed;
    } on MissingPluginException {
      // Widget tests and unsupported platforms: the plan still shows in-app.
      return true;
    }
  }
}
