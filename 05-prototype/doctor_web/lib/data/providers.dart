import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_models.dart';
import 'api.dart';
import 'http_client.dart';
import 'models.dart';
import 'result.dart';

final apiProvider = Provider<ClinicApi>((ref) {
  final client = createHttpClient();
  ref.onDispose(client.close);
  return ClinicApi(client);
});

/// The signed-in doctor, or null. Starts by asking the server whether the
/// browser still holds a valid session cookie.
final sessionProvider = AsyncNotifierProvider<SessionController, StaffSession?>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<StaffSession?> {
  @override
  Future<StaffSession?> build() async {
    try {
      return await ref.read(apiProvider).session();
    } on ApiException catch (e) {
      if (e.unauthenticated) return null;
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    final session = await ref.read(apiProvider).login(email, password);
    state = AsyncData(session);
  }

  Future<void> logout() async {
    try {
      await ref.read(apiProvider).logout();
    } finally {
      state = const AsyncData(null);
    }
  }

  /// Called when any request answers 401: the session expired.
  void expired() => state = const AsyncData(null);

  /// Sets a new password; on success the session no longer must change it.
  Future<void> changePassword(String current, String next) async {
    final session = await ref.read(apiProvider).changePassword(current, next);
    state = AsyncData(session);
  }
}

/// Runs [call]; on 401 marks the session expired so the router shows login.
Future<T> guarded<T>(Ref ref, Future<T> Function(ClinicApi api) call) async {
  try {
    return await call(ref.read(apiProvider));
  } on ApiException catch (e) {
    if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
    // The admin reset the password meanwhile: ask the server again, the
    // router then shows the change password screen.
    if (e.passwordChangeRequired) ref.invalidate(sessionProvider);
    rethrow;
  }
}

final worklistProvider = FutureProvider.autoDispose<Worklist>(
  (ref) => guarded(ref, (api) => api.worklist()),
);

final chartProvider = FutureProvider.autoDispose.family<ChartData, String>(
  (ref, id) => guarded(ref, (api) => api.chart(id)),
);

final historyProvider = FutureProvider.autoDispose
    .family<List<HistoryEntry>, String>(
      (ref, patientId) => guarded(ref, (api) => api.history(patientId)),
    );

/// Drug and ICD-10 lists for the prescription form; loaded once.
final catalogProvider = FutureProvider<Catalog>(
  (ref) => guarded(ref, (api) => api.catalog()),
);

/// Latest result version of a visit, or null before the first draft.
final resultProvider = FutureProvider.autoDispose.family<ResultDraft?, String>(
  (ref, id) => guarded(ref, (api) => api.result(id)),
);

// ---- bước 18 ---------------------------------------------------------------

final staffListProvider = FutureProvider.autoDispose<List<StaffAccount>>(
  (ref) => guarded(ref, (api) => api.staff()),
);

/// First page of a patient's access log, from the chart.
final accessLogProvider = FutureProvider.autoDispose
    .family<AccessLogPage, String>(
      (ref, patientId) =>
          guarded(ref, (api) => api.accessLog(patientId: patientId)),
    );

typedef DayRange = ({String from, String to});

final pilotMetricsProvider = FutureProvider.autoDispose
    .family<PilotMetrics, DayRange>(
      (ref, r) =>
          guarded(ref, (api) => api.pilotMetrics(from: r.from, to: r.to)),
    );
