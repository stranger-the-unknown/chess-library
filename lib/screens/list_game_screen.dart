import 'package:flutter/material.dart';

import '../models/playlist.dart';
import 'game_screen.dart';

/// Oyun listesinden açılan oyun; önceki ve sonraki oyuna aynı sayfada
/// geçiliyor.
///
/// Sıra listede görünen sıradır (arama, süzgeç, aralık ve ters sıralama
/// uygulanmış) ve oyun açıldığı andaki hâliyle sabit: okundu işaretlemek
/// "Okunmamışlar" süzgecinde sırayı kaydırmıyor. Liste bitince durulur;
/// sonraki listeye geçilmez.
class ListGameScreen extends StatefulWidget {
  const ListGameScreen({
    super.key,
    required this.games,
    required this.initialIndex,
    this.blackSide = false,
  });

  final List<SavedGame> games;
  final int initialIndex;

  /// Liste "Siyah tarafından oku" ile işaretli.
  final bool blackSide;

  @override
  State<ListGameScreen> createState() => _ListGameScreenState();
}

class _ListGameScreenState extends State<ListGameScreen> {
  late int _index = widget.initialIndex.clamp(0, widget.games.length - 1);

  /// Yeni oyuna taşınanlar: tahtanın yönü (elle çevrildiyse o) ve analiz.
  late bool _flipped = widget.blackSide;
  bool _analysisOn = false;

  void _step(int delta, GameCarry carry) {
    final next = _index + delta;
    if (next < 0 || next >= widget.games.length) return;
    setState(() {
      _index = next;
      _flipped = carry.flipped;
      _analysisOn = carry.analysisOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.games[_index];
    final length = widget.games.length;
    return GameScreen(
      // Anahtar oyunun kimliği: geçişte önceki oyunun konumu, denemeleri
      // ve zamanlayıcıları yeni oyuna sızmıyor.
      key: ValueKey(game.id),
      uciMoves: game.uciMoves,
      startFen: game.startFen,
      title: game.name,
      initialResult: game.result,
      whiteName: game.white,
      blackName: game.black,
      startFlipped: _flipped,
      startWithAnalysis: _analysisOn,
      sequence: length < 2
          ? null
          : GameSequence(
              position: _index + 1,
              length: length,
              onPrevious: _index > 0 ? (carry) => _step(-1, carry) : null,
              onNext:
                  _index < length - 1 ? (carry) => _step(1, carry) : null,
            ),
    );
  }
}
