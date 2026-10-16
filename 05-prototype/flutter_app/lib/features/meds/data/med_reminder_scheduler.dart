import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/notifications/notification_hub.dart';
import '../domain/med_reminder_planner.dart';

/// Doses marked "Đã uống" from a notification button. The button runs in a
/// background isolate with no access to the app's state, so it leaves the
/// dose keys here and the app moves them into the dose log when it next
/// runs or comes back to the foreground.
abstract interface class PendingDoseStore {
  Future<void> add(List<String> keys, DateTime at);

  /// Every pending dose, removed from the store.
  Future<List<({String key, DateTime at})>> drain();
}

class SecurePendingDoseStore implements PendingDoseStore {
  SecurePendingDoseStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'medicapp.pending_doses';

  Future<List<Object?>> _read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? [] : jsonDecode(raw) as List<Object?>;
  }

  @override
  Future<void> add(List<String> keys, DateTime at) async {
    final items = await _read();
    items.add({'keys': keys, 'at': at.toIso8601String()});
    await _storage.write(key: _key, value: jsonEncode(items));
  }

  @override
  Future<List<({String key, DateTime at})>> drain() async {
    try {
      final items = await _read();
      if (items.isEmpty) return const [];
      await _storage.delete(key: _key);
      return [
        for (final item in items.cast<Map<String, Object?>>())
          for (final key in (item['keys']! as List<Object?>).cast<String>())
            (key: key, at: DateTime.parse(item['at']! as String)),
      ];
    } on MissingPluginException {
      return const [];
    }
  }
}

class MemoryPendingDoseStore implements PendingDoseStore {
  final _items = <({String key, DateTime at})>[];

  @override
  Future<void> add(List<String> keys, DateTime at) async =>
      _items.addAll([for (final key in keys) (key: key, at: at)]);

  @override
  Future<List<({String key, DateTime at})>> drain() async {
    final items = [..._items];
    _items.clear();
    return items;
  }
}

/// What a medication notification carries, so its buttons can act without
/// the app: the doses it is about, the follow-up to cancel once they are
/// taken, and its own text to show again when snoozed.
class MedPayload {
  const MedPayload({
    required this.keys,
    required this.title,
    required this.summary,
    required this.header,
    required this.html,
    this.followUpId,
    this.withActions = true,
  });
  final List<String> keys;
  final String title, summary, header, html;
  final int? followUpId;

  /// Low-stock alerts have nothing to mark taken.
  final bool withActions;

  static const prefix = 'med:';

  String encode() =>
      prefix +
      jsonEncode({
        'k': keys,
        't': title,
        's': summary,
        'h': header,
        'b': html,
        'f': followUpId,
        'a': withActions,
      });

  static MedPayload? decode(String? payload) {
    if (payload == null || !payload.startsWith(prefix)) return null;
    final json =
        jsonDecode(payload.substring(prefix.length)) as Map<String, Object?>;
    return MedPayload(
      keys: (json['k']! as List<Object?>).cast<String>(),
      title: json['t']! as String,
      summary: json['s']! as String,
      header: json['h']! as String,
      html: json['b']! as String,
      followUpId: json['f'] as int?,
      withActions: json['a'] as bool? ?? true,
    );
  }
}

abstract final class MedActions {
  static const taken = 'taken';
  static const snooze = 'snooze';
}

const snoozeFor = Duration(minutes: 10);

AndroidNotificationDetails medDetails(MedPayload payload) =>
    AndroidNotificationDetails(
      'med_reminders',
      'Nhắc uống thuốc',
      channelDescription: 'Nhắc giờ uống thuốc theo đơn và khi sắp hết thuốc',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      // Medicine names stay hidden on the lock screen until unlocked.
      visibility: NotificationVisibility.private,
      icon: 'ic_stat_medic',
      color: AppColors.primary,
      subText: payload.header,
      styleInformation: BigTextStyleInformation(
        payload.html,
        htmlFormatBigText: true,
        contentTitle: payload.title,
      ),
      actions: payload.withActions
          ? const [
              AndroidNotificationAction(MedActions.taken, 'Đã uống'),
              AndroidNotificationAction(
                MedActions.snooze,
                'Nhắc lại sau 10 phút',
              ),
            ]
          : null,
    );

