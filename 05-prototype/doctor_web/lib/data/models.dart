import 'package:flutter/foundation.dart';
import 'package:medic_core/medic_core.dart';

/// Shapes returned by the clinic API (`backend/CLINIC-API.md`). Prescription
/// and dose data reuse the medic_core models so the app and the web read
/// the same JSON.
typedef Json = Map<String, Object?>;

/// The clinic's wall-clock time of an ISO-8601 timestamp, whatever the
/// browser's time zone. The server writes clinic times (`+07:00`); doses,
/// days and the 30-day window are all counted in that clock, so the offset
/// is dropped instead of converting to the viewer's zone.
DateTime clinicTime(String iso) {
  final m = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?')
      .firstMatch(iso);
  return DateTime.parse(m?.group(0) ?? iso);
}

List<Json> _list(Object? value) =>
    (value as List<Object?>? ?? const []).cast<Json>();

@immutable
class Staff {
  const Staff({
    required this.id,
    required this.name,
    required this.role,
    this.mustChangePassword = false,
  });
  final String id, name, role;

  /// Signed in with a one-time password: the web shows only the change
  /// password screen until a new one is set (bước 18).
  final bool mustChangePassword;

  /// The clinic admin manages accounts and sees the pilot numbers; no charts.
  bool get isAdmin => role == 'admin';

  factory Staff.fromJson(Json j) => Staff(
    id: j['id']! as String,
    name: j['name']! as String,
    role: j['role'] as String? ?? 'doctor',
    mustChangePassword: j['mustChangePassword'] as bool? ?? false,
  );
}

@immutable
class Clinic {
  const Clinic({required this.id, required this.name, required this.phone});
  final String id, name, phone;

  factory Clinic.fromJson(Json j) => Clinic(
    id: j['id']! as String,
    name: j['name']! as String,
    phone: j['phone'] as String? ?? '',
  );
}

@immutable
class StaffSession {
  const StaffSession(this.staff, this.clinic);
  final Staff staff;
  final Clinic clinic;

  factory StaffSession.fromJson(Json j) => StaffSession(
    Staff.fromJson(j['staff']! as Json),
    Clinic.fromJson(j['clinic']! as Json),
  );
}

enum VisitStatus {
  booked('Chưa đến'),
  arrived('Đã đến'),
  inProgress('Đang khám'),
  done('Đã khám xong'),
  cancelled('Đã hủy');

  const VisitStatus(this.label);
  final String label;

  static VisitStatus parse(String value) => switch (value) {
    'in_progress' => inProgress,
    _ => VisitStatus.values.byName(value),
  };
}

enum ConsentState { shared, declined, none }

enum ResultStatus { none, draft, sent }

@immutable
class PatientBrief {
  const PatientBrief({
    required this.id,
    required this.code,
    required this.name,
    required this.age,
    required this.gender,
  });
  final String id, code, name, gender;
  final int age;

  factory PatientBrief.fromJson(Json j) => PatientBrief(
    id: j['id']! as String,
    code: j['code']! as String,
    name: j['name']! as String,
    age: j['age']! as int,
    gender: j['gender']! as String,
  );
}

/// Medicines and their dose log, as shared from the app.
@immutable
class MedData {
  const MedData(this.courses, this.log);
  final List<MedicationCourse> courses;
  final Map<String, DoseLogEntry> log;

  static const empty = MedData([], {});

  factory MedData.fromJson(Json j, String patientId) => MedData(
    [
      for (final c in _list(j['courses']))
        MedicationCourse(
          id: c['id']! as String,
          profileId: patientId,
          visitId: c['visitId'] as String? ?? '',
          item: PrescriptionItem.fromJson(c['item']! as Json),
          prescribedAt: clinicTime(c['prescribedAt']! as String),
        ),
    ],
    {
      for (final e in _list(j['doseLog']))
        if (DoseLogEntry.fromJson(e) case final entry) entry.key: entry,
    },
  );
}

@immutable
class WorklistItem {
  const WorklistItem({
    required this.appointmentId,
    required this.time,
    required this.status,
    required this.kind,
    required this.specialty,
    required this.patient,
    required this.consent,
    required this.hasSummary,
    required this.flagged,
    required this.resultStatus,
    required this.chiefComplaint,
    required this.meds,
  });
  final String appointmentId, time, kind, specialty;
  final VisitStatus status;
  final PatientBrief patient;
  final ConsentState consent;
  final bool hasSummary, flagged;
  final ResultStatus resultStatus;

  /// The summary's reason for the visit, when shared.
  final String? chiefComplaint;
  final MedData meds;

