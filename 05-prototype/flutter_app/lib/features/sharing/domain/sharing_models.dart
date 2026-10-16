import 'package:flutter/foundation.dart';

/// What a person may share with the clinic for one visit (bước 16). Each is
/// a separate choice on the "Chia sẻ với phòng khám" page; the wire names
/// are the backend's.
enum ShareScope {
  intake(
    'intake',
    'Câu trả lời trước khám',
    'Những gì bạn trả lời ở phần "Câu hỏi trước khám".',
  ),
  doseLog(
    'dose_log',
    '30 ngày uống thuốc',
    'Những liều bạn ghi đã uống hoặc bỏ, theo đơn của phòng khám, trong 30 '
        'ngày gần nhất.',
  ),
  selfMeds(
    'self_meds',
    'Thuốc tự dùng',
    'Thuốc bạn tự mua uống, ngoài đơn của bác sĩ.',
  );

  const ShareScope(this.wire, this.label, this.detail);
  final String wire, label, detail;

  static ShareScope? fromWire(String value) =>
      values.where((scope) => scope.wire == value).firstOrNull;
}

/// Version of the sharing page's wording, sent with every consent.
const sharingWordingVersion = 1;

/// Days a consent lasts after the visit, as the backend computes it.
const sharingDays = 30;

/// Vietnam wall-clock time of [instant], as a naive value like appointment
/// dates in the app.
DateTime vietnamClock(DateTime instant) {
  final utc = instant.toUtc().add(const Duration(hours: 7));
  return DateTime(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}

/// A naive Vietnam wall-clock value written as ISO-8601 with `+07:00`, the
/// form the clinic API uses.
String vietnamIso(DateTime clock) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${clock.year.toString().padLeft(4, '0')}-${two(clock.month)}-'
      '${two(clock.day)}T${two(clock.hour)}:${two(clock.minute)}:'
      '${two(clock.second)}+07:00';
}

DateTime? _instant(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

String? _wire(DateTime? value) => value?.toUtc().toIso8601String();

enum SharingState { shared, revoked, expired }

/// The latest consent the clinic holds for one appointment (ConsentView).
@immutable
class SharingConsent {
  const SharingConsent({
    required this.state,
    required this.scope,
    required this.grantedAt,
    required this.expiresAt,
    this.revokedAt,
  });
  final SharingState state;
  final Set<ShareScope> scope;
  final DateTime grantedAt, expiresAt;
  final DateTime? revokedAt;

  bool activeAt(DateTime now) =>
      state == SharingState.shared && expiresAt.isAfter(now);

  bool covers(ShareScope value, DateTime now) =>
      activeAt(now) && scope.contains(value);

  Map<String, Object?> toJson() => {
    'state': state.name,
    'scope': [for (final value in scope) value.wire],
    'grantedAt': _wire(grantedAt),
    'expiresAt': _wire(expiresAt),
    'revokedAt': _wire(revokedAt),
  };

  factory SharingConsent.fromJson(Map<String, Object?> json) => SharingConsent(
    state: SharingState.values.byName(json['state']! as String),
    scope: {
      for (final value in json['scope']! as List<Object?>)
        ?ShareScope.fromWire(value! as String),
    },
    grantedAt: _instant(json['grantedAt'])!,
    expiresAt: _instant(json['expiresAt'])!,
    revokedAt: _instant(json['revokedAt']),
  );
}

@immutable
class SelfMed {
  const SelfMed({required this.name, required this.how});
  final String name, how;

  Map<String, Object?> toJson() => {'name': name, 'how': how};

  factory SelfMed.fromJson(Map<String, Object?> json) =>
      SelfMed(name: json['name']! as String, how: json['how'] as String? ?? '');
}

@immutable
class ClinicRef {
  const ClinicRef({required this.id, required this.name, this.phone = ''});
  final String id, name, phone;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'phone': phone};

  factory ClinicRef.fromJson(Map<String, Object?> json) => ClinicRef(
    id: json['id']! as String,
    name: json['name']! as String,
    phone: json['phone'] as String? ?? '',
  );
}

/// An appointment the clinic holds for this phone number
/// (`GET /v1/patient/appointments`).
@immutable
class ServerAppointment {
  const ServerAppointment({
    required this.id,
    required this.clinic,
    required this.startsAt,
    required this.time,
    required this.specialty,
    required this.kind,
    required this.status,
    required this.resultStatus,
    this.consent,
    this.intakeCount = 0,
    this.selfMeds = const [],
    this.patientName = '',
  });
  final String id;
  final ClinicRef clinic;
  final DateTime startsAt;

  /// `HH:mm` in Vietnam.
  final String time;
  final String specialty, kind;

  /// `booked`, `arrived`, `in_progress`, `done` or `cancelled`.
  final String status;

  /// `none` or `sent`.
  final String resultStatus;
  final SharingConsent? consent;
  final int intakeCount;
  final List<SelfMed> selfMeds;

  /// Not in the contract's list body; filled from `patient.name` when the
  /// server sends it, else from the session.
  final String patientName;