/// Handles the "Đã uống" and "Nhắc lại" buttons. Returns true when
/// [response] was one of them.
Future<bool> handleMedAction(
  NotificationResponse response, {
  required FlutterLocalNotificationsPlugin plugin,
  required PendingDoseStore store,
  required DateTime now,
  AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle,
}) async {
  final payload = MedPayload.decode(response.payload);
  if (payload == null) return false;
  switch (response.actionId) {
    case MedActions.taken:
      await store.add(payload.keys, now);
      if (payload.followUpId case final id?) await plugin.cancel(id: id);
      return true;
    case MedActions.snooze:
      final again = now.add(snoozeFor);
      await plugin.zonedSchedule(
        id:
            NotificationIds.snoozeStart +
            payload.keys.join().hashCode.abs() %
                (NotificationIds.snoozeEnd - NotificationIds.snoozeStart),
        scheduledDate: NotificationHub.inVietnam(again),
        title: payload.title,
        body: payload.summary,
        payload: payload.encode(),
        androidScheduleMode: mode,
        notificationDetails: NotificationDetails(android: medDetails(payload)),
      );
      return true;
  }
  return false;
}

DateTime _vietnamNow() {
  final vietnam = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(
    vietnam.year,
    vietnam.month,
    vietnam.day,
    vietnam.hour,
    vietnam.minute,
    vietnam.second,
  );
}

/// Runs in a background isolate when a button that does not open the app
/// is pressed.
@pragma('vm:entry-point')
Future<void> medBackgroundResponse(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await handleMedAction(
    response,
    plugin: FlutterLocalNotificationsPlugin(),
    store: SecurePendingDoseStore(),
    now: _vietnamNow(),
  );
}

abstract interface class MedReminderScheduler {
  /// Replaces every scheduled medication reminder. Returns false when the
  /// user has not allowed notifications.
  Future<bool> replaceAll(List<MedReminder> reminders);

  /// Whether reminders ring on the minute (exact alarms allowed).
  Future<bool> canRingOnTime();

  /// Opens the system page that allows exact alarms.
  Future<void> allowRingOnTime();
}

class LocalMedReminderScheduler implements MedReminderScheduler {
  LocalMedReminderScheduler(this.hub);
  final NotificationHub hub;

  @override
  Future<bool> replaceAll(List<MedReminder> reminders) async {
    try {
      await hub.ready();
      var allowed = true;
      if (reminders.isNotEmpty) allowed = await hub.requestPermission();
      await hub.cancelRange(NotificationIds.medStart, NotificationIds.medEnd);
      final mode = await hub.scheduleMode();
      final count = NotificationIds.medEnd - NotificationIds.medStart;
      final plan = reminders.take(count).toList();
      final ids = {
        for (final (index, reminder) in plan.indexed)
          reminder.key: NotificationIds.medStart + index,
      };
      for (final reminder in plan) {
        final followUp = reminder.kind == MedReminderKind.dose
            ? ids['${MedReminderKind.followUp.name}|'
                  '${reminder.doseKeys.join(',')}']
            : null;
        final payload = MedPayload(
          keys: reminder.doseKeys,
          title: reminder.title,
          summary: reminder.summary,
          header: reminder.header,
          html: reminder.html,
          followUpId: followUp,
          withActions: reminder.kind != MedReminderKind.lowStock,
        );
        await hub.plugin.zonedSchedule(
          id: ids[reminder.key]!,
          scheduledDate: NotificationHub.inVietnam(reminder.at),
          title: reminder.title,
          body: reminder.summary,
          payload: payload.encode(),
          androidScheduleMode: mode,
          notificationDetails: NotificationDetails(
            android: medDetails(payload),
          ),
        );
      }
      return allowed;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<bool> canRingOnTime() async {
    try {
      return await hub.canScheduleExact();
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<void> allowRingOnTime() async {
    try {
      await hub.requestExact();
    } on MissingPluginException {
      return;
    }
  }
}
