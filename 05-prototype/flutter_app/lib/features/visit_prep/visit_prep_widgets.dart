import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import 'visit_prep.dart';
import 'visit_prep_catalog.dart';

const prepDisclaimer =
    'Lưu ý tự động từ hồ sơ của bạn, chỉ để tham khảo. Nếu cơ sở khám dặn '
    'khác, hãy làm theo cơ sở khám.';

/// Full preparation for one appointment, shown on its detail page.
class VisitPrepSection extends ConsumerWidget {
  const VisitPrepSection({super.key, required this.visitId});
  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref
        .watch(visitPrepNotesProvider)
        .where((note) => note.visitId == visitId)
        .toList();
    if (notes.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(
      key: const Key('visit-prep'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Chuẩn bị trước khi khám', style: text.titleLarge),
        ),
        const SizedBox(height: 12),
        for (final note in notes) ...[
          _NoteCard(note: note),
          const SizedBox(height: 12),
        ],
        Text(prepDisclaimer, style: text.bodySmall),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final VisitPrepNote note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final warn = AppTokens.of(context).tone(AppTone.warning);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(icon: AppIcons.prep, tone: AppTone.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _capital(note.condition.visitLabel),
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(note.headline, style: text.bodyLarge),
          const Divider(),
          for (final item in note.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AppIcon(
                      item.important ? AppIcons.clock : AppIcons.check,
                      size: 22,
                      color: item.important
                          ? warn.foreground
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: item.important
                          ? text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            )
                          : text.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Nguồn: ${note.condition.sources.map((s) => s.title).join('; ')}',
            style: text.bodySmall?.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

String _capital(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

/// The soonest note, at the top of Home.
class HomePrepBanner extends ConsumerWidget {
  const HomePrepBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(visitPrepNotesProvider);
    if (notes.isEmpty) return const SizedBox.shrink();
    final note = notes.first;
    final colors = AppTokens.of(context).tone(AppTone.warning);
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppTokens.of(context).cardRadius);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        key: const Key('home-prep'),
        color: colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.foreground, width: 1.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () => context.push(AppRoutes.appointment(note.visitId)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(AppIcons.prep, color: colors.foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lưu ý trước khi khám',
                        style: text.titleMedium?.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note.headline,
                  style: text.bodyLarge?.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Xem cách chuẩn bị',
                  style: text.labelLarge?.copyWith(color: AppColors.primary),
                ),
                if (notes.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Còn ${notes.length - 1} lưu ý khác trong Lịch hẹn.',
                    style: text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user say which conditions a profile is followed for.
class ProfileConditionsEditor extends StatelessWidget {
  const ProfileConditionsEditor({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bệnh đang theo dõi', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Dùng để nhắc cách chuẩn bị trước mỗi lần khám, như nhịn ăn hay '
            'kiêng rượu bia. Chọn tất cả bệnh phù hợp.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          AppChoiceGrid(
            minItemWidth: 150,
            children: [
              for (final condition in VisitPrepCatalog.conditions)
                AppSelectionChip(
                  key: ValueKey('condition-${condition.id}'),
                  label: VisitPrepCatalog.label(condition),
                  selected: selected.contains(condition.id),
                  onTap: () => onChanged(
                    selected.contains(condition.id)
                        ? [
                            for (final id in selected)
                              if (id != condition.id) id,
                          ]
                        : [...selected, condition.id],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
