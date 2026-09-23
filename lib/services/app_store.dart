import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'corrupt_data.dart';

/// Uygulamanın kalıcı verisine tek giriş noktası.
///
/// Oyun listeleri, bulmacalar, açılışlar ve ilerleme buradan okunup
/// yazılıyor; yedekleme de bütün anahtarları buradan görüyor. Ayarlar
/// ayrı: [SettingsService] onları doğrudan `SharedPreferences`'ta tutuyor.
///
/// İki gerçekleştirme var:
/// * [PrefsStore] — her şey `SharedPreferences`'ta. Android'de ve
///   testlerde. Android eklentisi zaten atomik ve arka planda yazıyor.
/// * [FileStore] — Windows. Veri anahtarları kendi dosyalarında, atomik
///   yazılıyor; ayarlar küçük tercih dosyasında kalıyor.
abstract class AppStore {
  /// Etkin depo. Windows'ta açılışta [FileStore] ile değiştiriliyor.
  static AppStore instance = PrefsStore();

  /// Büyük ve sık değişen veri. Windows'ta her biri ayrı dosyada.
  ///
  /// Ayar anahtarları bilerek dışarıda: küçükler ve tercih dosyasında
  /// kalmaları [SettingsService]'e hiç dokunmamayı sağlıyor.
  static const Set<String> dataKeys = {
    'playlists_v2',
    'playlists', // 9.0.3 öncesi oyun listeleri
    'puzzle_collections_v1',
    'puzzle_overrides_v1',
    'puzzle_progress_v1',
    'openings_custom_v1',
    'openings_progress_v1',
    'openings_notes_v1',
    'openings_hidden_v1',
  };

  /// Okunamayan bir kaydın kopyasının eki (bkz. `readOrQuarantine`).
  static const String quarantineSuffix = '_bozuk';

  static bool isDataKey(String key) {
    final base = key.endsWith(quarantineSuffix)
        ? key.substring(0, key.length - quarantineSuffix.length)
        : key;
    return dataKeys.contains(base);
  }

  Future<String?> getString(String key);
  Future<List<String>?> getStringList(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> remove(String key);

  /// Bütün anahtarlar ve değerleri (ayarlar dâhil); yedekleme için.
  Future<Map<String, Object>> readAll();

  /// Her şeyi siler (ayarlar dâhil).
  Future<void> clear();

  /// Yedekten gelen değeri türüne göre yazar.
  ///
  /// Tanınmayan tür anahtarı siler. Veri anahtarları yalnızca metin ya
  /// da metin listesi olabilir; başka bir tür (bozuk yedek) yazılmıyor.
  Future<bool> write(String key, Object? value) async {
    if (value is String) return setString(key, value);
    if (value is List) {
      return setStringList(key, value.map((e) => '$e').toList());
    }
    if (isDataKey(key)) return remove(key);
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    return prefs.remove(key);
  }
}

/// Her şey `SharedPreferences`'ta (Android, testler).
///
/// `SharedPreferences.getInstance()` her çağrıda yeniden alınıyor:
/// testler depoyu `setMockInitialValues` ile sıfırlıyor ve saklanan bir
/// örnek eskide kalırdı.
class PrefsStore extends AppStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async {
    final value = (await _prefs).get(key);
    return value is String ? value : null;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final value = (await _prefs).get(key);
    return value is List ? value.map((e) => '$e').toList() : null;
  }

  @override
  Future<bool> setString(String key, String value) async =>
      (await _prefs).setString(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) async =>
      (await _prefs).setStringList(key, value);

  @override
  Future<bool> remove(String key) async => (await _prefs).remove(key);

  @override
  Future<Map<String, Object>> readAll() async {
    final prefs = await _prefs;
    final result = <String, Object>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  @override
  Future<void> clear() async {
    await (await _prefs).clear();
  }
}

/// Windows: veri anahtarları `veri\` klasöründe, her biri kendi
/// dosyasında.
///
/// Neden: Windows'un `SharedPreferences` eklentisi bütün veriyi (bir
/// kullanıcıda 5,5 MB) tek dosyada tutuyor ve **her** yazmada — tek bir
/// ayar ya da bulmaca denemesi bile — dosyanın tamamını ana iş
/// parçacığında, atomik olmadan baştan yazıyordu. Yazma yarıda kalınca
/// bütün veri gidiyordu (B-1), her yazma arayüzü ~160 ms donduruyordu
/// (B-3).
///
/// Burada her anahtar kendi dosyasına **geçici dosyaya yaz, diske boşalt,
/// yeniden adlandır** yoluyla yazılıyor: yarıda kalan bir yazma eski
/// dosyayı olduğu gibi bırakıyor. Bir bulmaca denemesi yalnızca ilerleme
/// dosyasını, bir ayar yalnızca küçük tercih dosyasını yazıyor.
///
/// Değişmez kural: bir veri anahtarı tercih dosyasında **da** duruyorsa
/// geçerli olan odur (henüz taşınmamış ya da eski bir sürümle yazılmış).
/// Taşıma, yarım kalan taşıma ve eski sürüme dönüp geri gelme bu tek
/// kuralla doğru çalışıyor.
class FileStore extends AppStore {
  FileStore._(this.directory);

