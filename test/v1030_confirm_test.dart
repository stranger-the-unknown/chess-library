import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/l10n/app_strings.dart';
import 'package:chess_pgn_reader/screens/game_screen.dart';
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/services/unsaved_work.dart';
import 'package:chess_pgn_reader/widgets/app_dialogs.dart';
import 'package:chess_pgn_reader/widgets/chess_board_widget.dart';

/// 10.3.0: onay pencereleri ayarı.
///
/// Kapalıyken kaydedilmemiş hamlelerle çıkma, pencereyi kapatma, pes
/// etme ve yeniden başlatma sorulmuyor. Kayıtlı veriyi silen onaylar
/// ayardan bağımsız, her zaman soruluyor.

Future<void> _tapSquare(WidgetTester tester, String square) async {
  final rect = tester.getRect(find.byType(ChessBoardWidget));
  final s = rect.width / 8;
  await tester.tapAt(Offset(
    rect.left + ('abcdefgh'.indexOf(square[0]) + 0.5) * s,
    rect.top + (8 - int.parse(square[1]) + 0.5) * s,
  ));
  await tester.pump();
}

/// Ana ekran + üstüne itilmiş serbest tahta, bir hamle oynanmış.
Future<BuildContext> _boardWithMove(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(480, 1000);
  addTearDown(tester.view.reset);
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: key,
    home: const Scaffold(body: Text('ANA')),
  ));
  key.currentState!.push(MaterialPageRoute(
    builder: (_) => const GameScreen(title: 'Serbest'),
  ));
  await tester.pumpAndSettle();
  await _tapSquare(tester, 'e2');
  await _tapSquare(tester, 'e4');
  await tester.pumpAndSettle();
  expect(UnsavedWork.any, isTrue);
  return key.currentContext!;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'flutter.soundEnabled': false,
      'flutter.animateMoves': false,
      'flutter.soundDefaultsRestored': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/wakelock'),
            (c) async => null);
    Strings.language = AppLanguage.turkish;
    await SettingsService.instance.load();
  });

  test('ayar varsayılan olarak açık (davranış değişmiyor)', () {
    expect(SettingsService.instance.askConfirmations, isTrue);
  });

  testWidgets('kapalıyken kaydedilmemiş oyundan çıkmak sormuyor',
      (tester) async {
    SettingsService.instance.askConfirmations = false;
    await _boardWithMove(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(t('game.exitTitle')), findsNothing);
    expect(find.text('ANA'), findsOneWidget, reason: 'doğrudan çıkılmalı');
  });

  testWidgets('açıkken eskisi gibi soruyor', (tester) async {
    await _boardWithMove(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(t('game.exitTitle')), findsOneWidget);
  });

  testWidgets('kapalıyken pencereyi kapatmak sormuyor', (tester) async {
    SettingsService.instance.askConfirmations = false;
    final context = await _boardWithMove(tester);

    final leave = UnsavedWork.confirmExit(context);
    await tester.pumpAndSettle();
    expect(find.text(t('game.exitTitle')), findsNothing);
    expect(await leave, isTrue);
  });

  testWidgets('kayıtlı veriyi silen onay ayar kapalıyken de soruluyor',
      (tester) async {
    SettingsService.instance.askConfirmations = false;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    ));

    final answer = AppDialogs.confirm(
      context,
      title: 'Listeyi sil',
      message: 'Geri alınamaz.',
      destructive: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Listeyi sil'), findsOneWidget);
    await tester.tap(find.text(t('common.giveUp')));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
