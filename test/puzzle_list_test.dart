import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/models/puzzle.dart';
import 'package:chess_pgn_reader/screens/puzzles/puzzle_list_screen.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';

/// Numaralar ve sıralama birbirine karışmaya çok müsait: süzgeç açıkken
/// satırın numarası listedeki asıl numara olmalı, sıra ise ters. Bu iki
/// kural birbirinden bağımsız olduğu için ayrı ayrı denetlenir.

const _fens = [
  '3q1rk1/5pbp/5Qp1/8/8/2B5/5PPP/6K1 w - - 0 1',
  '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
  '8/8/3k4/8/8/8/6Q1/7K w - - 0 1',
  '8/8/8/4k3/8/8/4P3/4K3 w - - 0 1',
];

Future<PuzzleCollection> _seed({bool isEndgame = false}) async {
  SharedPreferences.setMockInitialValues({});
  PuzzleService.instance.resetCache();
  await SettingsService.instance.load();
  final collection = await PuzzleService.instance.createCollection(
    'Deneme',
    isEndgame: isEndgame,
  );
  await PuzzleService.instance.importFens(collection, _fens.join('\n'));
  return collection;
}

Future<void> _pump(WidgetTester tester, PuzzleCollection collection) async {
  // SettingsService.load() dili ayarlardan yeniden okur; metinleri
  // Türkçe aramak için dil tam ekrandan önce sabitlenir.
  Strings.language = AppLanguage.turkish;
  await tester.pumpWidget(
    MaterialApp(home: PuzzleListScreen(collection: collection)),
  );
  await tester.pumpAndSettle();
}

