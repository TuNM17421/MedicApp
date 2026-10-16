import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'http_client.dart';
import 'models.dart';

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
      return await ref.read(apiProvider).me();
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
}

/// Runs [call]; on 401 marks the session expired so the router shows login.
Future<T> guarded<T>(Ref ref, Future<T> Function(ClinicApi api) call) async {
  try {
    return await call(ref.read(apiProvider));
  } on ApiException catch (e) {
    if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
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
