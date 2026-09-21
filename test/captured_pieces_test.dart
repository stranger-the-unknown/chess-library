import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chess_pgn_reader/models/chess_engine.dart' as engine;
import 'package:chess_pgn_reader/services/settings_service.dart';
import 'package:chess_pgn_reader/widgets/captured_pieces.dart';

/// Alınan taşlar şeridi dar ekranda taşmamalı.
///
/// Şerit oyuncu satırının yarısını alıyor (360 dp'lik bir telefonda
/// ~151 dp), dolu bir takım ise ~190 dp istiyor. Taşan kısım ekranın
/// kenarında kesiliyordu: önce materyal farkı yazısı, sonra son taşlar
/// görünmez oluyordu.

/// Siyahın şahı dışında her şeyi alınmış: 8 piyon, 2 at, 2 fil, 2 kale
/// ve vezir. Beyazın şeridinin en uzun hâli.
const _allCaptured = '4k3/8/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1';

Future<Rect> _pumpStrip(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: CapturedPieces(
              side: engine.Color.white,
              game: engine.ChessGame.fromFen(_allCaptured),
              size: 16,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byType(CapturedPieces));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  testWidgets('dolu şerit dar satıra sığıyor', (tester) async {
    // 360 dp'lik telefonda şeride kalan yer.
    final strip = await _pumpStrip(tester, 151);

    // Taşma olsaydı RenderFlex hata bildirirdi.
    expect(tester.takeException(), isNull);

    // Materyal farkı şeridin sonunda: kesilen ilk şey oydu.
    final advantage = tester.getRect(find.text('+39'));
    expect(advantage.right, lessThanOrEqualTo(strip.right + 0.5),
        reason: 'fark yazısı şeridin dışına taşıyor');
  });

  testWidgets('yer bolken taşlar küçültülmüyor', (tester) async {
    final wide = await _pumpStrip(tester, 400);
    final wideSize = tester.getRect(find.text('+39')).width;
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('+39')).right,
        lessThanOrEqualTo(wide.right + 0.5));

    final narrowStrip = await _pumpStrip(tester, 151);
    final narrowSize = tester.getRect(find.text('+39')).width;
    expect(narrowStrip.width, 151);

    // Dar satırda tüm şerit oranlı küçülüyor; geniş satırda dokunulmuyor.
    expect(narrowSize, lessThan(wideSize));
  });
}