/// Ekrandaki "#n" başlıklarını göründükleri sırayla toplar.
List<String> _numbersOnScreen(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .where((text) => text.startsWith('#'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Strings.language = AppLanguage.turkish;
    // Süzgeç şeridi yatay kaydırılır; dar bir yüzeyde son çipler hiç
    // kurulmaz ve "yok" sanılır. Geniş bir pencerede sınanır.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.physicalSize = const Size(1600, 1400);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    Strings.language = AppLanguage.system;
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('liste baştan sona sıralanır', (tester) async {
    // Bulmaca kitapları baştan sona çözülür; liste de kitaptaki
    // sırayla açılmalı.
    final collection = await _seed();
    await _pump(tester, collection);

    expect(_numbersOnScreen(tester), ['#1', '#2', '#3', '#4']);
  });

  testWidgets('sıralama düğmesi yönü çevirir', (tester) async {
    final collection = await _seed();
    await _pump(tester, collection);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(_numbersOnScreen(tester), ['#4', '#3', '#2', '#1']);
  });

  testWidgets('süzgeç değişince sıralama varsayılana döner', (tester) async {
    // Ters sıralama tek bir bakış için açılıyor; süzgeç değişince o
    // niyet bitiyor. Açık kalsaydı kullanıcı her süzgeçte oku yeniden
    // tıklamak zorunda kalırdı.
    final collection = await _seed();
    await _pump(tester, collection);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(_numbersOnScreen(tester), ['#4', '#3', '#2', '#1']);

    await tester.tap(find.text('Çözülmemiş'));
    await tester.pumpAndSettle();
    expect(_numbersOnScreen(tester), ['#1', '#2', '#3', '#4']);
  });

  testWidgets('süzgeç açıkken numaralar listedeki asıl numara kalır', (
    tester,
  ) async {
    final collection = await _seed();
    final puzzles = await PuzzleService.instance.puzzlesOf(collection);
    // İkinci ve dördüncü bulmacayı çözülmüş yap.
    await PuzzleService.instance.markManySolved(
      [puzzles[1].id, puzzles[3].id],
      solved: true,
    );

    await _pump(tester, collection);
    await tester.tap(find.text('Çözülen'));
    await tester.pumpAndSettle();

    // Süzgeç iki satır bırakır ama numaraları 1 ve 2 değil, 2 ve 4.
    expect(_numbersOnScreen(tester), ['#2', '#4']);
  });

  testWidgets('sonuç süzgeçleri yalnızca oyun sonu listesinde görünür', (
    tester,
  ) async {
    final normal = await _seed();
    await _pump(tester, normal);
    expect(find.text('Beyaz kazanır'), findsNothing);

    final endgame = await _seed(isEndgame: true);
    await _pump(tester, endgame);
    expect(find.text('Beyaz kazanır'), findsOneWidget);
    expect(find.text('Beraberlik'), findsOneWidget);
    expect(find.text('Siyah kazanır'), findsOneWidget);
  });

  testWidgets('kaldırılan süzgeçler artık yok', (tester) async {
    final collection = await _seed(isEndgame: true);
    await _pump(tester, collection);
    expect(find.text('Mat var'), findsNothing);
    expect(find.text('Geçerken alma'), findsNothing);
  });

  group('Aralık işaretleme', () {
    test('yalnızca aralıktakiler işaretlenir', () async {
      final collection = await _seed();
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);

      // 2 ile 3 arası: listedeki ikinci ve üçüncü bulmaca.
      final changed = await PuzzleService.instance.markManySolved(
        [puzzles[1].id, puzzles[2].id],
        solved: true,
      );
      expect(changed, 2);

      final progress = await PuzzleService.instance.progressMap();
      expect(progress[puzzles[0].id]?.solved ?? false, isFalse);
      expect(progress[puzzles[1].id]?.solved, isTrue);
      expect(progress[puzzles[2].id]?.solved, isTrue);
      expect(progress[puzzles[3].id]?.solved ?? false, isFalse);
    });

    test('zaten işaretli olanlar sayılmaz', () async {
      final collection = await _seed();
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);
      final ids = puzzles.map((p) => p.id).toList();

      expect(await PuzzleService.instance.markManySolved(ids, solved: true), 4);
      expect(await PuzzleService.instance.markManySolved(ids, solved: true), 0);
      expect(await PuzzleService.instance.markManySolved(ids, solved: false), 4);
    });

    test('işaret kaldırılınca çözüm tarihi de silinir', () async {
      final collection = await _seed();
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);

      await PuzzleService.instance.markManySolved(
        [puzzles.first.id],
        solved: true,
      );
      expect(
        (await PuzzleService.instance.progressOf(puzzles.first.id)).solvedAt,
        isNotNull,
      );

      await PuzzleService.instance.markManySolved(
        [puzzles.first.id],
        solved: false,
      );
      expect(
        (await PuzzleService.instance.progressOf(puzzles.first.id)).solvedAt,
        isNull,
      );
    });
  });

  group('Bugün çözülen', () {
    test('bugün çözülenler sayılır, dünküler sayılmaz', () async {
      final collection = await _seed();
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);

      await PuzzleService.instance.markSolved(puzzles[0].id);
      await PuzzleService.instance.markSolved(puzzles[1].id);
      expect(await PuzzleService.instance.solvedToday(collection), 2);

      // Üçüncüsünü dün çözülmüş gibi göster.
      final progress = await PuzzleService.instance.progressOf(puzzles[2].id);
      progress
        ..solved = true
        ..solvedAt = DateTime.now().subtract(const Duration(days: 1));
      expect(await PuzzleService.instance.solvedToday(collection), 2);
    });

    test('eski kayıtlarda çözüm tarihi yoksa sayılmaz', () async {
      final collection = await _seed();
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);
      final progress = await PuzzleService.instance.progressOf(puzzles[0].id);
      // v2'den gelen kayıtta solvedAt yoktur.
      progress
        ..solved = true
        ..solvedAt = null;
      expect(await PuzzleService.instance.solvedToday(collection), 0);
    });
  });

  group('Oyun sonu işareti', () {
    test('sonradan açılıp kapatılabilir ve kalıcıdır', () async {
      final collection = await _seed();
      expect(collection.isEndgame, isFalse);

      await PuzzleService.instance.setEndgame(collection.id, true);
      PuzzleService.instance.resetCache();
      final reloaded = (await PuzzleService.instance.collections()).first;
      expect(reloaded.isEndgame, isTrue);

      await PuzzleService.instance.setEndgame(collection.id, false);
      PuzzleService.instance.resetCache();
      expect((await PuzzleService.instance.collections()).first.isEndgame,
          isFalse);
    });

    test('sonuç etiketleri iki yazımda da tanınır', () async {
      final collection = await _seed();
      await PuzzleService.instance.importFens(
        collection,
        '${_fens[0]}|beyaz-kazanir\n'
        '${_fens[1]}|draw\n'
        '${_fens[2]}|black-wins',
      );
      final puzzles = await PuzzleService.instance.puzzlesOf(collection);
      expect(puzzles.where((p) => p.marksWhiteWin), hasLength(1));
      expect(puzzles.where((p) => p.marksDraw), hasLength(1));
      expect(puzzles.where((p) => p.marksBlackWin), hasLength(1));
    });
  });
}
