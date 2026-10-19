import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_state.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../booking/application/booking_providers.dart';
import '../../booking/data/booking_catalog.dart';
import '../../booking/domain/booking_models.dart';
import '../../booking/presentation/booking_format.dart';
import '../application/smart_controller.dart';
import '../domain/smart_models.dart';

/// Conversational booking (SS00–SS08). Questions are text with quick
/// replies; the user may speak, type or tap. One proposal is reviewed before
/// the existing payment step.
class SmartPage extends ConsumerStatefulWidget {
  const SmartPage({super.key, this.fromBooking = false});
  final bool fromBooking;
  @override
  ConsumerState<SmartPage> createState() => _SmartPageState();
}

class _SmartPageState extends ConsumerState<SmartPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _proposalKey = GlobalKey();
  SmartController get actions => ref.read(smartControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  SmartEntry _entry() {
    if (!widget.fromBooking) return const SmartEntry();
    final draft = ref.read(bookingSessionProvider).draft;
    return SmartEntry(
      fromBooking: true,
      patientId: draft.patientId,
      type: draft.type,
      facilityId: draft.facilityId,
    );
  }

  void _start() {
    if (mounted) actions.start(_entry());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep the microphone open in the background (PRD §5.8).
    if (state != AppLifecycleState.resumed) actions.stopListening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await actions.sendText(text);
  }

  void _handOff(BookingHandoff handoff) {
    if (!mounted) return;
    if (widget.fromBooking) {
      ref.read(bookingSessionProvider.notifier).applyHandoff(handoff);
      context.pop();
    } else {
      ref.read(bookingHandoffProvider).pending = handoff;
      context.pushReplacement(AppRoutes.booking);
    }
  }

  Future<void> _confirm() async {
    final handoff = await actions.confirm();
    if (handoff != null) _handOff(handoff);
  }

  Future<void> _toBasicFlow() async => _handOff(await actions.toBasicFlow());

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(smartControllerProvider);
    ref.listen(
      smartControllerProvider.select((v) => (v.messages.length, v.phase)),
      (previous, next) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final duration = AppMotion.duration(context);
        // A new proposal is read from its top; new messages from the bottom.
        final heading = _proposalKey.currentContext;
        if (next.$2 == SmartPhase.proposal &&
            previous?.$2 != SmartPhase.proposal &&
            heading != null) {
          Scrollable.ensureVisible(heading, duration: duration);
          return;
        }
        final end = _scroll.position.maxScrollExtent;
        if (duration == Duration.zero) {
          _scroll.jumpTo(end);
        } else {
          _scroll.animateTo(end, duration: duration, curve: Curves.easeOut);
        }
      }),
    );
    return PopScope(
      canPop: s.phase != SmartPhase.confirming,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: ColoredBox(
                color: AppColors.primary,
                child: SafeArea(
                  bottom: false,
                  child: AppPageHeader(
                    title: 'Đặt lịch thông minh',
                    onBack: s.phase == SmartPhase.confirming
                        ? null
                        : () => AppRoutes.backOrHome(context),
                    onHelp: () => context.push(AppRoutes.help),
                  ),
                ),
              ),
            ),
            SliverSafeArea(
              top: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _body(
                      context,
                      s,
                    ).expand((w) => [w, const SizedBox(height: 12)]).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _bottom(context, s),
      ),
    );
  }

  List<Widget> _body(BuildContext context, SmartState s) {
    final theme = Theme.of(context).textTheme;
    final profiles = ref.watch(profileCatalogProvider);
    return [
      if (s.simulated && s.phase != SmartPhase.starting)
        const AppStatusBanner(
          key: Key('smart-simulated'),
          title: 'Mô phỏng AI',
          message: 'Gợi ý theo quy tắc mẫu, chưa nhận giọng nói. Cơ sở và lịch là dữ liệu minh họa.',
        ),
      if (s.phase == SmartPhase.starting)
        const AppLoadingState(label: 'Đang mở Đặt lịch thông minh…'),
      if (s.phase != SmartPhase.starting && !s.messages.any((m) => m.fromUser))
        Semantics(
          header: true,
          child: Text(
            'Bạn cần khám gì? Hãy nói hoặc nhập, ví dụ: “Tôi đau khớp gối, muốn khám sáng thứ Bảy ở An Bình”.',
            style: theme.titleMedium,
          ),
        ),
      for (final m in s.messages) _Bubble(message: m, profiles: profiles),
      if (s.partial.isNotEmpty)
        // Live transcript: shown, not announced character by character.
        ExcludeSemantics(
          child: _Bubble(
            message: SmartMessage(fromUser: true, text: s.partial),
            profiles: profiles,
            pending: true,
          ),
        ),
      if (s.notice.isNotEmpty)
        AppStatusBanner(
          status: AppStatus.warning,
          message: s.notice,
          liveRegion: true,
        ),
      if (s.error.isNotEmpty)
        AppStatusBanner(
          status: AppStatus.error,
          message: s.error,
          liveRegion: true,
        ),
      if (s.phase == SmartPhase.processing ||
          (s.processing && s.phase != SmartPhase.urgent))
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Đang cập nhật đề xuất…', style: theme.bodyMedium),
              ),
            ],
          ),
        ),
      if (s.phase == SmartPhase.asking && s.question != null)
        ..._question(context, s.question!, profiles),
      if (s.phase == SmartPhase.proposal && s.proposal != null)
        ..._proposal(context, s, profiles),
      if (s.phase == SmartPhase.urgent) ..._urgent(context, s),
      if (s.phase == SmartPhase.error) ...[
        OutlinedButton(onPressed: _start, child: const Text('Thử lại')),
        if (s.reply?.fields.time != null &&
            s.reply?.status == SmartStatus.ready)
          OutlinedButton(
            onPressed: actions.retryProposal,
            child: const Text('Tìm lại giờ khám'),
          ),
      ],
      if (s.phase != SmartPhase.urgent &&
          s.phase != SmartPhase.starting &&
          s.phase != SmartPhase.handedOff)
        TextButton(
          key: const Key('smart-basic-flow'),
          onPressed: s.phase == SmartPhase.confirming ? null : _toBasicFlow,
          child: const Text('Đặt lịch từng bước'),
        ),
    ];
  }

  List<Widget> _question(
    BuildContext context,
    SmartQuestion q,
    List<PreviewProfile> profiles,
  ) {
    String label(SmartOption o) => q.field == 'patientId'
        ? profiles
                  .where((p) => p.id == o.value)
                  .map((p) => '${p.name} (${p.relationship})')
                  .firstOrNull ??
              o.label
        : o.label;
    if (q.field == 'facilityId') {
      return [
        for (final o in q.options)
          AppChoiceCard(
            key: ValueKey('smart-option-${o.value}'),
            title: o.label,
            description: o.hint,
            icon: AppIcons.hospital,
            onTap: () => actions.choose(SmartOption(o.value, o.label), q.field),
          ),
      ];
    }
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in q.options)
            AppSelectionChip(
              key: ValueKey('smart-option-${o.value}'),
              label: label(o),
              pill: true,
              onTap: () =>
                  actions.choose(SmartOption(o.value, label(o)), q.field),
            ),
        ],
      ),
    ];
  }

  List<Widget> _proposal(
    BuildContext context,
    SmartState s,
    List<PreviewProfile> profiles,
  ) {
    final draft = s.proposal!.draft;
    final fields = s.reply!.fields;
    final facility = BookingCatalog.facility(draft.facilityId!);
    final doctor = BookingCatalog.doctors(
      draft.facilityId!,
      draft.departmentId!,
    ).firstWhere((d) => d.id == draft.slot!.doctorId);
    String title(String text, String field) =>
        s.changed.contains(field) ? '$text · vừa đổi' : text;
    return [
      Semantics(
        key: _proposalKey,
        header: true,
        liveRegion: true,
        child: Text(
          'Đề xuất lịch khám',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
      AppReviewSection(
        key: const Key('smart-section-patient'),
        title: title('Người khám', 'patientId'),
        items: [
          (
            label: 'Họ và tên',
            value: profiles.firstWhere((p) => p.id == draft.patientId).name,
          ),
        ],
        onEdit: () => _editPatient(profiles),
      ),
      AppReviewSection(
        title: title('Hình thức khám', 'type'),
        items: [(label: 'Hình thức', value: draft.type!.label)],
        onEdit: _editType,
      ),
      AppReviewSection(
        title: title('Nơi khám', 'facilityId'),
        items: [
          (label: 'Cơ sở', value: facility.name),
          (label: 'Địa chỉ', value: facility.address),
        ],
        onEdit: () => _editFacility(draft),
      ),
      AppReviewSection(
        title: title('Chuyên khoa', 'departmentId'),
        items: [
          (
            label: 'Khoa',
            value: BookingCatalog.department(draft.departmentId!).name,
          ),
          if (fields.departmentReason != null &&
              s.reply!.sources['departmentId'] == 'suggested')
            (label: 'Vì sao gợi ý', value: fields.departmentReason!),
          if (fields.symptoms != null)
            (label: 'Nhu cầu bạn đã nói', value: fields.symptoms!),
        ],
        onEdit: () => _editDepartment(draft, profiles),
      ),
      AppReviewSection(
        title: title('Bác sĩ', 'doctorId'),
        items: [
          (
            label: fields.doctorId == null ? 'Bác sĩ còn lịch' : 'Bác sĩ',
            value: doctor.name,
          ),
        ],
        onEdit: () => _editDoctor(draft),
      ),
      AppReviewSection(
        key: const Key('smart-section-time'),
        title: title('Ngày giờ', 'time'),
        items: [
          (
            label: fields.time?.earliest == true
                ? 'Giờ còn chỗ sớm nhất phù hợp'
                : 'Giờ hẹn',
            value: '${bookingDate(draft.date!)} · ${draft.slot!.time}',
          ),
        ],
        onEdit: () => _editTime(draft),
      ),
      AppReviewSection(
        title: 'Chi phí',
        items: [
          (
            label: draft.type == VisitType.insurance
                ? 'Phí đặt lịch'
                : 'Phí khám dự kiến',
            value: bookingMoney(s.proposal!.fee),
          ),
        ],
      ),
      Text(
        'Người nhận thông báo',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      TextFormField(
        key: const Key('smart-contact-name'),
        initialValue: s.contactName,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Họ và tên'),
        onChanged: (v) => actions.setContact(name: v),
      ),
      TextFormField(
        key: const Key('smart-contact-phone'),
        initialValue: s.contactPhone,
        maxLength: 10,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Số điện thoại'),
        onChanged: (v) => actions.setContact(phone: v),
      ),
      if (s.canUndo)
        OutlinedButton.icon(
          key: const Key('smart-undo'),
          onPressed: actions.undo,
          icon: const AppIcon(AppIcons.undo),
          label: const Text('Hoàn tác thay đổi vừa rồi'),
        ),
    ];
  }

  // The app only suggests 115: the button opens the phone's dialer with the
  // number filled in, and the user decides whether to press call.
  List<Widget> _urgent(BuildContext context, SmartState s) {
    final signs = s.reply?.urgentSigns ?? const <String>[];
    return [
      AppStatusBanner(
        key: const Key('smart-urgent'),
        status: AppStatus.error,
        title: 'Bạn có thể cần hỗ trợ y tế ngay',
        message: [
          if (signs.isNotEmpty) 'Bạn có nhắc tới: ${signs.join(', ')}.',
          'Đây có thể là dấu hiệu cần cấp cứu. Hãy gọi cấp cứu 115 hoặc đến cơ sở y tế gần nhất ngay. Ứng dụng không tiếp tục đặt lịch khám thường cho mô tả này.',
        ].join(' '),
        liveRegion: true,
      ),
      FilledButton.icon(
        key: const Key('smart-call-115'),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: () => _dial115(context),
        icon: const AppIcon(AppIcons.phone),
        label: const Text('Gọi 115'),
      ),
      Text(
        'Ứng dụng chỉ mở màn hình gọi điện với số 115. Bạn tự quyết định có bấm gọi hay không.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      OutlinedButton.icon(
        key: const Key('smart-urgent-map'),
        onPressed: () => context.push(AppRoutes.facilityMap),
        icon: const AppIcon(AppIcons.location),
        label: const Text('Xem cơ sở y tế gần nhất'),
      ),
      TextButton(
        onPressed: () => context.go(AppRoutes.home),
        child: const Text('Về Trang chủ'),
      ),
    ];
  }

  Future<void> _dial115(BuildContext context) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: '115'));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không mở được màn hình gọi. Hãy tự bấm số 115 trên điện thoại.',
          ),
        ),
      );
    }
  }

  Widget? _bottom(BuildContext context, SmartState s) {
    if (s.phase == SmartPhase.urgent ||
        s.phase == SmartPhase.starting ||
        s.phase == SmartPhase.handedOff) {
      return null;
    }
    if (s.micOn) return _ListeningBar(state: s, actions: actions);
    final composer = _Composer(
      controller: _input,
      onSend: _send,
      onMic: actions.startListening,
      micLabel: s.proposal != null ? 'Nói lại' : 'Nói',
      enabled: s.phase != SmartPhase.confirming && s.phase != SmartPhase.error,
    );
    if (s.phase != SmartPhase.proposal && s.phase != SmartPhase.confirming) {
      return composer;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        composer,
        AppPrimaryActionBar(
          key: const Key('smart-confirm'),
          label: 'Xác nhận và tiếp tục thanh toán',
          isLoading: s.phase == SmartPhase.confirming,
          onPressed: s.canConfirm ? _confirm : null,
        ),
      ],
    );
  }

  // ---- Edit sheets ----------------------------------------------------------

  Future<String?> _pick(
    String title,
    List<
      ({String value, String label, String? hint, bool enabled, String? reason})
    >
    options,
  ) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(title, style: Theme.of(sheet).textTheme.titleLarge),
        const SizedBox(height: 16),
        for (final o in options) ...[
          AppChoiceCard(
            key: ValueKey('smart-pick-${o.value}'),
            title: o.label,
            description: o.hint,
            enabled: o.enabled,
            unavailableReason: o.reason,
            onTap: () => Navigator.pop(sheet, o.value),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );

  Future<void> _editPatient(List<PreviewProfile> profiles) async {
    final value = await _pick('Đổi người khám', [
      for (final p in profiles)
        (
          value: p.id,
          label: p.name,
          hint: p.relationship,
          enabled: true,
          reason: null,
        ),
    ]);
    if (value != null) await actions.edit('patientId', value);
  }

  Future<void> _editType() async {
    final value = await _pick('Đổi hình thức khám', [
      for (final t in VisitType.values)
        (
          value: t.name,
          label: t.label,
          hint: null,
          enabled: true,
          reason: null,
        ),
    ]);
    if (value != null) await actions.edit('type', value);
  }

  Future<void> _editFacility(BookingDraft draft) async {
    final value = await _pick('Đổi nơi khám', [
      for (final f in BookingCatalog.facilities)
        (
          value: f.id,
          label: f.name,
          hint: f.address,
          enabled: draft.type != VisitType.insurance || f.acceptsInsurance,
          reason: 'Cơ sở này không hỗ trợ khám BHYT.',
        ),
    ]);
    if (value != null) await actions.edit('facilityId', value);
  }

  Future<void> _editDepartment(
    BookingDraft draft,
    List<PreviewProfile> profiles,
  ) async {
    final patient = profiles.firstWhere((p) => p.id == draft.patientId);
    final age = profileAge(patient, ref.read(bookingTodayProvider));
    final facility = BookingCatalog.facility(draft.facilityId!);
    final value = await _pick('Đổi chuyên khoa', [
      for (final d in BookingCatalog.departments)
        if (facility.departments.contains(d.id))
          (
            value: d.id,
            label: d.name,
            hint: null,
            enabled: d.maxAge == null || age <= d.maxAge!,
            reason: 'Chuyên khoa này chỉ nhận người đến ${d.maxAge} tuổi.',
          ),
    ]);
    if (value != null) await actions.edit('departmentId', value);
  }

  Future<void> _editDoctor(BookingDraft draft) async {
    final value = await _pick('Đổi bác sĩ', [
      (
        value: 'any',
        label: 'Bác sĩ phù hợp còn lịch',
        hint: 'Không cần chọn đích danh',
        enabled: true,
        reason: null,
      ),
      for (final d in BookingCatalog.doctors(
        draft.facilityId!,
        draft.departmentId!,
      ))
        (value: d.id, label: d.name, hint: null, enabled: true, reason: null),
    ]);
    if (value != null) {
      await actions.edit('doctorId', value == 'any' ? null : value);
    }
  }

  Future<void> _editTime(BookingDraft draft) async {
    final today = ref.read(bookingTodayProvider);
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => _TimeSheet(
        draft: draft,
        dates: BookingCatalog.dates(today),
        loadSlots: actions.slotsFor,
      ),
    );
    if (result is BookingSlot) {
      actions.chooseSlot(result);
    } else if (result is String) {
      await actions.edit('time', result);
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.profiles,
    this.pending = false,
  });
  final SmartMessage message;
  final List<PreviewProfile> profiles;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: user ? AppColors.selected : Colors.white,
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Semantics(
              label: user ? 'Bạn nói' : 'Trợ lý',
              child: Text(
                pending ? '${message.text}…' : message.text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontStyle: pending ? FontStyle.italic : null,
                  color: pending ? AppColors.secondaryInk : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onMic,
    required this.micLabel,
    required this.enabled,
  });
  final TextEditingController controller;
  final VoidCallback onSend, onMic;
  final String micLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mic = FilledButton.icon(
      key: const Key('smart-mic'),
      onPressed: enabled ? onMic : null,
      icon: const AppIcon(AppIcons.mic),
      label: Text(micLabel),
    );
    final field = TextField(
      key: const Key('smart-input'),
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 3,
      maxLength: 500,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSend(),
      decoration: InputDecoration(
        labelText: 'Nhập tay',
        counterText: '',
        suffixIcon: IconButton(
          key: const Key('smart-send'),
          tooltip: 'Gửi',
          onPressed: enabled ? onSend : null,
          icon: const AppIcon(AppIcons.send),
        ),
      ),
    );
    // Large system text stacks the controls instead of shrinking them.
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 24;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [mic, const SizedBox(height: 12), field],
                )
              : Row(
                  children: [
                    mic,
                    const SizedBox(width: 12),
                    Expanded(child: field),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ListeningBar extends StatelessWidget {
  const _ListeningBar({required this.state, required this.actions});
  final SmartState state;
  final SmartController actions;

  @override
  Widget build(BuildContext context) {
    final connecting = state.phase == SmartPhase.connecting;
    final seconds = state.listenSeconds;
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    AppIcon(
                      connecting ? AppIcons.clock : AppIcons.mic,
                      color: connecting
                          ? AppColors.outline
                          : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        connecting
                            ? 'Đang kết nối micro…'
                            : 'Micro đang bật · $time',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Giọng nói đang được gửi tới dịch vụ chuyển chữ để xử lý.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    key: const Key('smart-finish-turn'),
                    onPressed: connecting ? null : actions.finishTurn,
                    child: const Text('Xong lượt nói'),
                  ),
                  FilledButton.icon(
                    key: const Key('smart-stop'),
                    onPressed: actions.stopListening,
                    icon: const AppIcon(AppIcons.micOff),
                    label: const Text('Dừng'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSheet extends StatefulWidget {
  const _TimeSheet({
    required this.draft,
    required this.dates,
    required this.loadSlots,
  });
  final BookingDraft draft;
  final List<DateTime> dates;
  final Future<List<BookingSlot>> Function(DateTime) loadSlots;
  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  late Future<List<BookingSlot>> _slots = widget.loadSlots(widget.draft.date!);

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      Text('Đổi ngày giờ', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppSelectionChip(
            key: const Key('smart-time-earliest'),
            label: 'Sớm nhất còn chỗ',
            pill: true,
            onTap: () => Navigator.pop(context, 'earliest'),
          ),
          for (final date in widget.dates)
            AppSelectionChip(
              key: ValueKey('smart-time-${_iso(date)}'),
              label: bookingDate(date).split(',').first,
              subtitle: '${date.day}/${date.month}',
              onTap: () => Navigator.pop(context, 'date:${_iso(date)}'),
            ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        'Giờ khác trong ${bookingDate(widget.draft.date!)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      FutureBuilder<List<BookingSlot>>(
        future: _slots,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppErrorState(
              message: 'Chưa tải được giờ khám.',
              onRetry: () =>
                  setState(() => _slots = widget.loadSlots(widget.draft.date!)),
            );
          }
          if (!snapshot.hasData) {
            return const AppLoadingState(label: 'Đang tải giờ khám…');
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in snapshot.data!)
                AppSelectionChip(
                  key: ValueKey('smart-slot-${slot.time}'),
                  label: slot.time,
                  pill: true,
                  enabled: slot.available,
                  selected: slot.key == widget.draft.slot?.key,
                  onTap: () => Navigator.pop(context, slot),
                ),
            ],
          );
        },
      ),
    ],
  );
}
