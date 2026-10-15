enum VisitType { insurance, service }

enum DoctorMode { any, named }

enum PayMethod { atHospital, wallet, card }

enum PaymentStatus { confirmed, failed, checking, paidUnconfirmed }

enum DemoOutcome { success, failure, unknown, paidUnconfirmed }

enum BookingStage {
  type,
  patient,
  facility,
  department,
  doctor,
  dateTime,
  review,
  payment,
  result,
}

extension VisitTypeLabel on VisitType {
  String get label =>
      this == VisitType.insurance ? 'Khám BHYT' : 'Khám dịch vụ';
}

extension PayMethodLabel on PayMethod {
  String get label => switch (this) {
    PayMethod.atHospital => 'Thanh toán tại viện',
    PayMethod.wallet => 'Ví điện tử',
    PayMethod.card => 'Thẻ ngân hàng',
  };
}

extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
    PaymentStatus.confirmed => 'Đặt lịch thành công',
    PaymentStatus.failed => 'Thanh toán chưa thành công',
    PaymentStatus.checking => 'Đang kiểm tra thanh toán',
    PaymentStatus.paidUnconfirmed =>
      'Đã nhận thanh toán, lịch chưa được xác nhận',
  };
}

extension BookingStageLabel on BookingStage {
  int get step => switch (this) {
    BookingStage.type => 1,
    BookingStage.patient => 2,
    BookingStage.facility ||
    BookingStage.department ||
    BookingStage.doctor => 3,
    BookingStage.dateTime => 4,
    BookingStage.review => 5,
    _ => 6,
  };
  String get label => switch (this) {
    BookingStage.type => 'Hình thức khám',
    BookingStage.patient => 'Người khám',
    BookingStage.facility => 'Nơi khám',
    BookingStage.department => 'Chuyên khoa',
    BookingStage.doctor => 'Bác sĩ',
    BookingStage.dateTime => 'Ngày và giờ khám',
    BookingStage.review => 'Kiểm tra thông tin',
    BookingStage.payment => 'Thanh toán',
    BookingStage.result => 'Kết quả',
  };
}

class Facility {
  const Facility(
    this.id,
    this.name,
    this.address,
    this.fee,
    this.acceptsInsurance,
    this.payAtHospital,
    this.departments,
  );
  final String id, name, address;
  final int fee;
  final bool acceptsInsurance, payAtHospital;
  final List<String> departments;
}

class Department {
  const Department(this.id, this.name, {this.maxAge});
  final String id, name;
  final int? maxAge;
}

class Doctor {
  const Doctor(this.id, this.name);
  final String id, name;
}

class BookingSlot {
  const BookingSlot(this.date, this.time, this.doctorId);
  final DateTime date;
  final String time;
  final String? doctorId;
  bool get available => doctorId != null;
  String get key => '$doctorId|${date.toIso8601String()}|$time';
}

const _unchanged = Object();

class BookingDraft {
  const BookingDraft({
    required this.id,
    this.type,
    this.patientId,
    this.facilityId,
    this.departmentId,
    this.doctorMode,
    this.doctorId,
    this.date,
    this.slot,
    this.method,
    this.note = '',
    this.contactName = 'Phạm Văn Hòa',
    this.contactPhone = '0900000123',
  });
  final String id, note, contactName, contactPhone;
  final VisitType? type;
  final String? patientId, facilityId, departmentId, doctorId;
  final DoctorMode? doctorMode;
  final DateTime? date;
  final BookingSlot? slot;
  final PayMethod? method;

  BookingStage? get firstMissing {
    if (type == null) return BookingStage.type;
    if (patientId == null) return BookingStage.patient;
    if (facilityId == null) return BookingStage.facility;
    if (departmentId == null) return BookingStage.department;
    if (doctorMode == null ||
        (doctorMode == DoctorMode.named && doctorId == null)) {
      return BookingStage.doctor;
    }
    if (date == null || slot == null) return BookingStage.dateTime;
    return null;
  }

  BookingDraft copyWith({
    Object? type = _unchanged,
    Object? patientId = _unchanged,
    Object? facilityId = _unchanged,
    Object? departmentId = _unchanged,
    Object? doctorMode = _unchanged,
    Object? doctorId = _unchanged,
    Object? date = _unchanged,
    Object? slot = _unchanged,
    Object? method = _unchanged,
    String? note,
    String? contactName,
    String? contactPhone,
  }) => BookingDraft(
    id: id,
    type: identical(type, _unchanged) ? this.type : type as VisitType?,
    patientId: identical(patientId, _unchanged)
        ? this.patientId
        : patientId as String?,
    facilityId: identical(facilityId, _unchanged)
        ? this.facilityId
        : facilityId as String?,
    departmentId: identical(departmentId, _unchanged)
        ? this.departmentId
        : departmentId as String?,
    doctorMode: identical(doctorMode, _unchanged)
        ? this.doctorMode
        : doctorMode as DoctorMode?,
    doctorId: identical(doctorId, _unchanged)
        ? this.doctorId
        : doctorId as String?,
    date: identical(date, _unchanged) ? this.date : date as DateTime?,
    slot: identical(slot, _unchanged) ? this.slot : slot as BookingSlot?,
    method: identical(method, _unchanged) ? this.method : method as PayMethod?,
    note: note ?? this.note,
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
  );
}

class VisitSummary {
  const VisitSummary({
    required this.id,
    required this.patientName,
    required this.type,
    required this.facilityName,
    required this.address,
    required this.departmentName,
    required this.doctorName,
    required this.date,
    required this.time,
    required this.fee,
    required this.method,
    required this.contactName,
    required this.contactPhone,
    required this.note,
  });
  final String id,
      patientName,
      facilityName,
      address,
      departmentName,
      doctorName,
      time,
      contactName,
      contactPhone,
      note;
  final VisitType type;
  final DateTime date;
  final int fee;
  final PayMethod method;
}

class PaymentReceipt {
  const PaymentReceipt({
    required this.status,
    required this.method,
    this.appointmentCode,
    this.transactionCode,
  });
  final PaymentStatus status;
  final PayMethod method;
  final String? appointmentCode, transactionCode;
  bool get unresolved =>
      status == PaymentStatus.checking ||
      status == PaymentStatus.paidUnconfirmed;
}

class AppointmentRecord {
  const AppointmentRecord(this.visit, this.receipt);
  final VisitSummary visit;
  final PaymentReceipt receipt;
}

class DemoOptions {
  const DemoOptions({
    this.outcome = DemoOutcome.success,
    this.networkError = false,
    this.slotTaken = false,
    this.facilityConfirmed = false,
  });
  final DemoOutcome outcome;
  final bool networkError, slotTaken, facilityConfirmed;
}

class BookingException implements Exception {
  const BookingException(this.message);
  final String message;
}

class SlotUnavailable extends BookingException {
  const SlotUnavailable()
    : super('Giờ này vừa hết chỗ. Vui lòng chọn giờ khác.');
}
