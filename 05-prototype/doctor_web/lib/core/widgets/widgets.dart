import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';

String fmtDate(String iso) =>
    '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
String fmtShort(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}';
String fmtDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String fmtClock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String initials(String name) => name
    .split(' ')
    .where((w) => w.isNotEmpty)
    .toList()
    .reversed
    .take(2)
    .toList()
    .reversed
    .map((w) => w[0])
    .join()
    .toUpperCase();

/// Tabular figures, so times and percentages line up in columns.
const tabular = [FontFeature.tabularFigures()];

enum Tone { neutral, brand, ok, warn, danger, ai, pt }

({Color bg, Color fg}) toneColors(DwColors c, Tone tone) => switch (tone) {
  Tone.neutral => (bg: c.surface3, fg: c.fg2),
  Tone.brand => (bg: c.brandSoft, fg: c.brandInk),
  Tone.ok => (bg: c.okSoft, fg: c.okInk),
  Tone.warn => (bg: c.partSoft, fg: c.partInk),
  Tone.danger => (bg: c.missSoft, fg: c.missInk),
  Tone.ai => (bg: c.aiSoft, fg: c.ai),
  Tone.pt => (bg: c.ptSoft, fg: c.pt),
};

/// A small pill with an icon and a label. Never colour alone.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.tone = Tone.neutral});
  final String label;
  final IconData? icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = toneColors(DwColors.of(context), tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: t.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a piece of information comes from.
enum Source {
  ai('AI tóm tắt', LucideIcons.sparkles, Tone.ai),
  app('Dữ liệu app', LucideIcons.database, Tone.brand),
  patient('Người bệnh nhập', LucideIcons.pencil, Tone.pt);

  const Source(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final Tone tone;
}

class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {super.key});
  final Source source;

  @override
  Widget build(BuildContext context) =>
      Tag(source.label, icon: source.icon, tone: source.tone);
}

Widget statusTag(VisitStatus status, {ResultStatus? result}) {
  if (result == ResultStatus.sent) {
    return const Tag(
      'Đã gửi kết quả',
      icon: LucideIcons.circleCheck,
      tone: Tone.ok,
    );
  }
  return switch (status) {
    VisitStatus.booked => Tag(
      status.label,
      icon: LucideIcons.clock,
      tone: Tone.neutral,
    ),
    VisitStatus.arrived => Tag(
      status.label,
      icon: LucideIcons.userCheck,
      tone: Tone.warn,
    ),
    VisitStatus.inProgress => Tag(
      status.label,
      icon: LucideIcons.stethoscope,
      tone: Tone.brand,
    ),
    VisitStatus.done => Tag(
      status.label,
      icon: LucideIcons.check,
      tone: Tone.neutral,
    ),
    VisitStatus.cancelled => Tag(
      status.label,
      icon: LucideIcons.x,
      tone: Tone.neutral,
    ),
  };
}

Widget summaryTag(
  ConsentState consent, {
  required bool has,
  bool flagged = false,
}) {
  if (consent == ConsentState.shared && flagged) {
    return const Tag(
      'Có câu cần chú ý',
      icon: LucideIcons.triangleAlert,
      tone: Tone.danger,
    );
  }
  if (consent == ConsentState.shared && has) {
    return const Tag('Có tóm tắt', icon: LucideIcons.fileText, tone: Tone.ai);
  }
  if (consent == ConsentState.declined) {
    return const Tag('Không chia sẻ', icon: LucideIcons.eyeOff);
  }
  return const Tag('Chưa có', icon: LucideIcons.hourglass);
}

/// A white panel with an optional header row.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.trailing = const [],
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.all(16),
  });
  final String? title;
  final List<Widget> trailing;
  final Widget child;
  final Widget? footer;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Dw.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  ...trailing,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
          if (footer != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 28, color: c.muted),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Label above a value, as in the prototype's key-value lists.
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key});
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14),
          child: value,
        ),
      ],
    ),
  );
}

/// Shown while a request runs or after it failed, with a retry.
class LoadError extends StatelessWidget {
  const LoadError(this.error, {super.key, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(
            icon: LucideIcons.cloudOff,
            title: 'Chưa tải được dữ liệu',
            text: error is ApiException
                ? (error as ApiException).message
                : 'Kiểm tra kết nối rồi thử lại.',
          ),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}