  factory WorklistItem.fromJson(Json j) {
    final patient = PatientBrief.fromJson(j['patient']! as Json);
    return WorklistItem(
      appointmentId: j['appointmentId']! as String,
      time: j['time']! as String,
      status: VisitStatus.parse(j['status']! as String),
      kind: j['kind'] as String? ?? '',
      specialty: j['specialty'] as String? ?? '',
      patient: patient,
      consent: ConsentState.values.byName(j['consent']! as String),
      hasSummary: j['hasSummary'] as bool? ?? false,
      flagged: j['flagged'] as bool? ?? false,
      resultStatus: ResultStatus.values.byName(
        j['resultStatus'] as String? ?? 'none',
      ),
      chiefComplaint: j['chiefComplaint'] as String?,
      meds: MedData.fromJson(j, patient.id),
    );
  }
}

@immutable
class Worklist {
  const Worklist(this.date, this.now, this.items);
  final String date;
  final DateTime now;
  final List<WorklistItem> items;

  factory Worklist.fromJson(Json j) => Worklist(
    j['date']! as String,
    clinicTime(j['now']! as String),
    [for (final i in _list(j['items'])) WorklistItem.fromJson(i)],
  );
}

@immutable
class PatientDetail {
  const PatientDetail({
    required this.brief,
    required this.birthDate,
    required this.address,
    required this.weightKg,
    required this.insuranceCode,
    required this.allergy,
    required this.conditions,
  });
  final PatientBrief brief;
  final String birthDate, address, insuranceCode, allergy;
  final num? weightKg;
  final List<String> conditions;

  factory PatientDetail.fromJson(Json j) => PatientDetail(
    brief: PatientBrief.fromJson(j),
    birthDate: j['birthDate'] as String? ?? '',
    address: j['address'] as String? ?? '',
    weightKg: j['weightKg'] as num?,
    insuranceCode: j['insuranceCode'] as String? ?? '',
    allergy: j['allergy'] as String? ?? '',
    conditions: (j['conditions'] as List<Object?>? ?? const []).cast<String>(),
  );
}

@immutable
class Consent {
  const Consent({
    required this.state,
    this.grantedAt,
    this.expiresAt,
    this.reason,
    this.revokedAt,
  });
  final ConsentState state;
  final DateTime? grantedAt, expiresAt;

  /// Why a once-given consent no longer holds: 'revoked' or 'expired'.
  final String? reason;
  final DateTime? revokedAt;

  factory Consent.fromJson(Json? j) => j == null
      ? const Consent(state: ConsentState.none)
      : Consent(
          state: ConsentState.values.byName(j['state']! as String),
          grantedAt: _date(j['grantedAt']),
          expiresAt: _date(j['expiresAt']),
          reason: j['reason'] as String?,
          revokedAt: _date(j['revokedAt']),
        );
}

DateTime? _date(Object? value) => value is String ? clinicTime(value) : null;

@immutable
class IntakeAnswer {
  const IntakeAnswer({
    required this.id,
    required this.channel,
    required this.question,
    required this.answer,
    required this.answeredAt,
  });
  final String id, channel, question, answer;
  final DateTime answeredAt;

  /// "Lúc đặt lịch" or "Câu hỏi trước khám", as the prototype labels them.
  String get channelLabel =>
      channel == 'booking' ? 'Lúc đặt lịch' : 'Câu hỏi trước khám';

  factory IntakeAnswer.fromJson(Json j) => IntakeAnswer(
    id: j['id']! as String,
    channel: j['channel']! as String,
    question: j['question'] as String? ?? '',
    answer: j['answer']! as String,
    answeredAt: clinicTime(j['answeredAt']! as String),
  );
}

@immutable
class SummarySection {
  const SummarySection(this.key, this.text, this.sources);
  final String key, text;
  final List<String> sources;

  factory SummarySection.fromJson(Json j) => SummarySection(
    j['key']! as String,
    j['text']! as String,
    (j['sources'] as List<Object?>? ?? const []).cast<String>(),
  );
}

@immutable
class Summary {
  const Summary({
    required this.id,
    required this.mode,
    required this.createdAt,
    required this.sections,
    required this.flags,
    required this.feedback,
  });
  final String id, mode;
  final DateTime createdAt;
  final List<SummarySection> sections;
  final List<SummarySection> flags;

  /// 'up', 'down' or null.
  final String? feedback;

  SummarySection? section(String key) =>
      sections.where((s) => s.key == key).firstOrNull;

  Summary withFeedback(String value) => Summary(
    id: id,
    mode: mode,
    createdAt: createdAt,
    sections: sections,
    flags: flags,
    feedback: value,
  );