  /// Veri dosyalarının klasörü.
  final Directory directory;

  final Map<String, Object> _memory = {};

  /// Aynı anahtara art arda gelen yazmalar sırayla yapılsın: yoksa iki
  /// yazma aynı geçici dosyayı paylaşırdı.
  final Map<String, Future<bool>> _queue = {};

  static const String _stringExt = '.txt';
  static const String _listExt = '.list.json';

  /// Klasörü açar, dosyaları okur ve tercih dosyasında kalan veriyi
  /// taşır.
  ///
  /// Taşıma başarısız olursa hata fırlatmıyor: taşınamayan anahtar
  /// tercih dosyasında kalıyor ve yukarıdaki kural gereği okunmaya devam
  /// ediyor; bir sonraki açılışta yeniden deneniyor. Klasör ya da bir
  /// dosya okunamazsa hata fırlatıyor; çağıran [PrefsStore] ile devam
  /// etmeli.
  static Future<FileStore> open(Directory supportDir) async {
    final dir = Directory('${supportDir.path}${Platform.pathSeparator}veri');
    await dir.create(recursive: true);
    final store = FileStore._(dir);
    await store._load();
    try {
      await store._migrate(supportDir);
    } catch (_) {
      // Taşınamayan veri tercih dosyasında duruyor; kural gereği okunuyor.
    }
    return store;
  }

  /// Taşımada eski tercih dosyasının kopyasının adı.
  @visibleForTesting
  static String migrationCopyPrefix = 'shared_preferences.tasima-oncesi-';

  File _fileFor(String key, {required bool list}) => File(
      '${directory.path}${Platform.pathSeparator}$key${list ? _listExt : _stringExt}');

  static String _stamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');

