import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/models/move_entry.dart';
import 'package:chess_pgn_reader/models/opening.dart';
import 'package:chess_pgn_reader/screens/openings/opening_study_screen.dart';
import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/move_list.dart';

/// Hamle şeridinin iki hatası.
///
/// * "Sona git" ve "başa dön" tuşlarına basınca şerit yerinde kalıyordu.
///   Sebep: `ListView.builder` yalnızca görünen aralığı kurar, uzaktaki
///   hamlenin bağlamı yoktur ve `ensureVisible` yapacak bir şey bulamaz;
///   başa dönmekte ise imleç -1 olduğu için işlev hiç çalışmıyordu.
/// * Şeridin kenarında yarısı görünen bir hamlenin üstüne gelince vurgu
///   şeridin dışına taşıyordu: `InkWell` kendi Material'ı olmadığı için
///   mürekkebi kaydırma alanının dışındaki bir Material'a çiziyordu.
///
/// Şerit yerine kaydırma konumu ölçülüyor: "hangi hamle görünüyor"
/// sorusunun ölçülebilir karşılığı bu.

/// Uzun bir oyun: şerit hiçbir ekrana sığmasın.
List<MoveEntry> _longGame() {
  final position = engine.ChessGame();
  final history = <MoveEntry>[];
  // Atları ileri geri oynatarak uzun ama kurallı bir oyun üretiyoruz.
  const cycle = [
    'g1f3',
    'g8f6',
    'f3g1',
    'f6g8',
    'b1c3',
    'b8c6',
    'c3b1',
    'c6b8',
  ];
  for (int i = 0; i < 48; i++) {
    final uci = cycle[i % cycle.length];
    final move = position.moveFromUci(uci)!;
    final san = position.sanFor(move);
    position.makeMove(move);
    history.add(MoveEntry(move: move, san: san, fenAfter: position.fen));
  }
  return history;
}

/// Satırları eşit olmayan bir oyun.
///
/// Gerçek bir oyunda açılış hamleleri kısa ("e4"), sonrakiler uzundur
/// ("Raxf7+"). `ListView.builder` görmediği satırların genişliğini
/// gördüklerinin ortalamasından tahmin eder; baştan sona atlarken tahmin
/// gerçek sondan kısa kalıyor ve şerit sona varamıyor. Şeridi ilgilendiren
/// tek şey yazının kendisi olduğu için hamle nesnesi tekrar kullanılıyor.
List<MoveEntry> _unevenGame() {
  final position = engine.ChessGame();
  final sample = position.moveFromUci('e2e4')!;
  final fen = position.fen;
  const files = 'abcdefgh';
  return [
    for (int i = 0; i < 160; i++)
      MoveEntry(
        move: sample,
        san: i < 40 ? '${files[i % 8]}4' : 'R${files[i % 8]}xf7+',
        fenAfter: fen,
      ),
  ];
}

class _Harness extends StatefulWidget {
  final List<MoveEntry> moves;
  const _Harness(this.moves);

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int cursor = 0;

  /// Tahtadaki "sona git" / "başa dön" tuşlarının karşılığı.
  void moveTo(int index) => setState(() => cursor = index);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 52,
            child: MoveList(
              moves: widget.moves,
              currentIndex: cursor,
              onMoveTap: (index) => setState(() => cursor = index),
            ),
          ),
        ),
      ),
    );
  }
}

ScrollPosition _position(WidgetTester tester) {
  final scrollable = tester.widget<Scrollable>(
    find.descendant(
      of: find.byType(MoveList),
      matching: find.byType(Scrollable),
    ),
  );
  return (scrollable.controller as ScrollController).position;
}

