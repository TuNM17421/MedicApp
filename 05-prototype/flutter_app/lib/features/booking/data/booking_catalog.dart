import '../domain/booking_models.dart';

abstract final class BookingCatalog {
  static const facilities = [
    Facility(
      'anbinh',
      'Phòng khám Đa khoa An Bình',
      '12 đường Hoa Sữa, phường An Phú',
      250000,
      true,
      true,
      ['general', 'heart', 'bones', 'ent', 'eyes', 'children'],
    ),
    Facility(
      'songxanh',
      'Bệnh viện Sông Xanh',
      '88 đại lộ Sông Xanh, phường Tân Mỹ',
      500000,
      false,
      false,
      ['general', 'heart', 'bones', 'eyes', 'endocrine'],
    ),
    Facility(
      'hoalac',
      'Trung tâm Y tế Hòa Lạc',
      '5 ngõ Cây Gạo, xã Hòa Lạc',
      180000,
      true,
      true,
      ['general', 'bones', 'ent', 'children', 'endocrine'],
    ),
  ];
  static const departments = [
    Department('general', 'Nội tổng quát'),
    Department('heart', 'Tim mạch'),
    Department('bones', 'Cơ Xương Khớp'),
    Department('ent', 'Tai Mũi Họng'),
    Department('eyes', 'Mắt'),
    Department('endocrine', 'Nội tiết'),
    Department('children', 'Nhi khoa', maxAge: 15),
  ];
  static Facility facility(String id) =>
      facilities.firstWhere((value) => value.id == id);
  static Department department(String id) =>
      departments.firstWhere((value) => value.id == id);
  static List<Doctor> doctors(String facilityId, String departmentId) {
    const names = [
      'Nguyễn Thu Hà',
      'Trần Quốc Bảo',
      'Lê Minh Châu',
      'Phạm Đức Long',
      'Võ Thanh Tâm',
      'Đỗ Ngọc Anh',
      'Hoàng Văn Sơn',
      'Bùi Thị Hạnh',
    ];
    final offset =
        facilities.indexOf(facility(facilityId)) * 3 +
        departments.indexOf(department(departmentId)) * 2;
    return [
      for (var i = 0; i < 2; i++)
        Doctor(
          '$facilityId-$departmentId-$i',
          'BS. ${names[(offset + i) % names.length]}',
        ),
    ];
  }

  static List<DateTime> dates(DateTime today) {
    final result = <DateTime>[];
    var date = today;
    while (result.length < 6) {
      date = DateTime(date.year, date.month, date.day + 1);
      if (date.weekday != DateTime.sunday) result.add(date);
    }
    return List.unmodifiable(result);
  }

  static int fee(BookingDraft draft) =>
      draft.type == VisitType.insurance ? 0 : facility(draft.facilityId!).fee;
  static List<PayMethod> methods(BookingDraft draft) {
    if (draft.type == VisitType.insurance) return const [PayMethod.atHospital];
    return [
      if (facility(draft.facilityId!).payAtHospital) PayMethod.atHospital,
      PayMethod.wallet,
      PayMethod.card,
    ];
  }
}
