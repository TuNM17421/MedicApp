import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_state.dart';
import '../../auth/auth_controller.dart';
import '../../booking/application/booking_providers.dart';
import '../data/doctor_portal.dart';
import '../domain/visit_result.dart';

final doctorPortalProvider = Provider<DoctorPortal>(
  (ref) => const MockDoctorPortal(),
);

class ResultsState {
  const ResultsState({this.results = const [], this.fetching = const {}});
  final List<VisitResult> results;

  /// Visit ids whose result is being asked from the doctor's system.
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

  /// Asks the doctor's system for [visitId]'s result and keeps it.
  Future<VisitResult?> fetch(String visitId) async {
    if (state.fetching.contains(visitId)) return null;
    final record = ref
        .read(appointmentsProvider)
        .records
        .where((record) => record.visit.id == visitId)
        .firstOrNull;
    if (record == null) return null;
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
          .resultFor(record.visit, patient);
      if (!ref.mounted || result == null) return result;
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
