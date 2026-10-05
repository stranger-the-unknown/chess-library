import 'package:flutter/material.dart';

import '../models/game_filter.dart';
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
    this.player,
  });

  final List<SavedGame> games;
  final int initialIndex;

  /// Liste "Siyah tarafından oku" ile işaretli.
  final bool blackSide;

  /// "Oyuncunun gözünden oku" adı: o oyuncunun olduğu oyunlarda tahta onun
  /// tarafından (kural [listGameFlipped]).
  final String? player;

  @override
  State<ListGameScreen> createState() => _ListGameScreenState();
}

class _ListGameScreenState extends State<ListGameScreen> {
  late int _index = widget.initialIndex.clamp(0, widget.games.length - 1);

  /// Yeni oyuna taşınanlar: elle çevirme ve analiz.
  ///
  /// Yön oyundan oyuna değişebiliyor (oyuncu bir oyunda beyaz, ötekinde
  /// siyah); taşınan şey yönün kendisi değil, kullanıcının oyunun kendi
  /// yönüne göre tahtayı çevirip çevirmediği.
  bool _userFlip = false;
  bool _analysisOn = false;

  bool _baseFlipped(SavedGame game) => listGameFlipped(
        game,
        blackSide: widget.blackSide,
        player: widget.player,
      );

  void _step(int delta, GameCarry carry) {
    final next = _index + delta;
    if (next < 0 || next >= widget.games.length) return;
    setState(() {
      _userFlip = carry.flipped != _baseFlipped(widget.games[_index]);
      _index = next;
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
      startFlipped: _baseFlipped(game) != _userFlip,
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
