import 'dart:math' as math;

import 'package:flutter/services.dart';

/// "Mã nhận kết quả" printed at the bottom of the paper prescription:
/// 10 Crockford base32 characters shown as XXXX-XXXX-XX. Read the same way
/// as the backend: any case, dashes and spaces ignored, O as 0, I and L as 1.
const claimCodeLength = 10;

final _crockford = RegExp(r'^[0-9A-HJKMNP-TV-Z]+$');

String _canonical(String input) =>
    input.toUpperCase().replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');

/// The 10 characters the backend expects, or null when [input] cannot be a
/// claim code (wrong length or a character outside the alphabet, such as U).
String? normalizeClaimCode(String input) {
  final code = _canonical(input.replaceAll(RegExp(r'[\s-]'), ''));
  if (code.length != claimCodeLength || !_crockford.hasMatch(code)) {
    return null;
  }
  return code;
}

/// Groups up to 10 characters as XXXX-XXXX-XX, as printed on the paper.
String formatClaimCode(String code) {
  final parts = [
    for (final (start, end) in const [(0, 4), (4, 8), (8, 10)])
      if (code.length > start)
        code.substring(start, math.min(end, code.length)),
  ];
  return parts.join('-');
}

/// Upper-cases and groups the code while the person types or pastes it.
class ClaimCodeInputFormatter extends TextInputFormatter {
  const ClaimCodeInputFormatter();

  static String _clean(String text) =>
      _canonical(text.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), ''));

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = _clean(newValue.text);
    final code = raw.substring(0, math.min(raw.length, claimCodeLength));
    final cursor = newValue.selection.isValid
        ? math.min(newValue.selection.end, newValue.text.length)
        : newValue.text.length;
    final before = math.min(
      _clean(newValue.text.substring(0, cursor)).length,
      code.length,
    );
    final offset = before + (before > 4 ? 1 : 0) + (before > 8 ? 1 : 0);
    return TextEditingValue(
      text: formatClaimCode(code),
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
