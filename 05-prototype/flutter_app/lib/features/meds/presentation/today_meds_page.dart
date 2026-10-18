import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:medic_core/medic_core.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_state.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';

import '../../visit_prep/visit_prep.dart';
import '../application/meds_providers.dart';
import '../domain/med_reminder_planner.dart';

final _time = DateFormat('HH:mm');

/// Rebuilds every minute so due doses turn into missed ones on screen, and
/// picks up doses marked on a notification while the page is open.
mixin _MinuteTick<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.read(doseLogProvider.notifier).drainPending();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

String _whoTitle(PreviewProfile? profile) =>
    profile == null || profile.relationship == selfRelationship
    ? 'Thuốc của bạn'
    : whoShort(profile);

class TodayMedsPage extends ConsumerStatefulWidget {
  const TodayMedsPage({super.key});

  @override
  ConsumerState<TodayMedsPage> createState() => _TodayMedsPageState();
}

class _TodayMedsPageState extends ConsumerState<TodayMedsPage>
    with _MinuteTick {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(ringOnTimeProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(prepClockProvider)();
    final courses = ref.watch(medicationCoursesProvider);
    final log = ref.watch(doseLogProvider);
    final profiles = ref.watch(profileCatalogProvider);
    final today = dosesOn(now, courses, log, now);
    final ringOnTime = ref.watch(ringOnTimeProvider);
    PreviewProfile? profile(String id) =>
        profiles.where((p) => p.id == id).firstOrNull;

    final people = {for (final dose in today) dose.course.profileId};
    final entries = log.values.toList();
    final low = [
      for (final course in courses)
        if (course.activeOn(now) && daysLeft(course, entries) <= lowStockDays)
          course,
    ];

    return Scaffold(
      body: AppPageBody(
        title: 'Thuốc hôm nay',
        onBack: () => AppRoutes.backOrHome(context),
        children: [
          if (courses.isEmpty)
            const AppEmptyState(
              title: 'Chưa có thuốc',
              message: 'Khi bác sĩ gửi đơn thuốc, lịch uống và lời nhắc sẽ hiện ở đây.',
            )
          else ...[
            _DaySummary(doses: today, now: now),
            const _AlarmCard(),
            if (ringOnTime == false)
              _RingOnTimeCard(
                onAllow: () async {
                  await ref.read(ringOnTimeProvider.notifier).allow();
                  await ref.read(ringOnTimeProvider.notifier).check();
                },
              ),
            for (final course in low)
              _LowStockCard(
                course: course,
                who: profile(course.profileId),
                days: daysLeft(course, entries),
              ),
            if (today.isEmpty)
              const AppStatusBanner(
                status: AppStatus.success,
                message: 'Hôm nay không có liều nào cần uống.',
              ),
            for (final id in people) ...[
              Semantics(
                header: true,
                child: Text(
                  _whoTitle(profile(id)),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final dose in today)
                if (dose.course.profileId == id) DoseCard(dose: dose),
            ],
            for (final id in {for (final c in courses) c.profileId})
              _HistoryCard(
                title: {for (final c in courses) c.profileId}.length == 1
                    ? 'Lịch sử uống thuốc'
                    : 'Lịch sử: ${_whoTitle(profile(id))}',
                courses: [
                  for (final c in courses)
                    if (c.profileId == id) c,
                ],
                log: log,
                now: now,
              ),
          ],
        ],
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.doses, required this.now});
  final List<ScheduledDose> doses;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final taken = doses.where((d) => d.state == DoseState.taken).length;
    final missed = doses.where((d) => d.state == DoseState.missed).length;
    final next = doses
        .where((d) => d.state == DoseState.upcoming || d.state == DoseState.due)
        .firstOrNull;
    return AppSurface(
      child: Row(
        children: [
          const AppIconTile(icon: AppIcons.pill),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đã uống $taken/${doses.length} liều',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    DateFormat('EEEE, dd/MM', 'vi').format(now),
                    if (missed > 0) 'lỡ $missed liều',
                    if (next != null) 'tiếp theo ${_time.format(next.at)}',
                  ].join(' · '),
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns alarm-style reminders on, after saying what the phone will ask.
class _AlarmCard extends ConsumerWidget {
  const _AlarmCard();

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bật chuông báo uống thuốc?'),
        content: const Text(
          'Đến giờ uống, điện thoại đổ chuông như đồng hồ báo thức, kể cả '
          'khi để im lặng, cho đến khi bạn bấm Đã uống hoặc Nhắc lại.\n\n'
          'Điện thoại sẽ hỏi bạn cho phép "Báo thức và lời nhắc" và hiện '
          'lời nhắc trên màn hình khóa.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            key: const Key('meds-alarm-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final access = await ref.read(medAlarmProvider.notifier).turnOn();
    if (!context.mounted) return;
    final message = !access.onTime
        ? 'Chưa bật được chuông vì điện thoại chưa cho phép "Báo thức và '
              'lời nhắc". Lời nhắc vẫn đến như thông báo thường.'
        : access.fullScreen
        ? 'Đã bật chuông báo uống thuốc.'
        : 'Đã bật chuông. Khi khóa máy, lời nhắc hiện ở thanh thông báo '
              'thay vì cả màn hình.';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(medAlarmProvider);
    final text = Theme.of(context).textTheme;
    return AppSurface(
      // Read out with its switch as one control.
      child: MergeSemantics(
        child: Row(
          children: [
            const AppIconTile(icon: AppIcons.alarm),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chuông báo uống thuốc', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    on
                        ? 'Đang bật: đổ chuông như báo thức đến khi bạn trả lời.'
                        : 'Đang tắt: chỉ hiện thông báo đến giờ uống.',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            Switch(
              key: const Key('meds-alarm'),
              value: on,
              onChanged: (value) => value
                  ? _turnOn(context, ref)
                  : ref.read(medAlarmProvider.notifier).turnOff(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingOnTimeCard extends StatelessWidget {
  const _RingOnTimeCard({required this.onAllow});
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppStatusBanner(
        status: AppStatus.warning,
        title: 'Lời nhắc có thể đến trễ vài phút',
        message:
            'Điện thoại đang tiết kiệm pin nên có thể báo muộn. Cho phép '
            '"Báo thức và lời nhắc" để nhắc đúng giờ.',
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('meds-ring-on-time'),
        onPressed: onAllow,
        child: const Text('Bật nhắc đúng giờ'),
      ),
    ],
  );
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({
    required this.course,
    required this.who,
    required this.days,
  });
  final MedicationCourse course;
  final PreviewProfile? who;
  final int days;

  @override
  Widget build(BuildContext context) {
    final self = who == null || who!.relationship == selfRelationship;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStatusBanner(
          status: AppStatus.warning,
          title: 'Sắp hết ${course.item.name}',
          message:
              [
                    if (!self) whoShort(who),
                    days == 0 ? 'đã hết thuốc' : 'còn khoảng $days ngày thuốc',
                  ]
                  .join(': ')
                  .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase()),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: Key('meds-low-${course.id}'),
          onPressed: () => context.push(AppRoutes.booking),
          child: const Text('Đặt lịch tái khám'),
        ),
      ],
    );
  }
}

/// One dose with what to do about it.
class DoseCard extends ConsumerWidget {
  const DoseCard({super.key, required this.dose});
  final ScheduledDose dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final item = dose.course.item;
    final (tone, label) = switch (dose.state) {
      DoseState.upcoming => (AppTone.sky, 'Chưa đến giờ'),
      DoseState.due => (AppTone.teal, 'Đến giờ uống'),
      DoseState.taken => (
        AppTone.success,
        'Đã uống lúc ${_time.format(dose.entry!.at)}',
      ),
      DoseState.skipped => (
        AppTone.peach,
        'Bỏ liều: ${dose.entry!.reason?.label ?? ''}',
      ),
      DoseState.missed => (AppTone.error, 'Lỡ liều'),
    };
    final colors = AppTokens.of(context).tone(tone);
    final log = ref.read(doseLogProvider.notifier);
    final open = dose.entry == null;
    return AppSurface(
      key: Key('dose-${dose.key}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_time.format(dose.at), style: text.titleLarge),
                    Text(dose.dose.slot.label, style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${formatAmount(dose.dose.amount)} ${item.form}',
                        if (item.meal != MealTiming.any) item.meal.label,
                      ].join(', '),
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        label,
                        style: text.labelMedium?.copyWith(
                          color: colors.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (open)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: Key('dose-take-${dose.key}'),
                    onPressed: () => log.taken(dose.key),
                    child: const Text('Đã uống'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    key: Key('dose-skip-${dose.key}'),
                    onPressed: () async {
                      final reason = await _askReason(context);
                      if (reason != null) log.skipped(dose.key, reason);
                    },
                    child: const Text('Bỏ liều'),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('dose-undo-${dose.key}'),
                onPressed: () => log.undo(dose.key),
                icon: const AppIcon(AppIcons.undo),
                label: const Text('Hoàn tác'),
              ),
            ),
        ],
      ),
    );
  }

  static Future<SkipReason?> _askReason(BuildContext context) =>
      showModalBottomSheet<SkipReason>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Vì sao bỏ liều này?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Lý do được ghi vào lịch sử uống thuốc.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final reason in SkipReason.values) ...[
                  OutlinedButton(
                    key: Key('skip-reason-${reason.name}'),
                    onPressed: () => Navigator.of(context).pop(reason),
                    child: Text(reason.label),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      );
}

/// The last four weeks, one square per day: all taken, some missed, none
/// taken, or nothing due.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.courses,
    required this.log,
    required this.now,
  });
  final String title;
  final List<MedicationCourse> courses;
  final Map<String, DoseLogEntry> log;
  final DateTime now;

  static const days = 28;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tokens = AppTokens.of(context);
    final today = dayOf(now);
    final cells = [
      for (var i = days - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          rate: adherenceOn(
            today.subtract(Duration(days: i)),
            courses,
            log,
            now,
          ),
        ),
    ];
    final rated = cells.where((c) => c.rate != null).toList();
    final average = rated.isEmpty
        ? null
        : rated.fold<double>(0, (s, c) => s + c.rate!) / rated.length;
    Color colorOf(double? rate) => switch (rate) {
      null => AppColors.divider,
      1 => tokens.tone(AppTone.success).foreground,
      0 => tokens.tone(AppTone.error).foreground,
      _ => tokens.tone(AppTone.warning).foreground,
    };
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            average == null
                ? '4 tuần gần nhất: chưa có liều nào đến hạn.'
                : '4 tuần gần nhất: uống đúng ${(average * 100).round()}% số liều.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 6.0;
              final size = (constraints.maxWidth - gap * 6) / 7;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cell in cells)
                    Semantics(
                      label:
                          '${DateFormat('dd/MM').format(cell.day)}: '
                          '${cell.rate == null ? 'không có liều' : '${(cell.rate! * 100).round()}%'}',
                      child: Container(
                        width: size,
                        height: size.clamp(0, 36).toDouble(),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorOf(cell.rate),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            '${cell.day.day}',
                            style: text.labelSmall?.copyWith(
                              color: cell.rate == null
                                  ? AppColors.secondaryInk
                                  : Colors.white,
                            ),
                            textScaler: TextScaler.noScaling,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final (rate, label) in const [
                (1.0, 'Uống đủ'),
                (0.5, 'Lỡ một phần'),
                (0.0, 'Không uống'),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colorOf(rate),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(label, style: text.bodySmall),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// On Home while any medicine is due today.
class HomeMedsCard extends ConsumerStatefulWidget {
  const HomeMedsCard({super.key});

  @override
  ConsumerState<HomeMedsCard> createState() => _HomeMedsCardState();
}

class _HomeMedsCardState extends ConsumerState<HomeMedsCard> with _MinuteTick {
  @override
  Widget build(BuildContext context) {
    final now = ref.watch(prepClockProvider)();
    final courses = ref.watch(medicationCoursesProvider);
    if (!courses.any((c) => c.activeOn(now))) return const SizedBox.shrink();
    final doses = dosesOn(now, courses, ref.watch(doseLogProvider), now);
    final missed = doses.where((d) => d.state == DoseState.missed).length;
    final left = doses
        .where((d) => d.state == DoseState.upcoming || d.state == DoseState.due)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppLinkCard(
        key: const Key('home-meds'),
        title: 'Thuốc hôm nay',
        subtitle: [
          if (missed > 0) 'Lỡ $missed liều',
          if (left.isEmpty)
            'Đã xong các liều hôm nay'
          else
            'Còn ${left.length} liều · tiếp theo ${_time.format(left.first.at)}',
        ].join(' · '),
        icon: AppIcons.pill,
        tone: missed > 0 ? AppTone.error : AppTone.success,
        onTap: () => context.push(AppRoutes.meds),
      ),
    );
  }
}
