import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/config/app_config.dart';
import '../../../app/notifications.dart';
import '../../../app/state/app_state.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/notifications/notification_hub.dart';
import '../../auth/auth_controller.dart';
import '../../booking/application/booking_providers.dart';
import '../../booking/domain/booking_models.dart';
import '../../meds/domain/med_reminder_planner.dart' show whoShort;
import '../../records/application/records_providers.dart';
import '../../sharing/application/sharing_providers.dart';
import '../../visit_prep/visit_prep.dart';
import '../data/family_api.dart';
import '../domain/family_models.dart';

/// The local backend when the build names one (API_BASE_URL). Without it
/// linking is not offered: two phones need a server in between.
final familyApiProvider = Provider<FamilyApi?>(
  (ref) => AppConfig.hasApiBaseUrl
      ? HttpFamilyApi(baseUrl: AppConfig.apiBaseUrl)
      : null,
);

/// The signed-in account's links.
final familyLinksProvider = Provider<List<FamilyLink>>((ref) {
  final phone = ref.watch(authSessionProvider);
  return ref.watch(mockAccountStoreProvider)[phone]?.links ?? const [];
});

/// The owner's link for [profileId] that is not ended, if any.
FamilyLink? ownerLinkFor(List<FamilyLink> links, String profileId) => links
    .where(
      (l) =>
          l.role == FamilyRole.owner &&
          l.profileId == profileId &&
          l.status != FamilyLinkStatus.ended,
    )
    .firstOrNull;

/// Family profiles whose medicines ring on that person's own phone: their
/// prescriptions give this phone no reminders, only missed-dose alerts.
final medsOnOtherPhoneProvider = Provider<Set<String>>(
  (ref) => {
    for (final link in ref.watch(familyLinksProvider))
      if (link.role == FamilyRole.owner && link.linked) link.profileId,
  },
);

/// Shows an alert about the linked person's dose on this phone.
abstract interface class FamilyAlertNotifier {
  Future<void> show(FamilyLink link, FamilyAlert alert, String who);
}

final familyAlertNotifierProvider = Provider<FamilyAlertNotifier>(
  (ref) => LocalFamilyAlertNotifier(ref.watch(notificationHubProvider)),
);

/// "Mẹ Lan chưa uống thuốc 07:00".
String familyAlertTitle(FamilyAlert alert, String who) => switch (alert.kind) {
  FamilyAlertKind.missed => '$who chưa uống thuốc ${alert.label}',
  FamilyAlertKind.skipped => '$who bỏ liều thuốc ${alert.label}',
  FamilyAlertKind.taken => '$who đã uống thuốc ${alert.label} (muộn)',
};

String familyAlertBody(FamilyAlert alert) => [
  if (alert.meds.isNotEmpty) alert.meds.join(', '),
  if (alert.kind == FamilyAlertKind.skipped)
    'Lý do: ${_reasons[alert.reason] ?? 'không ghi'}',
  if (alert.kind != FamilyAlertKind.taken) 'Bạn có thể gọi hỏi thăm.',
].join('. ');

const _reasons = {
  'forgot': 'quên uống',
  'outOfStock': 'hết thuốc',
  'unwell': 'thấy khó chịu',
  'other': 'lý do khác',
};

class LocalFamilyAlertNotifier implements FamilyAlertNotifier {
  LocalFamilyAlertNotifier(this.hub);
  final NotificationHub hub;

  /// Taps open Thuốc hôm nay, where the alert is listed.
  static const payloadPrefix = 'family:';

  @override
  Future<void> show(FamilyLink link, FamilyAlert alert, String who) async {
    try {
      await hub.ready();
      await hub.plugin.show(
        id:
            NotificationIds.familyStart +
            '${link.id}|${alert.key}|${alert.kind.name}'.hashCode.abs() %
                (NotificationIds.familyEnd - NotificationIds.familyStart),
        title: familyAlertTitle(alert, who),
        body: familyAlertBody(alert),
        payload: '$payloadPrefix${link.id}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'family_alerts',
            'Người thân lỡ liều',
            channelDescription:
                'Báo khi người thân đã liên kết quên hoặc bỏ liều thuốc',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
            icon: 'ic_stat_medic',
            color: AppColors.primary,
          ),
        ),
      );
    } on MissingPluginException {
      return;
    }
  }
}

/// FNV-1a, so a fingerprint is the same on every run (String.hashCode need
/// not be).
String fingerprint(Object? value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(jsonEncode(value))) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

/// An appointment as it travels: without whose profile it is on this phone.
Map<String, Object?> wireAppointment(AppointmentRecord record) {
  final json = record.toJson();
  final visit = {...(json['visit']! as Map<String, Object?>)};
  visit['patientId'] = null;
  visit['patientName'] = '';
  return {...json, 'visit': visit};
}

