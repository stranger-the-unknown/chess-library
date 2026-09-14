import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Bir tahtanın zeminini çizer.
///
/// Tahtanın görsel dosyası yoktur: kareler kullanıcının seçtiği iki
/// renkten doğrudan tuvale çizilir. Böylece her ölçüde kusursuz keskin
/// çıkar (ölçekleme bulanıklığı ya da sıkıştırma izi olmaz), hiç yer
/// kaplamaz ve iki renkli dama deseni kimsenin telifinde değildir.
///
/// Hem oyun tahtası hem ayarlardaki önizleme bunu kullanır; ikisinin
/// ayrışıp birinin boş kalması böylece mümkün olmaz.
class BoardBackground extends StatelessWidget {
  /// Belirtilmezse ayarlardaki renkler kullanılır.
  final int? light;
  final int? dark;

  /// Belirtilmezse ayarlardaki ahşap dokusu tercihi kullanılır.
  final bool? wood;

  const BoardBackground({super.key, this.light, this.dark, this.wood});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return CustomPaint(
      painter: CheckerPainter(
        Color(light ?? settings.boardLight),
        Color(dark ?? settings.boardDark),
        wood: wood ?? settings.boardWood,
      ),
      size: Size.infinite,
    );
  }
}

/// İki renkli 8x8 kare deseni, isteğe bağlı ahşap damarıyla.
class CheckerPainter extends CustomPainter {
  final Color light;
  final Color dark;

  /// Kareler üzerine hafif bir damar deseni bindirilsin mi?
  final bool wood;

  const CheckerPainter(this.light, this.dark, {this.wood = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Genişlik ve yükseklik ayrı hesaplanır: tahtanın kendisi karedir ama
    // ayarlardaki önizleme kutusu kare olmayabilir; tek bir kenardan
    // hesaplanırsa altta boyanmamış bir şerit kalıyordu.
    final cellW = size.width / 8;
    final cellH = size.height / 8;
    final paint = Paint();
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        paint.color = (row + col) % 2 == 0 ? light : dark;
        canvas.drawRect(
          // Bitişik kareler arasında saç teli boşluk kalmasın diye
          // kenarlar bir sonraki hücrenin başlangıcına kadar uzatılır.
          Rect.fromLTRB(
            col * cellW,
            row * cellH,
            (col + 1) * cellW,
            (row + 1) * cellH,
          ),
          paint,
        );
      }
    }

    if (wood) _paintGrain(canvas, size);
  }

  /// Tahtanın üstüne hafif bir ahşap damarı çizer.
  ///
  /// Desen bir görselden gelmez; hafifçe dalgalı yatay çizgilerden
  /// kurulur. Böylece hangi renk çifti seçilirse seçilsin damar o
  /// renklerin üstünde doğar — sabit bir ahşap görseli tek bir renge
  /// bağlı kalırdı. Tohum sabittir: desen her çizimde aynı olur, tahta
  /// ekranda titremez.
  void _paintGrain(Canvas canvas, Size size) {
    final random = math.Random(20260914);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const lineCount = 110;
    for (int i = 0; i < lineCount; i++) {
      final y = random.nextDouble() * size.height;
      final darker = random.nextBool();
      // Damar çok belirgin olursa taşların okunmasını zorlaştırıyor;
      // parlaklığı yüzde birkaç oynatmakla yetiniliyor.
      paint
        ..color = (darker ? Colors.black : Colors.white).withValues(
          alpha: 0.015 + random.nextDouble() * 0.045,
        )
        ..strokeWidth = size.height * (0.002 + random.nextDouble() * 0.010);

      final amplitude = size.height * (0.002 + random.nextDouble() * 0.010);
      final frequency = 1 + random.nextDouble() * 2.5;
      final phase = random.nextDouble() * math.pi * 2;

      final path = Path()..moveTo(0, y);
      const steps = 10;
      for (int step = 1; step <= steps; step++) {
        final x = size.width * step / steps;
        final wave = math.sin(phase + (x / size.width) * math.pi * frequency);
        path.lineTo(x, y + wave * amplitude);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CheckerPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.dark != dark ||
      oldDelegate.wood != wood;
}
