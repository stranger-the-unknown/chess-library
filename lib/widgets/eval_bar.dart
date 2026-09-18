import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motorun değerlendirmesini gösteren dikey çubuk.
///
/// [scoreCp] beyazın bakış açısından santipiyon; [mateIn] doluysa mat
/// mesafesi gösterilir.
class EvalBar extends StatelessWidget {
  final int? scoreCp;
  final int? mateIn;
  final bool flipped;
  final bool thinking;

  const EvalBar({
    super.key,
    required this.scoreCp,
    this.mateIn,
    this.flipped = false,
    this.thinking = false,
  });

  /// Skoru 0..1 aralığında beyaz payına çevirir.
  double get _whiteShare {
    if (mateIn != null) return mateIn! > 0 ? 1 : 0;
    final score = scoreCp;
    if (score == null) return 0.5;
    // Lojistik eğri: ±400 santipiyon civarı doyuma yaklaşır.
    final clamped = score.clamp(-1500, 1500) / 400.0;
    return 1 / (1 + math.exp(-clamped));
  }

  String get label {
    if (mateIn != null) return 'M${mateIn!.abs()}';
    final score = scoreCp;
    if (score == null) return '·';
    final body = (score.abs() / 100).toStringAsFixed(1);
    if (score > 0) return '+$body';
    if (score < 0) return '-$body';
    return '0.0';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = _whiteShare;
    final whiteAhead = share >= 0.5;

    return SizedBox(
      width: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF2B2622)
                  : const Color(0xFF3A3530),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              alignment: flipped ? Alignment.topCenter : Alignment.bottomCenter,
              heightFactor: share.clamp(0.02, 0.98),
              child: Container(color: const Color(0xFFF2EEE7)),
            ),
            Align(
              alignment: whiteAhead
                  ? (flipped ? Alignment.topCenter : Alignment.bottomCenter)
                  : (flipped ? Alignment.bottomCenter : Alignment.topCenter),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: whiteAhead
                        ? const Color(0xFF2A2622)
                        : const Color(0xFFF2EEE7),
                  ),
                ),
              ),
            ),
            if (thinking)
              const Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
