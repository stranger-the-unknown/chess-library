import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
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
/// Anahtar listesi elle tutulmaz: `SharedPreferences` zaten yalnızca bu
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
    final prefs = await SharedPreferences.getInstance();

    final keys = prefs.getKeys().where((k) => !_notBackedUp.contains(k)).toList()
      ..sort();
    final data = <String, Object?>{};
    for (int i = 0; i < keys.length; i++) {
      final value = prefs.get(keys[i]);
      if (value == null) continue;
      data[keys[i]] = value;
      if (i % 8 == 7) {
        onProgress?.call(0.6 * (i + 1) / keys.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(0.6);

    final counts = countsOf(data);
    final payload = jsonEncode(data);
    onProgress?.call(0.8);

    final document = <String, Object?>{
      'app': magic,
      'format': formatVersion,
      'appVersion': appVersionName,
      'platform': defaultTargetPlatform.name,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': counts,
      // Dosyanın yarım yazılması ya da aktarımda bozulması sessizce
      // yanlış veri yüklenmesine yol açardı; bu damga onu yakalar.
      'checksum': checksum(payload),
      'data': data,
    };
    final text = const JsonEncoder.withIndent('  ').convert(document);
    onProgress?.call(1);
    return text;
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
  /// Yazmadan **önce** var olan verinin kopyası bellekte tutulur; yazma
  /// yarıda kalırsa eski hâle dönülür. Böylece başarısız bir içe
  /// aktarma kullanıcının verisini yarım bırakmaz.
  Future<void> apply(
    Map<String, Object?> data, {
    ImportMode mode = ImportMode.replace,
    ValueChanged<double>? onProgress,
  }) async {
    onProgress?.call(0);
    final prefs = await SharedPreferences.getInstance();
    final previous = <String, Object?>{
      for (final key in prefs.getKeys()) key: prefs.get(key),
    };

    try {
      if (mode == ImportMode.replace) {
        for (final key in previous.keys) {
          if (_notBackedUp.contains(key)) continue;
          await prefs.remove(key);
        }
      }
      onProgress?.call(0.1);

      final entries = data.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        Object? value = entries[i].value;
        if (mode == ImportMode.merge) {
          value = _merged(prefs, entries[i].key, value);
          if (value == null) continue;
        }
        // Yazma başarısızsa (disk dolu) geri yükleme başarılı
        // sayılmıyordu: ilerleme %100'e gidiyor, "içeri aktarıldı"
        // yazıyor ama veri diske hiç ulaşmıyordu.
        if (!await _write(prefs, entries[i].key, value)) {
          throw const FormatException('writeFailed');
        }
        if (i % 4 == 3) {
          onProgress?.call(0.1 + 0.85 * (i + 1) / entries.length);
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (_) {
      // Geri al: yazılanları temizleyip eski değerleri koy.
      for (final key in prefs.getKeys().toList()) {
        await prefs.remove(key);
      }
      for (final entry in previous.entries) {
        await _write(prefs, entry.key, entry.value);
      }
      await reloadServices();
      rethrow;
    }

    onProgress?.call(0.95);
    await reloadServices();
    onProgress?.call(1);
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
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getKeys().length;
    await prefs.clear();
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

  Future<bool> _write(SharedPreferences prefs, String key, Object? value) {
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is List) {
      return prefs.setStringList(key, value.map((e) => '$e').toList());
    }
    return prefs.remove(key);
  }

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
  Object? _merged(SharedPreferences prefs, String key, Object? incoming) {
    if (_mergeableLists.containsKey(key)) {
      if (incoming is! String) return null;
      final current = prefs.getString(key);
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
      final current = prefs.getString(key);
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