  bool get cancelled => status == 'cancelled';
  bool get hasResult => resultStatus == 'sent';

  /// Start in Vietnam wall-clock time.
  DateTime get start => vietnamClock(startsAt);

  /// When a consent given now would end: 30 days after the visit, or after
  /// today when the visit has passed (the backend's rule).
  DateTime expiryIfGrantedAt(DateTime now) {
    final fromVisit = startsAt.add(const Duration(days: sharingDays));
    return fromVisit.isAfter(now)
        ? fromVisit
        : now.add(const Duration(days: sharingDays));
  }

  ServerAppointment withConsent(SharingConsent? value) => ServerAppointment(
    id: id,
    clinic: clinic,
    startsAt: startsAt,
    time: time,
    specialty: specialty,
    kind: kind,
    status: status,
    resultStatus: resultStatus,
    consent: value,
    intakeCount: intakeCount,
    selfMeds: selfMeds,
    patientName: patientName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'clinic': clinic.toJson(),
    'startsAt': _wire(startsAt),
    'time': time,
    'specialty': specialty,
    'kind': kind,
    'status': status,
    'resultStatus': resultStatus,
    'consent': consent?.toJson(),
    'intakeCount': intakeCount,
    'selfMeds': [for (final med in selfMeds) med.toJson()],
    'patientName': patientName,
  };

  /// Reads both the server body and [toJson]'s output.
  factory ServerAppointment.fromJson(
    Map<String, Object?> json, {
    String fallbackName = '',
  }) {
    final startsAt = _instant(json['startsAt'])!;
    final time = json['time'] as String? ?? '';
    return ServerAppointment(
      id: json['id']! as String,
      clinic: ClinicRef.fromJson(json['clinic']! as Map<String, Object?>),
      startsAt: startsAt,
      time: RegExp(r'^\d{2}:\d{2}$').hasMatch(time)
          ? time
          : vietnamIso(vietnamClock(startsAt)).substring(11, 16),
      specialty: json['specialty'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? 'booked',
      // The backend reports a draft as 'none'; anything but 'sent' is none.
      resultStatus: json['resultStatus'] == 'sent' ? 'sent' : 'none',
      consent: switch (json['consent']) {
        final Map<String, Object?> value => SharingConsent.fromJson(value),
        _ => null,
      },
      intakeCount: (json['intakeCount'] as num?)?.toInt() ?? 0,
      selfMeds: [
        for (final med in json['selfMeds'] as List<Object?>? ?? const [])
          SelfMed.fromJson(med! as Map<String, Object?>),
      ],
      patientName: switch (json) {
        {'patientName': final String name} when name.isNotEmpty => name,
        {'patient': {'name': final String name}} when name.isNotEmpty => name,
        _ => fallbackName,
      },
    );
  }
}

enum IntakeChannel {
  booking('booking'),
  preVisit('pre_visit');

  const IntakeChannel(this.wire);
  final String wire;
}

/// One answer the person gave about a visit. [id] is stable for the same
/// question, so sending again updates the clinic's copy instead of adding.
@immutable
class IntakeAnswer {
  const IntakeAnswer({
    required this.id,
    required this.channel,
    required this.question,
    required this.answer,
    required this.answeredAt,
  });
  final String id;
  final IntakeChannel channel;
  final String question, answer;

  /// Vietnam wall-clock time.
  final DateTime answeredAt;

  Map<String, Object?> toWire() => {
    'id': id,
    'channel': channel.wire,
    'question': question,
    'answer': answer,
    'answeredAt': vietnamIso(answeredAt),
  };

  Map<String, Object?> toJson() => {
    ...toWire(),
    'answeredAt': answeredAt.toIso8601String(),
  };

  factory IntakeAnswer.fromJson(Map<String, Object?> json) => IntakeAnswer(
    id: json['id']! as String,
    channel: IntakeChannel.values.firstWhere(
      (channel) => channel.wire == json['channel'],
      orElse: () => IntakeChannel.preVisit,
    ),
    question: json['question']! as String,
    answer: json['answer']! as String,
    answeredAt: DateTime.parse(json['answeredAt']! as String),
  );
}

/// Signed-in session with the clinic backend. Kept with the account, so it
/// reaches the device only when the account holder agreed to on-device
/// storage; otherwise it lives in memory until the app closes.
@immutable
class PatientSession {
  const PatientSession({
    required this.token,
    required this.expiresAt,
    required this.phone,
    this.name = '',
  });
  final String token;
  final DateTime expiresAt;
  final String phone, name;

  bool validAt(DateTime now) => expiresAt.isAfter(now);

  Map<String, Object?> toJson() => {
    'token': token,
    'expiresAt': _wire(expiresAt),
    'phone': phone,
    'name': name,
  };

  factory PatientSession.fromJson(Map<String, Object?> json) => PatientSession(
    token: json['token']! as String,
    expiresAt: _instant(json['expiresAt'])!,
    phone: json['phone']! as String,
    name: json['name'] as String? ?? '',
  );
}
