import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum OutboxKind { intake, selfMeds, doses }

/// One upload waiting to reach the clinic. Kept with the account (so in the
/// encrypted vault after on-device consent) until the server accepts it, or
/// refuses it for good.
@immutable
class OutboxItem {
  const OutboxItem({
    required this.kind,
    required this.body,
    this.appointmentId,
    this.attempts = 0,
  });
  final OutboxKind kind;

  /// Null for dose events, which the server matches by course id.
  final String? appointmentId;

  /// The JSON body as sent.
  final Map<String, Object?> body;
  final int attempts;

  OutboxItem retried() => OutboxItem(
    kind: kind,
    body: body,
    appointmentId: appointmentId,
    attempts: attempts + 1,
  );

  List<Map<String, Object?>> get events => [
    for (final event in body['events'] as List<Object?>? ?? const [])
      (event! as Map).cast<String, Object?>(),
  ];

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'appointmentId': appointmentId,
    'body': body,
    'attempts': attempts,
  };

  factory OutboxItem.fromJson(Map<String, Object?> json) => OutboxItem(
    kind: OutboxKind.values.byName(json['kind']! as String),
    appointmentId: json['appointmentId'] as String?,
    body: (json['body']! as Map).cast<String, Object?>(),
    attempts: json['attempts'] as int? ?? 0,
  );
}

/// The most dose events one request may carry (contract limit).
const maxDoseEventsPerRequest = 500;

String _doseKey(Map<String, Object?> event) =>
    '${event['courseId']}|${event['day']}|${event['slot']}';

/// Adds [item] to [queue]. Intake answers and self meds replace what was
/// waiting for the same appointment (each upload carries the full set);
/// dose events merge into the waiting batch, the newest mark of a dose
/// winning, since the server upserts by course, day and slot.
List<OutboxItem> enqueue(List<OutboxItem> queue, OutboxItem item) {
  if (item.kind != OutboxKind.doses) {
    return List.unmodifiable([
      for (final waiting in queue)
        if (waiting.kind != item.kind ||
            waiting.appointmentId != item.appointmentId)
          waiting,
      item,
    ]);
  }
  final index = queue.indexWhere(
    (waiting) =>
        waiting.kind == OutboxKind.doses &&
        waiting.events.length < maxDoseEventsPerRequest,
  );
  final merged = <String, Map<String, Object?>>{
    if (index >= 0)
      for (final event in queue[index].events) _doseKey(event): event,
    for (final event in item.events) _doseKey(event): event,
  };
  final events = merged.values.toList();
  final batches = [
    for (var i = 0; i < events.length; i += maxDoseEventsPerRequest)
      OutboxItem(
        kind: OutboxKind.doses,
        body: {
          'events': events.sublist(
            i,
            math.min(i + maxDoseEventsPerRequest, events.length),
          ),
        },
        attempts: i == 0 && index >= 0 ? queue[index].attempts : 0,
      ),
  ];
  if (index < 0) return List.unmodifiable([...queue, ...batches]);
  return List.unmodifiable([
    ...queue.take(index),
    batches.first,
    ...queue.skip(index + 1),
    ...batches.skip(1),
  ]);
}
