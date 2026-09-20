import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ana menü `_logo` widget'ının birebir kopyası.
/// home_screen.dart ile aynı tutulmalı.
Widget homeLogo() {
  return Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(
        colors: [Color(0xFF8FBB57), Color(0xFF4E7327)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    alignment: Alignment.center,
    child: const Text(
      '♞',
      style: TextStyle(fontSize: 30, color: Colors.white, height: 1.1),
    ),
  );
}

Future<void> _writePng(RenderRepaintBoundary boundary, double pr, String path) async {
  final image = await boundary.toImage(pixelRatio: pr);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('ana menü logosunu launcher PNG olarak dışa aktar', (tester) async {
    const logical = 54.0;

    await tester.binding.setSurfaceSize(const Size(logical, logical));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: Color(0x00000000),
          child: Center(
            child: RepaintBoundary(
              child: _ExactHomeLogo(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary),
    );

    Directory('assets/icon').createSync(recursive: true);
    await _writePng(boundary, 1024 / logical, 'assets/icon/icon.png');
    await _writePng(boundary, 1024 / logical, 'assets/icon/icon_foreground.png');
    await _writePng(boundary, 512 / logical, 'assets/icon/menu_logo_512.png');
    await _writePng(boundary, 1.0, 'assets/icon/menu_logo_54.png');
  });
}

class _ExactHomeLogo extends StatelessWidget {
  const _ExactHomeLogo();

  @override
  Widget build(BuildContext context) => homeLogo();
}
