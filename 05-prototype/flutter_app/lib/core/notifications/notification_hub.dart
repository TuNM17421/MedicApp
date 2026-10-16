import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notification id ranges, so each feature can replace its own schedule
/// without touching the others'.
abstract final class NotificationIds {
  static const visitStart = 0, visitEnd = 1000;
  static const medStart = 1000, medEnd = 9000;
  static const snoozeStart = 9000, snoozeEnd = 10000;
}

/// One plugin instance for the whole app. The plugin keeps a single tap
/// handler, so visit and medication reminders both go through here and are
/// told apart by their payload prefix (`visit:` or `med:`).
class NotificationHub {
  NotificationHub({
    required this.onResponse,
    this.onBackgroundResponse,
    FlutterLocalNotificationsPlugin? plugin,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  final void Function(NotificationResponse response) onResponse;

  /// Top-level function run in a background isolate for buttons that do not
  /// open the app.
  final DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse;
  Future<void>? _ready;

  static final vietnam = () {
    tz_data.initializeTimeZones();
    return tz.getLocation('Asia/Ho_Chi_Minh');
  }();

  /// [at] is Vietnam wall-clock time held in a local DateTime.
  static tz.TZDateTime inVietnam(DateTime at) =>
      tz.TZDateTime(vietnam, at.year, at.month, at.day, at.hour, at.minute);

  Future<void> ready() => _ready ??= _init();

  Future<void> _init() async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_medic'),
      ),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
    // Opened from a notification while the app was closed.
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      if (launch!.notificationResponse case final response?) {
        onResponse(response);
      }
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  /// Exact alarms when the user allowed them (Android 14 denies them by
  /// default), otherwise inexact ones that Android may deliver a few
  /// minutes late.
  Future<AndroidScheduleMode> scheduleMode() async =>
      await _android?.canScheduleExactNotifications() ?? false
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  /// Opens the system page where the user allows exact alarms.
  Future<void> requestExact() async => _android?.requestExactAlarmsPermission();

  /// Cancels the scheduled and shown notifications whose id is in
  /// [start, end).
  Future<void> cancelRange(int start, int end) async {
    final pending = await plugin.pendingNotificationRequests();
    final active = await plugin.getActiveNotifications();
    final ids = {
      for (final request in pending) request.id,
      for (final shown in active) ?shown.id,
    };
    for (final id in ids) {
      if (id >= start && id < end) await plugin.cancel(id: id);
    }
  }
}

/// True when the plugin is not available (widget tests, desktop).
bool isMissingPlugin(Object error) => error is MissingPluginException;
