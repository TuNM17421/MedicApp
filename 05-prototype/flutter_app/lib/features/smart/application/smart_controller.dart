import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../app/state/app_state.dart';
import '../../booking/application/booking_providers.dart';
import '../../booking/data/booking_catalog.dart';
import '../../booking/domain/booking_models.dart';
import '../data/smart_gateway.dart';
import '../data/voice_capture.dart';
import '../domain/smart_models.dart';
import 'silence_detector.dart';

final smartGatewayProvider = Provider<SmartGateway>(
  (ref) => HttpSmartGateway(baseUrl: AppConfig.apiBaseUrl),
);
final voiceCaptureProvider = Provider<VoiceCapture>((ref) {
  final capture = RecordVoiceCapture();
  ref.onDispose(capture.dispose);
  return capture;
});

/// Where Smart Scheduling was opened from and what is already confirmed.
class SmartEntry {
  const SmartEntry({
    this.fromBooking = false,
    this.patientId,
    this.type,
    this.facilityId,
  });
  final bool fromBooking;
  final String? patientId, facilityId;
  final VisitType? type;
}

class SmartState {
  const SmartState({
    this.phase = SmartPhase.starting,
    this.simulated = true,
    this.voiceAvailable = false,
    this.messages = const [],
    this.partial = '',
    this.reply,
    this.version = -1,
    this.proposal,
    this.slotQuestion,
    this.notice = '',
    this.error = '',
    this.micOn = false,
    this.listenSeconds = 0,
    this.pendingTurns = 0,
    this.changed = const [],
    this.canUndo = false,
    this.contactName = 'Phạm Văn Hòa',
    this.contactPhone = '0900000123',
  });
  final SmartPhase phase;
  final bool simulated, voiceAvailable, micOn, canUndo;
  final List<SmartMessage> messages;
  final String partial, notice, error, contactName, contactPhone;
  final SmartReply? reply;
  final int version, listenSeconds, pendingTurns;
  final SmartProposal? proposal;

  /// Local question when no slot fits the chosen time (no server round trip).
  final SmartQuestion? slotQuestion;
  final List<String> changed;

  SmartQuestion? get question => slotQuestion ?? reply?.question;
  bool get processing => pendingTurns > 0 || (reply?.processing ?? false);
  bool get contactValid =>
      contactName.trim().isNotEmpty &&
      RegExp(r'^0\d{9}$').hasMatch(contactPhone.trim());
  bool get canConfirm =>
      phase == SmartPhase.proposal &&
      proposal != null &&
      !processing &&
      !micOn &&
      contactValid;

  SmartState copyWith({
    SmartPhase? phase,
    bool? simulated,
    bool? voiceAvailable,
    List<SmartMessage>? messages,
    String? partial,
    SmartReply? reply,
    int? version,
    Object? proposal = _keep,
    Object? slotQuestion = _keep,
    String? notice,
    String? error,
    bool? micOn,
    int? listenSeconds,
    int? pendingTurns,
    List<String>? changed,
    bool? canUndo,
    String? contactName,
    String? contactPhone,
  }) => SmartState(
    phase: phase ?? this.phase,
    simulated: simulated ?? this.simulated,
    voiceAvailable: voiceAvailable ?? this.voiceAvailable,
    messages: messages ?? this.messages,
    partial: partial ?? this.partial,
    reply: reply ?? this.reply,
    version: version ?? this.version,
    proposal: identical(proposal, _keep)
        ? this.proposal
        : proposal as SmartProposal?,
    slotQuestion: identical(slotQuestion, _keep)
        ? this.slotQuestion
        : slotQuestion as SmartQuestion?,
    notice: notice ?? this.notice,
    error: error ?? this.error,
    micOn: micOn ?? this.micOn,
    listenSeconds: listenSeconds ?? this.listenSeconds,
    pendingTurns: pendingTurns ?? this.pendingTurns,
    changed: changed ?? this.changed,
    canUndo: canUndo ?? this.canUndo,
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
  );
}

const _keep = Object();

final smartControllerProvider =
    NotifierProvider.autoDispose<SmartController, SmartState>(
      SmartController.new,
    );

