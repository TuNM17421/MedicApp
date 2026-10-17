import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/config/app_config.dart';
import '../../../app/state/app_state.dart';
import '../../auth/auth_controller.dart';
import '../../meds/application/meds_providers.dart';
import '../../records/application/records_providers.dart';
import '../../visit_prep/visit_prep.dart';
import '../data/patient_api.dart';
import '../domain/outbox.dart';
import '../domain/sharing_models.dart';

/// The clinic's patient API when the build names a backend (API_BASE_URL);
/// null offline, where sign-in stays the prototype's phone + password.
final patientApiProvider = Provider<PatientApi?>(
  (ref) => AppConfig.hasApiBaseUrl
      ? HttpPatientApi(baseUrl: AppConfig.apiBaseUrl)
      : null,
);

/// Real time, for consent expiry (instants, not Vietnam wall-clock values).
final sharingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The signed-in account's clinic session, null offline.
final patientSessionProvider = Provider<PatientSession?>((ref) {
  final phone = ref.watch(authSessionProvider);
  return ref.watch(mockAccountStoreProvider)[phone]?.session;
});

/// Profile the clinic's appointments are attached to: the account holder.
String selfProfileId(List<PreviewProfile> profiles) =>
    (profiles.where((p) => p.relationship == selfRelationship).firstOrNull ??
            profiles.firstOrNull)
        ?.id ??
    '';

@immutable
class ServerAppointmentsState {
  const ServerAppointmentsState({
    this.items = const [],
    this.loading = false,
    this.error,
  });
  final List<ServerAppointment> items;
  final bool loading;
  final String? error;

  ServerAppointment? byId(String id) =>
      items.where((item) => item.id == id).firstOrNull;
}

final serverAppointmentsProvider =
    NotifierProvider<ServerAppointmentsController, ServerAppointmentsState>(
      ServerAppointmentsController.new,
    );

/// One clinic appointment by id, null for the app's own bookings.
final serverAppointmentProvider = Provider.family<ServerAppointment?, String>(
  (ref, id) =>
      ref.watch(serverAppointmentsProvider.select((state) => state.byId(id))),
);

/// Appointments the clinic holds for the signed-in phone, cached with the
/// account so they show offline too.
class ServerAppointmentsController extends Notifier<ServerAppointmentsState> {
  @override
  ServerAppointmentsState build() {
    final phone = ref.watch(authSessionProvider);
    return ServerAppointmentsState(
      items: phone == null
          ? const []
          : ref.read(mockAccountStoreProvider)[phone]?.serverAppointments ??
                const [],
    );
  }

  void _store(List<ServerAppointment> items) {
    state = ServerAppointmentsState(
      items: List.unmodifiable(items),
      loading: state.loading,
      error: state.error,
    );
    ref
        .read(authSessionProvider.notifier)
        .updateAccount(
          (account) => account.copyWith(serverAppointments: items),
        );
  }

  /// Fetches the list and the results the clinic has sent. Does nothing
  /// offline or signed out; errors are kept in [ServerAppointmentsState.error].
  Future<void> refresh() async {
    final api = ref.read(patientApiProvider);
    final session = ref.read(patientSessionProvider);
    if (api == null || session == null || state.loading) return;
    state = ServerAppointmentsState(items: state.items, loading: true);
    String? error;
    try {
      final profiles = ref.read(profileCatalogProvider);
      final self = profiles.where((p) => p.id == selfProfileId(profiles));
      final items = await api.appointments(
        session.token,
        fallbackName: session.name.isNotEmpty
            ? session.name
            : self.firstOrNull?.name ?? '',
      );
      if (!ref.mounted) return;
      _store(items);
      await _fetchResults(api, session.token, items);
    } on PatientApiException catch (failure) {
      if (failure.code == 'unauthenticated') {
        _expired();
        return;
      }
      error = failure.message;
    } finally {
      if (ref.mounted) {
        state = ServerAppointmentsState(items: state.items, error: error);
      }
    }
  }

  Future<void> _fetchResults(
    PatientApi api,
    String token,
    List<ServerAppointment> items,
  ) async {
    final profileId = selfProfileId(ref.read(profileCatalogProvider));
    for (final item in items) {
      if (!item.hasResult) continue;
      try {
        final result = await api.result(token, item.id, profileId: profileId);
        if (!ref.mounted) return;
        if (result != null) {
          ref.read(visitResultsProvider.notifier).put(result);
        }
      } on PatientApiException catch (failure) {
        if (failure.code == 'unauthenticated') rethrow;
        debugPrint('Result ${item.id} not fetched: ${failure.code}');
      }
    }
  }

