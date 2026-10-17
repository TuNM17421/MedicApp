import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/result.dart';
import 'result_dialogs.dart';
import 'rx_sheet.dart';

/// "1", "0,5", "1,5": dose amounts as written on Vietnamese prescriptions.
String fmtAmount(num n) =>
    n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', ',');

/// Diagnosis written as "Gút (M10)" in the patient's conditions.
(String, String)? parseCondition(String text) {
  final m = RegExp(r'^(.+?)\s*\(([A-Za-z0-9.]+)\)$').firstMatch(text.trim());
  return m == null ? null : (m.group(2)!.toUpperCase(), m.group(1)!);
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum _Save { idle, saving, saved, failed }

/// The result being written: diagnosis, prescription, advice and follow-up.
/// Every change is saved as a draft shortly after; sending signs it.
class RxEditor extends ConsumerStatefulWidget {
  const RxEditor({super.key, required this.chart, required this.draft});
  final ChartData chart;
  final ResultDraft? draft;

  @override
  ConsumerState<RxEditor> createState() => _RxEditorState();
}

class _RxEditorState extends ConsumerState<RxEditor> {
  late final ClinicApi _api = ref.read(apiProvider);
  late final List<(String, String)> _diagnosis = [...?widget.draft?.diagnosis];
  late final List<EditableItem> _items = [
    for (final i in widget.draft?.items ?? const <PrescriptionItem>[])
      EditableItem.from(i),
  ];
  late final _advice = TextEditingController(text: widget.draft?.advice);
  late final _note = TextEditingController(text: widget.draft?.internalNote);
  late String? _followUp = widget.draft?.followUpDate;

  /// The item whose editor is open, or null.
  EditableItem? _open;

  Timer? _debounce;
  _Save _save = _Save.idle;
  DateTime? _savedAt;
  bool _again = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _savedAt = widget.draft?.updatedAt;
    if (_savedAt != null) _save = _Save.saved;
  }

  @override
  void dispose() {
    // Leaving the tab must not lose the last few keystrokes.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(
        _api
            .saveDraft(widget.chart.appointmentId, _body)
            .then((_) {}, onError: (_) {}),
      );
    }
    _advice.dispose();
    _note.dispose();
    super.dispose();
  }

  Json get _body => {
    'diagnosis': [
      for (final d in _diagnosis) [d.$1, d.$2],
    ],
    'items': [for (final i in _items) i.toItem().toJson()],
    'advice': _advice.text,
    'followUpDate': _followUp,
    'internalNote': _note.text,
  };

  void _changed([VoidCallback? change]) {
    setState(change ?? () {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _persist);
  }

  Future<void> _persist() async {
    if (_save == _Save.saving) {
      _again = true;
      return;
    }
    setState(() => _save = _Save.saving);
    try {
      final saved = await _api.saveDraft(widget.chart.appointmentId, _body);
      if (!mounted) return;
      setState(() {
        _save = _Save.saved;
        _savedAt = saved.updatedAt;
      });
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (mounted) setState(() => _save = _Save.failed);
    }
    if (_again && mounted) {
      _again = false;
      await _persist();
    }
  }

  /// Saves now, waiting for any save in flight.
  Future<bool> _flush() async {
    _debounce?.cancel();
    while (_save == _Save.saving) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _persist();
    return _save == _Save.saved;
  }

  List<String> get _problems => [
    if (_diagnosis.isEmpty) 'Chưa có chẩn đoán.',
    for (final (i, item) in _items.indexed)
      if (item.problems.isNotEmpty)
        'Thuốc ${i + 1}${item.name.isEmpty ? '' : ' (${item.title})'}: '
            '${item.problems.join(' ').toLowerCase()}',
  ];

  RxSheet _sheet(StaffSession session) => RxSheet.of(
    chart: widget.chart,
    session: session,
    diagnosis: _diagnosis,
    items: [
      for (final i in _items)
        if (i.problems.isEmpty) i.toItem(),
    ],
    advice: _advice.text,
    followUpDate: _followUp,
  );

  Future<void> _send(StaffSession session) async {
    final ok = await showSendDialog(
      context,
      sheet: _sheet(session),
      amendment: (widget.draft?.version ?? 1) > 1,
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      if (!await _flush()) {
        throw const ApiException(0, 'save', 'Chưa lưu được bản nháp.');
      }
      await _api.sendResult(widget.chart.appointmentId);
      final id = widget.chart.appointmentId;
      ref.invalidate(resultProvider(id));
      ref.invalidate(chartProvider(id));
      ref.invalidate(worklistProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi kết quả cho người bệnh.')),
        );
      }
    } on ApiException catch (e) {
      if (e.unauthenticated) ref.read(sessionProvider.notifier).expired();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reuse(HistoryEntry last) => _changed(() {
    for (final item in last.items) {
      _items.add(
        EditableItem.from(item)
          ..quantityManual = false
          ..recompute(),
      );
    }
    _open = null;
  });

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final catalog = ref.watch(catalogProvider).value ?? const Catalog([], []);
    final draft = widget.draft;
    final problems = _problems;
    final last = widget.chart.lastVisit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draft != null && draft.version > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Note(
              icon: LucideIcons.filePen,
              tone: Tone.warn,
              text:
                  'Đang sửa kết quả đã gửi (bản ${draft.version}). '
                  'Lý do: ${draft.amendReason ?? ''}. Người bệnh vẫn thấy bản '
                  'trước cho tới khi bạn gửi bản này.',
            ),
          ),
        Panel(
          title: 'Chẩn đoán',
          child: _DiagnosisField(
            value: _diagnosis,
            catalog: catalog.icd10,
            suggestions: [
              for (final c in widget.chart.patient.conditions)
                ?parseCondition(c),
            ],
            onAdd: (d) => _changed(() {
              if (!_diagnosis.any((x) => x.$1 == d.$1)) _diagnosis.add(d);
            }),
            onRemove: (d) => _changed(() => _diagnosis.remove(d)),
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Đơn thuốc',
          trailing: [if (_items.isNotEmpty) Tag('${_items.length} thuốc')],
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Chưa kê thuốc. Đơn không có thuốc vẫn gửi được.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final (i, item) in _items.indexed)
                _open == item
                    ? _ItemEditor(
                        key: ObjectKey(item),
                        index: i,
                        item: item,
                        drugs: catalog.drugs,
                        onChanged: () => _changed(),
                        onDone: () => setState(() => _open = null),
                        onRemove: () => _changed(() {
                          _items.remove(item);
                          _open = null;
                        }),
                      )
                    : _ItemRow(
                        index: i,
                        item: item,
                        onEdit: () => setState(() => _open = item),
                        onRemove: () => _changed(() => _items.remove(item)),
                      ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _changed(() {
                      final item = EditableItem();
                      _items.add(item);
                      _open = item;
                    }),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Thêm thuốc'),
                  ),
                  if (last != null && last.items.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _reuse(last),
                      icon: const Icon(LucideIcons.copy, size: 16),
                      label: Text('Dùng lại đơn ${fmtDate(last.date)}'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Lời dặn và hẹn tái khám',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _advice,
                minLines: 2,
                maxLines: 6,
                maxLength: 2000,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Lời dặn',
                  hintText: 'Mỗi dòng một ý, in đúng như vậy trên đơn.',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Hẹn tái khám',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 6),
              _FollowUpPicker(
                from: widget.chart.now,
                value: _followUp,
                onChanged: (v) => _changed(() => _followUp = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Ghi chú nội bộ',
                  helperText:
                      'Chỉ phòng khám xem. Không in, không gửi người bệnh.',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ActionBar(
          save: _save,
          savedAt: _savedAt,
          problems: problems,
          sending: _sending,
          amendment: (draft?.version ?? 1) > 1,
          onRetrySave: _persist,
          onPreview: session == null
              ? null
              : () => showRxPreview(context, _sheet(session)),
          onSend: session == null || problems.isNotEmpty || _sending
              ? null
              : () => _send(session),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.tone, required this.text});
  final IconData icon;
  final Tone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final (bg, fg) = switch (tone) {
      Tone.warn => (c.partSoft, c.partInk),
      Tone.danger => (c.missSoft, c.missInk),
      Tone.ok => (c.okSoft, c.okInk),
      _ => (c.surface2, c.fg2),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Dw.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisField extends StatelessWidget {
  const _DiagnosisField({
    required this.value,
    required this.catalog,
    required this.suggestions,
    required this.onAdd,
    required this.onRemove,
  });
  final List<(String, String)> value;
  final List<(String, String)> catalog;
  final List<(String, String)> suggestions;
  final ValueChanged<(String, String)> onAdd, onRemove;

  @override
  Widget build(BuildContext context) {
    final quick = suggestions
        .where((s) => !value.any((v) => v.$1 == s.$1))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in value)
                  InputChip(
                    label: Text('${d.$2} (${d.$1})'),
                    onDeleted: () => onRemove(d),
                    deleteButtonTooltipMessage: 'Bỏ chẩn đoán',
                  ),
              ],
            ),
          ),
        Autocomplete<(String, String)>(
          displayStringForOption: (d) => '${d.$1} · ${d.$2}',
          optionsBuilder: (text) {
            final q = text.text.trim().toLowerCase();
            if (q.isEmpty) return const [];
            return catalog
                .where(
                  (d) =>
                      d.$1.toLowerCase().startsWith(q) ||
                      d.$2.toLowerCase().contains(q),
                )
                .take(8);
          },
          onSelected: onAdd,
          fieldViewBuilder: (context, controller, focus, submit) => TextField(
            controller: controller,
            focusNode: focus,
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              prefixIcon: Icon(LucideIcons.search, size: 16),
              hintText: 'Tìm theo mã ICD-10 hoặc tên bệnh',
            ),
          ),
          optionsViewBuilder: (context, select, options) => _Options(
            options: options,
            select: select,
            label: (d) => (d.$1, d.$2),
          ),
        ),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Bệnh đang theo dõi:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final s in quick)
                ActionChip(
                  avatar: const Icon(LucideIcons.plus, size: 14),
                  label: Text('${s.$2} (${s.$1})'),
                  onPressed: () => onAdd(s),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Dropdown list for the two search fields.
class _Options<T extends Object> extends StatelessWidget {
  const _Options({
    required this.options,
    required this.select,
    required this.label,
  });
  final Iterable<T> options;
  final AutocompleteOnSelected<T> select;
  final (String, String) Function(T) label;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: c.surface,
        borderRadius: BorderRadius.circular(Dw.radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            children: [
              for (final o in options)
                InkWell(
                  onTap: () => select(o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            label(o).$1,
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 13,
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                        Expanded(child: Text(label(o).$2)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A medicine as it will print, with edit and remove.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.onEdit,
    required this.onRemove,
  });
  final int index;
  final EditableItem item;
  final VoidCallback onEdit, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final problems = item.problems;
    final usage = [
      item.usageLine,
      if (item.note.trim().isNotEmpty) item.note.trim(),
    ].where((s) => s.isNotEmpty).join('. ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: problems.isEmpty ? c.line : c.part),
        borderRadius: BorderRadius.circular(Dw.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}.',
              style: TextStyle(color: c.muted, fontFeatures: tabular),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.name.isEmpty ? 'Chưa chọn thuốc' : item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.quantity != null)
                      Text(
                        'SL: ${item.quantity} ${item.form}',
                        style: TextStyle(color: c.fg2, fontFeatures: tabular),
                      ),
                    if (item.days != null)
                      Text(
                        '${item.days} ngày',
                        style: TextStyle(color: c.fg2, fontFeatures: tabular),
                      ),
                  ],
                ),
                if (usage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(usage, style: TextStyle(color: c.fg2)),
                  ),
                if (problems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      problems.join(' '),
                      style: TextStyle(color: c.partInk, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sửa thuốc',
            onPressed: onEdit,
            icon: const Icon(LucideIcons.pencil, size: 16),
          ),
          IconButton(
            tooltip: 'Bỏ thuốc',
            onPressed: onRemove,
            icon: const Icon(LucideIcons.trash2, size: 16),
          ),
        ],
      ),
    );
  }
}

/// Inline editor for one medicine: name from the catalog, dose per time of
/// day, meal timing, days, quantity (auto from dose × days) and a note.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    super.key,
    required this.index,
    required this.item,
    required this.drugs,
    required this.onChanged,
    required this.onDone,
    required this.onRemove,
  });
  final int index;
  final EditableItem item;
  final List<CatalogDrug> drugs;
  final VoidCallback onChanged, onDone, onRemove;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  EditableItem get item => widget.item;
  late final _strength = TextEditingController(text: item.strength);
  late final _days = TextEditingController(
    text: _dayChoices.contains(item.days) ? '' : item.days?.toString(),
  );
  late final _quantity = TextEditingController(text: item.quantity?.toString());
  late final _note = TextEditingController(text: item.note);

  static const _dayChoices = [5, 7, 14, 28, 30];

  @override
  void dispose() {
    _strength.dispose();
    _days.dispose();
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    change();
    item.recompute();
    if (!item.quantityManual) {
      _quantity.text = item.quantity?.toString() ?? '';
    }
    widget.onChanged();
  }

  void _step(DoseSlot slot, num delta) => _update(() {
    final next = ((item.amounts[slot] ?? 0) + delta).clamp(0, 10);
    item.amounts[slot] = next % 1 == 0 ? next.toInt() : next;
  });

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final text = Theme.of(context).textTheme;
    final preview = RxSheet.usage(item.toItem());

    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s, style: text.labelSmall),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.brand),
        borderRadius: BorderRadius.circular(Dw.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Thuốc ${widget.index + 1}', style: text.titleSmall),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final name = Autocomplete<CatalogDrug>(
                initialValue: TextEditingValue(text: item.name),
                displayStringForOption: (d) => d.name,
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return const [];
                  return widget.drugs
                      .where((d) => d.title.toLowerCase().contains(q))
                      .take(8);
                },
                onSelected: (d) => _update(() {
                  item
                    ..name = d.name
                    ..strength = d.strength
                    ..form = d.form
                    ..route = d.route;
                  _strength.text = d.strength;
                }),
                fieldViewBuilder: (context, controller, focus, submit) =>
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      autofocus: item.name.isEmpty,
                      onChanged: (v) => _update(() => item.name = v),
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Tên thuốc',
                        prefixIcon: Icon(LucideIcons.search, size: 16),
                      ),
                    ),
                optionsViewBuilder: (context, select, options) => _Options(
                  options: options,
                  select: select,
                  label: (d) => (d.form, d.title),
                ),
              );
              final strength = TextField(
                controller: _strength,
                onChanged: (v) => _update(() => item.strength = v),
                decoration: const InputDecoration(labelText: 'Hàm lượng'),
              );
              if (box.maxWidth < 520) {
                return Column(
                  children: [name, const SizedBox(height: 10), strength],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: name),
                  const SizedBox(width: 10),
                  Expanded(child: strength),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          label('Liều mỗi lần (${item.form})'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in DoseSlot.values)
                _DoseStepper(
                  slot: slot,
                  amount: item.amounts[slot] ?? 0,
                  onStep: (d) => _step(slot, d),
                ),
            ],
          ),
          const SizedBox(height: 14),
          label('Thời điểm uống'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in [
                MealTiming.before,
                MealTiming.after,
                MealTiming.any,
              ])
                ChoiceChip(
                  label: Text(switch (m) {
                    MealTiming.before => 'Trước ăn',
                    MealTiming.after => 'Sau ăn',
                    MealTiming.any => 'Không phụ thuộc bữa ăn',
                  }),
                  selected: item.meal == m,
                  onSelected: (_) => _update(() => item.meal = m),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Số ngày'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final d in _dayChoices)
                        ChoiceChip(
                          label: Text('$d'),
                          selected: item.days == d,
                          onSelected: (_) => _update(() {
                            item.days = d;
                            _days.clear();
                          }),
                        ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _days,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          onChanged: (v) =>
                              _update(() => item.days = int.tryParse(v)),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Khác',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(
                    item.quantityManual
                        ? 'Số lượng (đã sửa tay)'
                        : 'Số lượng (tự tính: liều × ngày)',
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: _quantity,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          onChanged: (v) => _update(() {
                            item
                              ..quantity = int.tryParse(v)
                              ..quantityManual = v.isNotEmpty;
                          }),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: item.form,
                          ),
                        ),
                      ),
                      if (item.quantityManual)
                        TextButton(
                          onPressed: () =>
                              _update(() => item.quantityManual = false),
                          child: const Text('Tự tính lại'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLength: 300,
            onChanged: (v) => _update(() => item.note = v),
            decoration: const InputDecoration(
              labelText: 'Ghi chú cách dùng',
              hintText: 'Ví dụ: Uống nhiều nước. Ngưng khi hết đau.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(Dw.radius),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Trên đơn: ',
                    style: TextStyle(color: c.muted),
                  ),
                  TextSpan(
                    text: item.name.isEmpty ? '…' : item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (item.quantity != null)
                    TextSpan(text: '   ${item.quantity} ${item.form}'),
                  TextSpan(
                    text: item.doses.isEmpty
                        ? '\nChưa chọn liều.'
                        : '\n$preview',
                  ),
                ],
              ),
            ),
          ),
          if (item.problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Còn thiếu: ${item.problems.join(' ')}',
                style: TextStyle(color: c.partInk, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: widget.onRemove,
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: const Text('Bỏ thuốc này'),
              ),
              const Spacer(),
              FilledButton(onPressed: widget.onDone, child: const Text('Xong')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoseStepper extends StatelessWidget {
  const _DoseStepper({
    required this.slot,
    required this.amount,
    required this.onStep,
  });
  final DoseSlot slot;
  final num amount;
  final ValueChanged<num> onStep;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final on = amount > 0;
    return Semantics(
      label: '${slot.label}: ${fmtAmount(amount)}',
      child: Container(
        decoration: BoxDecoration(
          color: on ? c.brandSoft : c.surface,
          border: Border.all(color: on ? c.brand : c.line),
          borderRadius: BorderRadius.circular(Dw.radius),
        ),
        padding: const EdgeInsets.only(left: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              child: Text(
                slot.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: on ? c.brandInk : c.fg2,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Bớt ${slot.label.toLowerCase()}',
              visualDensity: VisualDensity.compact,
              onPressed: amount > 0 ? () => onStep(-0.5) : null,
              icon: const Icon(LucideIcons.minus, size: 14),
            ),
            SizedBox(
              width: 28,
              child: Text(
                fmtAmount(amount),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Thêm ${slot.label.toLowerCase()}',
              visualDensity: VisualDensity.compact,
              // A whole tablet first; halves from the stepper after that.
              onPressed: amount < 10
                  ? () => onStep(amount == 0 ? 1 : 0.5)
                  : null,
              icon: const Icon(LucideIcons.plus, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpPicker extends StatelessWidget {
  const _FollowUpPicker({
    required this.from,
    required this.value,
    required this.onChanged,
  });
  final DateTime from;
  final String? value;
  final ValueChanged<String?> onChanged;

  static const _weeks = [1, 2, 4, 12];

  @override
  Widget build(BuildContext context) {
    final day = DateTime(from.year, from.month, from.day);
    final presets = {
      for (final w in _weeks) _iso(day.add(Duration(days: 7 * w))): w,
    };
    final custom = value != null && !presets.containsKey(value);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Không hẹn'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final MapEntry(key: iso, value: w) in presets.entries)
          ChoiceChip(
            label: Text('$w tuần (${fmtShort(iso)})'),
            selected: value == iso,
            onSelected: (_) => onChanged(iso),
          ),
        ChoiceChip(
          avatar: const Icon(LucideIcons.calendar, size: 14),
          label: Text(custom ? fmtDate(value!) : 'Chọn ngày'),
          selected: custom,
          onSelected: (_) async {
            final picked = await showDatePicker(
              context: context,
              firstDate: day.add(const Duration(days: 1)),
              lastDate: day.add(const Duration(days: 366)),
              initialDate: custom
                  ? DateTime.parse(value!)
                  : day.add(const Duration(days: 14)),
            );
            if (picked != null) onChanged(_iso(picked));
          },
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.save,
    required this.savedAt,
    required this.problems,
    required this.sending,
    required this.amendment,
    required this.onRetrySave,
    required this.onPreview,
    required this.onSend,
  });
  final _Save save;
  final DateTime? savedAt;
  final List<String> problems;
  final bool sending, amendment;
  final VoidCallback onRetrySave;
  final VoidCallback? onPreview, onSend;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final status = switch (save) {
      _Save.idle => const Text('Bản nháp chưa lưu.'),
      _Save.saving => const Text('Đang lưu nháp…'),
      _Save.saved => Text(
        'Đã lưu nháp lúc ${savedAt == null ? '' : fmtClock(savedAt!)}.',
      ),
      _Save.failed => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Chưa lưu được nháp.', style: TextStyle(color: c.missInk)),
          TextButton(onPressed: onRetrySave, child: const Text('Lưu lại')),
        ],
      ),
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problems.isNotEmpty) ...[
            _Note(
              icon: LucideIcons.circleAlert,
              tone: Tone.warn,
              text: 'Chưa gửi được: ${problems.join(' ')}',
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(color: c.muted, fontSize: 13),
                child: status,
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPreview,
                    icon: const Icon(LucideIcons.fileText, size: 16),
                    label: const Text('Xem đơn theo mẫu'),
                  ),
                  FilledButton.icon(
                    onPressed: onSend,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.send, size: 16),
                    label: Text(
                      amendment ? 'Gửi bản sửa' : 'Ký và gửi kết quả',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
