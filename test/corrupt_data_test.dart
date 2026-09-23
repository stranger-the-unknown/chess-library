import 'package:flutter_test/flutter_test.dart';

import 'package:chess_pgn_reader/services/opening_service.dart';
import 'package:chess_pgn_reader/services/puzzle_service.dart';
import 'package:chess_pgn_reader/services/storage_service.dart';
import 'package:chess_pgn_reader/services/app_store.dart';

import 'support/device.dart';

/// Bozuk bir kayıt uygulamanın o bölümünü kapatmamalı.
///
/// Koruma 9.0.3'te yalnızca oyun listelerinin yeni anahtarına konmuştu.
/// Açılışlar, bulmacalar ve eski liste anahtarı açıkta kalmıştı: yarım
/// yazılmış tek bir kayıt `jsonDecode`'da hata fırlatıyor, hata yükleme
/// yordamından ekrana kadar gidiyor ve o sekme hiç açılmıyordu.
///
/// Bozuk veri silinmiyor: `<anahtar>_bozuk` altında duruyor ki elle
/// kurtarılabilsin.

/// Yarım yazılmış JSON — diski dolan bir cihazda tam olarak böyle kalır.
const _broken = '[{"id":"a","name":"Yar';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bozuk açılış kaydı açılışlar sekmesini kapatmıyor', () async {
    await resetDevice({
      'openings_custom_v1': _broken,
      'openings_notes_v1': _broken,
      'openings_progress_v1': _broken,
    });
    OpeningService.instance.resetCache();

    expect(await OpeningService.instance.all(), isEmpty);
    expect(await OpeningService.instance.progressMap(), isEmpty);

    final store = AppStore.instance;
    expect(
      await store.getString('openings_custom_v1_bozuk'),
      _broken,
      reason: 'bozuk veri elle kurtarılabilsin diye saklanmalı',
    );
    expect(await store.getString('openings_notes_v1_bozuk'), _broken);
    expect(await store.getString('openings_progress_v1_bozuk'), _broken);
  });

  test('bozuk bulmaca kaydı bulmacalar sekmesini kapatmıyor', () async {
    await resetDevice({
      'puzzle_collections_v1': _broken,
      'puzzle_progress_v1': _broken,
    });
    PuzzleService.instance.resetCache();

    await PuzzleService.instance.collections();
    expect((await PuzzleService.instance.progressMap()), isEmpty);

    final store = AppStore.instance;
    expect(await store.getString('puzzle_collections_v1_bozuk'), _broken);
    expect(await store.getString('puzzle_progress_v1_bozuk'), _broken);
  });

  test('bozuk eski liste kaydı listelerim sekmesini kapatmıyor', () async {
    // 'playlists' 8.x öncesinden kalan anahtar; yeni anahtar yoksa
    // okunup taşınıyor. Taşıma sırasında bozuk veri hata fırlatıyordu.
    await resetDevice({'playlists': _broken});
    StorageService.instance.resetCache();

    expect(await StorageService.instance.loadPlaylists(), isEmpty);

    final store = AppStore.instance;
    expect(await store.getString('playlists_bozuk'), _broken);
  });
}
