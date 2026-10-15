import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_state.dart';
import '../data/booking_catalog.dart';
import '../data/booking_repository.dart';
import '../domain/booking_models.dart';

final bookingTodayProvider = Provider<DateTime>((ref) {
  final vietnam = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(vietnam.year, vietnam.month, vietnam.day);
});
final demoOptionsProvider =
    NotifierProvider<DemoOptionsController, DemoOptions>(
      DemoOptionsController.new,
    );

class DemoOptionsController extends Notifier<DemoOptions> {
  @override
  DemoOptions build() => const DemoOptions();
  void set(DemoOptions value) => state = value;
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => MockBookingRepository(
    today: ref.read(bookingTodayProvider),
    options: () => ref.read(demoOptionsProvider),
  ),
);

class AppointmentLedger {
  const AppointmentLedger({
    this.records = const [],
    this.checking = const {},
    this.errors = const {},
  });
  final List<AppointmentRecord> records;
  final Set<String> checking;
  final Map<String, String> errors;
}

final appointmentsProvider =
    NotifierProvider<AppointmentsController, AppointmentLedger>(
      AppointmentsController.new,
    );

class AppointmentsController extends Notifier<AppointmentLedger> {
  @override
  AppointmentLedger build() => const AppointmentLedger();

  void upsert(AppointmentRecord record) => state = AppointmentLedger(
    records: List.unmodifiable([
      record,
      ...state.records.where((item) => item.visit.id != record.visit.id),
    ]),
    checking: state.checking,
    errors: Map.unmodifiable({...state.errors}..remove(record.visit.id)),
  );

  Future<void> check(String id) async {
    final record = state.records
        .where((record) => record.visit.id == id)
        .firstOrNull;
    if (record == null ||
        !record.receipt.unresolved ||
        state.checking.contains(id)) {
      return;
    }
    state = AppointmentLedger(
      records: state.records,
      checking: Set.unmodifiable({...state.checking, id}),
      errors: Map.unmodifiable({...state.errors}..remove(id)),
    );
    try {
      final receipt = await ref.read(bookingRepositoryProvider).check(id);
      if (ref.mounted) upsert(AppointmentRecord(record.visit, receipt));
    } on BookingException catch (error) {
      if (ref.mounted) {
        state = AppointmentLedger(
          records: state.records,
          checking: state.checking,
          errors: Map.unmodifiable({...state.errors, id: error.message}),
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = AppointmentLedger(
          records: state.records,
          checking: state.checking,
          errors: Map.unmodifiable({
            ...state.errors,
            id: 'Chưa kiểm tra được trạng thái. Vui lòng thử lại.',
          }),
        );
      }
    } finally {
      if (ref.mounted) {
        state = AppointmentLedger(
          records: state.records,
          checking: Set.unmodifiable({...state.checking}..remove(id)),
          errors: state.errors,
        );
      }
    }
  }
}

class BookingSession {
  const BookingSession({
    required this.draft,
    this.stage = BookingStage.type,
    this.editing = false,
    this.busy = false,
    this.loadingSlots = false,
    this.slots = const [],
    this.error = '',
    this.notice = '',
    this.receipt,
  });
  final BookingDraft draft;
  final BookingStage stage;
  final bool editing, busy, loadingSlots;
  final List<BookingSlot> slots;
  final String error, notice;
  final PaymentReceipt? receipt;
  BookingSession copyWith({
    BookingDraft? draft,
    BookingStage? stage,
    bool? editing,
    bool? busy,
    bool? loadingSlots,
    List<BookingSlot>? slots,
    String? error,
    String? notice,
    PaymentReceipt? receipt,
  }) => BookingSession(
    draft: draft ?? this.draft,
    stage: stage ?? this.stage,
    editing: editing ?? this.editing,
    busy: busy ?? this.busy,
    loadingSlots: loadingSlots ?? this.loadingSlots,
    slots: slots ?? this.slots,
    error: error ?? this.error,
    notice: notice ?? this.notice,
    receipt: receipt ?? this.receipt,
  );
}

final bookingSessionProvider =
    NotifierProvider.autoDispose<BookingController, BookingSession>(
      BookingController.new,
    );

class BookingController extends Notifier<BookingSession> {
  int _loadVersion = 0;
  static int _sequence = 0;
  @override
  BookingSession build() => BookingSession(
    draft: BookingDraft(
      id: 'D${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
    ),
  );
  bool get _locked =>
      state.busy ||
      (state.receipt != null && state.receipt!.status != PaymentStatus.failed);

