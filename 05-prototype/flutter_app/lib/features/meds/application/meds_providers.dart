import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/notifications.dart';
import '../../../app/state/app_state.dart';
import '../../auth/auth_controller.dart';
import '../../records/application/records_providers.dart';
import '../../sharing/application/sharing_providers.dart';

import '../../visit_prep/reminder_scheduler.dart';
import '../../visit_prep/visit_prep.dart';
import '../data/med_reminder_scheduler.dart';
import '../domain/med_reminder_planner.dart';

/// Every medicine from the signed-in account's prescriptions.
final medicationCoursesProvider = Provider<List<MedicationCourse>>(
  (ref) =>
      List.unmodifiable(coursesFrom(ref.watch(visitResultsProvider).results)),
);

final pendingDoseStoreProvider = Provider<PendingDoseStore>(
  (ref) => SecurePendingDoseStore(),
);

/// Splits a [doseKey] back into its parts.
({String courseId, String day, DoseSlot slot})? parseDoseKey(String key) {
  final parts = key.split('|');
  if (parts.length != 3) return null;
  final slot = DoseSlot.values.where((s) => s.name == parts[2]).firstOrNull;
  if (slot == null) return null;
  return (courseId: parts[0], day: parts[1], slot: slot);
}

final doseLogProvider =
    NotifierProvider<DoseLogController, Map<String, DoseLogEntry>>(
      DoseLogController.new,
    );

/// What was taken or skipped, by [doseKey]. Belongs to the signed-in
/// account and is saved with it in the encrypted vault after consent.
class DoseLogController extends Notifier<Map<String, DoseLogEntry>> {
  @override
  Map<String, DoseLogEntry> build() {
    final phone = ref.watch(authSessionProvider);
    final entries = phone == null
        ? const <DoseLogEntry>[]
        : ref.read(mockAccountStoreProvider)[phone]?.doseLog ?? const [];
    return Map.unmodifiable({for (final entry in entries) entry.key: entry});
  }

  DateTime _now() => ref.read(prepClockProvider)();

  void _save(Map<String, DoseLogEntry> next) {
    state = Map.unmodifiable(next);
    final entries = next.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    ref
        .read(authSessionProvider.notifier)
        .updateAccount((account) => account.copyWith(doseLog: entries));
  }

  DoseLogEntry? _entry(
    String key,
    DoseMark mark, {
    SkipReason? reason,
    DateTime? at,
  }) {
    final parts = parseDoseKey(key);
    if (parts == null) return null;
    return DoseLogEntry(
      courseId: parts.courseId,
      day: parts.day,
      slot: parts.slot,
      mark: mark,
      at: at ?? _now(),
      reason: reason,
    );
  }

  /// Sends new marks to clinics the person shares the dose log with.
  void _share(Iterable<DoseLogEntry> entries) =>
      ref.read(outboxProvider.notifier).queueDoses(entries);

  void taken(String key) {
    if (_entry(key, DoseMark.taken) case final entry?) {
      _save({...state, key: entry});
      _share([entry]);
    }
  }

  void skipped(String key, SkipReason reason) {
    if (_entry(key, DoseMark.skipped, reason: reason) case final entry?) {
      _save({...state, key: entry});
      _share([entry]);
    }
  }

  void undo(String key) {
    if (!state.containsKey(key)) return;
    _save({...state}..remove(key));
  }

