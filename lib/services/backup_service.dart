import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/app_strings.dart';
import 'app_store.dart';
import 'opening_service.dart';
import 'puzzle_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Veri kökten değiştiğinde artan sayaç.
///
/// Ana ekranlar bir `IndexedStack` içinde canlı kalıyor: sekme
/// değiştirmek `initState`'i yeniden çalıştırmaz. Yedek geri
/// yüklendiğinde bu sayaç artar, kabuk da sayfaları sıfırdan kurar;
/// yoksa geri yükleme çalıştığı hâlde ekranda eski veri kalıyordu.
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

/// İçe aktarma biçimi.
enum ImportMode {
  /// Var olan veriyi silip yedektekiyle değiştirir. Cihaz değiştirirken
  /// kullanılır: iki taraf birebir aynı olur.
  replace,

  /// Yedeği var olanın üstüne ekler. Aynı kimlikli kayıt varsa yedektinki
  /// yazar; olmayanlar eklenir. Ayarlara dokunulmaz.
  merge,
}

/// Yedekteki verinin özeti; içe aktarmadan önce kullanıcıya gösterilir.
class BackupSummary {
  final String appVersion;
  final String platform;
  final DateTime? exportedAt;
  final int playlists;
  final int games;
  final int puzzleCollections;
  final int puzzles;
  final int openings;
  final bool hasSettings;

  const BackupSummary({
    this.appVersion = '',
    this.platform = '',
    this.exportedAt,
    this.playlists = 0,
    this.games = 0,
    this.puzzleCollections = 0,
    this.puzzles = 0,
    this.openings = 0,
    this.hasSettings = false,
  });
}

