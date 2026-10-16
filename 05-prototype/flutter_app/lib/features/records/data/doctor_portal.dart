import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/state/app_state.dart';
import '../../booking/application/booking_providers.dart';
import '../../booking/domain/booking_models.dart';
import '../domain/claim_code.dart';

/// Why a claim code did not bring a result; [message] is shown as is.
class ResultClaimException implements Exception {
  const ResultClaimException(this.code, this.message);
  final String code, message;

  static const invalid = ResultClaimException(
    'invalid_code',
    'Mã gồm 10 chữ và số, in cuối đơn thuốc, ví dụ K7MQ-4XR2-9D.',
  );
  static const notFound = ResultClaimException(
    'not_found',
    'Mã không đúng hoặc đã hết hạn.',
  );
  static const rateLimited = ResultClaimException(
    'rate_limited',
    'Bạn nhập sai nhiều lần. Thử lại sau 1 phút.',
  );
  static const network = ResultClaimException(
    'network',
    'Chưa kết nối được phòng khám. Kiểm tra mạng rồi thử lại.',
  );
  static const server = ResultClaimException(
    'server',
    'Phòng khám chưa trả được kết quả. Thử lại sau ít phút.',
  );

  @override
  String toString() => 'ResultClaimException($code)';
}

/// The doctor-side web system that returns a visit's diagnosis and
/// prescription. Patients have no server account yet, so they claim a result
/// with the code printed on the paper prescription.
abstract class DoctorPortal {
  /// The result behind [code], attached to [visit]. Throws
  /// [ResultClaimException] with a message ready to show.
  Future<VisitResult> claim(
    String code, {
    required VisitSummary visit,
    PreviewProfile? patient,
  });
}

/// `GET /v1/results/claim/:code` on the clinic backend (CLINIC-API.md,
/// "Người bệnh nhận kết quả bằng mã"). The server leaves out visitId and
/// profileId; the app attaches the result to its own visit.
class HttpDoctorPortal implements DoctorPortal {
  HttpDoctorPortal({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  @override
  Future<VisitResult> claim(
    String code, {
    required VisitSummary visit,
    PreviewProfile? patient,
  }) async {
    final normalized = normalizeClaimCode(code);
    if (normalized == null) throw ResultClaimException.invalid;
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('$baseUrl/v1/results/claim/$normalized'))
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw ResultClaimException.network;
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 404:
        throw ResultClaimException.notFound;
      case 429:
        throw ResultClaimException.rateLimited;
      default:
        throw ResultClaimException.server;
    }
    try {
      final body = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, Object?>();
      return VisitResult.fromJson({
        ...body,
        'visitId': visit.id,
        'profileId': visit.patientId ?? patient?.id ?? '',
      });
    } on Object {
      // Malformed JSON or a field of the wrong type.
      throw ResultClaimException.server;
    }
  }
}

/// Offline stand-in: any well-formed code returns a plausible result built
/// from the patient's followed conditions, as the doctor's web form would
/// after the visit. Sample data for the prototype: these are common
/// first-line prescriptions, not advice for a real person.
class MockDoctorPortal implements DoctorPortal {
  const MockDoctorPortal({this.latency = const Duration(milliseconds: 600)});
  final Duration latency;

  @override
  Future<VisitResult> claim(
    String code, {
    required VisitSummary visit,
    PreviewProfile? patient,
  }) async {
    if (normalizeClaimCode(code) == null) throw ResultClaimException.invalid;
    await Future<void>.delayed(latency);
    return buildResult(visit, patient);
  }

