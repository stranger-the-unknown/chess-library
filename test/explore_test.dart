import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// Kayıtlı oyun: İspanyol açılışının ilk hamleleri.
const _gameMoves = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6'];

/// Tahtadaki bir karenin ekran koordinatı (beyaz aşağıda).
Offset _squareCenter(WidgetTester tester, String square) {
  final board = tester.getRect(find.byType(ChessBoardWidget));
  final size = board.width / 8;
  final file = 'abcdefgh'.indexOf(square[0]);
  final rank = int.parse(square[1]);
  return Offset(
    board.left + (file + 0.5) * size,
    board.top + (8 - rank + 0.5) * size,
  );
}

Future<void> _playMove(
  WidgetTester tester,
  String from,
  String to,
) async {
  await tester.tapAt(_squareCenter(tester, from));
  await tester.pump();
  await tester.tapAt(_squareCenter(tester, to));
  await tester.pump();
}

void main() {
  setUp(() {
    // Ses, titreşim ve animasyon testte kapalı: eklenti kanalları ve
    // zamanlayıcılar sonucu etkilemesin.
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
    });
    Strings.language = AppLanguage.turkish;
  });

  testWidgets('kayıtlı oyunda oynanan hamle deneme sayılır', (tester) async {
    await SettingsService.instance.load();

    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(uciMoves: _gameMoves, title: 'Kayıtlı oyun'),
    ));
    await tester.pump();

    // Başlangıçta oyunun hamleleri listede, deneme şeridi yok.
    expect(find.text('e4'), findsOneWidget);
    expect(find.text(t('game.exploreHint')), findsNothing);

    // Oyunda olmayan bir hamle oyna.
    await _playMove(tester, 'd2', 'd4');

    // Deneme şeridi çıkar ve hamle orada görünür.
    expect(find.text(t('game.exploreHint')), findsOneWidget);
    expect(find.text('d4'), findsOneWidget);

    // Oyunun hamle listesi değişmemiştir: "d4" listeye eklenmemiştir,
    // yalnızca deneme şeridinde vardır.
    expect(find.text('e4'), findsOneWidget);
    expect(find.text('Nf3'), findsOneWidget);

    // Deneme sırasında sonuç afişi gizlenir (bu oyunda sonuç yok zaten).
    // Şeritteki kapatma düğmesi oyuna döndürür.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close_rounded));
    await tester.pump();

    expect(find.text(t('game.exploreHint')), findsNothing);
    expect(find.text('d4'), findsNothing);

    // Ekranı kapatarak bekleyen zamanlayıcıları temizle.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('serbest tahtada hamle oyunun kendisidir', (tester) async {
    await SettingsService.instance.load();

    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(title: 'Serbest tahta'),
    ));
    await tester.pump();

    await _playMove(tester, 'd2', 'd4');

    // Deneme değil: hamle listeye girer, şerit çıkmaz.
    expect(find.text(t('game.exploreHint')), findsNothing);
    expect(find.text('d4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
