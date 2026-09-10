import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/chess_engine.dart' as engine;
import '../services/settings_service.dart';

/// Tek bir satranç taşını, seçili taş takımından çizer.
class PieceWidget extends StatelessWidget {
  final engine.Piece piece;
  final double size;

  /// Belirtilmezse ayarlardaki takım kullanılır.
  final String? pieceSet;

  const PieceWidget({
    super.key,
    required this.piece,
    required this.size,
    this.pieceSet,
  });

  /// "wp", "bq" gibi dosya kodu.
  static String codeFor(engine.Piece piece) {
    final color = piece.color == engine.Color.white ? 'w' : 'b';
    final type = switch (piece.type) {
      engine.PieceType.pawn => 'p',
      engine.PieceType.knight => 'n',
      engine.PieceType.bishop => 'b',
      engine.PieceType.rook => 'r',
      engine.PieceType.queen => 'q',
      engine.PieceType.king => 'k',
    };
    return '$color$type';
  }

  static String unicodeFor(engine.Piece piece) {
    final isWhite = piece.color == engine.Color.white;
    return switch (piece.type) {
      engine.PieceType.king => isWhite ? '♔' : '♚',
      engine.PieceType.queen => isWhite ? '♕' : '♛',
      engine.PieceType.rook => isWhite ? '♖' : '♜',
      engine.PieceType.bishop => isWhite ? '♗' : '♝',
      engine.PieceType.knight => isWhite ? '♘' : '♞',
      engine.PieceType.pawn => isWhite ? '♙' : '♟',
    };
  }

  @override
  Widget build(BuildContext context) {
    final set = pieceSet ?? SettingsService.instance.pieceSet;
    // Taşlar vektör (SVG) olarak saklanır: her ölçüde net çıkar ve dosya
    // boyutu küçüktür. Çözümlenen çizim flutter_svg tarafından
    // önbelleklenir, uzun listelerde yeniden ayrıştırılmaz.
    return SvgPicture.asset(
      BoardAssets.piecePath(set, codeFor(piece)),
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => SizedBox(width: size, height: size),
    );
  }
}
