import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/widgets/app_widgets.dart';

/// Camera and photo QR reading, replaceable in tests and screenshots where no
/// camera exists. Recognition runs on the phone; images are not uploaded.
abstract interface class CccdScanner {
  /// Live camera view that calls [onCode] with the raw text of each QR found.
  Widget preview({required ValueChanged<String> onCode});

  /// Lets the user pick a photo and returns its QR text. Returns null when the
  /// user cancels; throws [NoQrInImageException] when the photo has no QR.
  Future<String?> readFromImage();
}

class NoQrInImageException implements Exception {
  const NoQrInImageException();
}

final cccdScannerProvider = Provider<CccdScanner>(
  (ref) => const MobileCccdScanner(),
);

class MobileCccdScanner implements CccdScanner {
  const MobileCccdScanner();

  @override
  Widget preview({required ValueChanged<String> onCode}) =>
      _CameraView(onCode: onCode);

  @override
  Future<String?> readFromImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    final controller = MobileScannerController(autoStart: false);
    try {
      final capture = await controller.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      final value = capture?.barcodes
          .map((code) => code.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (value == null) throw const NoQrInImageException();
      return value;
    } finally {
      await controller.dispose();
    }
  }
}

class _CameraView extends StatefulWidget {
  const _CameraView({required this.onCode});
  final ValueChanged<String> onCode;

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final value = capture.barcodes
              .map((code) => code.rawValue)
              .whereType<String>()
              .firstOrNull;
          if (value != null) widget.onCode(value);
        },
        errorBuilder: (context, error) => ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'MedicApp chưa được phép dùng camera. Hãy cho phép trong '
                          'Cài đặt của điện thoại, hoặc chọn ảnh có mã QR bên dưới.'
                    : 'Không mở được camera. Hãy chọn ảnh có mã QR bên dưới.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 12,
        child: ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, state, _) {
            if (state.torchState == TorchState.unavailable) {
              return const SizedBox.shrink();
            }
            final on = state.torchState == TorchState.on;
            return FilledButton.tonalIcon(
              onPressed: _controller.toggleTorch,
              icon: const AppIcon(AppIcons.flashlight, size: 20),
              label: Text(on ? 'Tắt đèn' : 'Bật đèn'),
            );
          },
        ),
      ),
    ],
  );
}