  /// Refreshes appointments and results, then sends what is waiting. Called
  /// when the app starts or comes back to the foreground; does nothing
  /// offline or signed out.
  Future<void> sync() async {
    if (ref.read(patientSessionProvider) == null) return;
    await refresh();
    if (!ref.mounted) return;
    await ref.read(outboxProvider.notifier).flush();
  }

  void _expired() {
    if (ref.mounted) {
      state = ServerAppointmentsState(items: state.items);
    }
    ref.read(authSessionProvider.notifier).sessionExpired();
  }

  void _replaceConsent(String id, SharingConsent consent) => _store([
    for (final item in state.items)
      item.id == id ? item.withConsent(consent) : item,
  ]);

  /// Asks the clinic to see [scope] for appointment [id], then sends what
  /// the scope covers. Throws [PatientApiException] with a message to show.
  Future<SharingConsent> share(String id, Set<ShareScope> scope) async {
    final (api, token) = _online();
    try {
      final consent = await api.grantConsent(token, id, scope);
      if (ref.mounted) {
        _replaceConsent(id, consent);
        final appointment = state.byId(id);
        if (appointment != null) {
          ref.read(outboxProvider.notifier).queueVisit(appointment);
        }
      }
      return consent;
    } on PatientApiException catch (failure) {
      if (failure.code == 'unauthenticated') _expired();
      rethrow;
    }
  }

  /// Withdraws the consent; the clinic stops seeing the data on its next
  /// load. Uploads still waiting for this appointment are dropped.
  Future<SharingConsent> withdraw(String id) async {
    final (api, token) = _online();
    try {
      final consent = await api.revokeConsent(token, id);
      if (ref.mounted) {
        _replaceConsent(id, consent);
        ref.read(outboxProvider.notifier).dropVisit(id);
      }
      return consent;
    } on PatientApiException catch (failure) {
      if (failure.code == 'unauthenticated') _expired();
      rethrow;
    }
  }

  (PatientApi, String) _online() {
    final api = ref.read(patientApiProvider);
    final session = ref.read(patientSessionProvider);
    if (api == null || session == null) {
      throw const PatientApiException(
        'unauthenticated',
        'Cần đăng nhập bằng số điện thoại để chia sẻ với phòng khám.',
      );
    }
    return (api, session.token);
  }
}

final intakeAnswersProvider =
    NotifierProvider<IntakeController, Map<String, List<IntakeAnswer>>>(
      IntakeController.new,
    );

/// Answers to the questions before a visit, kept with the account and sent
/// to the clinic only while the person shares "Câu trả lời trước khám".
class IntakeController extends Notifier<Map<String, List<IntakeAnswer>>> {
  @override
  Map<String, List<IntakeAnswer>> build() {
    final phone = ref.watch(authSessionProvider);
    return phone == null
        ? const {}
        : ref.read(mockAccountStoreProvider)[phone]?.intake ?? const {};
  }

  void save(String visitId, List<IntakeAnswer> answers) {
    final next = Map<String, List<IntakeAnswer>>.unmodifiable({
      ...state,
      visitId: List<IntakeAnswer>.unmodifiable(answers),
    });
    state = next;
    ref
        .read(authSessionProvider.notifier)
        .updateAccount((account) => account.copyWith(intake: next));
    ref.read(outboxProvider.notifier).queueIntake(visitId);
  }
}

final outboxProvider = NotifierProvider<OutboxController, List<OutboxItem>>(
  OutboxController.new,
);

/// Uploads waiting for the clinic. Saved with the account, sent in order,
/// and retried on app start, on return to the app and after each new dose
/// mark. A refusal for good (403 consent_required, 404, 409, 422) drops the
/// item; a network or server error keeps it for the next try.
class OutboxController extends Notifier<List<OutboxItem>> {
  bool _flushing = false;

  @override
  List<OutboxItem> build() {
    final phone = ref.watch(authSessionProvider);
    return phone == null
        ? const []
        : ref.read(mockAccountStoreProvider)[phone]?.outbox ?? const [];
  }

  void _set(List<OutboxItem> next) {
    state = List.unmodifiable(next);
    ref
        .read(authSessionProvider.notifier)
        .updateAccount((account) => account.copyWith(outbox: next));
  }

  bool get _online =>
      ref.read(patientApiProvider) != null &&
      ref.read(patientSessionProvider) != null;

  DateTime _now() => ref.read(sharingClockProvider)();

  ServerAppointment? _appointment(String id) =>
      ref.read(serverAppointmentsProvider).byId(id);

  void add(OutboxItem item) {
    _set(enqueue(state, item));
    unawaited(flush());
  }