  static VisitResult buildResult(VisitSummary visit, PreviewProfile? patient) {
    final plans = [
      for (final id in patient?.conditions ?? const <String>[]) ?_plans[id],
    ];
    final (hour, minute) = _clock(visit.time);
    final issuedAt = DateTime(
      visit.date.year,
      visit.date.month,
      visit.date.day,
      hour,
      minute,
    );
    final items = [for (final plan in plans) plan.item];
    final days = items.fold(
      0,
      (longest, item) => item.days > longest ? item.days : longest,
    );
    final followUp = issuedAt.add(Duration(days: days == 0 ? 180 : days));
    final today = DateTime(issuedAt.year, issuedAt.month, issuedAt.day);
    return VisitResult(
      visitId: visit.id,
      profileId: visit.patientId ?? patient?.id ?? '',
      issuedAt: issuedAt,
      facilityName: visit.facilityName,
      facilityPhone: '0900000000',
      doctorName: visit.doctorName,
      patientName: visit.patientName,
      patientAge: patient == null ? 0 : profileAge(patient, today),
      patientGender: patient?.gender ?? '',
      address: patient?.address ?? '',
      diagnosis: plans.isEmpty
          ? 'Khám sức khỏe, chưa phát hiện bất thường cần dùng thuốc'
          : plans.map((plan) => plan.diagnosis).join('; '),
      items: items,
      advice: [
        for (final plan in plans) plan.advice,
        if (plans.isEmpty) 'Ăn uống điều độ, vận động 30 phút mỗi ngày.',
        'Hẹn tái khám ngày ${DateFormat('dd/MM/yyyy').format(followUp)}.',
      ],
      followUpDate: DateTime(followUp.year, followUp.month, followUp.day),
    );
  }

  static (int, int) _clock(String time) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
    if (match == null) return (8, 0);
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static const _plans = <String, _Plan>{
    'hypertension': _Plan(
      'Tăng huyết áp (I10)',
      PrescriptionItem(
        name: 'Amlodipin',
        strength: '5mg',
        form: 'viên',
        quantity: 30,
        doses: [Dose(DoseSlot.morning, 1)],
        days: 30,
      ),
      'Ăn nhạt, dưới 5 g muối mỗi ngày; đo huyết áp sáng và tối, ghi lại để mang theo khi tái khám.',
    ),
    'diabetes': _Plan(
      'Đái tháo đường type 2 (E11)',
      PrescriptionItem(
        name: 'Metformin',
        strength: '500mg',
        form: 'viên',
        quantity: 60,
        doses: [Dose(DoseSlot.morning, 1), Dose(DoseSlot.evening, 1)],
        meal: MealTiming.after,
        days: 30,
      ),
      'Hạn chế đồ ngọt và cơm trắng; đi bộ 30 phút mỗi ngày.',
    ),
    'dyslipidemia': _Plan(
      'Rối loạn lipid máu (E78)',
      PrescriptionItem(
        name: 'Atorvastatin',
        strength: '10mg',
        form: 'viên',
        quantity: 30,
        doses: [Dose(DoseSlot.evening, 1)],
        days: 30,
      ),
      'Hạn chế mỡ động vật và đồ chiên rán.',
    ),
    'gout': _Plan(
      'Gút (M10)',
      PrescriptionItem(
        name: 'Allopurinol',
        strength: '300mg',
        form: 'viên',
        quantity: 30,
        doses: [Dose(DoseSlot.morning, 1)],
        meal: MealTiming.after,
        days: 30,
        note: 'Uống nhiều nước trong ngày',
      ),
      'Uống đủ 2 lít nước mỗi ngày; hạn chế nội tạng, hải sản và bia rượu.',
    ),
    'gastritis': _Plan(
      'Viêm dạ dày (K29)',
      PrescriptionItem(
        name: 'Omeprazol',
        strength: '20mg',
        form: 'viên',
        quantity: 28,
        doses: [Dose(DoseSlot.morning, 1)],
        meal: MealTiming.before,
        days: 28,
        note: 'Uống trước ăn sáng 30 phút',
      ),
      'Ăn đúng giờ, tránh đồ cay, rượu bia và cà phê.',
    ),
  };
}

class _Plan {
  const _Plan(this.diagnosis, this.item, this.advice);
  final String diagnosis;
  final PrescriptionItem item;
  final String advice;
}
