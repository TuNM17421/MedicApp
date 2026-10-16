import 'package:flutter/foundation.dart';

/// Times of day a dose can be taken, in the order a prescription lists them.
enum DoseSlot {
  morning('Sáng', 7, 0),
  noon('Trưa', 11, 30),
  afternoon('Chiều', 16, 0),
  evening('Tối', 19, 0);

  const DoseSlot(this.label, this.hour, this.minute);
  final String label;

  /// Default reminder time; the user can change it later.
  final int hour, minute;
}

enum MealTiming {
  before('trước ăn'),
  after('sau ăn'),
  any('');

  const MealTiming(this.label);
  final String label;
}

@immutable
class Dose {
  const Dose(this.slot, this.amount);
  final DoseSlot slot;

  /// Units per dose, such as 1 or 0.5 (half a tablet).
  final num amount;

  Map<String, Object?> toJson() => {'slot': slot.name, 'amount': amount};
  factory Dose.fromJson(Map<String, Object?> json) => Dose(
    DoseSlot.values.byName(json['slot']! as String),
    json['amount']! as num,
  );
}

String formatAmount(num value) {
  if (value == 0.5) return '1/2';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString().replaceAll('.', ',');
}

/// One line under "Thuốc điều trị" on the Bộ Y tế prescription form
/// (Thông tư 18/2018/TT-BYT), with the parts a reminder needs kept apart
/// instead of as free text.
@immutable
class PrescriptionItem {
  const PrescriptionItem({
    required this.name,
    required this.strength,
    required this.form,
    required this.quantity,
    required this.doses,
    required this.days,
    this.route = 'Uống',
    this.meal = MealTiming.any,
    this.note = '',
  });
  final String name, strength, form, route, note;

  /// Total units dispensed, such as 30 (viên).
  final int quantity;
  final List<Dose> doses;
  final MealTiming meal;
  final int days;

  num get dailyAmount => doses.fold<num>(0, (sum, dose) => sum + dose.amount);

  /// "Amlodipin 5mg"
  String get title => '$name $strength';

  /// "Sáng 1 viên, tối 1 viên, sau ăn"
  String get schedule {
    final parts = [
      for (final (index, dose) in doses.indexed)
        '${index == 0 ? dose.slot.label : dose.slot.label.toLowerCase()} '
            '${formatAmount(dose.amount)} $form',
    ];
    return [...parts, if (meal != MealTiming.any) meal.label].join(', ');
  }

  /// Usage line as a doctor writes it on the paper form:
  /// "Ngày uống 2 lần, mỗi lần 1 viên, sáng - tối, sau ăn".
  String get usageLine {
    final amounts = doses.map((dose) => dose.amount).toSet();
    final perDose = amounts.length == 1
        ? 'mỗi lần ${formatAmount(amounts.single)} $form'
        : doses
              .map(
                (d) =>
                    '${d.slot.label.toLowerCase()} ${formatAmount(d.amount)} $form',
              )
              .join(', ');
    final slots = doses.map((d) => d.slot.label.toLowerCase()).join(' - ');
    return [
      'Ngày ${route.toLowerCase()} ${doses.length} lần',
      perDose,
      if (amounts.length == 1) slots,
      if (meal != MealTiming.any) meal.label,
    ].join(', ');
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'strength': strength,
    'form': form,
    'quantity': quantity,
    'route': route,
    'doses': [for (final dose in doses) dose.toJson()],
    'meal': meal.name,
    'days': days,
    'note': note,
  };

  factory PrescriptionItem.fromJson(Map<String, Object?> json) =>
      PrescriptionItem(
        name: json['name']! as String,
        strength: json['strength']! as String,
        form: json['form']! as String,
        quantity: json['quantity']! as int,
        route: json['route'] as String? ?? 'Uống',
        doses: List.unmodifiable([
          for (final dose in json['doses']! as List<Object?>)
            Dose.fromJson(dose! as Map<String, Object?>),
        ]),
        meal: MealTiming.values.byName(json['meal'] as String? ?? 'any'),
        days: json['days']! as int,
        note: json['note'] as String? ?? '',
      );
}

/// What the doctor's system returns after a visit: the fields of the Bộ Y tế
/// prescription form plus the visit it belongs to. Matching by visit id
/// (not by name and age, which the form has) means the result always lands
/// on the right profile.
@immutable
class VisitResult {
  const VisitResult({
    required this.visitId,
    required this.profileId,
    required this.issuedAt,
    required this.facilityName,
    required this.facilityPhone,
    required this.doctorName,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.diagnosis,
    required this.items,
    required this.advice,
    this.address = '',
    this.insuranceCode = '',
    this.weightKg,
    this.followUpDate,
  });

  final String visitId, profileId;
  final DateTime issuedAt;
  final String facilityName, facilityPhone, doctorName;
  final String patientName, patientGender, address, insuranceCode;
  final int patientAge;

  /// Required on the form only for children under 72 months.
  final num? weightKg;
  final String diagnosis;
  final List<PrescriptionItem> items;

  /// "Lời dặn": diet, daily routine and the follow-up appointment.
  final List<String> advice;
  final DateTime? followUpDate;

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'profileId': profileId,
    'issuedAt': issuedAt.toIso8601String(),
    'facilityName': facilityName,
    'facilityPhone': facilityPhone,
    'doctorName': doctorName,
    'patientName': patientName,
    'patientAge': patientAge,
    'patientGender': patientGender,
    'address': address,
    'insuranceCode': insuranceCode,
    'weightKg': weightKg,
    'diagnosis': diagnosis,
    'items': [for (final item in items) item.toJson()],
    'advice': advice,
    'followUpDate': followUpDate?.toIso8601String(),
  };

  factory VisitResult.fromJson(Map<String, Object?> json) => VisitResult(
    visitId: json['visitId']! as String,
    profileId: json['profileId']! as String,
    issuedAt: DateTime.parse(json['issuedAt']! as String),
    facilityName: json['facilityName']! as String,
    facilityPhone: json['facilityPhone']! as String,
    doctorName: json['doctorName']! as String,
    patientName: json['patientName']! as String,
    patientAge: json['patientAge']! as int,
    patientGender: json['patientGender']! as String,
    address: json['address'] as String? ?? '',
    insuranceCode: json['insuranceCode'] as String? ?? '',
    weightKg: json['weightKg'] as num?,
    diagnosis: json['diagnosis']! as String,
    items: List.unmodifiable([
      for (final item in json['items']! as List<Object?>)
        PrescriptionItem.fromJson(item! as Map<String, Object?>),
    ]),
    advice: List.unmodifiable(
      (json['advice']! as List<Object?>).cast<String>(),
    ),
    followUpDate: switch (json['followUpDate']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
  );
}