  /// Everything [appointment]'s consent covers, right after it is given.
  void queueVisit(ServerAppointment appointment) {
    final consent = appointment.consent;
    if (!_online || consent == null) return;
    final now = _now();
    if (consent.covers(ShareScope.intake, now)) _queueIntake(appointment.id);
    // Self meds: the app has no list of its own yet, so nothing to send.
    if (consent.covers(ShareScope.doseLog, now)) {
      final since = dayKey(
        ref
            .read(prepClockProvider)()
            .subtract(const Duration(days: sharingDays)),
      );
      _queueDoses([
        for (final entry in ref.read(doseLogProvider).values)
          if (entry.day.compareTo(since) >= 0) entry,
      ]);
    }
    unawaited(flush());
  }

  /// The visit's answers, when the person shares them for that visit.
  void queueIntake(String visitId) {
    if (!_online) return;
    final consent = _appointment(visitId)?.consent;
    if (consent == null || !consent.covers(ShareScope.intake, _now())) return;
    _queueIntake(visitId);
    unawaited(flush());
  }

  void _queueIntake(String visitId) {
    final answers = ref.read(intakeAnswersProvider)[visitId] ?? const [];
    if (answers.isEmpty) return;
    _set(
      enqueue(
        state,
        OutboxItem(
          kind: OutboxKind.intake,
          appointmentId: visitId,
          body: {
            'answers': [for (final answer in answers) answer.toWire()],
          },
        ),
      ),
    );
  }

  /// New dose marks, when any clinic appointment shares the dose log.
  void queueDoses(Iterable<DoseLogEntry> entries) {
    if (!_online) return;
    final now = _now();
    final sharing = ref
        .read(serverAppointmentsProvider)
        .items
        .any((item) => item.consent?.covers(ShareScope.doseLog, now) ?? false);
    if (!sharing) return;
    _queueDoses(entries);
    unawaited(flush());
  }

  /// Only marks of medicines a clinic prescribed (course id
  /// `<appointmentId>#<n>`); the app's own visits mean nothing to it.
  void _queueDoses(Iterable<DoseLogEntry> entries) {
    final clinicVisits = {
      for (final item in ref.read(serverAppointmentsProvider).items) item.id,
    };
    final events = [
      for (final entry in entries)
        if (clinicVisits.contains(entry.courseId.split('#').first))
          doseEventWire(entry),
    ];
    if (events.isEmpty) return;
    _set(
      enqueue(
        state,
        OutboxItem(kind: OutboxKind.doses, body: {'events': events}),
      ),
    );
  }

  /// After a withdrawal: the visit's own uploads are no longer wanted.
  void dropVisit(String appointmentId) => _set([
    for (final item in state)
      if (item.appointmentId != appointmentId) item,
  ]);

  /// Sends waiting items in order until one fails.
  Future<void> flush() async {
    final api = ref.read(patientApiProvider);
    final session = ref.read(patientSessionProvider);
    if (api == null || session == null || _flushing || state.isEmpty) return;
    _flushing = true;
    try {
      while (ref.mounted && state.isNotEmpty) {
        final item = state.first;
        try {
          await _send(api, session.token, item);
          if (!ref.mounted) return;
          _set([
            for (final waiting in state)
              if (!identical(waiting, item)) waiting,
          ]);
        } on PatientApiException catch (failure) {
          if (!ref.mounted) return;
          if (failure.code == 'unauthenticated') {
            ref.read(authSessionProvider.notifier).sessionExpired();
            return;
          }
          if (failure.permanent) {
            debugPrint('Upload dropped: ${failure.code}');
            _set([
              for (final waiting in state)
                if (!identical(waiting, item)) waiting,
            ]);
            continue;
          }
          _set([
            for (final waiting in state)
              identical(waiting, item) ? waiting.retried() : waiting,
          ]);
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _send(PatientApi api, String token, OutboxItem item) async {
    switch (item.kind) {
      case OutboxKind.intake:
        await api.putIntake(token, item.appointmentId!, [
          for (final answer in item.body['answers']! as List<Object?>)
            (answer! as Map).cast<String, Object?>(),
        ]);
      case OutboxKind.selfMeds:
        await api.putSelfMeds(token, item.appointmentId!, [
          for (final med in item.body['items']! as List<Object?>)
            (med! as Map).cast<String, Object?>(),
        ]);
      case OutboxKind.doses:
        await api.postDoseEvents(token, item.events);
    }
  }
}

/// Talks to the clinic once someone signs in. App start and return to the
/// foreground call [ServerAppointmentsController.sync] from the app root.
final clinicSyncProvider = Provider<void>((ref) {
  ref.listen(patientSessionProvider, (previous, next) {
    if (next != null && previous?.token != next.token) {
      unawaited(ref.read(serverAppointmentsProvider.notifier).sync());
    }
  });
});