Map<String, Object?> wireResult(VisitResult result) => {
  ...result.toJson(),
  'profileId': '',
};

AppointmentRecord appointmentFromWire(
  Map<String, Object?> body,
  PreviewProfile profile,
) {
  final visit = {...(body['visit']! as Map<String, Object?>)};
  visit['patientId'] = profile.id;
  visit['patientName'] = profile.name;
  return AppointmentRecord.fromJson({...body, 'visit': visit});
}

/// "2026-10-14T07:00:00+07:00" for a Vietnam wall-clock time.
String vietnamIso(DateTime at) =>
    '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(at)}+07:00';

DateTime _wallClock(String iso) {
  final utc = DateTime.parse(iso).toUtc().add(const Duration(hours: 7));
  return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute);
}

/// The member's doses of today and tomorrow, one per time of day, and the
/// marks made on them. Only the medicine titles leave the phone.
({List<Map<String, Object?>> doses, List<Map<String, Object?>> marks})
memberDoses({
  required List<MedicationCourse> courses,
  required Map<String, DoseLogEntry> log,
  required DateTime now,
}) {
  final groups = <String, List<ScheduledDose>>{};
  for (final day in [dayOf(now), dayOf(now).add(const Duration(days: 1))]) {
    for (final dose in dosesOn(day, courses, log, now)) {
      groups
          .putIfAbsent('${dayKey(dose.at)}|${dose.dose.slot.name}', () => [])
          .add(dose);
    }
  }
  final time = DateFormat('HH:mm');
  final doses = <Map<String, Object?>>[];
  final marks = <Map<String, Object?>>[];
  for (final MapEntry(key: key, value: group) in groups.entries) {
    doses.add({
      'key': key,
      'at': vietnamIso(group.first.at),
      'label': time.format(group.first.at),
      'meds': [for (final dose in group) dose.course.item.title],
    });
    final entries = [for (final dose in group) dose.entry];
    final skipped = entries.whereType<DoseLogEntry>().where(
      (e) => e.mark == DoseMark.skipped,
    );
    final mark = skipped.isNotEmpty
        ? skipped.first
        : entries.every((e) => e?.mark == DoseMark.taken)
        ? (entries.whereType<DoseLogEntry>().toList()
                ..sort((a, b) => a.at.compareTo(b.at)))
              .last
        : null;
    if (mark != null) {
      marks.add({
        'key': key,
        'mark': mark.mark.name,
        if (mark.reason case final reason?) 'reason': reason.name,
        'at': vietnamIso(mark.at),
      });
    }
  }
  return (doses: doses, marks: marks);
}

final familyControllerProvider = NotifierProvider<FamilyController, bool>(
  FamilyController.new,
);

/// Links and syncs this account's family profiles with other phones. The
/// state is true while a sync runs.
class FamilyController extends Notifier<bool> {
  @override
  bool build() => false;

  FamilyApi get _api => ref.read(familyApiProvider)!;

  MockAccount? get _account => ref.read(authSessionProvider.notifier).account;

  List<PreviewProfile> get _profiles => _account?.profiles ?? const [];

  PreviewProfile? _profile(String id) =>
      _profiles.where((p) => p.id == id).firstOrNull;

  String get _myName =>
      _profile(selfProfileId(_profiles))?.name ?? 'Người thân';

  void _saveLink(FamilyLink link) =>
      ref.read(authSessionProvider.notifier).updateAccount((account) {
        final others = account.links.where((l) => l.id != link.id);
        return account.copyWith(links: List.unmodifiable([...others, link]));
      });

  FamilyLink? _link(String id) =>
      _account?.links.where((l) => l.id == id).firstOrNull;

  /// Owner: makes a code for [profileId], replacing an ended link.
  Future<FamilyLink> invite(String profileId) async {
    final profile = _profile(profileId)!;
    final made = await _api.create(
      ownerName: _myName,
      profile: {
        'name': profile.name,
        'relationship': profile.relationship,
        'birthYear': profile.birthYear,
        'gender': ?profile.gender,
      },
    );
    final link = FamilyLink(
      id: made.link.id,
      token: made.token,
      role: FamilyRole.owner,
      profileId: profileId,
      status: FamilyLinkStatus.pending,
      inviteCode: made.invite.code,
      inviteExpiresAt: made.invite.expiresAt,
    );
    ref
        .read(authSessionProvider.notifier)
        .updateAccount(
          (account) => account.copyWith(
            links: List.unmodifiable([
              for (final l in account.links)
                if (!(l.role == FamilyRole.owner && l.profileId == profileId))
                  l,
              link,
            ]),
          ),
        );
    return link;
  }

