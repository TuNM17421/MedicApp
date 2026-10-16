import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/config/app_config.dart';
import '../../../app/state/app_state.dart';
import '../../auth/auth_controller.dart';
import '../../booking/application/booking_providers.dart';
import '../data/doctor_portal.dart';

/// The clinic backend when the build names one (API_BASE_URL), else the
/// offline mock so the demo works without a server.
final doctorPortalProvider = Provider<DoctorPortal>(
  (ref) => AppConfig.hasApiBaseUrl
      ? HttpDoctorPortal(baseUrl: AppConfig.apiBaseUrl)
      : const MockDoctorPortal(),
);

class ResultsState {
  const ResultsState({this.results = const [], this.fetching = const {}});
  final List<VisitResult> results;

  /// Visit ids whose result is being claimed from the doctor's system.
  final Set<String> fetching;

  VisitResult? forVisit(String visitId) =>
      results.where((result) => result.visitId == visitId).firstOrNull;
}

final visitResultsProvider =
    NotifierProvider<VisitResultsController, ResultsState>(
      VisitResultsController.new,
    );

/// Results belong to the signed-in account, like its appointments, and are
/// saved with it in the encrypted vault once its holder consented.
class VisitResultsController extends Notifier<ResultsState> {
  @override
  ResultsState build() {
    final phone = ref.watch(authSessionProvider);
    return ResultsState(
      results: phone == null
          ? const []
          : ref.read(mockAccountStoreProvider)[phone]?.results ?? const [],
    );
  }

  /// Claims [visitId]'s result with the code printed on the prescription
  /// and keeps it. Throws [ResultClaimException] with a message to show.
  Future<VisitResult> claim(String visitId, String code) async {
    if (state.fetching.contains(visitId)) {
      throw const ResultClaimException('busy', 'Đang nhận kết quả, chờ chút.');
    }
    final record = ref
        .read(appointmentsProvider)
        .records
        .where((record) => record.visit.id == visitId)
        .firstOrNull;
    if (record == null) {
      throw const ResultClaimException(
        'no_visit',
        'Không tìm thấy lượt khám này trong app.',
      );
    }
    final patient = ref
        .read(profileCatalogProvider)
        .where((profile) => profile.id == record.visit.patientId)
        .firstOrNull;
    state = ResultsState(
      results: state.results,
      fetching: {...state.fetching, visitId},
    );
    try {
      final result = await ref
          .read(doctorPortalProvider)
          .claim(code, visit: record.visit, patient: patient);
      if (!ref.mounted) return result;
      final results = List<VisitResult>.unmodifiable([
        result,
        ...state.results.where((item) => item.visitId != visitId),
      ]);
      state = ResultsState(results: results, fetching: state.fetching);
      ref
          .read(authSessionProvider.notifier)
          .updateAccount((account) => account.copyWith(results: results));
      return result;
    } finally {
      if (ref.mounted) {
        state = ResultsState(
          results: state.results,
          fetching: {...state.fetching}..remove(visitId),
        );
      }
    }
  }
}