  void _update(
    BookingDraft draft, {
    String notice = '',
    bool clearSlots = false,
  }) {
    if (_locked) return;
    _loadVersion++;
    state = state.copyWith(
      draft: draft,
      error: '',
      notice: notice,
      loadingSlots: false,
      slots: clearSlots ? const [] : null,
    );
  }

  void chooseType(VisitType type) {
    var draft = state.draft;
    if (draft.type == type) return;
    draft = draft.copyWith(type: type, method: null);
    if (draft.facilityId != null &&
        type == VisitType.insurance &&
        !BookingCatalog.facility(draft.facilityId!).acceptsInsurance) {
      _update(
        draft.copyWith(
          facilityId: null,
          departmentId: null,
          doctorMode: null,
          doctorId: null,
          slot: null,
        ),
        notice:
            'Nơi khám cũ không nhận BHYT. Chọn lại nơi, chuyên khoa và giờ.',
        clearSlots: true,
      );
    } else {
      _update(draft);
    }
  }

  void choosePatient(String id) {
    final profile = ref
        .read(profileCatalogProvider)
        .where((profile) => profile.id == id)
        .firstOrNull;
    if (profile == null || state.draft.patientId == id) return;
    var draft = state.draft.copyWith(patientId: id, note: '');
    final maxAge = draft.departmentId == null
        ? null
        : BookingCatalog.department(draft.departmentId!).maxAge;
    if (maxAge != null && age(profile) > maxAge) {
      draft = draft.copyWith(
        departmentId: null,
        doctorMode: null,
        doctorId: null,
        slot: null,
      );
      _update(
        draft,
        notice: 'Chuyên khoa cũ không phù hợp độ tuổi. Chọn lại chuyên khoa và giờ.',
        clearSlots: true,
      );
    } else {
      _update(
        draft,
        notice: state.draft.patientId == null
            ? ''
            : 'Đã đổi người khám và xóa ghi chú của người trước.',
      );
    }
  }

  int age(PreviewProfile profile) {
    final today = ref.read(bookingTodayProvider);
    var age = today.year - profile.birthYear;
    final dob = profile.birthDate;
    if (dob != null &&
        (today.month < dob.month ||
            (today.month == dob.month && today.day < dob.day))) {
      age--;
    }
    return age;
  }

  void chooseFacility(String id) {
    final facility = BookingCatalog.facility(id);
    if (state.draft.type == VisitType.insurance && !facility.acceptsInsurance) {
      return;
    }
    if (state.draft.facilityId == id) return;
    final keepDepartment = facility.departments.contains(
      state.draft.departmentId,
    );
    _update(
      state.draft.copyWith(
        facilityId: id,
        departmentId: keepDepartment ? state.draft.departmentId : null,
        doctorMode: null,
        doctorId: null,
        slot: null,
        method: null,
      ),
      notice: state.draft.facilityId == null
          ? ''
          : keepDepartment
          ? 'Đã đổi nơi khám. Chọn lại bác sĩ và giờ.'
          : 'Đã đổi nơi khám. Chọn lại chuyên khoa, bác sĩ và giờ.',
      clearSlots: true,
    );
  }

  void chooseDepartment(String id) {
    final draft = state.draft;
    if (draft.facilityId == null ||
        !BookingCatalog.facility(draft.facilityId!).departments.contains(id)) {
      return;
    }
    final patient = ref
        .read(profileCatalogProvider)
        .where((item) => item.id == draft.patientId)
        .firstOrNull;
    final maxAge = BookingCatalog.department(id).maxAge;
    if (patient == null || (maxAge != null && age(patient) > maxAge)) return;
    if (draft.departmentId == id) return;
    _update(
      draft.copyWith(
        departmentId: id,
        doctorMode: null,
        doctorId: null,
        slot: null,
        method: null,
      ),
      notice: draft.departmentId == null
          ? ''
          : 'Đã đổi chuyên khoa. Chọn lại bác sĩ và giờ.',
      clearSlots: true,
    );
  }

