/// Data read from the QR code on the front of a Vietnamese chip-based CCCD.
///
/// The code is plain text separated by `|`:
/// `số CCCD|số CMND cũ|họ tên|ngày sinh ddMMyyyy|giới tính|nơi thường trú|
/// ngày cấp ddMMyyyy`, and newer cards append further, often empty, fields.
/// Nothing here is sent anywhere; the result only pre-fills the profile form.
class CccdData {
  const CccdData({
    required this.idNumber,
    required this.name,
    required this.birthDate,
    this.oldIdNumber,
    this.gender,
    this.address,
    this.issueDate,
  });
  final String idNumber;
  final String? oldIdNumber;
  final String name;
  final DateTime birthDate;
  final String? gender;
  final String? address;
  final DateTime? issueDate;

  /// Shows only the first and last digits, e.g. `001•••••••345`.
  String get maskedIdNumber => maskIdNumber(idNumber);
}

String maskIdNumber(String value) => value.length < 7
    ? value
    : '${value.substring(0, 3)}${'•' * (value.length - 6)}'
          '${value.substring(value.length - 3)}';

enum CccdQrError {
  /// Not the `|`-separated layout of a CCCD QR code (a link, another card…).
  notCccd,

  /// The layout matches but the ID number, name or birth date is unusable.
  unreadable,
}

class CccdQrException implements Exception {
  const CccdQrException(this.error);
  final CccdQrError error;

  String get message => switch (error) {
    CccdQrError.notCccd => 'Mã này không phải mã QR trên thẻ CCCD. Hãy quét mã ở góc trên bên phải mặt trước thẻ.',
    CccdQrError.unreadable =>
      'Đọc được mã nhưng thiếu thông tin. Hãy thử quét lại hoặc tự nhập.',
  };

  @override
  String toString() => 'CccdQrException($error)';
}

/// Parses the raw QR text. Throws [CccdQrException] when it cannot be used.
CccdData parseCccdQr(String raw, {DateTime? today}) {
  final parts = raw.trim().split('|').map((part) => part.trim()).toList();
  if (parts.length < 6 || !RegExp(r'^\d{12}$').hasMatch(parts[0])) {
    throw const CccdQrException(CccdQrError.notCccd);
  }
  final name = parts[2].replaceAll(RegExp(r'\s+'), ' ');
  final birthDate = _date(parts[3]);
  final now = today ?? DateTime.now();
  if (name.isEmpty ||
      birthDate == null ||
      birthDate.year < 1900 ||
      birthDate.isAfter(now)) {
    throw const CccdQrException(CccdQrError.unreadable);
  }
  String? optional(int index) =>
      index < parts.length && parts[index].isNotEmpty ? parts[index] : null;
  return CccdData(
    idNumber: parts[0],
    oldIdNumber: optional(1),
    name: name,
    birthDate: birthDate,
    gender: optional(4),
    address: optional(5),
    issueDate: optional(6) == null ? null : _date(parts[6]),
  );
}

DateTime? _date(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
  final day = int.parse(value.substring(0, 2));
  final month = int.parse(value.substring(2, 4));
  final year = int.parse(value.substring(4));
  final date = DateTime(year, month, day);
  return date.day == day && date.month == month ? date : null;
}
