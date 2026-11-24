import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/game_filter.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../widgets/app_dialogs.dart';
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
    this.playlistId,
    this.numbers,
    this.total,
  });

  final List<SavedGame> games;
  final int initialIndex;

  /// Oyunların listesi. Verilmişse sıra satırında "okundu" ve "favori"
  /// düğmeleri çıkıyor (10.13.0): oyunu bitirince işaretlemek için listeye
  /// dönmek gerekmiyor.
  final String? playlistId;

  /// Oyun kimliği → listedeki numara ve listedeki toplam oyun sayısı.
  /// Verilmişse sıra satırı bunları gösteriyor (bulmaca ekranındaki gibi):
  /// süzgeç ya da ters sıra açıkken de numara listede görünenle aynı.
  /// Oklar yine açılan (süzülmüş) sırada geziyor.
  final Map<String, int>? numbers;
  final int? total;

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

  /// Oyunun "okundu" ya da "favori" işaretini değiştirir.
  ///
  /// Sıra değişmiyor: liste "Okunmamışlar" süzgeciyle açılmış olsa da
  /// işaretlenen oyun yerinde kalıyor, sonraki oyun aynı oyun.
  Future<void> _toggle(SavedGame game, {required bool read}) async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;
    final storage = StorageService.instance;
    try {
      final value = read
          ? await storage.toggleGameRead(playlistId, game.id)
          : await storage.toggleGameFavorite(playlistId, game.id);
      if (read) {
        game.read = value;
      } else {
        game.favorite = value;
      }
    } catch (_) {
      if (mounted) AppDialogs.snack(context, t('lists.saveFailed'));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.games[_index];
    final length = widget.games.length;
    final marks = widget.playlistId != null;
    return GameScreen(
      // Anahtar oyunun kimliği: geçişte önceki oyunun konumu, denemeleri
      // ve zamanlayıcıları yeni oyuna sızmıyor.
      key: ValueKey(game.id),
      uciMoves: game.uciMoves,
      startFen: game.startFen,
      title: game.name,
      // Oyuncu adları varsa oyunun adı üst çubukta yazmıyor (adlar tahtanın
      // yanında). Adı olmayan oyunda (tahtadan kaydedilen "Oyun 2026-…",
      // Beyaz/Siyah'ı "?" olan çalışma dosyaları) oyunu tanıtan tek şey adı:
      // orada yazıyor. Adlar kartta göründüğü gibi çözülüyor (alan, PGN
      // başlığı ya da "A - B" biçimindeki eski ad).
      showTitle: game.resolvedWhite == null && game.resolvedBlack == null,
      initialResult: game.result,
      whiteName: game.resolvedWhite,
      blackName: game.resolvedBlack,
      pgnTags: game.tags,
      startFlipped: _baseFlipped(game) != _userFlip,
      startWithAnalysis: _analysisOn,
      // Tek oyunda sıra satırı yalnızca işaretlenecek bir liste varsa
      // çıkıyor; orada ok ve sıra yazısı yok, yalnızca işaret düğmeleri.
      sequence: length < 2 && !marks
          ? null
          : GameSequence(
              position: _index + 1,
              length: length,
              number: widget.numbers?[game.id],
              total: widget.total,
              onPrevious: _index > 0 ? (carry) => _step(-1, carry) : null,
              onNext:
                  _index < length - 1 ? (carry) => _step(1, carry) : null,
              read: game.read,
              favorite: game.favorite,
              onToggleRead: marks ? () => _toggle(game, read: true) : null,
              onToggleFavorite:
                  marks ? () => _toggle(game, read: false) : null,
            ),
    );
  }
}