  void chooseDoctor(DoctorMode mode, [String? id]) {
    final draft = state.draft;
    if (draft.facilityId == null || draft.departmentId == null) return;
    if (mode == DoctorMode.named &&
        !BookingCatalog.doctors(
          draft.facilityId!,
          draft.departmentId!,
        ).any((doc) => doc.id == id)) {
      return;
    }
    if (draft.doctorMode == mode && draft.doctorId == id) return;
    final keepSlot = mode == DoctorMode.any || draft.slot?.doctorId == id;
    _update(
      draft.copyWith(
        doctorMode: mode,
        doctorId: mode == DoctorMode.any ? null : id,
        slot: keepSlot ? draft.slot : null,
      ),
      notice: !keepSlot && draft.slot != null
          ? 'Đã đổi bác sĩ. Chọn lại giờ khám.'
          : '',
      clearSlots: true,
    );
  }

  Future<void> chooseDate(DateTime date) async {
    if (_locked ||
        !BookingCatalog.dates(ref.read(bookingTodayProvider)).contains(date)) {
      return;
    }
    _update(state.draft.copyWith(date: date, slot: null), clearSlots: true);
    await loadSlots();
  }

  Future<void> loadSlots() async {
    if (_locked || state.draft.date == null) return;
    final version = ++_loadVersion;
    state = state.copyWith(loadingSlots: true, error: '');
    try {
      final slots = await ref
          .read(bookingRepositoryProvider)
          .loadSlots(state.draft);
      if (!ref.mounted || version != _loadVersion) return;
      state = state.copyWith(slots: slots, loadingSlots: false);
    } on BookingException catch (error) {
      if (ref.mounted && version == _loadVersion) {
        state = state.copyWith(
          loadingSlots: false,
          slots: const [],
          error: error.message,
        );
      }
    } catch (_) {
      if (ref.mounted && version == _loadVersion) {
        state = state.copyWith(
          loadingSlots: false,
          slots: const [],
          error: 'Chưa tải được giờ khám. Vui lòng thử lại.',
        );
      }
    }
  }

  void chooseSlot(BookingSlot slot) {
    if (!state.loadingSlots &&
        state.slots.any((item) => item.key == slot.key && item.available)) {
      _update(state.draft.copyWith(slot: slot));
    }
  }

  void chooseMethod(PayMethod method) {
    if (state.draft.firstMissing == null &&
        BookingCatalog.methods(state.draft).contains(method)) {
      _update(state.draft.copyWith(method: method));
    }
  }

  void setNote(String value) => _update(state.draft.copyWith(note: value));
  void setContact({String? name, String? phone}) =>
      _update(state.draft.copyWith(contactName: name, contactPhone: phone));

  void edit(BookingStage stage) {
    if (_locked || stage.index > BookingStage.dateTime.index) return;
    _loadVersion++;
    state = state.copyWith(
      stage: stage,
      editing: true,
      error: '',
      loadingSlots: false,
    );
    if (stage == BookingStage.dateTime) loadSlots();
  }

  void back() {
    if (_locked ||
        state.stage == BookingStage.type ||
        state.stage == BookingStage.result) {
      return;
    }
    _loadVersion++;
    final stage = state.editing && state.draft.firstMissing == null
        ? BookingStage.review
        : BookingStage.values[state.stage.index - 1];
    state = state.copyWith(
      stage: stage,
      editing: stage == BookingStage.review ? false : state.editing,
      error: '',
      loadingSlots: false,
    );
    if (stage == BookingStage.dateTime) loadSlots();
  }

  Future<void> next() async {
    if (_locked) return;
    final draft = state.draft;
    final missingHere = switch (state.stage) {
      BookingStage.type => draft.type == null,
      BookingStage.patient => draft.patientId == null,
      BookingStage.facility => draft.facilityId == null,
      BookingStage.department => draft.departmentId == null,
      BookingStage.doctor => draft.doctorMode == null,
      BookingStage.dateTime => draft.slot == null,
      _ => false,
    };
    if (missingHere) {
      state = state.copyWith(
        error: 'Vui lòng chọn ${state.stage.label.toLowerCase()} để tiếp tục.',
      );
      return;
    }
    if (state.stage == BookingStage.review) {
      await checkout();
      return;
    }
    final stage = state.editing
        ? draft.firstMissing ?? BookingStage.review
        : BookingStage.values[state.stage.index + 1];
    state = state.copyWith(
      stage: stage,
      editing: stage == BookingStage.review ? false : state.editing,
      error: '',
    );
    if (stage == BookingStage.dateTime) {
      if (state.draft.date == null) {
        await chooseDate(
          BookingCatalog.dates(ref.read(bookingTodayProvider)).first,
        );
      } else {
        await loadSlots();
      }
    }
  }

