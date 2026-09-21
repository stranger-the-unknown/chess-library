import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Ana menü `_logo` widget'ını birebir rasterize eder.
///
///   flutter run -d windows -t tool/export_home_logo.dart
///
/// Çıktı: assets/icon/icon.png (1024), icon_foreground.png,
///        menu_logo_512.png, menu_logo_54.png
/// Sonra: dart run flutter_launcher_icons
final _key = GlobalKey();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _Export(),
    ),
  );
}

class _Export extends StatefulWidget {
  const _Export();

  @override
  State<_Export> createState() => _ExportState();
}

class _ExportState extends State<_Export> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Directory('assets/icon').createSync(recursive: true);
    await _write(boundary, 1024 / 54, 'assets/icon/icon.png');
    await _write(boundary, 1024 / 54, 'assets/icon/icon_foreground.png');
    await _write(boundary, 512 / 54, 'assets/icon/menu_logo_512.png');
    await _write(boundary, 1.0, 'assets/icon/menu_logo_54.png');
    // ignore: avoid_print
    print('yazildi: assets/icon/icon.png');
    exit(0);
  }

  Future<void> _write(
    RenderRepaintBoundary boundary,
    double pr,
    String path,
  ) async {
    final image = await boundary.toImage(pixelRatio: pr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0x00000000),
      body: Center(
        child: RepaintBoundary(
          key: _key,
          child: _homeLogo(),
        ),
      ),
    );
  }
}

/// home_screen.dart `_logo` ile aynı; 1 piksel fark olmasın.
Widget _homeLogo() {
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
    child: Transform.translate(
      offset: const Offset(0, 5),
      child: const Text(
        '♞',
        style: TextStyle(
          fontFamily: 'NotoSansSymbols2',
          fontSize: 30,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    ),
  );
}
