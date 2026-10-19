import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_pages.dart';
import 'cccd_qr.dart';
import 'cccd_scanner.dart';

/// The card read by the scanner, waiting for the user to check and save it.
final cccdDraftProvider = NotifierProvider<CccdDraftController, CccdData?>(
  CccdDraftController.new,
);

class CccdDraftController extends Notifier<CccdData?> {
  @override
  CccdData? build() => null;

  void set(CccdData? value) => state = value;
}

/// Setting up the account holder's own profile is step 2 of signing up;
/// family profiles are added from the Profiles tab.
Widget _header(
  BuildContext context, {
  required bool self,
  required String title,
  VoidCallback? onBack,
}) => self
    ? AppFlowHeader(step: 2, totalSteps: 2, title: title, onBack: onBack)
    : AppPageHeader(
        title: title,
        onBack: onBack ?? () => AppRoutes.backOr(context, AppRoutes.profiles),
      );

class AddProfilePage extends ConsumerWidget {
  const AddProfilePage({super.key, required this.self});
  final bool self;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return FormPageScaffold(
      header: _header(
        context,
        self: self,
        title: self ? 'Hồ sơ của bạn' : 'Thêm hồ sơ người thân',
      ),
      children: [
        Text(
          self ? 'Tạo hồ sơ khám bệnh của bạn' : 'Tạo hồ sơ cho người thân',
          style: text.headlineMedium,
        ),
        Text(
          'Cách nhanh nhất là quét mã QR trên thẻ căn cước (CCCD). '
          'Họ tên, ngày sinh, giới tính và địa chỉ sẽ được điền sẵn.',
          style: text.bodyLarge,
        ),
        _MethodCard(
          key: const Key('add-profile-scan'),
          highlighted: true,
          icon: AppIcons.qr,
          title: 'Quét mã QR trên CCCD',
          description: 'Khoảng 10 giây. Bạn kiểm tra lại trước khi lưu.',
          badge: 'Nhanh nhất',
          onTap: () {
            ref.read(cccdDraftProvider.notifier).set(null);
            context.push(AppRoutes.scanCccd(self: self));
          },
        ),
        _MethodCard(
          key: const Key('add-profile-manual'),
          icon: AppIcons.edit,
          title: 'Tự nhập thông tin',
          description: 'Dùng khi không có thẻ CCCD gắn chip bên cạnh.',
          onTap: () {
            ref.read(cccdDraftProvider.notifier).set(null);
            context.push(AppRoutes.profileForm(self: self));
          },
        ),
        const AppStatusBanner(
          message:
              'Thông tin trên thẻ chỉ dùng để điền hồ sơ và được lưu trên '
              'điện thoại này. Ảnh camera không được lưu hay gửi đi.',
        ),
        if (self)
          TextButton(
            onPressed: () => ref.read(authSessionProvider.notifier).signOut(),
            child: const Text('Dùng số điện thoại khác'),
          ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
    this.highlighted = false,
  });
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppTokens.of(context).cardRadius);
    return Semantics(
      button: true,
      child: Material(
        color: highlighted ? AppColors.selected : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted ? AppColors.primary : AppColors.outline,
            width: highlighted ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (highlighted) ...[
                  const CccdCardIllustration(),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    AppIconTile(
                      icon: icon,
                      tone: highlighted ? AppTone.teal : AppTone.sky,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (badge != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge!,
                                style: text.labelMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          Text(title, style: text.titleLarge),
                          const SizedBox(height: 4),
                          Text(description, style: text.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ExcludeSemantics(child: AppIcon(AppIcons.next)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A drawn card front that points at the QR code in its top-right corner.
class CccdCardIllustration extends StatelessWidget {
  const CccdCardIllustration({super.key, this.maxWidth = 280});
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mã QR nằm ở góc trên bên phải, mặt trước thẻ CCCD',
    excludeSemantics: true,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: 1.586,
          child: LayoutBuilder(
            builder: (context, box) {
              final unit = box.maxWidth / 100;
              Widget line(double width) => Container(
                width: width * unit,
                height: 3.2 * unit,
                margin: EdgeInsets.only(bottom: 3 * unit),
                decoration: BoxDecoration(
                  color: const Color(0xFF9DB8B2),
                  borderRadius: BorderRadius.circular(unit),
                ),
              );
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE6F3F0), Color(0xFFCFE6EC)],
                  ),
                  borderRadius: BorderRadius.circular(5 * unit),
                  border: Border.all(color: const Color(0xFF9DB8B2)),
                ),
                padding: EdgeInsets.all(6 * unit),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        width: 13 * unit,
                        height: 13 * unit,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD9A441),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 17 * unit,
                      top: 2 * unit,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [line(40), line(30)],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        width: 22 * unit,
                        height: 28 * unit,
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8CCC7),
                          borderRadius: BorderRadius.circular(2 * unit),
                        ),
                        child: Icon(
                          AppIcons.person,
                          color: Colors.white,
                          size: 16 * unit,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 27 * unit,
                      bottom: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [line(28), line(22), line(30), line(18)],
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 24 * unit,
                        height: 24 * unit,
                        padding: EdgeInsets.all(1.5 * unit),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2 * unit),
                          border: Border.all(
                            color: const Color(0xFFE0522D),
                            width: 0.9 * unit,
                          ),
                        ),
                        child: Icon(
                          AppIcons.qr,
                          size: 19 * unit,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 26 * unit,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 2.5 * unit,
                          vertical: unit,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0522D),
                          borderRadius: BorderRadius.circular(2 * unit),
                        ),
                        child: Text(
                          'Mã QR ở đây',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 5 * unit,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class CccdScanPage extends ConsumerStatefulWidget {
  const CccdScanPage({super.key, required this.self});
  final bool self;

  @override
  ConsumerState<CccdScanPage> createState() => _CccdScanPageState();
}

class _CccdScanPageState extends ConsumerState<CccdScanPage> {
  String? _error;
  var _handled = false;
  var _picking = false;

  void _onCode(String raw) {
    if (_handled || !mounted) return;
    try {
      final data = parseCccdQr(raw);
      _handled = true;
      HapticFeedback.mediumImpact();
      ref.read(cccdDraftProvider.notifier).set(data);
      context.pushReplacement(AppRoutes.profileForm(self: widget.self));
    } on CccdQrException catch (error) {
      if (_error != error.message) setState(() => _error = error.message);
    }
  }

  Future<void> _pickImage() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final raw = await ref.read(cccdScannerProvider).readFromImage();
      if (raw != null) _onCode(raw);
    } on NoQrInImageException {
      _error = 'Không thấy mã QR trong ảnh. Hãy chọn ảnh chụp rõ góc có mã QR.';
    } catch (_) {
      _error =
          'Không đọc được ảnh này. Hãy thử ảnh khác hoặc quét bằng camera.';
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scanner = ref.watch(cccdScannerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1F1C),
      body: ListView(
        key: const Key('cccd-scan-scroll'),
        padding: EdgeInsets.zero,
        children: [
          SafeArea(
            bottom: false,
            child: AppPageHeader(
              title: 'Quét mã QR trên CCCD',
              onBack: () => AppRoutes.backOr(
                context,
                AppRoutes.addProfile(self: widget.self),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    scanner.preview(onCode: _onCode),
                    const IgnorePointer(child: _ScanFrame()),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Đưa mã QR vào giữa khung', style: text.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Mã QR nằm ở góc trên bên phải, mặt trước thẻ. Đặt thẻ ở '
                    'chỗ đủ sáng, giữ yên điện thoại. App tự đọc khi thấy mã.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  const CccdCardIllustration(maxWidth: 220),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    AppStatusBanner(
                      key: const Key('cccd-scan-error'),
                      status: AppStatus.warning,
                      message: _error!,
                      liveRegion: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('cccd-pick-image'),
                    onPressed: _picking ? null : _pickImage,
                    icon: const AppIcon(AppIcons.image),
                    label: Text(
                      _picking ? 'Đang đọc ảnh…' : 'Chọn ảnh có mã QR',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pushReplacement(
                      AppRoutes.profileForm(self: widget.self),
                    ),
                    child: const Text('Không quét được? Tự nhập thông tin'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _ScanFramePainter(), size: Size.infinite);
}

/// Dims the camera outside a rounded square and marks its corners.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width * .68;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    const r = 24.0;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(r))),
      ),
      Paint()..color = Colors.black54,
    );
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final length = side * .18;
    for (final (x, y, dx, dy) in [
      (rect.left, rect.top, 1.0, 1.0),
      (rect.right, rect.top, -1.0, 1.0),
      (rect.left, rect.bottom, 1.0, -1.0),
      (rect.right, rect.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * length)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * length, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) => false;
}

const _familyRelationships = [
  'Bố',
  'Mẹ',
  'Vợ',
  'Chồng',
  'Con',
  'Cháu',
  'Anh chị em',
  'Ông bà',
  'Khác',
];

class ProfileFormPage extends ConsumerStatefulWidget {
  const ProfileFormPage({super.key, required this.self});
  final bool self;

  @override
  ConsumerState<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends ConsumerState<ProfileFormPage> {
  final _form = GlobalKey<FormState>();
  late final CccdData? _card = ref.read(cccdDraftProvider);
  late final _name = TextEditingController(text: _card?.name);
  late final _birthDate = TextEditingController(
    text: _card == null ? null : _formatDate(_card.birthDate),
  );
  late final _address = TextEditingController(text: _card?.address);
  late String? _gender = switch (_card?.gender) {
    'Nam' => 'Nam',
    'Nữ' => 'Nữ',
    _ => null,
  };
  String? _relationship;
  var _showChoiceErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _birthDate.dispose();
    _address.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final [day, month, year] = [
      for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
    ];
    final date = DateTime(year, month, day);
    if (date.day != day ||
        date.month != month ||
        year < 1900 ||
        date.isAfter(DateTime.now())) {
      return null;
    }
    return date;
  }

  void _save() {
    final formValid = _form.currentState!.validate();
    final relationship = widget.self ? selfRelationship : _relationship;
    if (!formValid || _gender == null || relationship == null) {
      setState(() => _showChoiceErrors = true);
      return;
    }
    final birthDate = _parseDate(_birthDate.text)!;
    final profile = PreviewProfile(
      id: 'P${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      birthYear: birthDate.year,
      birthDate: birthDate,
      relationship: relationship,
      gender: _gender,
      idNumber: _card?.idNumber,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
    );
    ref.read(profileCatalogProvider.notifier).add(profile);
    ref.read(cccdDraftProvider.notifier).set(null);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.self) {
      ref.read(activeProfileIdProvider.notifier).select(profile.id);
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.profiles);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.self
              ? 'Đã tạo hồ sơ. Chào mừng ${profile.name}!'
              : 'Đã thêm hồ sơ ${profile.name}.',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final card = _card;
    return FormPageScaffold(
      scrollKey: const Key('profile-form-scroll'),
      header: _header(
        context,
        self: widget.self,
        title: card == null ? 'Nhập thông tin' : 'Kiểm tra thông tin',
        onBack: () =>
            AppRoutes.backOr(context, AppRoutes.addProfile(self: widget.self)),
      ),
      actionLabel: 'Lưu hồ sơ',
      onAction: _save,
      children: [
        if (card != null) ...[
          const AppStatusBanner(
            key: Key('profile-form-from-cccd'),
            status: AppStatus.success,
            title: 'Đã đọc thông tin từ thẻ CCCD',
            message: 'Vui lòng xem lại. Bạn có thể sửa nếu có chỗ chưa đúng.',
          ),
          AppSurface(
            child: Row(
              children: [
                const AppIconTile(icon: AppIcons.profile, tone: AppTone.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Số CCCD', style: text.bodySmall),
                      Text(
                        card.maskedIdNumber,
                        key: const Key('profile-form-id'),
                        style: text.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else
          Text(
            widget.self
                ? 'Nhập thông tin của bạn như trên giấy tờ tùy thân.'
                : 'Nhập thông tin của người thân như trên giấy tờ tùy thân.',
            style: text.bodyLarge,
          ),
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                key: const Key('profile-form-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: text.titleLarge,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Vui lòng nhập họ và tên.'
                    : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('profile-form-birth'),
                controller: _birthDate,
                keyboardType: TextInputType.datetime,
                textInputAction: TextInputAction.next,
                style: text.titleLarge,
                decoration: const InputDecoration(
                  labelText: 'Ngày sinh',
                  hintText: 'Ngày/tháng/năm, ví dụ 15/03/1965',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                validator: (value) => _parseDate(value ?? '') == null
                    ? 'Nhập ngày sinh theo dạng ngày/tháng/năm, ví dụ 15/03/1965.'
                    : null,
              ),
            ],
          ),
        ),
        _ChoiceGroup(
          label: 'Giới tính',
          options: const ['Nam', 'Nữ'],
          selected: _gender,
          error: _showChoiceErrors && _gender == null
              ? 'Vui lòng chọn giới tính.'
              : null,
          onSelected: (value) => setState(() => _gender = value),
        ),
        if (!widget.self)
          _ChoiceGroup(
            label: 'Người này là gì của bạn?',
            options: _familyRelationships,
            selected: _relationship,
            error: _showChoiceErrors && _relationship == null
                ? 'Vui lòng chọn quan hệ.'
                : null,
            onSelected: (value) => setState(() => _relationship = value),
          ),
        TextField(
          key: const Key('profile-form-address'),
          controller: _address,
          minLines: 2,
          maxLines: 4,
          style: text.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Địa chỉ (không bắt buộc)',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
        ),
      ],
    );
  }
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.error,
  });
  final String label;
  final List<String> options;
  final String? selected;
  final String? error;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      AppChoiceGrid(
        minItemWidth: options.length <= 2 ? 160 : 140,
        children: [
          for (final option in options)
            AppSelectionChip(
              key: ValueKey('choice-$option'),
              label: option,
              selected: option == selected,
              onTap: () => onSelected(option),
            ),
        ],
      ),
      if (error != null) ...[
        const SizedBox(height: 8),
        Text(
          error!,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );
}