  Future<void> _slotLost() async {
    state = state.copyWith(
      draft: state.draft.copyWith(slot: null, method: null),
      stage: BookingStage.dateTime,
      busy: false,
      notice: 'Giờ này vừa hết chỗ. Vui lòng chọn giờ khác.',
      error: '',
    );
    await loadSlots();
  }

  Future<void> checkout() async {
    if (_locked) return;
    if (state.draft.firstMissing != null) {
      state = state.copyWith(
        stage: state.draft.firstMissing,
        error: 'Vui lòng hoàn tất các lựa chọn còn thiếu.',
      );
      return;
    }
    if (state.draft.contactName.trim().isEmpty ||
        !RegExp(r'^0\d{9}$').hasMatch(state.draft.contactPhone.trim())) {
      state = state.copyWith(
        error: 'Kiểm tra tên người nhận thông báo và số điện thoại 10 chữ số, bắt đầu bằng 0.',
      );
      return;
    }
    state = state.copyWith(busy: true, error: '');
    try {
      final valid = await ref
          .read(bookingRepositoryProvider)
          .validateSlot(state.draft);
      if (!ref.mounted) return;
      if (!valid) {
        await _slotLost();
      } else {
        state = state.copyWith(stage: BookingStage.payment, busy: false);
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          busy: false,
          error: 'Chưa kiểm tra được giờ khám. Vui lòng thử lại.',
        );
      }
    }
  }

  VisitSummary _summary(BookingDraft draft) {
    final facility = BookingCatalog.facility(draft.facilityId!);
    final patient = ref
        .read(profileCatalogProvider)
        .firstWhere((profile) => profile.id == draft.patientId);
    return VisitSummary(
      id: draft.id,
      patientName: patient.name,
      type: draft.type!,
      facilityName: facility.name,
      address: facility.address,
      departmentName: BookingCatalog.department(draft.departmentId!).name,
      doctorName: BookingCatalog.doctors(
        draft.facilityId!,
        draft.departmentId!,
      ).firstWhere((doc) => doc.id == draft.slot!.doctorId).name,
      date: draft.date!,
      time: draft.slot!.time,
      fee: BookingCatalog.fee(draft),
      method: draft.method!,
      contactName: draft.contactName,
      contactPhone: draft.contactPhone,
      note: draft.note,
    );
  }

  Future<void> submit() async {
    if (_locked || state.draft.firstMissing != null) return;
    if (state.draft.method == null) {
      state = state.copyWith(error: 'Vui lòng chọn cách thanh toán.');
      return;
    }
    final draft = state.draft;
    state = state.copyWith(busy: true, error: '');
    try {
      final receipt = await ref.read(bookingRepositoryProvider).submit(draft);
      if (!ref.mounted) return;
      ref
          .read(appointmentsProvider.notifier)
          .upsert(AppointmentRecord(_summary(draft), receipt));
      state = state.copyWith(
        stage: BookingStage.result,
        busy: false,
        receipt: receipt,
      );
    } on SlotUnavailable {
      if (ref.mounted) await _slotLost();
    } catch (_) {
      // An unexpected submission error is ambiguous: never invite a second charge.
      if (!ref.mounted) return;
      final receipt = PaymentReceipt(
        status: PaymentStatus.checking,
        method: draft.method!,
      );
      ref
          .read(appointmentsProvider.notifier)
          .upsert(AppointmentRecord(_summary(draft), receipt));
      state = state.copyWith(
        stage: BookingStage.result,
        busy: false,
        receipt: receipt,
      );
    }
  }

  void retryFailed() {
    if (state.busy || state.receipt?.status != PaymentStatus.failed) return;
    state = BookingSession(draft: state.draft, stage: BookingStage.payment);
  }
}