  /// Owner: a fresh code once the old one expired.
  Future<FamilyLink> renewInvite(FamilyLink link) async {
    final invite = await _api.reinvite(link.id, link.token);
    final next = link.copyWith(
      inviteCode: () => invite.code,
      inviteExpiresAt: () => invite.expiresAt,
    );
    _saveLink(next);
    return next;
  }

  Future<FamilyInviter> peek(String code) => _api.peek(code);

  /// Member: accepts a code; this phone's own profile is the one linked.
  Future<FamilyLink> join(String code, {required bool shareMissed}) async {
    final claimed = await _api.claim(
      code: code,
      memberName: _myName,
      shareMissed: shareMissed,
    );
    final link = FamilyLink(
      id: claimed.link.id,
      token: claimed.token,
      role: FamilyRole.member,
      profileId: selfProfileId(_profiles),
      status: FamilyLinkStatus.linked,
      peerName: claimed.link.ownerName,
      shareMissed: shareMissed,
    );
    _saveLink(link);
    await sync();
    return _link(link.id) ?? link;
  }

  /// Either side: ends the link on both phones. Reminders come back here
  /// for the owner; the member keeps what was received.
  Future<void> unlink(FamilyLink link) async {
    try {
      await _api.end(link.id, link.token);
    } on FamilyApiException catch (failure) {
      if (!failure.linkGone) rethrow;
    }
    _saveLink(
      link.copyWith(
        status: FamilyLinkStatus.ended,
        inviteCode: () => null,
        inviteExpiresAt: () => null,
      ),
    );
    _refreshViews();
  }

  Future<void> setShareMissed(FamilyLink link, bool value) async {
    await _api.setShareMissed(link.id, link.token, value);
    _saveLink(
      link.copyWith(
        shareMissed: value,
        pushed: {...link.pushed}..remove('doses'),
      ),
    );
    if (value) unawaited(sync());
  }

  void _refreshViews() => ref.container
    ..invalidate(appointmentsProvider)
    ..invalidate(visitResultsProvider);

  /// Exchanges what changed with every live link. Network failures leave
  /// things as they are until the next try.
  Future<void> sync() async {
    final api = ref.read(familyApiProvider);
    final account = _account;
    if (api == null || account == null || state) return;
    final live = account.links.where((l) => l.status != FamilyLinkStatus.ended);
    if (live.isEmpty) return;
    state = true;
    try {
      for (final link in live.toList()) {
        try {
          await _syncOne(api, link);
        } on FamilyApiException catch (failure) {
          if (failure.linkGone) {
            _saveLink(link.copyWith(status: FamilyLinkStatus.ended));
          }
        }
        if (!ref.mounted) return;
      }
      _refreshViews();
    } finally {
      if (ref.mounted) state = false;
    }
  }

  Future<void> _syncOne(FamilyApi api, FamilyLink start) async {
    var link = start;
    // Read first, so items received are not sent straight back.
    while (true) {
      final feed = await api.read(link.id, link.token, after: link.cursor);
      if (!ref.mounted) return;
      link = await _apply(link, feed);
      if (!feed.more) break;
    }
    if (!link.linked) return;
    link = await _push(api, link);
    _saveLink(link);
  }

