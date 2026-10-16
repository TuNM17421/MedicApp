import 'package:flutter/foundation.dart';
import 'package:medic_core/medic_core.dart';

import 'models.dart';

enum ResultVersionStatus { draft, sent, amended }

/// One version of a visit's result (`ResultDraft` in CLINIC-API.md).
@immutable
class ResultDraft {
  const ResultDraft({
    required this.id,
    required this.appointmentId,
    required this.version,
    required this.status,
    required this.diagnosis,
    required this.items,
    required this.advice,
    required this.followUpDate,
    required this.internalNote,
    required this.amendReason,
    required this.signedBy,
    required this.signedAt,
    required this.updatedAt,
    required this.claimCode,
  });

  final String id, appointmentId, advice, internalNote;
  final int version;
  final ResultVersionStatus status;
  final List<(String code, String name)> diagnosis;
  final List<PrescriptionItem> items;
  final String? followUpDate, amendReason, signedBy, claimCode;
  final DateTime? signedAt;
  final DateTime updatedAt;

  bool get isDraft => status == ResultVersionStatus.draft;

  factory ResultDraft.fromJson(Json j) => ResultDraft(
    id: j['id']! as String,
    appointmentId: j['appointmentId']! as String,
    version: j['version']! as int,
    status: ResultVersionStatus.values.byName(j['status']! as String),
    diagnosis: [
      for (final d in j['diagnosis'] as List<Object?>? ?? const [])
        if (d case [final String code, final String name]) (code, name),
    ],
    items: [
      for (final i in j['items'] as List<Object?>? ?? const [])
        PrescriptionItem.fromJson(i! as Json),
    ],
    advice: j['advice'] as String? ?? '',
    followUpDate: j['followUpDate'] as String?,
    internalNote: j['internalNote'] as String? ?? '',
    amendReason: j['amendReason'] as String?,
    signedBy: j['signedBy'] as String?,
    signedAt: switch (j['signedAt']) {
      final String s => clinicTime(s),
      _ => null,
    },
    updatedAt: clinicTime(j['updatedAt']! as String),
    claimCode: j['claimCode'] as String?,
  );
}

@immutable
class CatalogDrug {
  const CatalogDrug({
    required this.name,
    required this.strength,
    required this.form,
    required this.route,
  });
  final String name, strength, form, route;

  String get title => strength.isEmpty ? name : '$name $strength';

  factory CatalogDrug.fromJson(Json j) => CatalogDrug(
    name: j['name']! as String,
    strength: j['strength'] as String? ?? '',
    form: j['form'] as String? ?? 'viên',
    route: j['route'] as String? ?? 'Uống',
  );
}

@immutable
class Catalog {
  const Catalog(this.drugs, this.icd10);
  final List<CatalogDrug> drugs;
  final List<(String code, String name)> icd10;

  factory Catalog.fromJson(Json j) => Catalog(
    [
      for (final d in j['drugs'] as List<Object?>? ?? const [])
        CatalogDrug.fromJson(d! as Json),
    ],
    [
      for (final d in j['icd10'] as List<Object?>? ?? const [])
        if (d case [final String code, final String name]) (code, name),
    ],
  );
}

/// One medicine while the doctor edits it. Kept loose (nullable numbers,
/// manual quantity flag) and turned into a [PrescriptionItem] for saving.
class EditableItem {
  EditableItem({
    this.name = '',
    this.strength = '',
    this.form = 'viên',
    this.route = 'Uống',
    Map<DoseSlot, num>? amounts,
    this.meal = MealTiming.after,
    this.days,
    this.quantity,
    this.quantityManual = false,
    this.note = '',
  }) : amounts = amounts ?? {};

  String name, strength, form, route, note;
  final Map<DoseSlot, num> amounts;
  MealTiming meal;
  int? days, quantity;

  /// True once the doctor typed a quantity; then it no longer follows
  /// dose × days.
  bool quantityManual;

  factory EditableItem.from(PrescriptionItem item) => EditableItem(
    name: item.name,
    strength: item.strength,
    form: item.form,
    route: item.route,
    amounts: {for (final d in item.doses) d.slot: d.amount},
    meal: item.meal,
    days: item.days,
    quantity: item.quantity,
    quantityManual: true,
    note: item.note,
  );

  EditableItem copy() => EditableItem(
    name: name,
    strength: strength,
    form: form,
    route: route,
    amounts: Map.of(amounts),
    meal: meal,
    days: days,
    quantity: quantity,
    quantityManual: quantityManual,
    note: note,
  );

  String get title => strength.isEmpty ? name : '$name $strength';

  List<Dose> get doses => [
    for (final slot in DoseSlot.values)
      if ((amounts[slot] ?? 0) > 0) Dose(slot, amounts[slot]!),
  ];

  num get dailyAmount => doses.fold<num>(0, (s, d) => s + d.amount);

  /// Quantity follows dose × days until typed by hand.
  void recompute() {
    if (quantityManual) return;
    final d = days;
    quantity = d == null || d <= 0 || dailyAmount <= 0
        ? null
        : (dailyAmount * d).ceil();
  }

  /// What is still missing before this line can be sent.
  List<String> get problems => [
    if (name.trim().isEmpty) 'Chọn tên thuốc.',
    if (doses.isEmpty) 'Chọn liều ít nhất một buổi.',
    if (days == null || days! < 1 || days! > 365) 'Nhập số ngày từ 1 đến 365.',
    if (quantity == null || quantity! < 1) 'Nhập số lượng.',
  ];

  PrescriptionItem toItem() => PrescriptionItem(
    name: name.trim(),
    strength: strength.trim(),
    form: form,
    route: route,
    quantity: quantity ?? 0,
    doses: doses,
    meal: meal,
    days: days ?? 0,
    note: note.trim(),
  );

  /// The line as printed, or empty while no dose is chosen.
  String get usageLine => doses.isEmpty ? '' : toItem().usageLine;
}