Future<void> _setCursor(WidgetTester tester, int index) async {
  tester.state<_HarnessState>(find.byType(_Harness)).moveTo(index);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sona gidince şerit de sona kayıyor', (tester) async {
    final moves = _longGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, 0, reason: 'başlangıçta başta olmalı');

    await _setCursor(tester, moves.length - 1);

    final position = _position(tester);
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'son hamle görünmüyor; şerit oyunun ortasında kaldı',
    );
  });

  testWidgets('başa dönünce şerit de başa dönüyor', (tester) async {
    final moves = _longGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    await _setCursor(tester, moves.length - 1);
    expect(_position(tester).pixels, greaterThan(0));

    // Başa dön: gösterilecek hamle yok, imleç -1.
    await _setCursor(tester, -1);

    expect(
      _position(tester).pixels,
      0,
      reason: 'başa dönüldüğünde şerit de başa dönmeli',
    );
  });

  testWidgets('satırlar eşit genişlikte değilken de sona gidiyor',
      (tester) async {
    final moves = _unevenGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    await _setCursor(tester, moves.length - 1);

    final position = _position(tester);
    expect(
      position.pixels,
      moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      reason: 'şerit sona varamadı: tek tahmin yetmiyor',
    );
  });

  testWidgets('satırlar eşit genişlikte değilken de başa dönüyor',
      (tester) async {
    final moves = _unevenGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    await _setCursor(tester, moves.length - 1);
    await _setCursor(tester, -1);

    expect(_position(tester).pixels, 0, reason: 'şerit başa dönmedi');
  });

  testWidgets('ortadaki bir hamleye atlayınca o hamle görünüyor',
      (tester) async {
    final moves = _longGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    await _setCursor(tester, moves.length ~/ 2);

    final position = _position(tester);
    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(position.maxScrollExtent));
  });

  testWidgets('her hamlenin kendi Material\'ı var', (tester) async {
    // Mürekkebin şeridin dışına taşmasını engelleyen şey bu: Material
    // kaydırma alanının içinde kalıyor ve vurgu onun sınırlarında
    // kırpılıyor.
    final moves = _longGame();
    await tester.pumpWidget(_Harness(moves));
    await tester.pumpAndSettle();

    final inkWell = find.descendant(
      of: find.byType(MoveList),
      matching: find.byType(InkWell),
    );
    expect(inkWell, findsWidgets);

    final wrapped = find.ancestor(
      of: inkWell.first,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.type == MaterialType.transparency &&
            widget.clipBehavior != Clip.none,
      ),
    );
    expect(
      wrapped,
      findsOneWidget,
      reason: 'kırpan bir Material yoksa vurgu şeridin dışına taşar',
    );
  });

  group('Açılış çalışma ekranındaki şerit', () {
    // Aynı hata oradaki şeritte de vardı: kural artık tek yerde
    // (`MoveScroller`) durduğu için ikisi birlikte düzeliyor.
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      OpeningService.instance.resetCache();
      await SettingsService.instance.load();
      Strings.language = AppLanguage.turkish;
    });

    tearDown(() {
      Strings.language = AppLanguage.system;
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('sona git şeridi de sona götürüyor', (tester) async {
      final moves = _longGame();
      final opening = Opening(
        id: 'deneme',
        eco: 'A00',
        family: 'Deneme',
        variation: 'Uzun',
        uciMoves: [for (final m in moves) m.move.uci],
        sanMoves: [for (final m in moves) m.san],
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      await tester.pumpWidget(
        MaterialApp(home: OpeningStudyScreen(opening: opening)),
      );
      await tester.pumpAndSettle();

      final strip = find.descendant(
        of: find.byType(OpeningStudyScreen),
        matching: find.byType(Scrollable),
      );
      ScrollPosition stripPosition() =>
          (tester.widget<Scrollable>(strip.first).controller
                  as ScrollController)
              .position;

      expect(stripPosition().pixels, 0);

      await tester.tap(find.byIcon(Icons.last_page_rounded));
      await tester.pumpAndSettle();

      final position = stripPosition();
      expect(
        position.pixels,
        position.maxScrollExtent,
        reason: 'şerit son hamleye gitmedi',
      );

      await tester.tap(find.byIcon(Icons.first_page_rounded));
      await tester.pumpAndSettle();
      expect(stripPosition().pixels, 0);
    });
  });
}
