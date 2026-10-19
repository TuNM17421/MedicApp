import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads Be Vietnam Pro so widget tests lay out text with real glyph widths
/// instead of the square test font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final loader = FontLoader('BeVietnamPro');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/BeVietnamPro-$weight.ttf')
        .readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  await testMain();
}
