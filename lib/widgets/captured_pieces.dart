import 'package:flutter/material.dart';

import '../models/chess_engine.dart' as engine;
import 'piece_widget.dart';

/// Bir tarafın aldığı taşları ve materyal farkını gösterir.
class CapturedPieces extends StatelessWidget {
  /// Taşları gösterilecek olan taraf (yani rakibinden aldığı taşlar).
  final engine.Color side;
  final engine.ChessGame game;
  final double size;

  const CapturedPieces({
    super.key,
    required this.side,
    required this.game,
    this.size = 18,
  });

  static const Map<engine.PieceType, int> _startCounts = {
    engine.PieceType.pawn: 8,
    engine.PieceType.knight: 2,
    engine.PieceType.bishop: 2,
    engine.PieceType.rook: 2,
    engine.PieceType.queen: 1,
  };

  @override
  Widget build(BuildContext context) {
    final opponent =
        side == engine.Color.white ? engine.Color.black : engine.Color.white;
    final remaining = game.pieceCounts(opponent);

    final captured = <engine.PieceType, int>{};
    _startCounts.forEach((type, start) {
      final missing = start - (remaining[type] ?? 0);
      if (missing > 0) captured[type] = missing;
    });

    final balance = game.materialBalance;
    final advantage = side == engine.Color.white ? balance : -balance;

    // Şerit oyuncu satırının yarısı kadar yer alıyor (360 dp'lik bir
    // telefonda ~151 dp), dolu bir takım ise ~190 dp istiyor: çok taş
    // alınan oyunlarda son taşlar ve "+5" yazısı ekranın kenarında
    // kesiliyordu. `FittedBox` yer yetmediğinde şeridin tamamını
    // küçültüp sığdırıyor; yer varsa hiçbir şey değişmiyor.
    return SizedBox(
      height: size + 2,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in const [
              engine.PieceType.pawn,
              engine.PieceType.knight,
              engine.PieceType.bishop,
              engine.PieceType.rook,
              engine.PieceType.queen,
            ])
              if (captured[type] != null)
                _stack(engine.Piece(type, opponent), captured[type]!),
            if (advantage > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '+$advantage',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Aynı türden taşlar üst üste bindirilerek yer kazanılır.
  Widget _stack(engine.Piece piece, int count) {
    final overlap = size * 0.42;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: SizedBox(
        width: size + overlap * (count - 1),
        height: size,
        child: Stack(
          children: [
            for (int i = 0; i < count; i++)
              Positioned(
                left: i * overlap,
                child: PieceWidget(piece: piece, size: size),
              ),
          ],
        ),
      ),
    );
  }
}
