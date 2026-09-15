import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/widgets/filter_strip.dart';

/// Süzgeç şeridi sığdığında sabit sekme gibi durmalı, sığmadığında
/// kaydırmalı olmalı. Eskiden hep kaydırmalıydı ve son çip ekranın
/// kenarından taşıyordu.
///
/// Testler gerçek etiket genişliğini değil **şeridin kararını** ölçüyor:
/// `flutter test` gerçek yazı tipi yerine her harfi kare sayan bir test
/// yazı tipi kullanıyor, o yüzden "dört Türkçe etiket telefona sığar mı"
/// sorusu testte anlamlı bir cevap vermiyor. Cihazda cevabı ölçüm
/// veriyor; burada ölçümün doğru dallandığı denetleniyor.

Future<void> _pump(
  WidgetTester tester,
  List<String> labels, {
  required double width,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FilterStrip(
          options: [
            for (final label in labels)
              FilterOption(
                label: label,
                selected: label == labels.first,
                onTap: () {},
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ölçüldüğünde şeride rahat sığan etiketler.
const _short = ['Bir', 'İki', 'Üç', 'Dört'];

/// Sığmayacak kadar uzun etiketler.
const _long = [
  'Tümü',
  'Çözülmemiş',
  'Çözülen',
  'Favoriler',
  'Beyaz kazanır',
  'Beraberlik',
  'Siyah kazanır',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sığan çipler sabit duruyor', (tester) async {
    await _pump(tester, _short, width: 400);

    expect(find.byType(ListView), findsNothing,
        reason: 'sığdığı hâlde kaydırmalı kalmış');
    for (final label in _short) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('sabit şeritte hiçbir çip ekrandan taşmıyor', (tester) async {
    await _pump(tester, _short, width: 400);

    for (final label in _short) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0),
          reason: '$label soldan taşıyor');
      expect(rect.right, lessThanOrEqualTo(400),
          reason: '$label sağdan taşıyor');
    }
  });

  testWidgets('sığmayan çipler kaydırmalıya düşüyor', (tester) async {
    await _pump(tester, _long, width: 400);

    expect(find.byType(ListView), findsOneWidget,
        reason: 'sığmadığı hâlde sabit kalmış, çipler taşar');
  });

  testWidgets('geniş ekranda uzun çipler de sabit duruyor', (tester) async {
    await _pump(tester, _long, width: 1400);

    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('dokunma seçeneği bildiriyor', (tester) async {
    String? tapped;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterStrip(
            options: [
              for (final label in _short)
                FilterOption(
                  label: label,
                  selected: false,
                  onTap: () => tapped = label,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Üç'));
    expect(tapped, 'Üç');
  });
}
