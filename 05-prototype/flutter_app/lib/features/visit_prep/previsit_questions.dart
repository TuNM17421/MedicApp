import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_widgets.dart';
import '../sharing/application/sharing_providers.dart';
import '../sharing/domain/sharing_models.dart';
import 'visit_prep.dart';

/// The questions asked before a clinic visit (bước 16), the same ones the
/// doctor's summary quotes. Ids are stable so a new answer replaces the
/// clinic's copy instead of adding one.
const preVisitQuestions = [
  (id: 'pre_visit.chief', text: 'Lần này bạn đi khám vì điều gì?'),
  (id: 'pre_visit.course', text: 'Bệnh nặng hơn hay nhẹ hơn so với trước?'),
  (id: 'pre_visit.self_meds', text: 'Bạn đã tự dùng thuốc gì chưa?'),
  (id: 'pre_visit.ask', text: 'Bạn muốn hỏi bác sĩ điều gì?'),
];

/// On a clinic appointment: a few questions answered at home, sent only
/// while the person shares "Câu trả lời trước khám" for this visit.
class PreVisitQuestionsSection extends ConsumerWidget {
  const PreVisitQuestionsSection({super.key, required this.visitId});
  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointment = ref.watch(serverAppointmentProvider(visitId));
    if (appointment == null || appointment.cancelled) {
      return const SizedBox.shrink();
    }
    final answers = ref.watch(intakeAnswersProvider)[visitId] ?? const [];
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppSurface(
        key: const Key('pre-visit-questions'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconTile(icon: AppIcons.prep, tone: AppTone.peach),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Câu hỏi trước khám', style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Trả lời vài câu để bác sĩ nắm trước. Câu trả lời chỉ gửi đi '
              'khi bạn chọn chia sẻ với phòng khám.',
              style: text.bodyLarge,
            ),
            for (final answer in answers) ...[
              const Divider(height: 24),
              Text(answer.question, style: text.bodySmall),
              const SizedBox(height: 4),
              Text(answer.answer, style: text.titleMedium),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('pre-visit-answer'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                useRootNavigator: true,
                showDragHandle: true,
                sheetAnimationStyle: AnimationStyle(
                  duration: AppMotion.duration(context),
                  reverseDuration: AppMotion.duration(context),
                ),
                builder: (_) => PreVisitAnswersSheet(visitId: visitId),
              ),
              child: Text(
                answers.isEmpty ? 'Trả lời câu hỏi' : 'Sửa câu trả lời',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PreVisitAnswersSheet extends ConsumerStatefulWidget {
  const PreVisitAnswersSheet({super.key, required this.visitId});
  final String visitId;

  @override
  ConsumerState<PreVisitAnswersSheet> createState() =>
      _PreVisitAnswersSheetState();
}

class _PreVisitAnswersSheetState extends ConsumerState<PreVisitAnswersSheet> {
  late final List<IntakeAnswer> _saved =
      ref.read(intakeAnswersProvider)[widget.visitId] ?? const [];
  late final _fields = [
    for (final question in preVisitQuestions)
      TextEditingController(
        text: _saved
            .where((answer) => answer.id == question.id)
            .firstOrNull
            ?.answer,
      ),
  ];

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _save() {
    final now = ref.read(prepClockProvider)();
    final answers = [
      for (final (index, question) in preVisitQuestions.indexed)
        if (_fields[index].text.trim() case final answer when answer.isNotEmpty)
          switch (_saved.where((saved) => saved.id == question.id)) {
            final previous
                when previous.isNotEmpty && previous.first.answer == answer =>
              previous.first,
            _ => IntakeAnswer(
              id: question.id,
              channel: IntakeChannel.preVisit,
              question: question.text,
              answer: answer,
              answeredAt: now,
            ),
          },
    ];
    ref.read(intakeAnswersProvider.notifier).save(widget.visitId, answers);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Câu hỏi trước khám', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Trả lời ngắn gọn bằng lời của bạn. Câu nào chưa muốn trả lời '
              'thì để trống.',
              style: text.bodyLarge,
            ),
            for (final (index, question) in preVisitQuestions.indexed) ...[
              const SizedBox(height: 20),
              TextField(
                key: Key('pre-visit-field-$index'),
                controller: _fields[index],
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                style: text.titleMedium,
                decoration: InputDecoration(
                  labelText: question.text,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 20),
            AppPrimaryButton(
              key: const Key('pre-visit-save'),
              label: 'Lưu câu trả lời',
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