  factory Summary.fromJson(Json j) => Summary(
    id: j['id']! as String,
    mode: j['mode'] as String? ?? '',
    createdAt: clinicTime(j['createdAt']! as String),
    sections: [
      for (final s in _list(j['sections'])) SummarySection.fromJson(s),
    ],
    flags: [
      for (final f in _list(j['flags']))
        SummarySection('flag', f['text']! as String, [
          ...(f['sources'] as List<Object?>? ?? const []).cast<String>(),
        ]),
    ],
    feedback: switch (j['feedback']) {
      final Json f => f['value'] as String?,
      _ => null,
    },
  );
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.appointmentId,
    required this.date,
    required this.clinicName,
    required this.doctorName,
    required this.diagnosis,
    required this.items,
    required this.advice,
    required this.followUpDate,
  });
  final String appointmentId, date, clinicName, doctorName, advice;
  final List<(String code, String name)> diagnosis;
  final List<PrescriptionItem> items;
  final String? followUpDate;

  String get diagnosisText =>
      diagnosis.map((d) => '${d.$2} (${d.$1})').join('; ');

  factory HistoryEntry.fromJson(Json j) => HistoryEntry(
    appointmentId: j['appointmentId']! as String,
    date: j['date']! as String,
    clinicName: j['clinicName'] as String? ?? '',
    doctorName: j['doctorName'] as String? ?? '',
    diagnosis: [
      for (final d in j['diagnosis'] as List<Object?>? ?? const [])
        if (d case [final String code, final String name]) (code, name),
    ],
    items: [for (final i in _list(j['items'])) PrescriptionItem.fromJson(i)],
    advice: j['advice'] as String? ?? '',
    followUpDate: j['followUpDate'] as String?,
  );
}

@immutable
class ChartData {
  const ChartData({
    required this.appointmentId,
    required this.time,
    required this.startsAt,
    required this.status,
    required this.kind,
    required this.specialty,
    required this.resultStatus,
    required this.patient,
    required this.consent,
    required this.periodFrom,
    required this.periodDays,
    required this.now,
    required this.summary,
    required this.intake,
    required this.meds,
    required this.selfMeds,
    required this.lastVisit,
  });
  final String appointmentId, time, kind, specialty;
  final DateTime startsAt, now, periodFrom;
  final int periodDays;
  final VisitStatus status;
  final ResultStatus resultStatus;
  final PatientDetail patient;
  final Consent consent;
  final Summary? summary;
  final List<IntakeAnswer> intake;
  final MedData meds;
  final List<(String name, String how)> selfMeds;
  final HistoryEntry? lastVisit;

  bool get shared => consent.state == ConsentState.shared;

  IntakeAnswer? answer(String id) =>
      intake.where((a) => a.id == id).firstOrNull;

  ChartData copyWith({VisitStatus? status, Summary? summary}) => ChartData(
    appointmentId: appointmentId,
    time: time,
    startsAt: startsAt,
    status: status ?? this.status,
    kind: kind,
    specialty: specialty,
    resultStatus: resultStatus,
    patient: patient,
    consent: consent,
    periodFrom: periodFrom,
    periodDays: periodDays,
    now: now,
    summary: summary ?? this.summary,
    intake: intake,
    meds: meds,
    selfMeds: selfMeds,
    lastVisit: lastVisit,
  );

  factory ChartData.fromJson(Json j) {
    final a = j['appointment']! as Json;
    final patient = PatientDetail.fromJson(j['patient']! as Json);
    final period = j['period']! as Json;
    return ChartData(
      appointmentId: a['id']! as String,
      time: a['time']! as String,
      startsAt: clinicTime(a['startsAt']! as String),
      status: VisitStatus.parse(a['status']! as String),
      kind: a['kind'] as String? ?? '',
      specialty: a['specialty'] as String? ?? '',
      resultStatus: ResultStatus.values.byName(
        a['resultStatus'] as String? ?? 'none',
      ),
      patient: patient,
      consent: Consent.fromJson(j['consent'] as Json?),
      periodFrom: clinicTime(period['from']! as String),
      periodDays: period['days']! as int,
      now: clinicTime(period['now']! as String),
      summary: switch (j['summary']) {
        final Json s => Summary.fromJson(s),
        _ => null,
      },
      intake: [for (final i in _list(j['intake'])) IntakeAnswer.fromJson(i)],
      meds: MedData.fromJson(j, patient.brief.id),
      selfMeds: [
        for (final m in _list(j['selfMeds']))
          (m['name']! as String, m['how'] as String? ?? ''),
      ],
      lastVisit: switch (j['lastVisit']) {
        final Json h => HistoryEntry.fromJson(h),
        _ => null,
      },
    );
  }
}
