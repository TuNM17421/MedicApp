import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../booking/domain/booking_models.dart';
import '../application/nearby_providers.dart';

/// Top of "Chọn nơi khám": the nearest facility the draft can use, from the
/// phone's position. Asks for location only when the user taps the button;
/// once allowed, the suggestion appears on its own the next time.
class NearbySuggestion extends ConsumerStatefulWidget {
  const NearbySuggestion({
    super.key,
    required this.draft,
    required this.onChoose,
    required this.onOpenMap,
  });
  final BookingDraft draft;
  final ValueChanged<String> onChoose;
  final VoidCallback onOpenMap;

  @override
  ConsumerState<NearbySuggestion> createState() => _NearbySuggestionState();
}

class _NearbySuggestionState extends ConsumerState<NearbySuggestion> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(nearbyProvider.notifier).refreshIfAllowed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nearby = ref.watch(nearbyProvider);
    final actions = ref.read(nearbyProvider.notifier);
    final text = Theme.of(context).textTheme;
    final nearest = nearestFor(nearby.position, widget.draft);
    final (message, action, onAction) = switch (nearby.phase) {
      NearbyPhase.idle => (
        'Cho phép dùng vị trí để gợi ý nơi khám gần bạn nhất. Vị trí chỉ dùng trên điện thoại này, không gửi đi.',
        'Dùng vị trí hiện tại',
        actions.locate,
      ),
      NearbyPhase.locating => ('Đang tìm vị trí của bạn…', null, null),
      NearbyPhase.ready when nearest == null => (
        'Chưa có cơ sở phù hợp với hình thức khám này gần bạn.',
        null,
        null,
      ),
      NearbyPhase.ready => ('', null, null),
      NearbyPhase.denied => (
        'Bạn chưa cho phép dùng vị trí. Bạn vẫn chọn cơ sở bên dưới như bình thường.',
        'Thử lại',
        actions.locate,
      ),
      NearbyPhase.deniedForever => (
        'Quyền vị trí của MedicApp đang tắt. Bật lại trong Cài đặt nếu muốn gợi ý nơi gần nhất.',
        'Mở Cài đặt',
        actions.openSettings,
      ),
      NearbyPhase.serviceOff => (
        'Định vị trên điện thoại đang tắt.',
        'Bật định vị',
        actions.openSettings,
      ),
      NearbyPhase.unavailable => (
        'Chưa lấy được vị trí. Bạn có thể thử lại hoặc chọn cơ sở bên dưới.',
        'Thử lại',
        actions.locate,
      ),
    };
    final chosen =
        nearest != null && widget.draft.facilityId == nearest.facility.id;
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppSurface(
        key: const Key('nearby-suggestion'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconTile(icon: AppIcons.location),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nearest == null ? 'Cơ sở gần bạn' : 'Gần bạn nhất',
                    style: text.titleMedium,
                  ),
                ),
                if (nearby.phase == NearbyPhase.locating)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (nearest != null && nearby.phase == NearbyPhase.ready) ...[
              Text(nearest.facility.name, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Cách khoảng ${formatDistance(nearest.km)} · ${nearest.facility.address}',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              if (chosen)
                Row(
                  children: [
                    const AppIcon(AppIcons.success, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Đã chọn cơ sở này', style: text.labelLarge),
                    ),
                  ],
                )
              else
                FilledButton(
                  key: const Key('nearby-choose'),
                  onPressed: () => widget.onChoose(nearest.facility.id),
                  child: const Text('Chọn cơ sở gần nhất'),
                ),
            ] else ...[
              Text(message, style: text.bodyMedium),
              if (action != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  key: const Key('nearby-locate'),
                  onPressed: onAction,
                  child: Text(action),
                ),
              ],
            ],
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('nearby-map'),
              onPressed: widget.onOpenMap,
              icon: const AppIcon(AppIcons.map, size: 20),
              label: const Text('Xem các cơ sở trên bản đồ'),
            ),
          ],
        ),
      ),
    );
  }
}