  Future<void> _load() async {
    final entries = await directory.list().toList();
    for (final entity in entries) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        // Yeniden adlandırılamamış, yani yarım kalmış bir yazma. Asıl
        // dosya eski hâliyle duruyor.
        try {
          await entity.delete();
        } catch (_) {}
        continue;
      }
      if (name.endsWith(_listExt)) {
        final key = name.substring(0, name.length - _listExt.length);
        if (!AppStore.isDataKey(key)) continue;
        final text = await _readWithRetry(entity);
        try {
          _memory[key] =
              (jsonDecode(text) as List).map((e) => '$e').toList();
        } catch (_) {
          // Kendi yazdığımız bir dosya bozuk çıktı: kenara al, silme.
          await entity.rename('${entity.path}.bozuk-${_stamp()}');
          corruptRecords.value++;
        }
      } else if (name.endsWith(_stringExt)) {
        final key = name.substring(0, name.length - _stringExt.length);
        if (!AppStore.isDataKey(key)) continue;
        _memory[key] = await _readWithRetry(entity);
      }
      // `.eski-...`, `.bozuk-...` gibi saklanan kopyalar okunmuyor.
    }
  }

  /// Okur; dosya o anda kilitliyse (virüs tarayıcısı) biraz bekleyip
  /// yeniden dener.
  static Future<String> _readWithRetry(File file) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await file.readAsString();
      } catch (_) {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  /// Tercih dosyasında kalan veri anahtarlarını dosyalara taşır.
  ///
  /// Sıra, hiçbir anda verinin tek kopyası riske girmeyecek şekilde:
  /// 1. Tercih dosyasının bire bir kopyası alınıyor (silinmiyor).
  /// 2. Her anahtar kendi dosyasına yazılıp **geri okunarak**
  ///    karşılaştırılıyor. Aynı adla farklı içerikli bir dosya varsa
  ///    (eski sürüme dönülüp geri gelinmiş) üstüne yazılmıyor, yeniden
  ///    adlandırılıp saklanıyor.
  /// 3. Ancak doğrulanan anahtarlar tercih dosyasından siliniyor.
  Future<void> _migrate(Directory supportDir) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = [
      for (final key in prefs.getKeys())
        if (AppStore.isDataKey(key)) key,
    ];
    if (pending.isEmpty) return;

    final sep = Platform.pathSeparator;
    final original = File('${supportDir.path}${sep}shared_preferences.json');
    if (await original.exists()) {
      final copy = File(
          '${supportDir.path}$sep$migrationCopyPrefix${_stamp()}.json');
      final temp = File('${copy.path}.tmp');
      try {
        await original.copy(temp.path);
        await temp.rename(copy.path);
      } catch (_) {
        // Kopya alınamadıysa (disk dolu) taşıma bu açılışta yapılmıyor;
        // veri tercih dosyasında kalıyor. Yarım kopya da kalmasın.
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
        rethrow;
      }
    }

    final verified = <String>[];
    for (final key in pending) {
      final value = prefs.get(key);
      final String contents;
      final bool list;
      if (value is String) {
        contents = value;
        list = false;
      } else if (value is List) {
        contents = jsonEncode(value.map((e) => '$e').toList());
        list = true;
      } else {
        continue; // Beklenmeyen tür: olduğu yerde kalsın.
      }
      final target = _fileFor(key, list: list);
      if (await target.exists()) {
        final existing = await target.readAsString();
        if (existing != contents) {
          await target.rename('${target.path}.eski-${_stamp()}');
        }
      }
      if (!await _writeAtomic(target, contents)) continue;
      if (await target.readAsString() != contents) continue;
      _memory[key] =
          list ? (value as List).map((e) => '$e').toList() : contents;
      verified.add(key);
    }
    for (final key in verified) {
      await prefs.remove(key);
    }
  }

  /// Geçici dosyaya yazar, diske boşaltır, asıl adla değiştirir.
  ///
  /// Değiştirme birkaç kez deneniyor: Windows'ta virüs tarayıcısı ya da
  /// arama dizinleyicisi asıl dosyayı kısa süre açık tutabiliyor ve o
  /// anda yeniden adlandırma reddediliyor. Tek denemede kullanıcı
  /// boşuna "kaydedilemedi" uyarısı görürdü.
  static Future<bool> _writeAtomic(File target, String contents) async {
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsString(contents, flush: true);
      for (var attempt = 0;; attempt++) {
        try {
          await temp.rename(target.path);
          return true;
        } catch (_) {
          if (attempt >= 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 50 << attempt));
        }
      }
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> _enqueue(String key, Future<bool> Function() job) {
    final previous = _queue[key] ?? Future<bool>.value(true);
    final next = previous.then((_) => job(), onError: (_) => job());
    _queue[key] = next;
    return next;
  }

  /// Bir yazma başarılı olunca tercih dosyasındaki eski kopya kalkıyor;
  /// yoksa kural gereği o okunmaya devam ederdi.
  Future<void> _dropFromPrefs(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) await prefs.remove(key);
  }

  @override
  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.get(key);
    if (!AppStore.isDataKey(key) || fromPrefs is String) {
      return fromPrefs is String ? fromPrefs : null;
    }
    final value = _memory[key];
    return value is String ? value : null;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.get(key);
    if (!AppStore.isDataKey(key) || fromPrefs is List) {
      return fromPrefs is List ? fromPrefs.map((e) => '$e').toList() : null;
    }
    final value = _memory[key];
    return value is List<String> ? List<String>.from(value) : null;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (!AppStore.isDataKey(key)) {
      return (await SharedPreferences.getInstance()).setString(key, value);
    }
    _memory[key] = value;
    final ok = await _enqueue(
        key, () => _writeAtomic(_fileFor(key, list: false), value));
    if (ok) await _dropFromPrefs(key);
    return ok;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    if (!AppStore.isDataKey(key)) {
      return (await SharedPreferences.getInstance())
          .setStringList(key, value);
    }
    final copy = List<String>.from(value);
    _memory[key] = copy;
    final ok = await _enqueue(
        key, () => _writeAtomic(_fileFor(key, list: true), jsonEncode(copy)));
    if (ok) await _dropFromPrefs(key);
    return ok;
  }

  @override
  Future<bool> remove(String key) async {
    if (!AppStore.isDataKey(key)) {
      return (await SharedPreferences.getInstance()).remove(key);
    }
    _memory.remove(key);
    final ok = await _enqueue(key, () async {
      try {
        for (final list in const [false, true]) {
          final file = _fileFor(key, list: list);
          if (await file.exists()) await file.delete();
        }
        return true;
      } catch (_) {
        return false;
      }
    });
    await _dropFromPrefs(key);
    return ok;
  }

  @override
  Future<Map<String, Object>> readAll() async {
    final result = <String, Object>{
      for (final entry in _memory.entries)
        entry.key: entry.value is List
            ? List<String>.from(entry.value as List)
            : entry.value,
    };
    // Tercih dosyasındaki değer geçerli (bkz. sınıf açıklaması).
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  @override
  Future<void> clear() async {
    for (final key in _memory.keys.toList()) {
      await remove(key);
    }
    await (await SharedPreferences.getInstance()).clear();
  }
}
