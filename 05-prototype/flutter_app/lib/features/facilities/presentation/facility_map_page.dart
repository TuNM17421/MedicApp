import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../booking/application/booking_providers.dart';
import '../../booking/data/booking_catalog.dart';
import '../../booking/domain/booking_models.dart';
import '../../booking/presentation/booking_format.dart';
import '../application/nearby_providers.dart';

/// Facilities on an OpenStreetMap map. From the booking flow, picking a pin
/// chooses that facility for the draft; from Home it starts a booking there.
class FacilityMapPage extends ConsumerStatefulWidget {
  const FacilityMapPage({super.key, this.fromBooking = false});
  final bool fromBooking;

  @override
  ConsumerState<FacilityMapPage> createState() => _FacilityMapPageState();
}

class _FacilityMapPageState extends ConsumerState<FacilityMapPage> {
  final _map = MapController();
  String? _selected;
  bool _picked = false;

  BookingDraft? get _draft =>
      widget.fromBooking ? ref.read(bookingSessionProvider).draft : null;

  @override
  void initState() {
    super.initState();
    _selected = _draft?.facilityId;
    final nearby = ref.read(nearbyProvider);
    if (_selected == null && nearby.phase == NearbyPhase.ready) {
      _selected = nearestFor(nearby.position, _draft)?.facility.id;
    }
    Future.microtask(() {
      if (mounted) ref.read(nearbyProvider.notifier).refreshIfAllowed();
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _select(String id) => setState(() {
    _selected = id;
    _picked = true;
  });

  void _onLocated(LatLng position) {
    final nearest = nearestFor(position, _draft);
    if (nearest == null) return;
    if (!_picked) setState(() => _selected = nearest.facility.id);
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [position, nearest.facility.location],
        padding: const EdgeInsets.all(72),
        maxZoom: 15,
      ),
    );
  }

  void _confirm(Facility facility) {
    if (widget.fromBooking) {
      ref.read(bookingSessionProvider.notifier).chooseFacility(facility.id);
      AppRoutes.backOr(context, AppRoutes.booking);
    } else {
      ref.read(bookingHandoffProvider).pending = BookingHandoff(
        BookingDraft(
          id: BookingController.newDraftId(),
          facilityId: facility.id,
        ),
        stage: BookingStage.type,
        notice: 'Đã chọn sẵn ${facility.name}. Bạn có thể đổi ở bước Nơi khám.',
      );
      context.pushReplacement(AppRoutes.booking);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(nearbyProvider, (previous, next) {
      if (next.phase == NearbyPhase.ready &&
          previous?.phase != NearbyPhase.ready) {
        _onLocated(next.position!);
      }
    });
    final nearby = ref.watch(nearbyProvider);
    final draft = widget.fromBooking
        ? ref.watch(bookingSessionProvider).draft
        : null;
    final distances = {
      if (nearby.position != null)
        for (final item in facilitiesByDistance(
          nearby.position!,
          BookingCatalog.facilities,
        ))
          item.facility.id: item.km,
    };
    final selected = _selected == null
        ? null
        : BookingCatalog.facility(_selected!);
    final points = [
      for (final facility in BookingCatalog.facilities) facility.location,
      ?nearby.position,
    ];
    return Scaffold(
      body: Column(
        children: [
          ColoredBox(
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: AppPageHeader(
                title: 'Cơ sở khám trên bản đồ',
                onBack: () => AppRoutes.backOrHome(context),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  key: const Key('facility-map'),
                  mapController: _map,
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                      coordinates: points,
                      padding: const EdgeInsets.all(56),
                      maxZoom: 15,
                    ),
                    minZoom: 5,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.medic_app',
                      tileProvider: ref.watch(mapTileProviderProvider),
                    ),
                    MarkerLayer(
                      markers: [
                        if (nearby.position != null)
                          Marker(
                            point: nearby.position!,
                            width: 32,
                            height: 32,
                            child: const _UserDot(),
                          ),
                        for (final facility in BookingCatalog.facilities)
                          Marker(
                            key: ValueKey('map-pin-${facility.id}'),
                            point: facility.location,
                            width: 56,
                            height: 56,
                            child: _FacilityPin(
                              facility: facility,
                              selected: facility.id == _selected,
                              allowed: facilityAllowed(facility, draft),
                              onTap: () => _select(facility.id),
                            ),
                          ),
                      ],
                    ),
                    const _Attribution(),
                  ],
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      key: const Key('map-locate'),
                      tooltip: 'Vị trí của tôi',
                      color: AppColors.primary,
                      onPressed: nearby.phase == NearbyPhase.ready
                          ? () => _onLocated(nearby.position!)
                          : ref.read(nearbyProvider.notifier).locate,
                      icon: nearby.phase == NearbyPhase.locating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const AppIcon(AppIcons.locate),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _FacilityPanel(
            facility: selected,
            km: selected == null ? null : distances[selected.id],
            nearest:
                selected != null &&
                nearestFor(nearby.position, draft)?.facility.id == selected.id,
            allowed: selected == null || facilityAllowed(selected, draft),
            nearby: nearby,
            fromBooking: widget.fromBooking,
            onConfirm: _confirm,
          ),
        ],
      ),
    );
  }
}

class _FacilityPanel extends ConsumerWidget {
  const _FacilityPanel({
    required this.facility,
    required this.km,
    required this.nearest,
    required this.allowed,
    required this.nearby,
    required this.fromBooking,
    required this.onConfirm,
  });
  final Facility? facility;
  final double? km;
  final bool nearest, allowed, fromBooking;
  final NearbyState nearby;
  final ValueChanged<Facility> onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final actions = ref.read(nearbyProvider.notifier);
    final status = switch (nearby.phase) {
      NearbyPhase.idle => (
        'Bấm nút định vị để tìm cơ sở gần bạn nhất.',
        'Dùng vị trí',
        actions.locate,
      ),
      NearbyPhase.denied => (
        'Chưa có quyền vị trí. Bạn vẫn chọn cơ sở trên bản đồ được.',
        'Thử lại',
        actions.locate,
      ),
      NearbyPhase.deniedForever => (
        'Quyền vị trí đang tắt cho MedicApp.',
        'Mở Cài đặt',
        actions.openSettings,
      ),
      NearbyPhase.serviceOff => (
        'Định vị trên điện thoại đang tắt.',
        'Bật định vị',
        actions.openSettings,
      ),
      NearbyPhase.unavailable => (
        'Chưa lấy được vị trí.',
        'Thử lại',
        actions.locate,
      ),
      NearbyPhase.locating || NearbyPhase.ready => null,
    };
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Expanded(child: Text(status.$1, style: text.bodySmall)),
                      TextButton(
                        key: const Key('map-status-action'),
                        onPressed: status.$3,
                        child: Text(status.$2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (facility == null)
                Text(
                  'Chạm vào một ghim trên bản đồ để xem cơ sở.',
                  style: text.bodyMedium,
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppIconTile(icon: AppIcons.hospital),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (nearest)
                            Text(
                              'Gần bạn nhất',
                              style: text.labelMedium?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          Text(facility!.name, style: text.titleMedium),
                          const SizedBox(height: 4),
                          Text(facility!.address, style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (km != null) _Fact('Cách ${formatDistance(km!)}'),
                    _Fact(
                      facility!.acceptsInsurance
                          ? 'Nhận BHYT'
                          : 'Không nhận BHYT',
                    ),
                    _Fact('Phí khám ${bookingMoney(facility!.fee)}'),
                  ],
                ),
                const SizedBox(height: 16),
                if (!allowed) ...[
                  Text(
                    'Cơ sở này không hỗ trợ khám BHYT.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 8),
                ],
                AppPrimaryButton(
                  key: const Key('map-confirm'),
                  label: fromBooking ? 'Chọn cơ sở này' : 'Đặt lịch tại đây',
                  onPressed: allowed ? () => onConfirm(facility!) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.divider),
    ),
    child: Text(label, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _FacilityPin extends StatelessWidget {
  const _FacilityPin({
    required this.facility,
    required this.selected,
    required this.allowed,
    required this.onTap,
  });
  final Facility facility;
  final bool selected, allowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = allowed ? AppColors.primary : AppColors.outline;
    final size = selected ? 52.0 : 40.0;
    return Semantics(
      button: true,
      selected: selected,
      label: facility.name,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : color,
                width: 3,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: AppIcon(
              AppIcons.hospital,
              color: selected ? Colors.white : color,
              size: selected ? 26 : 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Vị trí của bạn',
    child: Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x552563EB), blurRadius: 0, spreadRadius: 8),
          ],
        ),
      ),
    ),
  );
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: Colors.white.withValues(alpha: 0.85),
      child: Text(
        '© OpenStreetMap',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}
