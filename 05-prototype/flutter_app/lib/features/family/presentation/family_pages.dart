import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:medic_core/medic_core.dart' show dayOf;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/state/app_state.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../meds/domain/med_reminder_planner.dart' show whoShort;
import '../../profiles/cccd_scanner.dart';
import '../../visit_prep/visit_prep.dart' show prepClockProvider;
import '../application/family_providers.dart';
import '../data/family_api.dart';
import '../domain/family_models.dart';

final _time = DateFormat('HH:mm');

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(content: Text(message)));

Future<bool> _confirmUnlink(BuildContext context, String who) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy liên kết?'),
        content: Text(
          'Hai máy sẽ ngừng chia sẻ lịch hẹn và báo lỡ liều với $who.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ liên kết'),
          ),
          FilledButton(
            key: const Key('family-unlink-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hủy liên kết'),
          ),
        ],
      ),
    ) ??
    false;

/// On a family profile: link it with that person's own phone.
class FamilyLinkSection extends ConsumerStatefulWidget {
  const FamilyLinkSection({super.key, required this.profile});
  final PreviewProfile profile;

  @override
  ConsumerState<FamilyLinkSection> createState() => _FamilyLinkSectionState();
}

class _FamilyLinkSectionState extends ConsumerState<FamilyLinkSection> {
  var _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(familyControllerProvider.notifier)
          .invite(widget.profile.id);
      if (mounted) context.push(AppRoutes.familyInvite(widget.profile.id));
    } on FamilyApiException catch (failure) {
      if (mounted) _say(context, failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(FamilyLink link) async {
    if (!await _confirmUnlink(context, whoShort(widget.profile))) return;
    try {
      await ref.read(familyControllerProvider.notifier).unlink(link);
    } on FamilyApiException catch (failure) {
      if (mounted) _say(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final available = ref.watch(familyApiProvider) != null;
    final link = ownerLinkFor(
      ref.watch(familyLinksProvider),
      widget.profile.id,
    );
    final who = whoShort(widget.profile);
    return AppSurface(
      key: const Key('family-link-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppIconTile(icon: AppIcons.phone, tone: AppTone.sky),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  link?.linked ?? false
                      ? 'Đã liên kết với máy của $who'
                      : 'Máy riêng của $who',
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            link?.linked ?? false
                ? 'Chuông uống thuốc của $who kêu trên máy của $who. Lịch hẹn '
                      'hiện ở cả hai máy. Bạn được báo khi $who quên uống thuốc.'
                : 'Liên kết để $who tự nhận chuông uống thuốc trên máy của '
                      'mình. Lịch hẹn hiện ở cả hai máy, và bạn được báo khi '
                      '$who quên uống thuốc.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (!available)
            const AppStatusBanner(
              message: 'Bản thử này chưa nối máy chủ nên chưa liên kết được.',
            )
          else if (link == null)
            FilledButton(
              key: const Key('family-link-start'),
              onPressed: _busy ? null : _start,
              child: Text(_busy ? 'Đang tạo mã…' : 'Liên kết với máy của $who'),
            )
          else if (!link.linked)
            FilledButton(
              key: const Key('family-link-show'),
              onPressed: () =>
                  context.push(AppRoutes.familyInvite(widget.profile.id)),
              child: const Text('Xem mã liên kết'),
            )
          else
            OutlinedButton(
              key: const Key('family-unlink'),
              onPressed: () => _unlink(link),
              child: const Text('Hủy liên kết'),
            ),
        ],
      ),
    );
  }
}

/// The owner shows this to the family member's phone.
class FamilyInvitePage extends ConsumerStatefulWidget {
  const FamilyInvitePage({super.key, required this.profileId});
  final String profileId;

  @override
  ConsumerState<FamilyInvitePage> createState() => _FamilyInvitePageState();
}

class _FamilyInvitePageState extends ConsumerState<FamilyInvitePage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Fast while the code is on screen, so the page turns green at once.
    _poll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => ref.read(familyControllerProvider.notifier).sync(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _renew(FamilyLink link) async {
    try {
      await ref.read(familyControllerProvider.notifier).renewInvite(link);
    } on FamilyApiException catch (failure) {
      if (mounted) _say(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = ref
        .watch(profileCatalogProvider)
        .where((p) => p.id == widget.profileId)
        .firstOrNull;
    final link = ownerLinkFor(ref.watch(familyLinksProvider), widget.profileId);
    final who = whoShort(profile);
    final now = ref.watch(prepClockProvider)();
    final expired = link?.inviteExpiresAt?.isBefore(now) ?? true;
    return Scaffold(
      body: AppPageBody(
        title: 'Liên kết với máy của $who',
        onBack: () => AppRoutes.backOrHome(context),
        children: [
          if (link == null)
            const AppEmptyState(
              title: 'Chưa có mã liên kết',
              message: 'Quay lại hồ sơ để tạo mã.',
            )
          else if (link.linked) ...[
            AppStatusBanner(
              key: const Key('family-invite-done'),
              status: AppStatus.success,
              title: 'Đã liên kết với máy của $who',
              message:
                  'Từ giờ chuông uống thuốc của $who kêu trên máy của $who. '
                  'Bạn được báo khi $who quên uống thuốc.',
              liveRegion: true,
            ),
            AppPrimaryButton(
              label: 'Xong',
              onPressed: () => AppRoutes.backOrHome(context),
            ),
          ] else ...[
            Text(
              'Trên máy của $who, mở MedicApp, vào Tài khoản, chọn "Nhận liên '
              'kết từ người thân" rồi quét mã này.',
              style: text.bodyLarge,
            ),
            AppSurface(
              child: Column(
                children: [
                  if (expired)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Mã đã hết hạn.',
                        style: TextStyle(fontSize: 18),
                      ),
                    )
                  else
                    Semantics(
                      label: 'Mã QR liên kết',
                      child: QrImageView(
                        key: const Key('family-invite-qr'),
                        data: familyQr(link.inviteCode!),
                        size: 220,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.ink,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text('Hoặc nhập mã', style: text.bodyMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    expired ? '—' : link.inviteCode!,
                    key: const Key('family-invite-code'),
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!expired)
                    Text(
                      'Mã dùng được đến ${_time.format(link.inviteExpiresAt!.toLocal())}, '
                      'một lần.',
                      style: text.bodySmall,
                    ),
                ],
              ),
            ),
            if (expired)
              FilledButton(
                key: const Key('family-invite-renew'),
                onPressed: () => _renew(link),
                child: const Text('Tạo mã mới'),
              )
            else
              const AppStatusBanner(
                message: 'Đang chờ máy người thân quét mã…',
                liveRegion: true,
              ),
          ],
        ],
      ),
    );
  }
}

/// The family member's phone: scan or type the code, then agree.
class FamilyJoinPage extends ConsumerStatefulWidget {
  const FamilyJoinPage({super.key});

  @override
  ConsumerState<FamilyJoinPage> createState() => _FamilyJoinPageState();
}

class _FamilyJoinPageState extends ConsumerState<FamilyJoinPage> {
  final _code = TextEditingController();
  String? _error;
  String? _found;
  FamilyInviter? _inviter;
  var _shareMissed = true;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check(String raw) async {
    if (_busy || _inviter != null) return;
    final code = inviteCodeFrom(raw);
    if (code == null) {
      setState(() => _error = 'Mã gồm 8 chữ và số, ví dụ ABCD-EF23.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final inviter = await ref
          .read(familyControllerProvider.notifier)
          .peek(code);
      if (mounted) {
        setState(() {
          _found = code;
          _inviter = inviter;
        });
      }
    } on FamilyApiException catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(familyControllerProvider.notifier)
          .join(_found!, shareMissed: _shareMissed);
      if (!mounted) return;
      _say(context, 'Đã liên kết với ${_inviter!.ownerName}.');
      AppRoutes.backOr(context, AppRoutes.account);
    } on FamilyApiException catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _inviter = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final inviter = _inviter;
    return Scaffold(
      body: AppPageBody(
        title: 'Nhận liên kết từ người thân',
        onBack: () => AppRoutes.backOr(context, AppRoutes.account),
        children: [
          if (inviter == null) ...[
            Text(
              'Quét mã QR trên máy của người thân, hoặc nhập mã họ đọc cho bạn.',
              style: text.bodyLarge,
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1.4,
                child: ref.watch(cccdScannerProvider).preview(onCode: _check),
              ),
            ),
            AppTextField(
              key: const Key('family-join-code'),
              label: 'Mã liên kết',
              hint: 'ABCD-EF23',
              controller: _code,
              errorText: _error,
            ),
            AppPrimaryButton(
              key: const Key('family-join-check'),
              label: 'Tiếp tục',
              isLoading: _busy,
              onPressed: () => _check(_code.text),
            ),
          ] else ...[
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${inviter.ownerName} muốn liên kết với máy này',
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trong máy của ${inviter.ownerName}, bạn là '
                    '"${inviter.relationship}".',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final line in [
                    'Đơn thuốc của bạn chuyển sang máy này. Chuông uống thuốc '
                        'kêu trên máy này, không kêu trên máy của '
                        '${inviter.ownerName} nữa.',
                    'Lịch hẹn của bạn hiện ở cả hai máy. Ai đặt lịch thì cả '
                        'hai đều được nhắc.',
                    'Thuốc của ${inviter.ownerName} không chuyển sang máy này.',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: AppIcon(AppIcons.check, size: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(line, style: text.bodyLarge)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AppSurface(
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Báo cho ${inviter.ownerName} khi tôi quên hoặc bỏ '
                        'liều thuốc',
                        style: text.bodyLarge,
                      ),
                    ),
                    Switch(
                      key: const Key('family-join-share'),
                      value: _shareMissed,
                      onChanged: (value) =>
                          setState(() => _shareMissed = value),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              AppStatusBanner(status: AppStatus.warning, message: _error!),
            AppPrimaryButton(
              key: const Key('family-join-accept'),
              label: 'Đồng ý liên kết',
              isLoading: _busy,
              onPressed: _join,
            ),
            TextButton(
              onPressed: () => AppRoutes.backOr(context, AppRoutes.account),
              child: const Text('Không, cảm ơn'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether this build can link phones (it names a backend).
bool familyLinkingOn(WidgetRef ref) => ref.watch(familyApiProvider) != null;

/// On the account page: links where this phone is the family member, and
/// the way to accept one.
class MemberLinksSection extends ConsumerWidget {
  const MemberLinksSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(familyApiProvider) == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final links = [
      for (final link in ref.watch(familyLinksProvider))
        if (link.role == FamilyRole.member && link.linked) link,
    ];
    Future<void> unlink(FamilyLink link) async {
      if (!await _confirmUnlink(context, link.peerName ?? 'người thân')) {
        return;
      }
      try {
        await ref.read(familyControllerProvider.notifier).unlink(link);
      } on FamilyApiException catch (failure) {
        if (context.mounted) _say(context, failure.message);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final link in links)
          AppSurface(
            key: Key('member-link-${link.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Đã liên kết với ${link.peerName}',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Lịch hẹn của bạn hiện ở cả hai máy.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 8),
                MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Báo cho ${link.peerName} khi tôi quên uống thuốc',
                          style: text.bodyLarge,
                        ),
                      ),
                      Switch(
                        value: link.shareMissed,
                        onChanged: (value) async {
                          try {
                            await ref
                                .read(familyControllerProvider.notifier)
                                .setShareMissed(link, value);
                          } on FamilyApiException catch (failure) {
                            if (context.mounted) {
                              _say(context, failure.message);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => unlink(link),
                  child: const Text('Hủy liên kết'),
                ),
              ],
            ),
          ),
        AppLinkCard(
          key: const Key('family-join'),
          title: 'Nhận liên kết từ người thân',
          subtitle:
              'Quét mã trên máy của con cháu để nhận lịch hẹn và đơn thuốc',
          icon: AppIcons.family,
          tone: AppTone.sky,
          onTap: () => context.push(AppRoutes.familyJoin),
        ),
      ],
    );
  }
}

/// On Thuốc hôm nay (owner): family members reminded on their own phone,
/// with the latest missed or skipped doses.
class AwayMedsCard extends ConsumerWidget {
  const AwayMedsCard({super.key, required this.link});
  final FamilyLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profile = ref
        .watch(profileCatalogProvider)
        .where((p) => p.id == link.profileId)
        .firstOrNull;
    final who = whoShort(profile);
    final now = ref.watch(prepClockProvider)();
    final recent = [
      for (final alert in link.alerts)
        if (now.difference(alert.at).inHours < 48) alert,
    ];
    return AppSurface(
      key: Key('away-meds-${link.profileId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppIconTile(icon: AppIcons.phone, tone: AppTone.sky),
              const SizedBox(width: 12),
              Expanded(child: Text('Thuốc của $who', style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            link.shareMissed
                ? 'Chuông uống thuốc kêu trên máy của $who. Bạn sẽ được báo '
                      'khi $who quên hoặc bỏ liều.'
                : 'Chuông uống thuốc kêu trên máy của $who. $who đã tắt báo '
                      'lỡ liều cho bạn.',
            style: text.bodyMedium,
          ),
          for (final alert in recent.take(3)) ...[
            const SizedBox(height: 12),
            AppStatusBanner(
              status: alert.kind == FamilyAlertKind.taken
                  ? AppStatus.success
                  : AppStatus.warning,
              title:
                  '${familyAlertTitle(alert, who)}'
                  '${dayOf(alert.at) == dayOf(now) ? '' : ' hôm qua'}',
              message: familyAlertBody(alert),
            ),
          ],
        ],
      ),
    );
  }
}
