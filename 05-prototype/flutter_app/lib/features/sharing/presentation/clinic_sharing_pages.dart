import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../booking/presentation/booking_format.dart';
import '../application/sharing_providers.dart';
import '../data/patient_api.dart';
import '../domain/sharing_models.dart';

final _day = DateFormat('dd/MM');
final _date = DateFormat('dd/MM/yyyy');

/// "Đang chia sẻ đến 15/12", "Đã rút lại", "Chưa chia sẻ".
String sharingLabel(SharingConsent? consent, DateTime now) {
  if (consent == null) return 'Chưa chia sẻ';
  if (consent.state == SharingState.revoked) return 'Đã rút lại';
  if (!consent.activeAt(now)) return 'Đã hết hạn chia sẻ';
  return 'Đang chia sẻ đến ${_day.format(vietnamClock(consent.expiresAt))}';
}

/// Small coloured label with the sharing state of one appointment.
class SharingStatusChip extends ConsumerWidget {
  const SharingStatusChip({super.key, required this.consent});
  final SharingConsent? consent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(sharingClockProvider)();
    final active = consent?.activeAt(now) ?? false;
    final colors = AppTokens.of(context)
        .tone(active ? AppTone.success : AppTone.sky);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('sharing-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: AppIcon(
                active ? AppIcons.success : AppIcons.lock,
                size: 18,
                color: colors.foreground,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                sharingLabel(consent, now),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// On a clinic appointment: what is shared with the clinic, and the way to
/// change it.
class ClinicSharingSection extends ConsumerWidget {
  const ClinicSharingSection({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointment = ref.watch(serverAppointmentProvider(appointmentId));
    if (appointment == null || appointment.cancelled) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(sharingClockProvider)();
    final consent = appointment.consent;
    final active = consent?.activeAt(now) ?? false;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppSurface(
        key: const Key('clinic-sharing'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconTile(icon: AppIcons.lock, tone: AppTone.lavender),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chia sẻ với phòng khám',
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SharingStatusChip(consent: consent),
            const SizedBox(height: 8),
            Text(
              active
                  ? '${appointment.clinic.name} đang xem: '
                        '${_labels(consent!.scope)}.'
                  : 'Bạn có thể cho ${appointment.clinic.name} xem trước câu '
                        'trả lời và việc uống thuốc, để bác sĩ chuẩn bị.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (active)
              OutlinedButton(
                key: const Key('clinic-sharing-open'),
                onPressed: () =>
                    context.push(AppRoutes.shareWithClinic(appointmentId)),
                child: const Text('Xem, đổi hoặc rút lại'),
              )
            else
              FilledButton(
                key: const Key('clinic-sharing-open'),
                onPressed: () =>
                    context.push(AppRoutes.shareWithClinic(appointmentId)),
                child: const Text('Chọn thông tin chia sẻ'),
              ),
          ],
        ),
      ),
    );
  }
}

String _labels(Set<ShareScope> scope) => [
  for (final value in ShareScope.values)
    if (scope.contains(value)) value.label.toLowerCase(),
].join(', ');

/// "Chia sẻ với phòng khám": separate from keeping data on the phone. Says
/// what is shared, with which clinic and until when; nothing is pre-ticked
/// and the consent can be withdrawn here at any time.
class ClinicSharingPage extends ConsumerStatefulWidget {
  const ClinicSharingPage({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  ConsumerState<ClinicSharingPage> createState() => _ClinicSharingPageState();
}

class _ClinicSharingPageState extends ConsumerState<ClinicSharingPage> {
  Set<ShareScope>? _scope;
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  void _back() =>
      AppRoutes.backOr(context, AppRoutes.appointment(widget.appointmentId));

  Future<void> _share(Set<ShareScope> scope) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(serverAppointmentsProvider.notifier)
          .share(widget.appointmentId, scope);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Đã chia sẻ với phòng khám.')),
        );
      _back();
    } on PatientApiException catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(String clinic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rút lại, ngừng chia sẻ?'),
        content: Text(
          '$clinic sẽ không còn thấy các thông tin này từ lần mở hồ sơ '
          'tiếp theo.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ chia sẻ'),
          ),
          FilledButton(
            key: const Key('share-withdraw-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rút lại'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(serverAppointmentsProvider.notifier)
          .withdraw(widget.appointmentId);
      if (!mounted) return;
      setState(() {
        _confirmed = false;
        _scope = {};
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Đã rút lại. Phòng khám không còn thấy từ lần mở hồ sơ tiếp theo.',
            ),
          ),
        );
    } on PatientApiException catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointment = ref.watch(
      serverAppointmentProvider(widget.appointmentId),
    );
    if (appointment == null) {
      return Scaffold(
        body: AppPageBody(
          title: 'Chia sẻ với phòng khám',
          onBack: _back,
          children: const [
            AppEmptyState(
              title: 'Không tìm thấy lịch hẹn',
              message: 'Vui lòng quay lại danh sách lịch hẹn.',
            ),
          ],
        ),
      );
    }
    final now = ref.watch(sharingClockProvider)();
    final consent = appointment.consent;
    final active = consent?.activeAt(now) ?? false;
    final scope = _scope ?? (active ? {...consent!.scope} : <ShareScope>{});
    final clinic = appointment.clinic.name;
    final until = _date.format(
      vietnamClock(
        active ? consent!.expiresAt : appointment.expiryIfGrantedAt(now),
      ),
    );
    final start = appointment.start;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AppPageBody(
        title: 'Chia sẻ với phòng khám',
        onBack: _back,
        children: [
          Text('Bạn muốn cho $clinic xem những gì?', style: text.titleLarge),
          if (active)
            AppStatusBanner(
              status: AppStatus.success,
              title: 'Đang chia sẻ',
              message:
                  '$clinic đang xem: ${_labels(consent!.scope)}. '
                  'Đến hết ngày $until.',
            )
          else if (consent?.state == SharingState.revoked)
            AppStatusBanner(
              title: 'Đã rút lại',
              message: consent!.revokedAt == null
                  ? 'Phòng khám không còn thấy các thông tin này.'
                  : 'Bạn đã rút lại ngày '
                        '${_date.format(vietnamClock(consent.revokedAt!))}. '
                        'Phòng khám không còn thấy các thông tin này.',
            ),
          AppSurface(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Chia sẻ những gì', style: text.titleMedium),
                  ),
                  for (final value in ShareScope.values)
                    CheckboxListTile(
                      key: Key('share-scope-${value.wire}'),
                      value: scope.contains(value),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(
                              () => _scope = checked!
                                  ? {...scope, value}
                                  : ({...scope}..remove(value)),
                            ),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(value.label, style: text.titleMedium),
                      subtitle: Text(
                        value == ShareScope.selfMeds
                            ? '${value.detail} App chưa có danh sách này nên '
                                  'hiện chưa có gì để gửi.'
                            : value.detail,
                        style: text.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AppReviewSection(
            title: 'Với ai và đến khi nào',
            items: [
              (
                label: 'Phòng khám',
                value: appointment.clinic.phone.isEmpty
                    ? clinic
                    : '$clinic\nĐiện thoại ${appointment.clinic.phone}',
              ),
              (
                label: 'Cho lượt khám',
                value: [
                  '${bookingDate(start)} · ${appointment.time}',
                  if (appointment.specialty.isNotEmpty) appointment.specialty,
                ].join('\n'),
              ),
              (
                label: 'Đến khi nào',
                value:
                    'Đến hết ngày $until (30 ngày sau buổi khám). Sau đó '
                    'phòng khám không xem được nữa.',
              ),
              (
                label: 'Rút lại',
                value:
                    'Bất kỳ lúc nào, ngay trên trang này. Phòng khám sẽ không '
                    'còn thấy từ lần mở hồ sơ tiếp theo.',
              ),
            ],
          ),
          const AppStatusBanner(
            message:
                'Chỉ phòng khám này thấy, và chỉ cho lượt khám này. Việc này '
                'khác với "Lưu dữ liệu sức khỏe" trên điện thoại.',
          ),
          AppSurface(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const Key('share-confirm'),
                value: _confirmed,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _confirmed = value!),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Tôi đồng ý cho $clinic xem những mục đã chọn ở trên, '
                  'đến hết ngày $until.',
                  style: text.bodyLarge,
                ),
              ),
            ),
          ),
          if (_error != null)
            AppStatusBanner(
              status: AppStatus.error,
              message: _error!,
              liveRegion: true,
            ),
          AppPrimaryButton(
            key: const Key('share-submit'),
            label: active ? 'Lưu lựa chọn mới' : 'Đồng ý chia sẻ',
            isLoading: _busy,
            onPressed: _confirmed && scope.isNotEmpty
                ? () => _share(scope)
                : null,
          ),
          if (scope.isEmpty)
            Text('Chọn ít nhất một mục để chia sẻ.', style: text.bodyMedium),
          if (active)
            OutlinedButton(
              key: const Key('share-withdraw'),
              onPressed: _busy ? null : () => _withdraw(clinic),
              child: const Text('Rút lại, ngừng chia sẻ'),
            )
          else
            TextButton(
              key: const Key('share-later'),
              onPressed: _back,
              child: const Text('Không chia sẻ lúc này'),
            ),
        ],
      ),
    );
  }
}
