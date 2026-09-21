import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_solve_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// Çözüm gösterilirken tahta kapalı olmalı.
///
/// Adımlar 700 ms arayla oynanıyor; tahta açık kaldığı için kullanıcı
/// aralara kendi hamlesini sıkıştırabiliyordu ve tahta karışıyordu.
/// Hamlede ve rakip cevabında bu kilit 9.0.4'te kurulmuş, çözüm
/// gösterimi atlanmıştı.

/// Beyaz kaleyi gezdiren üç yarım hamle; mat yok, hepsi yasal.
Puzzle _puzzle(String id) => Puzzle(
      id: id,
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      solution: const ['a1a7', 'g8h8', 'a7b7'],
    );

bool _boardOpen(WidgetTester tester) => tester
    .widget<ChessBoardWidget>(find.byType(ChessBoardWidget))
    .interactive;

bool _nextEnabled(WidgetTester tester) => tester
        .widget<TextButton>(
          find.ancestor(
            of: find.text(t('common.next')),
            matching: find.byType(TextButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.hapticsEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
  });

  testWidgets('çözüm oynanırken tahta kapalı, bitince düğmeler açık',
      (tester) async {
    final puzzles = [_puzzle('p1'), _puzzle('p2')];
    final collection = PuzzleCollection(
      id: 'c1',
      name: 'Deneme',
      puzzles: puzzles,
    );

    await tester.pumpWidget(MaterialApp(
      home: PuzzleSolveScreen(
        collection: collection,
        puzzles: puzzles,
        initialIndex: 0,
      ),
    ));
    await tester.pumpAndSettle();

    // Çözümü kayıtlı bulmacada motor beklenmiyor: tahta açık başlar.
    expect(_boardOpen(tester), isTrue);

    await tester.tap(find.text(t('puzzles.solution')));
    await tester.pump();

    expect(_boardOpen(tester), isFalse,
        reason: 'çözüm oynanırken hamle yapılabiliyor');
    expect(_nextEnabled(tester), isFalse,
        reason: 'gösterim sürerken bulmaca değiştirilebiliyor');

    // Üç adım, her biri 700 ms.
    await tester.pump(const Duration(milliseconds: 700));
    expect(_boardOpen(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Gösterim bitti: tahta yine kapalı (çözüm görüldü) ama artık
    // sonraki bulmacaya geçilebiliyor.
    expect(find.text(t('puzzles.solutionShown')), findsOneWidget);
    expect(_boardOpen(tester), isFalse);
    expect(_nextEnabled(tester), isTrue,
        reason: 'gösterim bitince düğmeler açılmalı');
  });
}
