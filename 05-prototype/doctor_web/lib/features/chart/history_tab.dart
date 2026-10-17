import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';

/// Results sent earlier at this clinic, newest first.
class HistoryTab extends ConsumerWidget {
  const HistoryTab(this.patientId, {super.key});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider(patientId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => LoadError(
        e,
        onRetry: () => ref.invalidate(historyProvider(patientId)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Panel(
            child: EmptyState(
              icon: LucideIcons.history,
              title: 'Chưa có lần khám nào trước đây',
              text:
                  'Đây là lần đầu người bệnh khám tại phòng khám qua MedicApp.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final h in entries) ...[
              Panel(
                title: fmtDate(h.date),
                trailing: [
                  Text(
                    '${h.clinicName} · ${h.doctorName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyValue('Chẩn đoán', Text(h.diagnosisText)),
                    KeyValue(
                      'Đơn thuốc',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, item) in h.items.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: '${i + 1}. '),
                                    TextSpan(
                                      text: item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' · ${item.quantity} ${item.form}\n',
                                    ),
                                    TextSpan(
                                      text: [
                                        item.usageLine,
                                        if (item.note.isNotEmpty) item.note,
                                      ].join('. '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (h.advice.isNotEmpty)
                      KeyValue('Lời dặn', Text(h.advice)),
                    if (h.followUpDate != null)
                      KeyValue('Hẹn tái khám', Text(fmtDate(h.followUpDate!))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}