  Future<FamilyLink> _apply(FamilyLink start, FamilyFeed feed) async {
    var link = start;
    final profile = _profile(link.profileId);
    final who = profile == null ? 'Người thân' : whoShort(profile);
    final pushed = {...link.pushed};
    final alerts = [...link.alerts];
    final fresh = <FamilyAlert>[];
    var appointments = [...?_account?.appointments];
    var results = [...?_account?.results];
    for (final event in feed.events) {
      switch (event.kind) {
        case 'link.claimed':
          link = link.copyWith(
            status: FamilyLinkStatus.linked,
            peerName: () => event.body['memberName'] as String?,
            inviteCode: () => null,
            inviteExpiresAt: () => null,
          );
        case 'link.ended':
          link = link.copyWith(status: FamilyLinkStatus.ended);
        case 'link.settings':
          link = link.copyWith(
            shareMissed: event.body['shareMissed'] as bool? ?? true,
          );
        case 'appointment.upsert' when profile != null:
          final record = appointmentFromWire(event.body, profile);
          appointments = [
            record,
            ...appointments.where((r) => r.visit.id != record.visit.id),
          ];
          pushed['a:${record.visit.id}'] = fingerprint(wireAppointment(record));
        case 'appointment.cancel':
          appointments.removeWhere((r) => r.visit.id == event.id);
          pushed.remove('a:${event.id}');
        case 'result.upsert' when link.role == FamilyRole.member:
          final result = VisitResult.fromJson({
            ...event.body,
            'profileId': link.profileId,
          });
          results = [
            result,
            ...results.where((r) => r.visitId != result.visitId),
          ];
        case 'dose.missed' || 'dose.skipped' || 'dose.taken'
            when link.role == FamilyRole.owner:
          final alert = FamilyAlert(
            kind: switch (event.kind) {
              'dose.missed' => FamilyAlertKind.missed,
              'dose.skipped' => FamilyAlertKind.skipped,
              _ => FamilyAlertKind.taken,
            },
            key: event.id,
            at: _wallClock(event.body['at']! as String),
            label: event.body['label']! as String,
            meds: List.unmodifiable(
              (event.body['meds'] as List<Object?>? ?? []).cast<String>(),
            ),
            reason: event.body['reason'] as String?,
          );
          alerts.insert(0, alert);
          fresh.add(alert);
      }
    }
    link = link.copyWith(
      cursor: feed.cursor,
      pushed: Map.unmodifiable(pushed),
      alerts: List.unmodifiable(alerts.take(FamilyLink.maxAlerts)),
      status: feed.status == FamilyLinkStatus.ended
          ? FamilyLinkStatus.ended
          : null,
    );
    final saved = link;
    ref
        .read(authSessionProvider.notifier)
        .updateAccount(
          (account) => account.copyWith(
            appointments: List.unmodifiable(appointments),
            results: List.unmodifiable(results),
            links: List.unmodifiable([
              for (final l in account.links)
                if (l.id != saved.id) l,
              saved,
            ]),
          ),
        );
    final notifier = ref.read(familyAlertNotifierProvider);
    for (final alert in fresh) {
      await notifier.show(link, alert, who);
    }
    return link;
  }

  Future<FamilyLink> _push(FamilyApi api, FamilyLink link) async {
    final account = _account!;
    final pushed = {...link.pushed};
    final events = <Map<String, Object?>>[];
    final current = <String>{};
    for (final record in account.appointments) {
      if (record.visit.patientId != link.profileId) continue;
      final key = 'a:${record.visit.id}';
      current.add(key);
      final wire = wireAppointment(record);
      final print = fingerprint(wire);
      if (pushed[key] == print) continue;
      events.add({
        'kind': 'appointment.upsert',
        'id': record.visit.id,
        'body': wire,
      });
      pushed[key] = print;
    }
    for (final key in [...pushed.keys]) {
      if (key.startsWith('a:') && !current.contains(key)) {
        events.add({'kind': 'appointment.cancel', 'id': key.substring(2)});
        pushed.remove(key);
      }
    }
    // Only the linked person's prescriptions go to their phone; the owner's
    // own never leave this one.
    if (link.role == FamilyRole.owner) {
      for (final result in account.results) {
        if (result.profileId != link.profileId) continue;
        final key = 'r:${result.visitId}';
        final wire = wireResult(result);
        final print = fingerprint(wire);
        if (pushed[key] == print) continue;
        events.add({
          'kind': 'result.upsert',
          'id': result.visitId,
          'body': wire,
        });
        pushed[key] = print;
      }
    }
    for (var i = 0; i < events.length; i += 50) {
      await api.post(
        link.id,
        link.token,
        events.sublist(i, (i + 50).clamp(0, events.length)),
      );
    }
    if (link.role == FamilyRole.member && link.shareMissed) {
      final plan = memberDoses(
        courses: [
          for (final course in coursesFrom(account.results))
            if (course.profileId == link.profileId) course,
        ],
        log: {for (final entry in account.doseLog) entry.key: entry},
        now: ref.read(prepClockProvider)(),
      );
      final print = fingerprint([plan.doses, plan.marks]);
      if (pushed['doses'] != print) {
        await api.putDoses(
          link.id,
          link.token,
          doses: plan.doses,
          marks: plan.marks,
        );
        pushed['doses'] = print;
      }
    }
    return link.copyWith(pushed: Map.unmodifiable(pushed));
  }
}

/// Syncs every half minute while the app is open and a link exists; the
/// app also syncs when it starts and comes back to the foreground.
final familySyncProvider = Provider<void>((ref) {
  if (ref.watch(familyApiProvider) == null) return;
  final live = ref.watch(
    familyLinksProvider.select(
      (links) => links.any((l) => l.status != FamilyLinkStatus.ended),
    ),
  );
  if (!live) return;
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => ref.read(familyControllerProvider.notifier).sync(),
  );
  ref.onDispose(timer.cancel);
});
