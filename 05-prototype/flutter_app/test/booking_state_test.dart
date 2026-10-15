import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';
import 'package:medic_app/features/booking/application/booking_providers.dart';
import 'package:medic_app/features/booking/data/booking_catalog.dart';
import 'package:medic_app/features/booking/data/booking_repository.dart';
import 'package:medic_app/features/booking/domain/booking_models.dart';

final today = DateTime(2026, 10, 14);

ProviderContainer bookingContainer({
  DemoOptions options = const DemoOptions(),
  BookingRepository? repository,
}) {
  final container = ProviderContainer(
    overrides: [
      bookingTodayProvider.overrideWithValue(today),
      bookingRepositoryProvider.overrideWith(
        (ref) =>
            repository ??
            MockBookingRepository(
              today: today,
              options: () => ref.read(demoOptionsProvider),
              delay: Duration.zero,
            ),
      ),
    ],
  );
  container.read(demoOptionsProvider.notifier).set(options);
  container.listen(bookingSessionProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

Future<void> selectVisit(
  ProviderContainer container, {
  VisitType type = VisitType.service,
  String patient = 'self',
  String facility = 'anbinh',
  String department = 'general',
}) async {
  final actions = container.read(bookingSessionProvider.notifier);
  actions.chooseType(type);
  await actions.next();
  actions.choosePatient(patient);
  await actions.next();
  actions.chooseFacility(facility);
  await actions.next();
  actions.chooseDepartment(department);
  await actions.next();
  actions.chooseDoctor(DoctorMode.any);
  await actions.next();
  actions.chooseSlot(
    container
        .read(bookingSessionProvider)
        .slots
        .firstWhere((slot) => slot.available),
  );
  await actions.next();
}

void main() {
  test(
    'service booking produces one receipt even with repeated submit',
    () async {
      final c = bookingContainer();
      await selectVisit(c);
      final a = c.read(bookingSessionProvider.notifier);
      expect(c.read(bookingSessionProvider).stage, BookingStage.review);
      await a.checkout();
      a.chooseMethod(PayMethod.wallet);
      await Future.wait([a.submit(), a.submit()]);
      final record = c.read(appointmentsProvider).records.single;
      expect(record.receipt.status, PaymentStatus.confirmed);
      expect(record.receipt.transactionCode, isNotNull);
      expect(record.receipt.appointmentCode, isNotNull);
      final original = await c
          .read(bookingRepositoryProvider)
          .submit(c.read(bookingSessionProvider).draft);
      expect(original.appointmentCode, record.receipt.appointmentCode);
      await a.submit();
      expect(c.read(appointmentsProvider).records, hasLength(1));
    },
  );

  test('BHYT family booking limits facility and payment without claiming free care', () async {
    final c = bookingContainer();
    await selectVisit(c, type: VisitType.insurance, patient: 'mother');
    final a = c.read(bookingSessionProvider.notifier);
    a.chooseFacility('songxanh');
    expect(c.read(bookingSessionProvider).draft.facilityId, 'anbinh');
    await a.checkout();
    a.chooseMethod(PayMethod.card);
    expect(c.read(bookingSessionProvider).draft.method, isNull);
    a.chooseMethod(PayMethod.atHospital);
    await a.submit();
    final record = c.read(appointmentsProvider).records.single;
    expect(record.visit.patientName, 'Phạm Thị Lan');
    expect(record.visit.fee, 0);
    expect(record.receipt.transactionCode, isNull);
    expect(c.read(activeProfileProvider).id, 'self');
  });

  test(
    'editing type clears incompatible facility and dependent selections',
    () async {
      final c = bookingContainer();
      await selectVisit(c, facility: 'songxanh');
      final a = c.read(bookingSessionProvider.notifier);
      a.edit(BookingStage.type);
      a.chooseType(VisitType.insurance);
      final draft = c.read(bookingSessionProvider).draft;
      expect(draft.facilityId, isNull);
      expect(draft.departmentId, isNull);
      expect(draft.doctorMode, isNull);
      expect(draft.slot, isNull);
      await a.next();
      expect(c.read(bookingSessionProvider).stage, BookingStage.facility);
      expect(c.read(bookingSessionProvider).draft.patientId, 'self');
    },
  );

  test(
    'changing child to adult clears pediatric choice and private note',
    () async {
      final c = bookingContainer();
      await selectVisit(c, patient: 'child', department: 'children');
      final a = c.read(bookingSessionProvider.notifier);
      a.setNote('Ghi chú của trẻ');
      a.edit(BookingStage.patient);
      a.choosePatient('mother');
      expect(c.read(bookingSessionProvider).draft.note, isEmpty);
      expect(c.read(bookingSessionProvider).draft.departmentId, isNull);
      await a.next();
      expect(c.read(bookingSessionProvider).stage, BookingStage.department);
      a.chooseDepartment('children');
      expect(c.read(bookingSessionProvider).draft.departmentId, isNull);
    },
  );

  test('editing compatible patient returns to review; contact validation blocks checkout', () async {
    final c = bookingContainer();
    await selectVisit(c);
    final a = c.read(bookingSessionProvider.notifier);
    a.edit(BookingStage.patient);
    a.choosePatient('mother');
    await a.next();
    expect(c.read(bookingSessionProvider).stage, BookingStage.review);
    a.setContact(phone: '123');
    await a.checkout();
    expect(c.read(bookingSessionProvider).stage, BookingStage.review);
    expect(c.read(bookingSessionProvider).error, isNotEmpty);
  });

  test(
    'lost slot returns to date selection and preserves person and facility',
    () async {
      final c = bookingContainer(options: const DemoOptions(slotTaken: true));
      await selectVisit(c);
      final a = c.read(bookingSessionProvider.notifier);
      await a.checkout();
      final state = c.read(bookingSessionProvider);
      expect(state.stage, BookingStage.dateTime);
      expect(state.draft.slot, isNull);
      expect(state.draft.patientId, 'self');
      expect(state.draft.facilityId, 'anbinh');
      expect(state.notice, contains('vừa hết chỗ'));
      expect(c.read(appointmentsProvider).records, isEmpty);
      a.chooseSlot(state.slots.firstWhere((slot) => slot.available));
      await a.next();
      await a.checkout();
      expect(c.read(bookingSessionProvider).stage, BookingStage.payment);
    },
  );

  test(
    'network retry and fully booked day do not permit an unavailable slot',
    () async {
      final c = bookingContainer(
        options: const DemoOptions(networkError: true),
      );
      final a = c.read(bookingSessionProvider.notifier);
      a.chooseType(VisitType.service);
      a.choosePatient('self');
      a.chooseFacility('anbinh');
      a.chooseDepartment('general');
      a.chooseDoctor(DoctorMode.any);
      await a.chooseDate(BookingCatalog.dates(today).first);
      expect(c.read(bookingSessionProvider).error, isNotEmpty);
      await a.loadSlots();
      expect(c.read(bookingSessionProvider).error, isEmpty);
      expect(
        c.read(bookingSessionProvider).slots.any((slot) => slot.available),
        isTrue,
      );
      await a.chooseDate(BookingCatalog.dates(today)[2]);
      final slots = c.read(bookingSessionProvider).slots;
      expect(slots.every((slot) => !slot.available), isTrue);
      a.chooseSlot(slots.first);
      expect(c.read(bookingSessionProvider).draft.slot, isNull);
    },
  );

  test(
    'failed payment can retry without creating duplicate appointment records',
    () async {
      final c = bookingContainer(
        options: const DemoOptions(outcome: DemoOutcome.failure),
      );
      await selectVisit(c);
      final a = c.read(bookingSessionProvider.notifier);
      await a.checkout();
      a.chooseMethod(PayMethod.card);
      await a.submit();
      expect(
        c.read(appointmentsProvider).records.single.receipt.status,
        PaymentStatus.failed,
      );
      a.retryFailed();
      expect(c.read(bookingSessionProvider).stage, BookingStage.payment);
      await a.submit();
      expect(
        c.read(appointmentsProvider).records.single.receipt.status,
        PaymentStatus.confirmed,
      );
    },
  );

  for (final outcome in [DemoOutcome.unknown, DemoOutcome.paidUnconfirmed]) {
    test(
      '$outcome only resolves through status checks; no second charge',
      () async {
        final c = bookingContainer(options: DemoOptions(outcome: outcome));
        await selectVisit(c);
        final a = c.read(bookingSessionProvider.notifier);
        await a.checkout();
        a.chooseMethod(PayMethod.wallet);
        await a.submit();
        final record = c.read(appointmentsProvider).records.single;
        expect(record.receipt.unresolved, isTrue);
        expect(record.receipt.appointmentCode, isNull);
        a.retryFailed();
        await a.submit();
        expect(c.read(bookingSessionProvider).stage, BookingStage.result);
        final ledger = c.read(appointmentsProvider.notifier);
        await ledger.check(record.visit.id);
        expect(
          c.read(appointmentsProvider).records.single.receipt.unresolved,
          isTrue,
        );
        if (outcome == DemoOutcome.paidUnconfirmed) {
          c
              .read(demoOptionsProvider.notifier)
              .set(const DemoOptions(facilityConfirmed: true));
        }
        await ledger.check(record.visit.id);
        final resolved = c.read(appointmentsProvider).records.single;
        expect(resolved.receipt.status, PaymentStatus.confirmed);
        expect(
          resolved.receipt.transactionCode,
          record.receipt.transactionCode,
        );
        c.invalidate(bookingSessionProvider);
        expect(
          c.read(appointmentsProvider).records.single.receipt.appointmentCode,
          resolved.receipt.appointmentCode,
        );
        expect(c.read(bookingSessionProvider).draft.id, isNot(record.visit.id));
      },
    );
  }

  test('late slot response cannot overwrite a newer chosen date', () async {
    final repository = ControlledRepository();
    final c = bookingContainer(repository: repository);
    final a = c.read(bookingSessionProvider.notifier);
    final dates = BookingCatalog.dates(today);
    final first = a.chooseDate(dates[0]);
    final second = a.chooseDate(dates[1]);
    repository.pending[1].complete([BookingSlot(dates[1], '09:00', 'new')]);
    await second;
    repository.pending[0].complete([BookingSlot(dates[0], '08:00', 'old')]);
    await first;
    expect(c.read(bookingSessionProvider).draft.date, dates[1]);
    expect(c.read(bookingSessionProvider).slots.single.doctorId, 'new');
  });
  test('Back while editing the visit type never closes the flow', () async {
    final c = bookingContainer();
    final actions = c.read(bookingSessionProvider.notifier);
    await selectVisit(c, facility: 'songxanh');
    expect(c.read(bookingSessionProvider).stage, BookingStage.review);

    actions.edit(BookingStage.type);
    expect(actions.closesOnBack, isFalse);
    actions.back();
    expect(c.read(bookingSessionProvider).stage, BookingStage.review);

    // BHYT invalidates this facility: Back returns to the first missing choice.
    actions.edit(BookingStage.type);
    actions.chooseType(VisitType.insurance);
    actions.back();
    final session = c.read(bookingSessionProvider);
    expect(session.stage, BookingStage.facility);
    expect(session.draft.patientId, 'self');
  });

  test('change visit type from the facility step returns to facility', () async {
    final c = bookingContainer();
    final actions = c.read(bookingSessionProvider.notifier);
    actions.chooseType(VisitType.insurance);
    await actions.next();
    actions.choosePatient('self');
    await actions.next();
    expect(c.read(bookingSessionProvider).stage, BookingStage.facility);
    actions.edit(BookingStage.type);
    actions.back();
    expect(c.read(bookingSessionProvider).stage, BookingStage.facility);
    expect(c.read(bookingSessionProvider).draft.patientId, 'self');
  });
}

class ControlledRepository implements BookingRepository {
  final pending = <Completer<List<BookingSlot>>>[];
  @override
  Future<List<BookingSlot>> loadSlots(BookingDraft draft) {
    final result = Completer<List<BookingSlot>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<bool> validateSlot(BookingDraft draft) async => true;
  @override
  Future<PaymentReceipt> submit(BookingDraft draft) =>
      throw UnimplementedError();
  @override
  Future<PaymentReceipt> check(String draftId) => throw UnimplementedError();
}
