import 'dart:typed_data';

import '../../booking/domain/booking_models.dart';

/// Server reply status (backend `reply()`).
enum SmartStatus { ask, ready, urgent, fallback, superseded }

/// Screen states SS00–SS08 of the implementation PRD.
enum SmartPhase {
  starting, // creating the session
  ready, // SS00
  connecting, // SS01
  listening, // SS02
  processing, // SS03
  asking, // SS04
  proposal, // SS05
  confirming, // SS06
  error, // SS07
  urgent, // SS08
  handedOff, // payment has the draft
}

class SmartOption {
  const SmartOption(this.value, this.label, {this.hint});
  factory SmartOption.fromJson(Map<String, dynamic> json) => SmartOption(
    json['value'] as String,
    json['label'] as String,
    hint: json['hint'] as String?,
  );
  final String value, label;
  final String? hint;
}

class SmartQuestion {
  const SmartQuestion({
    required this.field,
    required this.text,
    required this.options,
    this.allowPicker = false,
  });
  factory SmartQuestion.fromJson(Map<String, dynamic> json) => SmartQuestion(
    field: json['field'] as String,
    text: json['text'] as String,
    options: [
      for (final option in (json['options'] as List? ?? const []))
        SmartOption.fromJson((option as Map).cast<String, dynamic>()),
    ],
    allowPicker: json['allow_picker'] == true,
  );
  final String field, text;
  final List<SmartOption> options;
  final bool allowPicker;
}

class SmartTime {
  const SmartTime({required this.earliest, this.date, this.period});
  factory SmartTime.fromJson(Map<String, dynamic> json) => SmartTime(
    earliest: json['kind'] == 'earliest',
    date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
    period: json['period'] as String?,
  );
  final bool earliest;
  final DateTime? date;

  /// `morning`, `afternoon` or null.
  final String? period;

  /// Value understood by the backend's `time` field.
  String get wire {
    final base = earliest
        ? 'earliest'
        : 'date:${date!.toIso8601String().substring(0, 10)}';
    return period == null ? base : '$base:$period';
  }
}

class SmartFields {
  const SmartFields({
    this.patientId,
    this.type,
    this.facilityId,
    this.departmentId,
    this.departmentReason,
    this.doctorId,
    this.time,
    this.symptoms,
  });
  factory SmartFields.fromJson(Map<String, dynamic> json) => SmartFields(
    patientId: json['patient_id'] as String?,
    type: switch (json['visit_type']) {
      'insurance' => VisitType.insurance,
      'service' => VisitType.service,
      _ => null,
    },
    facilityId: json['facility_id'] as String?,
    departmentId: json['department_id'] as String?,
    departmentReason: json['department_reason'] as String?,
    doctorId: json['doctor_id'] as String?,
    time: json['time'] == null
        ? null
        : SmartTime.fromJson((json['time'] as Map).cast<String, dynamic>()),
    symptoms: json['symptoms'] as String?,
  );
  final String? patientId, facilityId, departmentId, departmentReason;
  final String? doctorId, symptoms;
  final VisitType? type;
  final SmartTime? time;

  /// Current value of a field in the backend's wire format (for Undo).
  String? wire(String field) => switch (field) {
    'patientId' => patientId,
    'type' => type?.name,
    'facilityId' => facilityId,
    'departmentId' => departmentId,
    'doctorId' => doctorId,
    'time' => time?.wire,
    _ => null,
  };
}

class SmartReply {
  const SmartReply({
    required this.status,
    required this.version,
    required this.fields,
    this.sources = const {},
    this.question,
    this.notice,
    this.errorCode,
    this.errorMessage,
    this.processing = false,
    this.changed = const [],
    this.turnId,
  });
  factory SmartReply.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map?;
    return SmartReply(
      status: SmartStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SmartStatus.fallback,
      ),
      version: (json['draft_version'] as num?)?.toInt() ?? -1,
      fields: json['fields'] == null
          ? const SmartFields()
          : SmartFields.fromJson(
              (json['fields'] as Map).cast<String, dynamic>(),
            ),
      sources: ((json['sources'] as Map?) ?? const {}).cast<String, String>(),
      question: json['question'] == null
          ? null
          : SmartQuestion.fromJson(
              (json['question'] as Map).cast<String, dynamic>(),
            ),
      notice: json['notice'] as String?,
      errorCode: error?['code'] as String?,
      errorMessage: error?['message'] as String?,
      processing: json['processing'] == true,
      changed: [for (final f in (json['changed'] as List? ?? const [])) '$f'],
      turnId: json['turn_id'] as String?,
    );
  }
  final SmartStatus status;
  final int version;
  final SmartFields fields;
  final Map<String, String> sources;
  final SmartQuestion? question;
  final String? notice, errorCode, errorMessage, turnId;
  final bool processing;
  final List<String> changed;
}

class SmartSessionInfo {
  const SmartSessionInfo({
    required this.mode,
    required this.voiceAvailable,
    required this.reply,
  });
  final String mode;
  final bool voiceAvailable;
  final SmartReply reply;
  bool get simulated => mode != 'openai';
}

/// Minimal context sent to the backend: no names, phone numbers or birth dates.
class SmartContext {
  const SmartContext({
    required this.today,
    required this.profiles,
    this.patientId,
    this.type,
    this.facilityId,
  });
  final DateTime today;
  final List<({String id, String relationship, int age})> profiles;
  final String? patientId, facilityId;
  final VisitType? type;

  Map<String, dynamic> toJson() => {
    'today': today.toIso8601String().substring(0, 10),
    'profiles': [
      for (final p in profiles)
        {'id': p.id, 'relationship': p.relationship, 'age': p.age},
    ],
    'known': {
      'patient_id': patientId,
      'visit_type': type?.name,
      'facility_id': facilityId,
    },
  };
}

sealed class SmartAudioEvent {
  const SmartAudioEvent();
}

class AudioReady extends SmartAudioEvent {
  const AudioReady();
}

class TranscriptDelta extends SmartAudioEvent {
  const TranscriptDelta(this.turnId, this.text);
  final String turnId, text;
}

class TranscriptFinal extends SmartAudioEvent {
  const TranscriptFinal(this.turnId, this.text);
  final String turnId, text;
}

class TurnResult extends SmartAudioEvent {
  const TurnResult(this.reply);
  final SmartReply reply;
}

class TurnEmpty extends SmartAudioEvent {
  const TurnEmpty(this.turnId);
  final String turnId;
}

class AudioWarning extends SmartAudioEvent {
  const AudioWarning(this.reason, [this.remainingSeconds]);
  final String reason;
  final int? remainingSeconds;
}

class AudioStopped extends SmartAudioEvent {
  const AudioStopped(this.reason);
  final String reason;
}

class AudioError extends SmartAudioEvent {
  const AudioError(this.code, this.message);
  final String code, message;
}

/// One live microphone connection (app → backend → transcription).
abstract interface class SmartAudioLink {
  Stream<SmartAudioEvent> get events;
  void start();
  void sendAudio(Uint8List pcm16);
  void commit();
  void cancelTurn();
  void stop();
  Future<void> close();
}

/// Booking proposal built from server fields and the booking repository.
class SmartProposal {
  const SmartProposal({required this.draft, required this.fee});
  final BookingDraft draft;
  final int fee;
}

class SmartMessage {
  const SmartMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

class SmartGatewayException implements Exception {
  const SmartGatewayException(this.code, this.message);
  final String code, message;
  @override
  String toString() => 'SmartGatewayException($code)';
}