  /// Moves doses marked "Đã uống" on a notification into the log. Doses of
  /// courses this account does not have are kept for the account they
  /// belong to.
  Future<int> drainPending() async {
    final store = ref.read(pendingDoseStoreProvider);
    final pending = await store.drain();
    if (!ref.mounted || pending.isEmpty) return 0;
    final courses = {for (final c in ref.read(medicationCoursesProvider)) c.id};
    final next = {...state};
    final others = <({String key, DateTime at})>[];
    for (final item in pending) {
      final entry = _entry(item.key, DoseMark.taken, at: item.at);
      if (entry == null) continue;
      if (!courses.contains(entry.courseId)) {
        others.add(item);
      } else if (!next.containsKey(item.key)) {
        next[item.key] = entry;
      }
    }
    for (final item in others) {
      await store.add([item.key], item.at);
    }
    final added = next.length - state.length;
    if (added > 0 && ref.mounted) {
      final fresh = [
        for (final MapEntry(:key, :value) in next.entries)
          if (!state.containsKey(key)) value,
      ];
      _save(next);
      _share(fresh);
    }
    return added;
  }

  /// Called when the app starts or comes back to the foreground: picks up
  /// doses marked on notifications and rebuilds the schedules from the
  /// clock.
  Future<void> refresh() async {
    await drainPending();
    if (!ref.mounted) return;
    // Also the moment to resend marks that could not reach a clinic.
    unawaited(ref.read(outboxProvider.notifier).flush());
    // Through the container: the medication plan watches this log, and
    // `ref.invalidate` refuses (in debug) to invalidate a dependent, which
    // broke starting the app already signed in.
    ref.container
      ..invalidate(medReminderPlanProvider)
      ..invalidate(reminderPlanProvider);
  }
}

final medReminderPlanProvider = Provider<List<MedReminder>>((ref) {
  if (ref.watch(authSessionProvider) == null) return const [];
  return planMedReminders(
    courses: ref.watch(medicationCoursesProvider),
    log: ref.watch(doseLogProvider),
    profiles: ref.watch(profileCatalogProvider),
    now: ref.watch(prepClockProvider)(),
  );
});

final medReminderSchedulerProvider = Provider<MedReminderScheduler>(
  (ref) => LocalMedReminderScheduler(ref.watch(notificationHubProvider)),
);

/// Keeps the phone's medication schedule equal to [medReminderPlanProvider],
/// ringing like an alarm when [medAlarmProvider] is on.
final medReminderSyncProvider = Provider<void>((ref) {
  Future<void> replace(List<MedReminder> plan) async {
    final allowed = await ref
        .read(medReminderSchedulerProvider)
        .replaceAll(plan, ring: ref.read(medAlarmProvider));
    if (ref.mounted && !allowed) {
      ref.read(notificationsAllowedProvider.notifier).set(false);
    }
  }

  ref.listen(medReminderPlanProvider, (previous, next) async {
    if (listEquals(previous, next)) return;
    if (next.isEmpty && (previous == null || previous.isEmpty)) return;
    await replace(next);
  }, fireImmediately: true);
  ref.listen(medAlarmProvider, (previous, next) async {
    if (previous == next) return;
    final plan = ref.read(medReminderPlanProvider);
    if (plan.isNotEmpty) await replace(plan);
  });
});

final medAlarmSettingProvider = Provider<MedAlarmSetting>(
  (ref) => SecureMedAlarmSetting(),
);

/// Whether dose reminders ring like an alarm clock. Off until the person
/// turns it on and the phone allows exact alarms.
final medAlarmProvider = NotifierProvider<MedAlarm, bool>(MedAlarm.new);

class MedAlarm extends Notifier<bool> {
  @override
  bool build() {
    ref.read(medAlarmSettingProvider).read().then((on) {
      if (ref.mounted && on) state = true;
    });
    return false;
  }

  /// Asks the phone for what alarms need and turns them on when exact
  /// alarms are allowed; otherwise reminders stay plain notifications.
  Future<AlarmAccess> turnOn() async {
    final access = await ref.read(medReminderSchedulerProvider).allowAlarm();
    if (ref.mounted && access.onTime) {
      state = true;
      await ref.read(medAlarmSettingProvider).write(true);
    }
    return access;
  }

  Future<void> turnOff() async {
    state = false;
    await ref.read(medAlarmSettingProvider).write(false);
  }
}