/// Uygulamanın sakladığı **her şeyin** tek dosyaya yedeği.
///
/// Kapsam: oyun listeleri ve içindeki oyunlar (okundu, favori, not),
/// bulmaca listeleri ve ilerlemesi (çözüldü, favori, deneme, çözüm
/// tarihi), eklenen açılışlar ve açılış ilerlemesi/notları, ayarlar.
///
/// Anahtar listesi elle tutulmaz: depo ([AppStore]) yalnızca bu
/// uygulamanın verisini tutar, bu yüzden içindeki bütün anahtarlar
/// yazılır. Böylece ileride eklenen bir ayar yedeğin dışında kalmaz —
/// elle tutulan listelerde en sık yapılan hata buydu.
///
/// Dosya düz JSON metnidir: Windows ile Android arasında olduğu gibi
/// taşınır, mutlak yol ya da platforma özgü değer içermez.
class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  /// Dosya biçiminin sürümü. Yapı değişirse artar; okuyucu eski
  /// sürümleri de kabul eder.
  static const int formatVersion = 1;

  static const String magic = 'chess-library-backup';

  /// Birleştirmede kimliğe göre eşlenen listeler.
  ///
  /// Değer, kayıtların JSON'daki kimlik alanıdır.
  static const Map<String, String> _mergeableLists = {
    'playlists_v2': 'id',
    'puzzle_collections_v1': 'id',
    'openings_custom_v1': 'id',
  };

  /// Birleştirmede anahtar/değer olarak katılan haritalar.
  static const List<String> _mergeableMaps = [
    'puzzle_overrides_v1',
    'puzzle_progress_v1',
    'openings_progress_v1',
    'openings_notes_v1',
  ];

  // -------------------------------------------------------------------
  // Dışa aktarma
  // -------------------------------------------------------------------

  /// Tüm veriyi JSON metnine çevirir.
  ///
  /// [onProgress] 0 ile 1 arasında ilerleme bildirir; büyük veride
  /// ekranın donmaması için arada olay döngüsüne dönülür.
  /// Yedeğe girmeyen anahtarlar.
  ///
  /// Analiz kayıtları cihaza özeldir: yüz oyunun hamle hamle
  /// değerlendirmesi yedeği gereksiz şişirirdi ve başka cihazda yeniden
  /// üretilebilir. Geri yüklerken de dokunulmuyor, yoksa cihazdaki
  /// analizler yedekteki eskisiyle ezilirdi.
  /// 9.0.0'da kaldırılan analiz listelerinin anahtarı; eski bir yedek
  /// geri yüklenince o veri diriltilmesin diye dışarıda bırakılıyor.
  static const Set<String> _notBackedUp = {'analysis_lists_v1'};

  Future<String> exportAll({ValueChanged<double>? onProgress}) async {
    onProgress?.call(0);
    // Ayarlar ve veri tek yerden: Windows'ta veri ayrı dosyalarda duruyor,
    // ama yedeğin biçimi (anahtarlar ve değer türleri) aynı kalıyor. Yani
    // eski sürümün yedeği bu sürümde, bu sürümün yedeği eski sürümde
    // açılıyor.
    final all = await AppStore.instance.readAll();

    final keys = all.keys.where((k) => !_notBackedUp.contains(k)).toList()
      ..sort();
    final data = <String, Object?>{};
    for (int i = 0; i < keys.length; i++) {
      final value = all[keys[i]];
      if (value == null) continue;
      data[keys[i]] = value;
      if (i % 8 == 7) {
        onProgress?.call(0.6 * (i + 1) / keys.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(0.6);

    final text = _encodeDocument(data);
    onProgress?.call(1);
    return text;
  }

  /// [data]yı yedek dosyası biçiminde metne çevirir.
  String _encodeDocument(Map<String, Object?> data) {
    final payload = jsonEncode(data);
    final document = <String, Object?>{
      'app': magic,
      'format': formatVersion,
      'appVersion': appVersionName,
      'platform': defaultTargetPlatform.name,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': countsOf(data),
      // Dosyanın yarım yazılması ya da aktarımda bozulması sessizce
      // yanlış veri yüklenmesine yol açardı; bu damga onu yakalar.
      'checksum': checksum(payload),
      'data': data,
    };
    // Girintili yazım dosyayı büyütüyordu; binlerce oyunluk bir
    // kütüphanede fark ciddi. Okuyan taraf için bir şey değişmiyor.
    return jsonEncode(document);
  }

  // -------------------------------------------------------------------
  // Okuma ve içe aktarma
  // -------------------------------------------------------------------

  /// Yedeği çözümler ve özetini döner; hiçbir şey yazmaz.
  ///
  /// Kullanıcıya "bu dosyada şu kadar veri var, devam edelim mi?"
  /// diyebilmek için ayrı bir adımdır.
  Future<(BackupSummary, Map<String, Object?>)> read(String text) async {
    Object? decoded;
    try {
      decoded = await _decode(text);
    } on FormatException {
      throw const FormatException('badFile');
    }
    if (decoded is! Map) throw const FormatException('badFile');

    final document = Map<String, Object?>.from(decoded);
    if (document['app'] != magic || document['data'] is! Map) {
      throw const FormatException('badFile');
    }
    final format = document['format'];
    if (format is int && format > formatVersion) {
      throw const FormatException('newerFormat');
    }
    final data = Map<String, Object?>.from(document['data'] as Map);

    final stored = document['checksum'];
    if (stored is String && stored != checksum(jsonEncode(data))) {
      throw const FormatException('corrupt');
    }

    final counts = countsOf(data);
    return (
      BackupSummary(
        appVersion: '${document['appVersion'] ?? ''}',
        platform: '${document['platform'] ?? ''}',
        exportedAt: DateTime.tryParse('${document['exportedAt']}'),
        playlists: counts['playlists'] ?? 0,
        games: counts['games'] ?? 0,
        puzzleCollections: counts['puzzleCollections'] ?? 0,
        puzzles: counts['puzzles'] ?? 0,
        openings: counts['openings'] ?? 0,
        hasSettings: data.containsKey('pieceSet') ||
            data.containsKey('boardTheme') ||
            data.containsKey('themeMode'),
      ),
      data,
    );
  }

  /// [read] ile çözümlenmiş veriyi diske yazar.
  ///
  /// Yazmadan **önce** var olan verinin tam kopyası diske yazılır
  /// (bkz. [recoverInterruptedRestore]); kopya yazılamazsa geri yükleme
  /// hiç başlamaz. Yazma hata verirse eski hâle hemen dönülür. Süreç
  /// yarıda ölürse (pencere kapatıldı, sistem uygulamayı öldürdü) dönüş
  /// bir sonraki açılışta o kopyadan yapılır. Böylece başarısız bir içe
  /// aktarma kullanıcının verisini yarım bırakmaz.
  ///
  /// Değiştir kipinde yeni değerler **önce** yazılıyor, yedekte olmayan
  /// anahtarlar en son siliniyor. Eskiden önce her şey siliniyordu;
  /// arada kesilen bir geri yükleme cihazı neredeyse boş bırakıyordu.
  Future<void> apply(
    Map<String, Object?> data, {
    ImportMode mode = ImportMode.replace,
    ValueChanged<double>? onProgress,
  }) async {
    onProgress?.call(0);
    final store = AppStore.instance;
    final Map<String, Object?> previous = await store.readAll();
    final snapshot = await _writeSnapshot(previous);
    onProgress?.call(0.1);

    try {
      final entries = data.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        Object? value = entries[i].value;
        if (mode == ImportMode.merge) {
          value = await _merged(entries[i].key, value);
          if (value == null) continue;
        }
        // Yazma başarısızsa (disk dolu) geri yükleme başarılı
        // sayılmıyordu: ilerleme %100'e gidiyor, "içeri aktarıldı"
        // yazıyor ama veri diske hiç ulaşmıyordu.
        if (!await store.write(entries[i].key, value)) {
          throw const FormatException('writeFailed');
        }
        await debugAfterWrite?.call(i + 1);
        if (i % 4 == 3) {
          onProgress?.call(0.1 + 0.8 * (i + 1) / entries.length);
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (mode == ImportMode.replace) {
        for (final key in previous.keys) {
          if (_notBackedUp.contains(key) || data.containsKey(key)) continue;
          await store.remove(key);
        }
      }
    } catch (_) {
      // Eski hâle dön. Dönüş de tamamlanamazsa kopya kalır, açılışta
      // yeniden denenir.
      if (await _restoreExactly(previous)) {
        await _deleteSnapshot(snapshot);
      }
      await reloadServices();
      rethrow;
    }

    onProgress?.call(0.95);
    await reloadServices();
    await _deleteSnapshot(snapshot);
    onProgress?.call(1);
  }

  /// Yarıda kalmış bir geri yüklemeyi açılışta geri alır.
  ///
  /// [apply] başlamadan önce yazdığı kopyayı ancak iş bitince siliyor;
  /// açılışta kopya duruyorsa süreç geri yükleme sırasında ölmüş
  /// demektir ve disk yarı eski, yarı yeni bir hâldedir. Veri geri
  /// yüklemeden önceki hâline döndürülür; kullanıcı yedeği yeniden
  /// yükleyebilir. Bir şey yapıldıysa `true` döner.
  Future<bool> recoverInterruptedRestore() async {
    final File file;
    try {
      file = await _snapshotFile();
      if (!await file.exists()) return false;
    } catch (_) {
      return false;
    }
    final Map<String, Object?> previous;
    try {
      final (_, data) = await read(await file.readAsString());
      previous = data;
    } catch (_) {
      // Kopya yarım ya da boş: geri yükleme veriye dokunmadan önce
      // kesilmiş (kopya tamamlanmadan hiçbir şey yazılmıyor).
      await _deleteSnapshot(file);
      return false;
    }
    if (!await _restoreExactly(previous)) return false;
    await reloadServices();
    await _deleteSnapshot(file);
    return true;
  }

  /// Geri yükleme öncesi kopyanın bulunduğu klasör. Testler değiştirir.
  @visibleForTesting
  static Future<Directory> Function() snapshotDirectory =
      getApplicationSupportDirectory;

  /// Her yazmadan sonra çağrılır; testler süreci o noktada "öldürür".
  @visibleForTesting
  static Future<void> Function(int written)? debugAfterWrite;

  Future<File> _snapshotFile() async {
    final dir = await snapshotDirectory();
    return File('${dir.path}${Platform.pathSeparator}restore-snapshot.json');
  }

  /// Var olan veriyi geri yüklemeden önce diske yazar.
  ///
  /// Önce geçici dosyaya yazılıp sonra yeniden adlandırılıyor: yarım
  /// yazılmış bir kopya asıl adla hiç görünmez. Yazılamazsa (disk dolu)
  /// geri yükleme reddedilir; güvencesiz başlamaktansa hiç başlamamak.
  Future<File> _writeSnapshot(Map<String, Object?> previous) async {
    try {
      final file = await _snapshotFile();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(_encodeDocument(previous), flush: true);
      return await temp.rename(file.path);
    } catch (_) {
      throw const FormatException('writeFailed');
    }
  }

  /// Kopyayı kaldırır. Silinemezse (Windows'ta dosya kısa süre kilitli
  /// kalabiliyor) boşaltılır: boş kopya açılışta geri alınmaz, yani
  /// başarılı bir geri yükleme sonradan bozulmaz.
  Future<void> _deleteSnapshot(File file) async {
    try {
      await file.delete();
      return;
    } catch (_) {}
    try {
      await file.writeAsString('', flush: true);
    } catch (_) {}
  }

  /// Deponun içeriğini tam olarak [previous] yapar: önce değerler
  /// yazılır, sonra fazlalık anahtarlar silinir. Her şey yazılabildiyse
  /// `true` döner.
  Future<bool> _restoreExactly(Map<String, Object?> previous) async {
    final store = AppStore.instance;
    var ok = true;
    for (final entry in previous.entries) {
      if (!await store.write(entry.key, entry.value)) ok = false;
    }
    for (final key in (await store.readAll()).keys.toList()) {
      if (!previous.containsKey(key)) await store.remove(key);
    }
    return ok;
  }

  /// Açık ekranların eski veriyi göstermemesi için bütün önbellekleri
  /// boşaltır ve ayarları yeniden okur.
  /// Uygulamanın sakladığı her şeyi siler.
  ///
  /// Android'in otomatik yedeklemesi, uygulamayı kaldırıp yeniden
  /// kurunca eski veriyi geri getiriyor; kullanıcının "sıfırdan başlama"
  /// yolu bu yüzden uygulamanın içinde olmalı.
  ///
  /// Tek tek anahtar silmek yerine hepsi siliniyor: ileride eklenen bir
  /// anahtar unutulursa yarım temizlenmiş bir durum kalırdı.
  Future<int> wipeAll() async {
    final store = AppStore.instance;
    final count = (await store.readAll()).length;
    await store.clear();
    await reloadServices();
    return count;
  }

  Future<void> reloadServices() async {
    StorageService.instance.resetCache();
    PuzzleService.instance.resetCache();
    OpeningService.instance.resetCache();
    await SettingsService.instance.load();
    // Açık ekranlar kendi verilerini `initState` içinde okuyor; sayaç
    // artınca kabuk onları yeniden kurar.
    dataVersion.value++;
  }

  // -------------------------------------------------------------------
  // Yardımcılar
  // -------------------------------------------------------------------

  /// Birleştirme kipinde yazılacak değeri üretir.
  ///
  /// Kimlikli listelerde yedekteki kayıt aynı kimlikli eskisinin yerine
  /// geçer, geri kalanlar korunur. Haritalarda yedektinin anahtarları
  /// üste yazılır. Tanınmayan anahtarlara (ayarlar dâhil) dokunulmaz.
  ///
  /// Cihazdaki değer **yalnızca** birleştirilebilir anahtarlarda okunuyor.
  /// Eskiden en başta `getString` çağrılıyordu; cihazda aynı adla bir
  /// mantıksal ayar duruyorsa (ör. `soundEnabled`) bu çağrı tür hatasıyla
  /// patlıyor ve birleştirme kipiyle geri yükleme çöküyordu.
  Future<Object?> _merged(String key, Object? incoming) async {
    if (_mergeableLists.containsKey(key)) {
      if (incoming is! String) return null;
      final current = await AppStore.instance.getString(key);
      if (current == null) return incoming;
      final idField = _mergeableLists[key]!;
      final byId = <String, Map<String, dynamic>>{};
      for (final item in jsonDecode(current) as List) {
        final map = Map<String, dynamic>.from(item as Map);
        byId['${map[idField]}'] = map;
      }
      for (final item in jsonDecode(incoming) as List) {
        final map = Map<String, dynamic>.from(item as Map);
        byId['${map[idField]}'] = map;
      }
      return jsonEncode(byId.values.toList());
    }

    if (_mergeableMaps.contains(key)) {
      if (incoming is! String) return null;
      final current = await AppStore.instance.getString(key);
      if (current == null) return incoming;
      final merged = Map<String, dynamic>.from(jsonDecode(current) as Map)
        ..addAll(Map<String, dynamic>.from(jsonDecode(incoming) as Map));
      return jsonEncode(merged);
    }

    // Ayarlar ve tanınmayan anahtarlar: cihazın kendi tercihi kalsın.
    return null;
  }

  /// Yedekteki kayıt sayıları. Bozuk bir bölüm sayımı durdurmaz.
  @visibleForTesting
  Map<String, int> countsOf(Map<String, Object?> data) {
    int playlists = 0, games = 0, collections = 0, puzzles = 0, openings = 0;

    final rawPlaylists = data['playlists_v2'] ?? data['playlists'];
    if (rawPlaylists is String) {
      try {
        for (final entry in jsonDecode(rawPlaylists) as List) {
          playlists++;
          final list = (entry as Map)['games'];
          if (list is List) games += list.length;
        }
      } catch (_) {
        playlists = 0;
        games = 0;
      }
    }

    final rawCollections = data['puzzle_collections_v1'];
    if (rawCollections is String) {
      try {
        for (final entry in jsonDecode(rawCollections) as List) {
          collections++;
          final list = (entry as Map)['puzzles'];
          if (list is List) puzzles += list.length;
        }
      } catch (_) {
        collections = 0;
        puzzles = 0;
      }
    }

    final rawOpenings = data['openings_custom_v1'];
    if (rawOpenings is String) {
      try {
        openings = (jsonDecode(rawOpenings) as List).length;
      } catch (_) {
        openings = 0;
      }
    }

    return {
      'playlists': playlists,
      'games': games,
      'puzzleCollections': collections,
      'puzzles': puzzles,
      'openings': openings,
    };
  }

  /// Büyük dosyalarda çözümlemeyi ayrı bir iş parçacığına taşır.
  ///
  /// `jsonDecode` bloklayıcıdır: birkaç megabaytlık bir yedekte ana iş
  /// parçacığında saniyelerce takılır ve ilerleme çubuğu bile dönmez.
  Future<Object?> _decode(String text) {
    if (text.length < 256 * 1024) return Future.value(jsonDecode(text));
    return compute(jsonDecode, text);
  }

  /// FNV-1a (64 bit), onaltılık.
  ///
  /// Güvenlik için değil, bozulma sezmek için: ek paket gerektirmez ve
  /// megabaytlık metinleri milisaniyeler içinde özetler.
  @visibleForTesting
  static String checksum(String text) {
    const int prime = 0x100000001b3;
    int hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(text)) {
      hash = (hash ^ byte) * prime;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  /// Çözümleme hatasının kullanıcıya gösterilecek karşılığı.
  static String messageFor(Object error) {
    if (error is FormatException) {
      switch (error.message) {
        case 'newerFormat':
          return t('backup.newerFormat');
        case 'corrupt':
          return t('backup.corrupt');
        case 'writeFailed':
          return t('backup.writeFailed');
        default:
          return t('backup.badFile');
      }
    }
    return '$error';
  }
}
