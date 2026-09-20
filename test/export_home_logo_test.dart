import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Launcher PNG üretimi `tool/export_home_logo.dart` ile yapılır
/// (`flutter run -d windows -t tool/export_home_logo.dart`).
/// Bu dosya `flutter test` sırasında ikonları ezmesin diye boş.
void main() {
  test('export_home_logo is a tool, not a unit test', () {
    expect(File('tool/export_home_logo.dart').existsSync(), isTrue);
  });
}
