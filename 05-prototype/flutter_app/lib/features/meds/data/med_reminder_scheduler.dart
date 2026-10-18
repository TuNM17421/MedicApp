import 'dart:convert';
import 'dart:typed_data';
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

/// Whether the person turned on alarm-style medication reminders. A
/// setting of this phone, not of the account: it depends on what the phone
/// allowed.
abstract interface class MedAlarmSetting {
  Future<bool> read();
  Future<void> write(bool on);
}

class SecureMedAlarmSetting implements MedAlarmSetting {
  SecureMedAlarmSetting([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'medicapp.med_alarm';

  @override
  Future<bool> read() async {
    try {
      return await _storage.read(key: _key) == 'on';
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> write(bool on) async {
    try {
      await _storage.write(key: _key, value: on ? 'on' : 'off');
    } on MissingPluginException {
      return;
    }
  }
}

class MemoryMedAlarmSetting implements MedAlarmSetting {
  bool on = false;

  @override
  Future<bool> read() async => on;

  @override
  Future<void> write(bool value) async => on = value;
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
    this.ring = false,
  });
  final List<String> keys;
  final String title, summary, header, html;
  final int? followUpId;

  /// Low-stock alerts have nothing to mark taken.
  final bool withActions;

  /// Rings like an alarm clock instead of a plain notification, and keeps
  /// ringing when snoozed.
  final bool ring;

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
        'r': ring,
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
      ring: json['r'] as bool? ?? false,
    );
  }
}

abstract final class MedActions {
  static const taken = 'taken';
  static const snooze = 'snooze';
}

const snoozeFor = Duration(minutes: 10);

/// How long an alarm rings when nobody answers it. The follow-up 30 minutes
/// after the dose asks again.
const ringFor = Duration(minutes: 5);

/// Android's FLAG_INSISTENT: the sound repeats until the notification is
/// answered or dismissed.
const _insistent = 4;

/// Android fixes a channel's sound once it exists, so alarm-style reminders
/// get their own channel with the alarm tone on the alarm volume, which
/// plays in silent mode and through Do Not Disturb.
AndroidNotificationDetails medDetails(MedPayload payload) =>
    AndroidNotificationDetails(
      payload.ring ? 'med_alarms' : 'med_reminders',
      payload.ring ? 'Chuông báo uống thuốc' : 'Nhắc uống thuốc',
      channelDescription: payload.ring
          ? 'Đổ chuông như đồng hồ báo thức đến giờ uống thuốc'
          : 'Nhắc giờ uống thuốc theo đơn và khi sắp hết thuốc',
      importance: payload.ring ? Importance.max : Importance.high,
      priority: payload.ring ? Priority.max : Priority.high,
      category: payload.ring
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      sound: payload.ring
          ? const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert',
            )
          : null,
      audioAttributesUsage: payload.ring
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      additionalFlags: payload.ring ? Int32List.fromList([_insistent]) : null,
      fullScreenIntent: payload.ring,
      ongoing: payload.ring,
      autoCancel: !payload.ring,
      timeoutAfter: payload.ring ? ringFor.inMilliseconds : null,
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
      Future<void> schedule(AndroidScheduleMode mode) => plugin.zonedSchedule(
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
      if (!payload.ring) {
        await schedule(mode);
      } else {
        // Exact alarms can be taken back in the system settings meanwhile.
        try {
          await schedule(AndroidScheduleMode.alarmClock);
        } on PlatformException {
          await schedule(mode);
        }
      }
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

/// What the phone allowed when alarm-style reminders were turned on.
typedef AlarmAccess = ({bool onTime, bool fullScreen});

abstract interface class MedReminderScheduler {
  /// Replaces every scheduled medication reminder. Returns false when the
  /// user has not allowed notifications. With [ring], dose reminders ring
  /// like an alarm clock; they stay plain notifications while exact alarms
  /// are not allowed.
  Future<bool> replaceAll(List<MedReminder> reminders, {bool ring = false});

  /// Asks for what alarm-style reminders need: notifications, exact alarms
  /// and, best effort, covering the lock screen.
  Future<AlarmAccess> allowAlarm();

  /// Whether reminders ring on the minute (exact alarms allowed).
  Future<bool> canRingOnTime();

  /// Opens the system page that allows exact alarms.
  Future<void> allowRingOnTime();
}

class LocalMedReminderScheduler implements MedReminderScheduler {
  LocalMedReminderScheduler(this.hub);
  final NotificationHub hub;

  @override
  Future<bool> replaceAll(
    List<MedReminder> reminders, {
    bool ring = false,
  }) async {
    try {
      await hub.ready();
      var allowed = true;
      if (reminders.isNotEmpty) allowed = await hub.requestPermission();
      await hub.cancelRange(NotificationIds.medStart, NotificationIds.medEnd);
      final mode = await hub.scheduleMode();
      final alarm = ring && mode == AndroidScheduleMode.exactAllowWhileIdle;
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
          ring: alarm && reminder.kind == MedReminderKind.dose,
        );
        await hub.plugin.zonedSchedule(
          id: ids[reminder.key]!,
          scheduledDate: NotificationHub.inVietnam(reminder.at),
          title: reminder.title,
          body: reminder.summary,
          payload: payload.encode(),
          androidScheduleMode: payload.ring
              ? AndroidScheduleMode.alarmClock
              : mode,
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
  Future<AlarmAccess> allowAlarm() async {
    try {
      await hub.ready();
      if (!await hub.requestPermission()) {
        return (onTime: false, fullScreen: false);
      }
      if (!await hub.canScheduleExact()) await hub.requestExact();
      final onTime = await hub.canScheduleExact();
      if (!onTime) return (onTime: false, fullScreen: false);
      return (onTime: true, fullScreen: await hub.requestFullScreen());
    } on MissingPluginException {
      return (onTime: true, fullScreen: true);
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
