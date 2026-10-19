import 'package:flutter/foundation.dart';

/// Which side of a link this phone is. The owner made the family profile
/// (the caregiver); the member is that person, on their own phone.
enum FamilyRole { owner, member }

enum FamilyLinkStatus { pending, linked, ended }

/// What the member's phone reported about a dose (owner side only).
enum FamilyAlertKind { missed, skipped, taken }

/// A missed, skipped or late dose of the linked person, as the owner sees it.
@immutable
class FamilyAlert {
  const FamilyAlert({
    required this.kind,
    required this.key,
    required this.at,
    required this.label,
    this.meds = const [],
    this.reason,
  });
  final FamilyAlertKind kind;

  /// The member's dose key; one dose can be missed, then taken.
  final String key;

  /// When the dose was due (Vietnam wall-clock).
  final DateTime at;

  /// "07:00".
  final String label;
  final List<String> meds;

  /// `forgot`, `outOfStock`, `unwell` or `other` for a skipped dose.
  final String? reason;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'key': key,
    'at': at.toIso8601String(),
    'label': label,
    'meds': meds,
    'reason': reason,
  };

  factory FamilyAlert.fromJson(Map<String, Object?> json) => FamilyAlert(
    kind: FamilyAlertKind.values.byName(json['kind']! as String),
    key: json['key']! as String,
    at: DateTime.parse(json['at']! as String),
    label: json['label']! as String,
    meds: List.unmodifiable((json['meds'] as List<Object?>? ?? []).cast()),
    reason: json['reason'] as String?,
  );
}

/// A family profile linked with that person's own phone (Liên kết hai máy).
/// Kept in the account, so in the encrypted vault after consent; [token] is
/// this phone's secret for the link.
@immutable
class FamilyLink {
  const FamilyLink({
    required this.id,
    required this.token,
    required this.role,
    required this.profileId,
    required this.status,
    this.peerName,
    this.inviteCode,
    this.inviteExpiresAt,
    this.cursor = 0,
    this.shareMissed = true,
    this.pushed = const {},
    this.alerts = const [],
  });
  final String id, token;
  final FamilyRole role;

  /// The local profile the link is about: the family profile on the owner's
  /// phone, the holder's own profile on the member's.
  final String profileId;
  final FamilyLinkStatus status;

  /// The other side's name: the member once linked, or the owner.
  final String? peerName;

  /// Owner, while pending: the code the member types or scans.
  final String? inviteCode;
  final DateTime? inviteExpiresAt;

  /// Last event read from the other side.
  final int cursor;

  /// Member: whether the owner hears of missed and skipped doses.
  final bool shareMissed;

  /// What this phone last sent, by item key, as a fingerprint, so only
  /// changes go out and items received are not sent back.
  final Map<String, String> pushed;

  /// Owner: the latest dose alerts, newest first.
  final List<FamilyAlert> alerts;

  static const maxAlerts = 20;

  bool get linked => status == FamilyLinkStatus.linked;

  FamilyLink copyWith({
    FamilyLinkStatus? status,
    String? Function()? peerName,
    String? Function()? inviteCode,
    DateTime? Function()? inviteExpiresAt,
    int? cursor,
    bool? shareMissed,
    Map<String, String>? pushed,
    List<FamilyAlert>? alerts,
  }) => FamilyLink(
    id: id,
    token: token,
    role: role,
    profileId: profileId,
    status: status ?? this.status,
    peerName: peerName == null ? this.peerName : peerName(),
    inviteCode: inviteCode == null ? this.inviteCode : inviteCode(),
    inviteExpiresAt: inviteExpiresAt == null
        ? this.inviteExpiresAt
        : inviteExpiresAt(),
    cursor: cursor ?? this.cursor,
    shareMissed: shareMissed ?? this.shareMissed,
    pushed: pushed ?? this.pushed,
    alerts: alerts ?? this.alerts,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'token': token,
    'role': role.name,
    'profileId': profileId,
    'status': status.name,
    'peerName': peerName,
    'inviteCode': inviteCode,
    'inviteExpiresAt': inviteExpiresAt?.toIso8601String(),
    'cursor': cursor,
    'shareMissed': shareMissed,
    'pushed': pushed,
    'alerts': [for (final alert in alerts) alert.toJson()],
  };

  factory FamilyLink.fromJson(Map<String, Object?> json) => FamilyLink(
    id: json['id']! as String,
    token: json['token']! as String,
    role: FamilyRole.values.byName(json['role']! as String),
    profileId: json['profileId']! as String,
    status: FamilyLinkStatus.values.byName(json['status']! as String),
    peerName: json['peerName'] as String?,
    inviteCode: json['inviteCode'] as String?,
    inviteExpiresAt: switch (json['inviteExpiresAt']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
    cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    shareMissed: json['shareMissed'] as bool? ?? true,
    pushed: Map.unmodifiable(
      (json['pushed'] as Map<String, Object?>? ?? const {}).cast(),
    ),
    alerts: List.unmodifiable([
      for (final alert in json['alerts'] as List<Object?>? ?? const [])
        FamilyAlert.fromJson(alert! as Map<String, Object?>),
    ]),
  );
}

/// What a QR made by the owner's phone holds.
const familyQrPrefix = 'medicapp://lien-ket?ma=';

String familyQr(String code) => '$familyQrPrefix$code';

/// "ABCD-EF23" from a scanned QR or typed text; null when it is neither.
String? inviteCodeFrom(String raw) {
  var text = raw.trim();
  if (text.startsWith(familyQrPrefix)) {
    text = text.substring(familyQrPrefix.length);
  }
  final plain = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^[A-HJKMNP-Z2-9]{8}$').hasMatch(plain)) return null;
  return '${plain.substring(0, 4)}-${plain.substring(4)}';
}
