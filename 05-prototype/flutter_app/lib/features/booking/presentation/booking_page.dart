import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_state.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/booking_providers.dart';
import '../data/booking_catalog.dart';
import '../domain/booking_models.dart';
import 'appointment_pages.dart';
import 'booking_format.dart';
import 'booking_ux.dart';

class BookingPage extends ConsumerStatefulWidget {
  const BookingPage({super.key});
  @override
  ConsumerState<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends ConsumerState<BookingPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _dob = TextEditingController();
  final _relationship = TextEditingController(text: 'Người thân');
  final _feedbackKey = GlobalKey();
  String _query = '';
  BookingController get actions => ref.read(bookingSessionProvider.notifier);
  @override
  void dispose() {
    for (final controller in [_search, _name, _dob, _relationship]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _back(BookingSession session) {
    if (session.busy) return;
    if (session.stage == BookingStage.type ||
        session.stage == BookingStage.result) {
      AppRoutes.backOrHome(context);
    } else {
      actions.back();
    }
  }

  Future<void> _addPatient() async {
    final form = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.duration(context),
        reverseDuration: AppMotion.duration(context),
      ),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Thêm người khám',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('new-patient-name'),
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập họ và tên.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('new-patient-dob'),
                  controller: _dob,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Ngày sinh',
                    hintText: 'dd/MM/yyyy',
                  ),
                  validator: (value) => _parseBirthDate(value ?? '') == null
                      ? 'Nhập ngày sinh hợp lệ theo dd/MM/yyyy.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _relationship,
                  textInputAction: TextInputAction.done,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Quan hệ'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập quan hệ.'
                      : null,
                ),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  label: 'Lưu người khám',
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    final birthDate = _parseBirthDate(_dob.text)!;
                    final profile = PreviewProfile(
                      id: 'P${DateTime.now().microsecondsSinceEpoch}',
                      name: _name.text.trim(),
                      birthYear: birthDate.year,
                      birthDate: birthDate,
                      relationship: _relationship.text.trim(),
                    );
                    ref.read(profileCatalogProvider.notifier).add(profile);
                    actions.choosePatient(profile.id);
                    Navigator.pop(sheetContext);
                    _name.clear();
                    _dob.clear();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _parseBirthDate(String value) {
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(value.trim())) return null;
    final parts = value.trim().split('/').map(int.parse).toList();
    final date = DateTime(parts[2], parts[1], parts[0]);
    if (date.day != parts[0] ||
        date.month != parts[1] ||
        date.year < 1900 ||
        date.isAfter(ref.read(bookingTodayProvider))) {
      return null;
    }
    return date;
  }

  String _normal(String value) {
    var result = value.toLowerCase();
    for (final pair in [
      ('a', 'àáạảãâầấậẩẫăằắặẳẵ'),
      ('e', 'èéẹẻẽêềếệểễ'),
      ('i', 'ìíịỉĩ'),
      ('o', 'òóọỏõôồốộổỗơờớợởỡ'),
      ('u', 'ùúụủũưừứựửữ'),
      ('y', 'ỳýỵỷỹ'),
      ('d', 'đ'),
    ]) {
      result = result.replaceAll(RegExp('[${pair.$2}]'), pair.$1);
    }
    return result;
  }

  List<Widget> _content(BookingSession session) {
    final draft = session.draft;
    final profiles = ref.watch(profileCatalogProvider);
    switch (session.stage) {
      case BookingStage.type:
        return [
          for (final type in VisitType.values)
            AppChoiceCard(
              key: ValueKey('type-${type.name}'),
              title: type.label,
              description: type == VisitType.insurance
                  ? 'Bảo hiểm y tế'
                  : 'Tự chi trả',
              icon: type == VisitType.insurance
                  ? AppIcons.profile
                  : AppIcons.doctor,
              selected: draft.type == type,
              onTap: () => actions.chooseType(type),
            ),
        ];
      case BookingStage.patient:
        return [
          for (final profile in profiles)
            AppChoiceCard(
              key: ValueKey('booking-patient-${profile.id}'),
              title: profile.name,
              description:
                  '${profile.relationship} · Sinh năm ${profile.birthYear}',
              icon: AppIcons.person,
              tone: AppTone.lavender,
              selected: draft.patientId == profile.id,
              onTap: () => actions.choosePatient(profile.id),
            ),
          OutlinedButton(
            onPressed: _addPatient,
            child: const Text('Thêm người khám'),
          ),
        ];
      case BookingStage.facility:
        return [
          for (final facility in BookingCatalog.facilities) ...[
            AppChoiceCard(
              key: ValueKey('facility-${facility.id}'),
              title: facility.name,
              description: facility.address,
              icon: AppIcons.hospital,
              selected: draft.facilityId == facility.id,
              enabled:
                  draft.type != VisitType.insurance ||
                  facility.acceptsInsurance,
              unavailableReason: 'Cơ sở này không hỗ trợ khám BHYT.',
              onTap: () => actions.chooseFacility(facility.id),
            ),
            if (draft.type == VisitType.insurance && !facility.acceptsInsurance)
              TextButton(
                onPressed: () => actions.edit(BookingStage.type),
                child: const Text('Đổi hình thức khám'),
              ),
          ],
        ];
      case BookingStage.department:
        final patient = profiles.firstWhere(
          (profile) => profile.id == draft.patientId,
        );
        final departments = BookingCatalog.departments.where(
          (dept) =>
              BookingCatalog.facility(draft.facilityId!).departments
                  .contains(dept.id) &&
              _normal(dept.name).contains(_normal(_query)),
        );
        return [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Tìm chuyên khoa',
              prefixIcon: AppIcon(AppIcons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (departments.isEmpty)
            AppEmptyState(
              title: 'Không tìm thấy chuyên khoa',
              message: 'Thử tên khác hoặc xóa từ khóa.',
              actionLabel: 'Xóa từ khóa',
              onAction: () => setState(() {
                _search.clear();
                _query = '';
              }),
            ),
          for (final department in departments)
            AppChoiceCard(
              key: ValueKey('department-${department.id}'),
              title: department.name,
              icon: AppIcons.doctor,
              selected: draft.departmentId == department.id,
              enabled:
                  department.maxAge == null ||
                  actions.age(patient) <= department.maxAge!,
              unavailableReason:
                  'Chuyên khoa này chỉ nhận người đến ${department.maxAge} tuổi.',
              onTap: () => actions.chooseDepartment(department.id),
            ),
        ];
      case BookingStage.doctor:
        return [
          AppChoiceCard(
            key: const Key('doctor-any'),
            title: 'Bác sĩ phù hợp còn lịch',
            description: 'Không cần chọn bác sĩ đích danh',
            icon: AppIcons.doctor,
            selected: draft.doctorMode == DoctorMode.any,
            onTap: () => actions.chooseDoctor(DoctorMode.any),
          ),
          for (final doctor in BookingCatalog.doctors(
            draft.facilityId!,
            draft.departmentId!,
          ))
            AppChoiceCard(
              key: ValueKey('doctor-${doctor.id}'),
              title: doctor.name,
              icon: AppIcons.person,
              selected:
                  draft.doctorMode == DoctorMode.named &&
                  draft.doctorId == doctor.id,
              onTap: () => actions.chooseDoctor(DoctorMode.named, doctor.id),
            ),
        ];
      case BookingStage.dateTime:
        return [
          AppChoiceGrid(
            children: [
              for (final date in BookingCatalog.dates(
                ref.watch(bookingTodayProvider),
              ))
                AppSelectionChip(
                  key: ValueKey('date-${date.toIso8601String()}'),
                  label: bookingDate(date).split(',').first,
                  subtitle: '${date.day}/${date.month}',
                  selected: draft.date == date,
                  onTap: () => actions.chooseDate(date),
                ),
            ],
          ),
          if (session.loadingSlots) const BookingSlotsSkeleton(),
          if (!session.loadingSlots &&
              session.error.isEmpty &&
              session.slots.any((slot) => slot.available))
            Semantics(
              liveRegion: true,
              child: Text(
                'Có ${session.slots.where((slot) => slot.available).length} khung giờ còn chỗ. Chọn giờ phù hợp với bạn.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (!session.loadingSlots && session.error.isNotEmpty)
            OutlinedButton(
              onPressed: actions.loadSlots,
              child: const Text('Thử tải giờ lại'),
            ),
          if (!session.loadingSlots &&
              session.slots.isNotEmpty &&
              !session.slots.any((slot) => slot.available))
            const AppEmptyState(
              title: 'Ngày này đã hết lịch',
              message: 'Vui lòng chọn ngày khác.',
            ),
          if (!session.loadingSlots)
            for (final period in [
              (label: 'Buổi sáng', afternoon: false),
              (label: 'Buổi chiều', afternoon: true),
            ]) ...[
              if (session.slots.isNotEmpty)
                Text(
                  period.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              AppChoiceGrid(
                minItemWidth: 120,
                children: [
                  for (final slot in session.slots.where(
                    (slot) =>
                        (int.parse(slot.time.split(':').first) >= 12) ==
                        period.afternoon,
                  ))
                    AppSelectionChip(
                      key: ValueKey('booking-slot-${slot.time}'),
                      label: slot.time,
                      pill: true,
                      enabled: slot.available,
                      selected: draft.slot?.key == slot.key,
                      onTap: () => actions.chooseSlot(slot),
                    ),
                ],
              ),
            ],
        ];
      case BookingStage.review:
        final facility = BookingCatalog.facility(draft.facilityId!);
        final doctor = BookingCatalog.doctors(
          draft.facilityId!,
          draft.departmentId!,
        ).firstWhere((doctor) => doctor.id == draft.slot!.doctorId);
        return [
          AppReviewSection(
            title: 'Người khám',
            items: [
              (
                label: 'Họ và tên',
                value: profiles
                    .firstWhere((profile) => profile.id == draft.patientId)
                    .name,
              ),
            ],
            onEdit: () => actions.edit(BookingStage.patient),
          ),
          AppReviewSection(
            title: 'Hình thức khám',
            items: [(label: 'Hình thức', value: draft.type!.label)],
            onEdit: () => actions.edit(BookingStage.type),
          ),
          AppReviewSection(
            title: 'Nơi khám',
            items: [
              (label: 'Cơ sở', value: facility.name),
              (label: 'Địa chỉ', value: facility.address),
            ],
            onEdit: () => actions.edit(BookingStage.facility),
          ),
          AppReviewSection(
            title: 'Chuyên khoa',
            items: [
              (
                label: 'Khoa',
                value: BookingCatalog.department(draft.departmentId!).name,
              ),
            ],
            onEdit: () => actions.edit(BookingStage.department),
          ),
          AppReviewSection(
            title: 'Bác sĩ',
            items: [(label: 'Bác sĩ', value: doctor.name)],
            onEdit: () => actions.edit(BookingStage.doctor),
          ),
          AppReviewSection(
            title: 'Ngày giờ',
            items: [
              (
                label: 'Giờ hẹn',
                value: '${bookingDate(draft.date!)} · ${draft.slot!.time}',
              ),
            ],
            onEdit: () => actions.edit(BookingStage.dateTime),
          ),
          AppReviewSection(
            title: 'Chi phí',
            items: [
              (
                label: draft.type == VisitType.insurance
                    ? 'Phí đặt lịch'
                    : 'Phí khám dự kiến',
                value: bookingMoney(BookingCatalog.fee(draft)),
              ),
            ],
          ),
          if (draft.type == VisitType.insurance)
            const AppStatusBanner(
              message: 'Quyền lợi BHYT và khoản cần thanh toán được cơ sở xác nhận khi đến khám.',
            ),
          Text(
            'Người nhận thông báo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          TextFormField(
            key: const Key('booking-contact-name'),
            initialValue: draft.contactName,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Họ và tên'),
            onChanged: (value) => actions.setContact(name: value),
          ),
          TextFormField(
            key: const Key('booking-contact-phone'),
            initialValue: draft.contactPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 10,
            decoration: const InputDecoration(labelText: 'Số điện thoại'),
            onChanged: (value) => actions.setContact(phone: value),
          ),
          ExpansionTile(
            expansionAnimationStyle: AnimationStyle(
              duration: AppMotion.duration(context),
              reverseDuration: AppMotion.duration(context),
            ),
            title: const Text('Thêm ghi chú cho bác sĩ'),
            children: [
              TextFormField(
                key: ValueKey('booking-note-${draft.patientId}'),
                initialValue: draft.note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
                onChanged: actions.setNote,
              ),
            ],
          ),
        ];
      case BookingStage.payment:
        return [
          const AppStatusBanner(
            message: 'Thanh toán thử nghiệm — không thu tiền thật.',
          ),
          AppReviewSection(
            title: 'Khoản thanh toán',
            items: [
              (
                label: draft.type == VisitType.insurance
                    ? 'Phí đặt lịch'
                    : 'Phí khám dự kiến',
                value: bookingMoney(BookingCatalog.fee(draft)),
              ),
            ],
          ),
          for (final method in BookingCatalog.methods(draft))
            AppChoiceCard(
              key: ValueKey('payment-${method.name}'),
              title: method.label,
              icon: AppIcons.payment,
              selected: draft.method == method,
              onTap: () => actions.chooseMethod(method),
            ),
          if (draft.type == VisitType.insurance)
            const AppStatusBanner(
              message: 'Phần viện phí và quyền lợi BHYT sẽ được cơ sở xác nhận. Không thực hiện thu phí online cho lựa chọn này.',
            ),
        ];
      case BookingStage.result:
        return [
          AppointmentRecordView(id: draft.id, onRetry: actions.retryFailed),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bookingSessionProvider);
    ref.listen(bookingSessionProvider.select((value) => value.stage), (
      previous,
      next,
    ) {
      if (previous != next) {
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    });
    final stage = session.stage;
    ref.listen(
      bookingSessionProvider.select((value) => (value.error, value.notice)),
      (previous, next) {
        if (previous != next && (next.$1.isNotEmpty || next.$2.isNotEmpty)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final feedback = _feedbackKey.currentContext;
            if (mounted && feedback != null) {
              Scrollable.ensureVisible(
                feedback,
                alignment: 0.1,
                duration: AppMotion.duration(context),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
    );
    final patient = ref
        .watch(profileCatalogProvider)
        .where((profile) => profile.id == session.draft.patientId)
        .firstOrNull;
    final label = stage == BookingStage.result
        ? 'Xem lịch hẹn'
        : stage == BookingStage.payment
        ? session.draft.method == PayMethod.atHospital
              ? 'Xác nhận trả tại viện'
              : 'Thanh toán thử'
        : session.editing && session.draft.firstMissing == null
        ? 'Lưu và về trang Kiểm tra'
        : switch (stage) {
            BookingStage.type => 'Tiếp tục: Chọn người khám',
            BookingStage.patient => 'Tiếp tục: Chọn nơi khám',
            BookingStage.facility => 'Tiếp tục: Chọn chuyên khoa',
            BookingStage.department => 'Tiếp tục: Chọn bác sĩ',
            BookingStage.doctor => 'Tiếp tục: Chọn ngày giờ',
            BookingStage.dateTime => 'Kiểm tra thông tin',
            _ => 'Tiếp tục: Thanh toán',
          };
    return PopScope(
      canPop:
          !session.busy &&
          (stage == BookingStage.type || stage == BookingStage.result),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(session);
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: FocusTraversalGroup(
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppColors.primary,
                    child: SafeArea(
                      bottom: false,
                      child: AppFlowHeader(
                        step: stage.step,
                        title: stage.label,
                        patientName: patient?.name,
                        onBack: session.busy ? null : () => _back(session),
                        onHelp: session.busy
                            ? null
                            : () => context.push(AppRoutes.help),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: BookingStepEntrance(
                      step: stage,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            liveRegion: true,
                            child: Text(
                              switch (stage) {
                                BookingStage.result => 'Kết quả đặt lịch',
                                BookingStage.review => 'Kiểm tra thông tin',
                                BookingStage.payment => 'Cách thanh toán',
                                _ => 'Chọn ${stage.label.toLowerCase()}',
                              },
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(key: _feedbackKey),
                          if (session.notice.isNotEmpty) ...[
                            AppStatusBanner(
                              status: AppStatus.warning,
                              message: session.notice,
                              liveRegion: true,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (session.error.isNotEmpty) ...[
                            AppStatusBanner(
                              status: AppStatus.error,
                              message: session.error,
                              liveRegion: true,
                            ),
                            const SizedBox(height: 16),
                          ],
                          ..._content(session).expand(
                            (widget) => [widget, const SizedBox(height: 12)],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: AppPrimaryActionBar(
          key: const Key('booking-action'),
          label: label,
          isLoading: session.busy,
          onPressed: session.loadingSlots
              ? null
              : stage == BookingStage.result
              ? () => context.go(AppRoutes.appointments)
              : stage == BookingStage.payment
              ? actions.submit
              : actions.next,
        ),
      ),
    );
  }
}
