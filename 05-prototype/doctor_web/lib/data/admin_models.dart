import 'package:flutter/foundation.dart';

import 'models.dart';

/// Bước 18 shapes: accounts, access log and pilot numbers
/// (`backend/CLINIC-API.md`, "Quản trị và vận hành").

@immutable
class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.name,
    required this.fullName,
    required this.title,
    required this.email,
    required this.role,
    required this.active,
    required this.locked,
    required this.mustChangePassword,
    required this.lastLoginAt,
  });
  final String id, name, fullName, title, email, role;
  final bool active, locked, mustChangePassword;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == 'admin';
  String get roleLabel => isAdmin ? 'Quản trị' : 'Bác sĩ';

  factory StaffAccount.fromJson(Json j) => StaffAccount(
    id: j['id']! as String,
    name: j['name']! as String,
    fullName: j['fullName'] as String? ?? '',
    title: j['title'] as String? ?? '',
    email: j['email']! as String,
    role: j['role']! as String,
    active: j['active'] as bool? ?? true,
    locked: j['locked'] as bool? ?? false,
    mustChangePassword: j['mustChangePassword'] as bool? ?? false,
    lastLoginAt: switch (j['lastLoginAt']) {
      final String at => clinicTime(at),
      _ => null,
    },
  );
}

/// An account and the one-time password the server shows once.
typedef IssuedPassword = ({StaffAccount staff, String password});

@immutable
class AccessLogEntry {
  const AccessLogEntry({
    required this.at,
    required this.actorKind,
    required this.actorName,
    required this.label,
    required this.visitDate,
  });
  final DateTime at;
  final String actorKind, actorName, label;
  final String? visitDate;

  factory AccessLogEntry.fromJson(Json j) {
    final actor = j['actor']! as Json;
    return AccessLogEntry(
      at: clinicTime(j['at']! as String),
      actorKind: actor['kind']! as String,
      actorName: actor['name']! as String,
      label: j['label']! as String,
      visitDate: j['visitDate'] as String?,
    );
  }
}

@immutable
class AccessLogPage {
  const AccessLogPage({
    required this.patientId,
    required this.patientCode,
    required this.patientName,
    required this.total,
    required this.items,
    required this.nextOffset,
  });
  final String patientId, patientCode, patientName;
  final int total;
  final List<AccessLogEntry> items;
  final int? nextOffset;

  factory AccessLogPage.fromJson(Json j) {
    final p = j['patient']! as Json;
    return AccessLogPage(
      patientId: p['id']! as String,
      patientCode: p['code']! as String,
      patientName: p['name']! as String,
      total: j['total']! as int,
      items: [
        for (final e in j['items']! as List<Object?>)
          AccessLogEntry.fromJson(e! as Json),
      ],
      nextOffset: j['nextOffset'] as int?,
    );
  }
}

/// One line of the pilot numbers: the whole range or one day.
@immutable
class MetricsRow {
  const MetricsRow({
    required this.date,
    required this.visits,
    required this.withSummary,
    required this.feedbackUp,
    required this.feedbackDown,
    required this.upRate,
    required this.sent,
    required this.received,
    required this.medianMinutes,
    required this.p90Minutes,
    required this.amended,
  });
  final String? date;
  final int visits, withSummary, feedbackUp, feedbackDown, sent, received;
  final int amended;
  final double? upRate;
  final int? medianMinutes, p90Minutes;

  factory MetricsRow.fromJson(Json j) => MetricsRow(
    date: j['date'] as String?,
    visits: j['visits']! as int,
    withSummary: j['withSummary']! as int,
    feedbackUp: j['feedbackUp']! as int,
    feedbackDown: j['feedbackDown']! as int,
    upRate: (j['upRate'] as num?)?.toDouble(),
    sent: j['sent']! as int,
    received: j['received']! as int,
    medianMinutes: j['medianMinutes'] as int?,
    p90Minutes: j['p90Minutes'] as int?,
    amended: j['amended']! as int,
  );
}

@immutable
class PilotMetrics {
  const PilotMetrics(this.from, this.to, this.totals, this.days);
  final String from, to;
  final MetricsRow totals;
  final List<MetricsRow> days;

  factory PilotMetrics.fromJson(Json j) => PilotMetrics(
    j['from']! as String,
    j['to']! as String,
    MetricsRow.fromJson(j['totals']! as Json),
    [
      for (final d in j['days']! as List<Object?>)
        MetricsRow.fromJson(d! as Json),
    ],
  );
}
