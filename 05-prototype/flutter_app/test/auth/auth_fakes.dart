import 'package:flutter/material.dart';
import 'package:medic_app/features/profiles/cccd_scanner.dart';

/// Synthetic card in the real QR layout. Not a real person.
const sampleCccdQr =
    '079065001234||Trần Thị Mai|15031965|Nữ|'
    'Số 12 Nguyễn Trãi, Phường Bến Thành, TP. Hồ Chí Minh|01072021';

class FakeScanner implements CccdScanner {
  ValueChanged<String>? _onCode;
  Future<String?> Function() image = () async => null;

  /// Behaves as if the camera found a QR code with [raw] text.
  void emit(String raw) => _onCode!(raw);

  @override
  Widget preview({required ValueChanged<String> onCode}) {
    _onCode = onCode;
    return const ColoredBox(key: Key('fake-camera'), color: Color(0xFF26332F));
  }

  @override
  Future<String?> readFromImage() => image();
}