class SmartController extends Notifier<SmartState> {
  SmartConnection? _connection;
  SmartAudioLink? _audio;
  StreamSubscription<SmartAudioEvent>? _audioEvents;
  StreamSubscription<Uint8List>? _capture;
  Timer? _ticker;
  final _vad = SilenceDetector();
  final _undo = <({String field, String? value})>[];
  int _turnSeq = 0;
  int _proposalRun = 0;
  SmartEntry _entry = const SmartEntry();
  late VoiceCapture _device;

  /// One booking draft ID per conversation, so repository checks (and the
  /// payment ledger later) see the same draft across re-proposals.
  final String _draftId = BookingController.newDraftId();

  @override
  SmartState build() {
    _device = ref.read(voiceCaptureProvider);
    ref.onDispose(() {
      _stopCapture();
      _ticker?.cancel();
      _audioEvents?.cancel();
      _audio?.close();
      _connection?.close();
    });
    return const SmartState();
  }

  SmartEntry get entry => _entry;

  Future<void> start(SmartEntry entry) async {
    _entry = entry;
    state = const SmartState();
    final today = ref.read(bookingTodayProvider);
    final profiles = ref.read(profileCatalogProvider);
    try {
      final connection = await ref
          .read(smartGatewayProvider)
          .start(
            SmartContext(
              today: today,
              profiles: [
                for (final p in profiles)
                  (
                    id: p.id,
                    relationship: p.relationship,
                    age: profileAge(p, today),
                  ),
              ],
              patientId: entry.patientId,
              type: entry.type,
              facilityId: entry.facilityId,
            ),
          );
      if (!ref.mounted) {
        unawaited(connection.close());
        return;
      }
      _connection = connection;
      state = state.copyWith(
        phase: SmartPhase.ready,
        simulated: connection.info.simulated,
        voiceAvailable: connection.info.voiceAvailable,
      );
      // From the home page the user starts by describing the need freely;
      // from the booking flow the known context leads to its next question.
      await _apply(connection.info.reply, announce: entry.fromBooking);
      if (state.phase == SmartPhase.asking && !entry.fromBooking) {
        state = state.copyWith(phase: SmartPhase.ready);
      }
    } on SmartGatewayException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(phase: SmartPhase.error, error: error.message);
      }
    }
  }

  // ---- Turns ---------------------------------------------------------------

  Future<void> sendText(String text) async {
    final value = text.trim();
    final connection = _connection;
    if (value.isEmpty || connection == null || _blocked) return;
    await stopListening();
    state = state.copyWith(
      messages: [
        ...state.messages,
        SmartMessage(fromUser: true, text: value),
      ],
      pendingTurns: state.pendingTurns + 1,
      phase: SmartPhase.processing,
      error: '',
      notice: '',
    );
    await _request(() => connection.text(value, 't${++_turnSeq}'));
  }

  Future<void> choose(SmartOption option, String field) async {
    final connection = _connection;
    if (connection == null || _blocked) return;
    await stopListening();
    state = state.copyWith(
      messages: [
        ...state.messages,
        SmartMessage(fromUser: true, text: option.label),
      ],
      pendingTurns: state.pendingTurns + 1,
      error: '',
      notice: '',
    );
    await _request(() => connection.choose(field, option.value));
  }

  /// Manual edit from the proposal. Kept over late model results by the server.
  Future<void> edit(String field, String? value, {bool undo = false}) async {
    final connection = _connection;
    final current = state.reply?.fields;
    if (connection == null || current == null || _blocked) return;
    if (!undo) _undo.add((field: field, value: current.wire(field)));
    state = state.copyWith(
      pendingTurns: state.pendingTurns + 1,
      error: '',
      notice: '',
      canUndo: _undo.isNotEmpty,
    );
    await _request(() => connection.edit(field, value));
  }

  Future<void> undo() async {
    if (_undo.isEmpty || _blocked) return;
    final last = _undo.removeLast();
    state = state.copyWith(canUndo: _undo.isNotEmpty);
    await edit(last.field, last.value, undo: true);
  }

  bool get _blocked =>
      state.phase == SmartPhase.confirming ||
      state.phase == SmartPhase.handedOff;

  Future<void> _request(Future<SmartReply> Function() call) async {
    try {
      final reply = await call();
      if (!ref.mounted) return;
      state = state.copyWith(pendingTurns: state.pendingTurns - 1);
      await _apply(reply);
    } on SmartGatewayException catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        pendingTurns: state.pendingTurns - 1,
        phase: state.reply?.question != null
            ? SmartPhase.asking
            : state.proposal != null
            ? SmartPhase.proposal
            : SmartPhase.error,
        error: error.code == 'session_not_found'
            ? 'Phiên đặt lịch thông minh đã hết hạn. Vui lòng bắt đầu lại.'
            : error.message,
      );
    }
  }

  /// Applies a server reply unless a newer one was already applied.
  Future<void> _apply(SmartReply reply, {bool announce = true}) async {
    if (reply.status == SmartStatus.superseded ||
        reply.version < state.version) {
      if (state.phase == SmartPhase.processing && !state.processing) {
        state = state.copyWith(phase: _restingPhase);
      }
      return;
    }
    final messages = [...state.messages];
    if (announce && reply.notice != null) {
      messages.add(SmartMessage(fromUser: false, text: reply.notice!));
    }
    final lastAssistant = messages.where((m) => !m.fromUser).lastOrNull;
    if (announce &&
        reply.question != null &&
        reply.question!.text != lastAssistant?.text) {
      messages.add(SmartMessage(fromUser: false, text: reply.question!.text));
    }
    state = state.copyWith(
      reply: reply,
      version: reply.version,
      messages: messages,
      changed: reply.changed,
      slotQuestion: null,
      error: reply.errorMessage ?? '',
    );
    switch (reply.status) {
      case SmartStatus.urgent:
        await stopListening();
        state = state.copyWith(phase: SmartPhase.urgent, proposal: null);
      case SmartStatus.ready:
        await stopListening();
        await _buildProposal();
      case SmartStatus.ask || SmartStatus.fallback:
        if (reply.question != null) await stopListening();
        state = state.copyWith(
          phase: state.processing ? SmartPhase.processing : SmartPhase.asking,
          proposal: null,
        );
      case SmartStatus.superseded:
        break;
    }
  }

  // ---- Proposal ------------------------------------------------------------

  BookingDraft? _draftFromFields(SmartFields f) {
    if (f.patientId == null ||
        f.type == null ||
        f.facilityId == null ||
        f.departmentId == null) {
      return null;
    }
    return BookingDraft(
      id: _draftId,
      type: f.type,
      patientId: f.patientId,
      facilityId: f.facilityId,
      departmentId: f.departmentId,
      doctorMode: f.doctorId == null ? DoctorMode.any : DoctorMode.named,
      doctorId: f.doctorId,
      contactName: state.contactName,
      contactPhone: state.contactPhone,
    );
  }

  /// Earliest available slot matching the requested day/period, read from
  /// the booking repository (the stand-in for the hospital schedule).
  Future<BookingSlot?> _findSlot(BookingDraft base, SmartTime time) async {
    final dates = time.earliest
        ? BookingCatalog.dates(ref.read(bookingTodayProvider))
        : [time.date!];
    final repository = ref.read(bookingRepositoryProvider);
    for (final date in dates) {
      final slots = await repository.loadSlots(base.copyWith(date: date));
      for (final slot in slots) {
        if (!slot.available) continue;
        final afternoon = int.parse(slot.time.split(':').first) >= 12;
        if (time.period == 'morning' && afternoon) continue;
        if (time.period == 'afternoon' && !afternoon) continue;
        return slot;
      }
    }
    return null;
  }

  /// What to offer when [time] has no free slot: the other half of the same
  /// day when it still has room, then only the days that still have room.
  Future<SmartQuestion> _slotQuestion(BookingDraft base, SmartTime time) async {
    final repository = ref.read(bookingRepositoryProvider);
    final open = <DateTime, List<BookingSlot>>{};
    for (final date in BookingCatalog.dates(ref.read(bookingTodayProvider))) {
      final free = [
        for (final slot in await repository.loadSlots(
          base.copyWith(date: date),
        ))
          if (slot.available) slot,
      ];
      if (free.isNotEmpty) open[date] = free;
    }
    String iso(DateTime date) => date.toIso8601String().substring(0, 10);
    bool afternoon(BookingSlot slot) =>
        int.parse(slot.time.split(':').first) >= 12;
    final asked = time.earliest ? null : time.date;
    final options = <SmartOption>[];
    String text;
    if (asked != null && time.period != null && open[asked] != null) {
      final other = time.period == 'morning' ? 'afternoon' : 'morning';
      final (askedName, otherName) = time.period == 'morning'
          ? ('sáng', 'chiều')
          : ('chiều', 'sáng');
      text =
          'Buổi $askedName ${_dateLabel(asked)} đã kín. Buổi $otherName cùng ngày còn chỗ, hoặc bạn chọn ngày khác.';
      if (open[asked]!.any((s) => afternoon(s) == (other == 'afternoon'))) {
        options.add(
          SmartOption(
            'date:${iso(asked)}:$other',
            '${otherName[0].toUpperCase()}${otherName.substring(1)} ${_dateLabel(asked)}',
          ),
        );
      }
    } else if (asked != null) {
      text = '${_dateLabel(asked)} đã kín lịch. Bạn muốn khám khi nào?';
    } else if (open.isEmpty) {
      return const SmartQuestion(
        field: 'time',
        text: 'Không còn giờ trống trong 6 ngày tới. Bạn có thể đổi nơi khám, chuyên khoa hoặc bác sĩ.',
        options: [],
      );
    } else {
      text = 'Không còn giờ trống phù hợp với thời gian bạn chọn. Bạn muốn khám khi nào?';
    }
    options.addAll([
      if (open.isNotEmpty) const SmartOption('earliest', 'Sớm nhất còn chỗ'),
      for (final date in open.keys)
        if (date != asked) SmartOption('date:${iso(date)}', _dateLabel(date)),
    ]);
    return SmartQuestion(field: 'time', text: text, options: options);
  }

  Future<void> _buildProposal({String notice = ''}) async {
    final fields = state.reply?.fields;
    final base = fields == null ? null : _draftFromFields(fields);
    if (fields?.time == null || base == null) return;
    final run = ++_proposalRun;
    final version = state.version;
    state = state.copyWith(phase: SmartPhase.processing, proposal: null);
    try {
      final slot = await _findSlot(base, fields!.time!);
      if (!ref.mounted || run != _proposalRun || version != state.version) {
        return;
      }
      if (slot == null) {
        final question = await _slotQuestion(base, fields.time!);
        if (!ref.mounted || run != _proposalRun || version != state.version) {
          return;
        }
        state = state.copyWith(
          phase: SmartPhase.asking,
          // Said in the conversation too: the options alone do not tell the
          // user why the time they asked for was not proposed.
          messages: [
            ...state.messages,
            if (state.messages.lastOrNull?.text != question.text)
              SmartMessage(fromUser: false, text: question.text),
          ],
          slotQuestion: question,
          notice: fields.doctorId == null
              ? notice
              : 'Bạn cũng có thể đổi sang bác sĩ khác còn lịch.',
        );
        return;
      }
      final draft = base.copyWith(date: slot.date, slot: slot);
      state = state.copyWith(
        phase: SmartPhase.proposal,
        proposal: SmartProposal(draft: draft, fee: BookingCatalog.fee(draft)),
        notice: notice,
      );
    } on BookingException catch (error) {
      if (!ref.mounted || run != _proposalRun) return;
      state = state.copyWith(phase: SmartPhase.error, error: error.message);
    }
  }

  Future<void> retryProposal() => _buildProposal();

  /// Picks another free time on the proposed day without changing the request.
  void chooseSlot(BookingSlot slot) {
    final proposal = state.proposal;
    if (proposal == null || _blocked || !slot.available) return;
    final draft = proposal.draft.copyWith(date: slot.date, slot: slot);
    state = state.copyWith(
      proposal: SmartProposal(draft: draft, fee: BookingCatalog.fee(draft)),
      changed: const ['time'],
    );
  }

  Future<List<BookingSlot>> slotsFor(DateTime date) async {
    final proposal = state.proposal;
    if (proposal == null) return const [];
    return ref
        .read(bookingRepositoryProvider)
        .loadSlots(proposal.draft.copyWith(date: date, slot: null));
  }

  void setContact({String? name, String? phone}) {
    state = state.copyWith(contactName: name, contactPhone: phone);
  }

  /// SS06: re-check eligibility, slot and fee, then hand the draft to the
  /// existing payment step in one atomic update. The model has no part here.
  Future<BookingHandoff?> confirm() async {
    final proposal = state.proposal;
    if (!state.canConfirm || proposal == null) {
      if (!state.contactValid) {
        state = state.copyWith(
          error: 'Kiểm tra tên người nhận thông báo và số điện thoại 10 chữ số, bắt đầu bằng 0.',
        );
      }
      return null;
    }
    final draft = proposal.draft.copyWith(
      contactName: state.contactName.trim(),
      contactPhone: state.contactPhone.trim(),
    );
    state = state.copyWith(phase: SmartPhase.confirming, error: '');
    final version = state.version;
    final patient = ref
        .read(profileCatalogProvider)
        .where((p) => p.id == draft.patientId)
        .firstOrNull;
    final maxAge = BookingCatalog.department(draft.departmentId!).maxAge;
    final ageOk =
        patient != null &&
        (maxAge == null ||
            profileAge(patient, ref.read(bookingTodayProvider)) <= maxAge);
    bool valid;
    try {
      valid =
          ageOk &&
          await ref.read(bookingRepositoryProvider).validateSlot(draft);
    } on Exception {
      if (!ref.mounted) return null;
      state = state.copyWith(
        phase: SmartPhase.proposal,
        error: 'Chưa kiểm tra được giờ khám. Vui lòng thử lại.',
      );
      return null;
    }
    if (!ref.mounted) return null;
    if (version != state.version) {
      state = state.copyWith(phase: SmartPhase.proposal);
      return null;
    }
    if (!valid) {
      await _buildProposal(
        notice: 'Giờ đã chọn vừa hết chỗ. Mình đã đề xuất giờ khác, vui lòng kiểm tra và xác nhận lại.',
      );
      return null;
    }
    final fee = BookingCatalog.fee(draft);
    if (fee != proposal.fee) {
      state = state.copyWith(
        phase: SmartPhase.proposal,
        proposal: SmartProposal(draft: draft, fee: fee),
        notice:
            'Phí khám vừa thay đổi. Vui lòng kiểm tra lại trước khi tiếp tục.',
      );
      return null;
    }
    await _finish();
    return BookingHandoff(draft, stage: BookingStage.payment);
  }

  /// AC16: hand valid choices to the basic flow; dependent choices that no
  /// longer fit are dropped by the same rules as manual booking.
  Future<BookingHandoff> toBasicFlow() async {
    final f = state.reply?.fields ?? const SmartFields();
    final facility = f.facilityId == null
        ? null
        : BookingCatalog.facility(f.facilityId!);
    final facilityOk =
        facility != null &&
        (f.type != VisitType.insurance || facility.acceptsInsurance);
    final departmentOk =
        facilityOk &&
        f.departmentId != null &&
        facility.departments.contains(f.departmentId);
    final proposal = state.proposal?.draft;
    final draft = BookingDraft(
      id: BookingController.newDraftId(),
      type: f.type,
      patientId: f.patientId,
      facilityId: facilityOk ? f.facilityId : null,
      departmentId: departmentOk ? f.departmentId : null,
      doctorMode: departmentOk
          ? (f.doctorId == null ? DoctorMode.any : DoctorMode.named)
          : null,
      doctorId: departmentOk ? f.doctorId : null,
      date: departmentOk ? proposal?.date : null,
      contactName: state.contactName,
      contactPhone: state.contactPhone,
    );
    await _finish();
    return BookingHandoff(draft);
  }

  Future<void> _finish() async {
    await stopListening();
    state = state.copyWith(phase: SmartPhase.handedOff);
    final connection = _connection;
    _connection = null;
    await _audio?.close();
    _audio = null;
    await connection?.close();
  }

  // ---- Voice ---------------------------------------------------------------

  Future<void> startListening() async {
    final connection = _connection;
    if (connection == null || state.micOn || _blocked) return;
    if (!state.voiceAvailable) {
      state = state.copyWith(
        notice: state.simulated
            ? 'Chế độ Mô phỏng AI chưa nhận giọng nói. Bạn có thể nhập tay hoặc chọn nhanh.'
            : 'Nhận giọng nói chưa sẵn sàng. Bạn có thể nhập tay hoặc chọn nhanh.',
      );
      return;
    }
    if (!await _device.ensurePermission()) {
      if (ref.mounted) {
        state = state.copyWith(
          notice: 'Chưa có quyền dùng micro. Bạn vẫn có thể nhập tay hoặc chọn nhanh.',
        );
      }
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: SmartPhase.connecting,
      micOn: true,
      partial: '',
      notice: '',
      error: '',
      listenSeconds: 0,
    );
    if (_audio == null) {
      _audio = connection.openAudio();
      _audioEvents = _audio!.events.listen(_onAudio);
    }
    _audio!.start();
  }

  Future<void> _beginCapture() async {
    try {
      final stream = await _device.start();
      if (!ref.mounted || !state.micOn) {
        await _device.stop();
        return;
      }
      _vad.reset();
      _capture = stream.listen((chunk) {
        _audio?.sendAudio(chunk);
        if (_vad.add(chunk)) _audio?.commit();
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (ref.mounted && state.micOn) {
          state = state.copyWith(listenSeconds: state.listenSeconds + 1);
        }
      });
      state = state.copyWith(phase: SmartPhase.listening);
    } on Exception {
      if (!ref.mounted) return;
      _audio?.stop();
      state = state.copyWith(
        micOn: false,
        phase: _restingPhase,
        notice: 'Không mở được micro. Bạn có thể nhập tay hoặc chọn nhanh.',
      );
    }
  }

  /// Optional "Xong lượt nói" for when silence detection is unsure.
  void finishTurn() {
    if (!state.micOn) return;
    _vad.reset();
    _audio?.commit();
  }

  Future<void> stopListening() async {
    if (!state.micOn) return;
    await _stopCapture();
    _audio?.stop();
    if (ref.mounted) {
      state = state.copyWith(micOn: false, partial: '', phase: _restingPhase);
    }
  }

  Future<void> _stopCapture() async {
    _ticker?.cancel();
    _ticker = null;
    await _capture?.cancel();
    _capture = null;
    await _device.stop();
  }

  SmartPhase get _restingPhase {
    if (state.phase == SmartPhase.urgent ||
        state.phase == SmartPhase.handedOff ||
        state.phase == SmartPhase.confirming) {
      return state.phase;
    }
    if (state.processing) return SmartPhase.processing;
    if (state.proposal != null) return SmartPhase.proposal;
    if (state.question != null) return SmartPhase.asking;
    return SmartPhase.ready;
  }

  Future<void> _onAudio(SmartAudioEvent event) async {
    if (!ref.mounted) return;
    switch (event) {
      case AudioReady():
        if (state.micOn) await _beginCapture();
      case TranscriptDelta(:final text):
        // Display only; never triggers processing (PRD §5.5).
        state = state.copyWith(partial: text);
      case TranscriptFinal(:final text):
        state = state.copyWith(
          partial: '',
          messages: [
            ...state.messages,
            SmartMessage(fromUser: true, text: text),
          ],
          pendingTurns: state.pendingTurns + 1,
          phase: SmartPhase.processing,
          // A new utterance makes any shown proposal stale.
          proposal: null,
        );
      case TurnResult(:final reply):
        state = state.copyWith(pendingTurns: state.pendingTurns - 1);
        await _apply(reply);
      case TurnEmpty():
        state = state.copyWith(
          partial: '',
          notice: 'Chưa nghe rõ. Bạn có thể nói lại hoặc nhập tay.',
        );
      case AudioWarning(:final reason, :final remainingSeconds):
        state = state.copyWith(
          notice: reason == 'session_ending'
              ? 'Micro sẽ dừng sau khoảng ${remainingSeconds ?? 15} giây do giới hạn phiên.'
              : 'Lượt nói đã đủ dài nên được gửi xử lý. Bạn có thể nói tiếp.',
        );
      case AudioStopped(:final reason):
        await _stopCapture();
        if (!ref.mounted) return;
        state = state.copyWith(
          micOn: false,
          partial: '',
          phase: _restingPhase,
          notice: switch (reason) {
            'session_limit' => 'Đã hết thời lượng nói của phiên này. Bạn có thể nhập tay hoặc chọn nhanh.',
            'closed' =>
              'Kết nối micro đã đóng. Phần chưa xử lý cần nói hoặc nhập lại.',
            _ => state.notice,
          },
        );
        if (reason == 'closed') {
          _audioEvents?.cancel();
          _audio = null;
        }
      case AudioError(:final message):
        await _stopCapture();
        if (!ref.mounted) return;
        state = state.copyWith(
          micOn: false,
          partial: '',
          phase: _restingPhase,
          notice: message,
        );
    }
  }
}

String _dateLabel(DateTime date) {
  const names = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ nhật',
  ];
  return '${names[date.weekday - 1]} ${date.day}/${date.month}';
}
