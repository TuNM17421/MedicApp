import '../domain/booking_models.dart';
import 'booking_catalog.dart';

abstract interface class BookingRepository {
  Future<List<BookingSlot>> loadSlots(BookingDraft draft);
  Future<bool> validateSlot(BookingDraft draft);
  Future<PaymentReceipt> submit(BookingDraft draft);
  Future<PaymentReceipt> check(String draftId);
}

/// Deterministic, in-memory simulator. No payment gateway or network requests.
class MockBookingRepository implements BookingRepository {
  MockBookingRepository({
    required this.today,
    required this.options,
    this.delay = const Duration(milliseconds: 300),
  });
  final DateTime today;
  final DemoOptions Function() options;
  final Duration delay;
  final _taken = <String>{};
  final _receipts = <String, PaymentReceipt>{};
  final _checks = <String, int>{};
  final _failedOnce = <String>{};
  final _networkFailed = <String>{}, _slotTaken = <String>{};
  int _sequence = 4821;

  int _hash(String value) =>
      value.codeUnits.fold(7, (hash, char) => (hash * 31 + char) & 0x7fffffff);
  bool _free(String doctorId, DateTime date, String time) =>
      date != BookingCatalog.dates(today)[2] &&
      !_taken.contains('$doctorId|${date.toIso8601String()}|$time') &&
      _hash('$doctorId|${date.toIso8601String()}|$time') % 100 >= 38;

  List<BookingSlot> _slots(BookingDraft draft) {
    if (draft.facilityId == null ||
        draft.departmentId == null ||
        draft.date == null ||
        draft.doctorMode == null) {
      return const [];
    }
    final doctors =
        BookingCatalog.doctors(draft.facilityId!, draft.departmentId!).where(
          (doc) =>
              draft.doctorMode == DoctorMode.any || doc.id == draft.doctorId,
        );
    return [
      for (final time in [
        '07:30',
        '08:00',
        '08:30',
        '09:00',
        '09:30',
        '10:00',
        '10:30',
        '13:30',
        '14:00',
        '14:30',
        '15:00',
        '15:30',
        '16:00',
      ])
        BookingSlot(
          draft.date!,
          time,
          doctors
              .where((doc) => _free(doc.id, draft.date!, time))
              .firstOrNull
              ?.id,
        ),
    ];
  }

  @override
  Future<List<BookingSlot>> loadSlots(BookingDraft draft) async {
    await Future<void>.delayed(delay);
    if (options().networkError && _networkFailed.add(draft.id)) {
      throw const BookingException(
        'Không tải được giờ khám. Vui lòng thử lại.',
      );
    }
    return List.unmodifiable(_slots(draft));
  }

  bool _valid(BookingDraft draft) {
    if (draft.firstMissing != null ||
        !BookingCatalog.dates(today).contains(draft.date)) {
      return false;
    }
    final facility = BookingCatalog.facility(draft.facilityId!);
    if (draft.type == VisitType.insurance && !facility.acceptsInsurance) {
      return false;
    }
    if (!facility.departments.contains(draft.departmentId)) return false;
    return _slots(draft).any(
      (slot) =>
          slot.time == draft.slot!.time &&
          slot.doctorId == draft.slot!.doctorId,
    );
  }

  @override
  Future<bool> validateSlot(BookingDraft draft) async {
    await Future<void>.delayed(delay);
    if (options().slotTaken && draft.slot != null && _slotTaken.add(draft.id)) {
      _taken.add(draft.slot!.key);
    }
    return _valid(draft);
  }

  PaymentReceipt _confirmed(PayMethod method, {String? transactionCode}) =>
      PaymentReceipt(
        status: PaymentStatus.confirmed,
        method: method,
        appointmentCode: 'LK-${++_sequence}',
        transactionCode: transactionCode,
      );

  @override
  Future<PaymentReceipt> submit(BookingDraft draft) async {
    // Store the receipt before any caller can submit this draft again.
    // Callers also serialize submissions; unresolved receipts are never retried.
    await Future<void>.delayed(delay);
    final existing = _receipts[draft.id];
    if (existing != null && existing.status != PaymentStatus.failed) {
      return existing;
    }
    if (!_valid(draft)) throw const SlotUnavailable();
    if (!BookingCatalog.methods(draft).contains(draft.method)) {
      throw const BookingException('Phương thức thanh toán không phù hợp.');
    }
    final method = draft.method!;
    final outcome = options().outcome;
    final transaction = 'GD-${++_sequence}';
    final PaymentReceipt receipt;
    if (method == PayMethod.atHospital) {
      receipt = _confirmed(method);
    } else if (outcome == DemoOutcome.failure && _failedOnce.add(draft.id)) {
      receipt = PaymentReceipt(status: PaymentStatus.failed, method: method);
    } else if (outcome == DemoOutcome.unknown) {
      receipt = PaymentReceipt(
        status: PaymentStatus.checking,
        method: method,
        transactionCode: transaction,
      );
    } else if (outcome == DemoOutcome.paidUnconfirmed) {
      receipt = PaymentReceipt(
        status: PaymentStatus.paidUnconfirmed,
        method: method,
        transactionCode: transaction,
      );
    } else {
      receipt = _confirmed(method, transactionCode: transaction);
    }
    _receipts[draft.id] = receipt;
    if (receipt.status != PaymentStatus.failed) _taken.add(draft.slot!.key);
    return receipt;
  }

  @override
  Future<PaymentReceipt> check(String draftId) async {
    await Future<void>.delayed(delay);
    final receipt = _receipts[draftId];
    if (receipt == null) {
      throw const BookingException(
        'Không tìm thấy giao dịch. Vui lòng liên hệ hỗ trợ.',
      );
    }
    _checks[draftId] = (_checks[draftId] ?? 0) + 1;
    if ((receipt.status == PaymentStatus.checking && _checks[draftId]! >= 2) ||
        (receipt.status == PaymentStatus.paidUnconfirmed &&
            options().facilityConfirmed)) {
      return _receipts[draftId] = _confirmed(
        receipt.method,
        transactionCode: receipt.transactionCode,
      );
    }
    return receipt;
  }
}
