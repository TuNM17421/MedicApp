import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:medic_core/medic_core.dart';

import '../../app/theme.dart';
import '../widgets/widgets.dart';

/// Colour, glyph and label of one day in the 30-day strip.
({Color color, Color ink, String glyph, String label}) dayStyle(
  DwColors c,
  DayStatus status,
) => switch (status) {
  DayStatus.taken => (
    color: c.ok,
    ink: Colors.white,
    glyph: '✓',
    label: 'Đã uống',
  ),
  DayStatus.partial => (
    color: c.part,
    ink: Colors.white,
    glyph: '½',
    label: 'Uống thiếu liều',
  ),
  DayStatus.missed => (
    color: c.miss,
    ink: Colors.white,
    glyph: '×',
    label: 'Không uống',
  ),
  DayStatus.none => (
    color: c.surface3,
    ink: c.muted,
    glyph: '',
    label: 'Không có liều',
  ),
};

/// One cell per day; the glyph repeats what the colour says so the strip
/// reads without colour. Hover or long-press shows the day's detail.
class DoseStrip extends StatelessWidget {
  const DoseStrip(this.adherence, {super.key});
  final CourseAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final days = adherence.days;
    return Semantics(
      label:
          '${adherence.course.item.title}: ${adherence.takenDoses} trên '
          '${adherence.dueDoses} liều đã uống trong ${days.length} ngày',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 26,
              child: Row(
                children: [
                  for (final (i, day) in days.indexed)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i == days.length - 1 ? 0 : 2,
                        ),
                        child: _Cell(day, dayStyle(c, day.status)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: LayoutBuilder(
                builder: (context, box) {
                  final cell = box.maxWidth / days.length;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final (i, day) in days.indexed)
                        if (i % 7 == 0)
                          Positioned(
                            left: i * cell,
                            top: 0,
                            child: Text(
                              fmtShort(day.day),
                              style: TextStyle(
                                fontSize: 11,
                                color: c.muted,
                                fontFeatures: tabular,
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.day, this.style);
  final DayAdherence day;
  final ({Color color, Color ink, String glyph, String label}) style;

  @override
  Widget build(BuildContext context) {
    final reasons = {
      for (final r in day.missedReasons) r?.label ?? unrecordedLabel,
    };
    final detail = [
      '${fmtDate(day.day)}: ${style.label}',
      if (day.due > 0) '${day.taken}/${day.due} liều',
      if (reasons.isNotEmpty) reasons.join(', '),
    ].join(' · ');
    return Tooltip(
      message: detail,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: style.color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: switch (day.status) {
          DayStatus.taken => Icon(
            LucideIcons.check,
            size: 14,
            color: style.ink,
          ),
          DayStatus.missed => Icon(LucideIcons.x, size: 14, color: style.ink),
          _ => FittedBox(
            child: Text(
              style.glyph,
              style: TextStyle(
                color: style.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        },
      ),
    );
  }
}

/// Legend for the strip.
class StripLegend extends StatelessWidget {
  const StripLegend({super.key, required this.showPartial});
  final bool showPartial;

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final statuses = [
      DayStatus.taken,
      if (showPartial) DayStatus.partial,
      DayStatus.missed,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in statuses)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dayStyle(c, s).color,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  dayStyle(c, s).glyph,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(dayStyle(c, s).label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        Text(
          'Ngưỡng đạt: $adherenceThreshold% số liều',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }
}

/// Doses not taken by reason, one stacked bar per reason with a segment per
/// medicine (fixed colour order), count written at the end of each bar.
class ReasonBars extends StatelessWidget {
  const ReasonBars(this.courses, {super.key});
  final List<CourseAdherence> courses;

  static List<Color> palette(DwColors c) => [c.s1, c.s2, c.ai, c.pt];

  @override
  Widget build(BuildContext context) {
    final c = DwColors.of(context);
    final colors = palette(c);
    final counts = [
      for (final course in courses)
        Map.fromEntries(course.missedByReason.map((e) => MapEntry(e.$1, e.$2))),
    ];
    final reasons = <String>{
      for (final r in SkipReason.values) r.label,
      unrecordedLabel,
    }.where((r) => counts.any((m) => (m[r] ?? 0) > 0)).toList();
    if (reasons.isEmpty) return const SizedBox.shrink();
    int total(String r) => counts.fold(0, (s, m) => s + (m[r] ?? 0));
    final maxTotal = reasons.map(total).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (i, course) in courses.indexed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    course.course.item.title,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(r, style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final unit = (box.maxWidth - 40) / maxTotal;
                      return Row(
                        children: [
                          for (final (i, m) in counts.indexed)
                            if ((m[r] ?? 0) > 0)
                              Tooltip(
                                message:
                                    '${courses[i].course.item.title}: ${m[r]} liều',
                                child: Container(
                                  width: unit * m[r]!,
                                  height: 16,
                                  margin: const EdgeInsets.only(right: 2),
                                  decoration: BoxDecoration(
                                    color: colors[i % colors.length],
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                          const SizedBox(width: 6),
                          Text(
                            '${total(r)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabular,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
