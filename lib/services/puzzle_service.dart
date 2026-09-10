import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chess_engine.dart' as engine;
import '../models/puzzle.dart';

/// Bulmaca listelerini yükler, düzenlemeleri ve ilerlemeyi saklar.
///
/// Hazır listeler binlerce pozisyon içerdiği için her açılışta tamamını
/// yeniden kaydetmek yerine üç katman kullanılır:
///   1. Varlık dosyası  - değişmeyen temel liste
///   2. Değişiklikler   - kullanıcının düzenlediği / sildiği / eklediği
///   3. İlerleme        - çözüldü, favori, deneme sayısı
class PuzzleService {
  static final PuzzleService instance = PuzzleService._();
  PuzzleService._();

  static const _collectionsKey = 'puzzle_collections_v1';
  static const _overridesKey = 'puzzle_overrides_v1';
  static const _progressKey = 'puzzle_progress_v1';

  /// Uygulamayla birlikte gelen hazır listeler.
  ///
  /// Bu sürümde gömülü bulmaca kitabı yoktur: listeleri kullanıcı kendisi
  /// oluşturur, FEN yapıştırarak ya da metin dosyası alarak doldurur.
  /// Varlık dosyasından yükleme düzeneği (`assetPath`) yerinde bırakıldı;
  /// ileride bir liste eklenmek istenirse tek yapılacak buraya yazmaktır.
  static List<PuzzleCollection> get _defaults => const [];

  List<PuzzleCollection>? _collections;
  Map<String, Map<String, dynamic>>? _overrides;
  Map<String, PuzzleProgress>? _progress;
  final Map<String, List<Puzzle>> _assetCache = {};

  /// Bellekteki önbelleği boşaltır.
  ///
  /// Yalnızca testler içindir: veri gerçekten diske yazıldı mı diye
  /// servisi soğuk başlatmayı sağlar.
  @visibleForTesting
  void debugReset() {
    _collections = null;
    _overrides = null;
    _progress = null;
    _assetCache.clear();
  }

  // ---------------------------------------------------------------------
  // Koleksiyonlar
  // ---------------------------------------------------------------------

  Future<List<PuzzleCollection>> collections() async {
    if (_collections != null) return _collections!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_collectionsKey);
    if (raw == null) {
      _collections = List<PuzzleCollection>.from(_defaults);
      await _saveCollections();
    } else {
      final list = (jsonDecode(raw) as List)
          .map((e) => PuzzleCollection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // Artık uygulamayla gelmeyen hazır listeleri düşür.
      //
      // Önceki sürümlerde gömülü bulmaca kitapları vardı. Bu kayıtlar
      // ayarlarda kalırsa var olmayan bir varlık dosyası okunmaya
      // çalışılır ve liste ekranı hiç açılmaz. Kullanıcının kendi
      // listeleri (`assetPath` boş) elbette korunur.
      final before = list.length;
      list.removeWhere(
          (c) => c.isBuiltIn && !_defaults.any((preset) => preset.id == c.id));
      final dropped = before != list.length;

      // Uygulama güncellemesiyle gelen yeni hazır listeleri ekle.
      for (final preset in _defaults) {
        if (!list.any((c) => c.id == preset.id)) list.add(preset);
      }
      // Hazır listelerin adları dile bağlıdır; her açılışta tazelenir.
      for (final preset in _defaults) {
        final index = list.indexWhere((c) => c.id == preset.id);
        if (index != -1) {
          list[index].name = preset.name;
          list[index].description = preset.description;
        }
      }
      _collections = list;
      // Düşen kayıtlar bir daha okunmasın diye hemen yazılır.
      if (dropped) await _saveCollections();
    }
    return _collections!;
  }

  Future<void> _saveCollections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _collectionsKey,
      jsonEncode(_collections!.map((c) => c.toJson()).toList()),
    );
  }

  Future<PuzzleCollection> createCollection(
    String name, {
    String? description,
  }) async {
    final all = await collections();
    final collection = PuzzleCollection(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      description: description,
    );
    all.add(collection);
    await _saveCollections();
    return collection;
  }

  Future<void> renameCollection(
    String id,
    String name, {
    String? description,
  }) async {
    final all = await collections();
    final collection = all.firstWhere((c) => c.id == id);
    collection.name = name;
    if (description != null) collection.description = description;
    await _saveCollections();
  }

  Future<void> deleteCollection(String id) async {
    final all = await collections();
    all.removeWhere((c) => c.id == id);
    await _saveCollections();

    // Bu listeye ait değişiklikleri ve ilerlemeyi de temizle.
    final overrides = await _loadOverrides();
    overrides.removeWhere((key, _) => key.startsWith('$id#'));
    final progress = await _loadProgress();
    progress.removeWhere((key, _) => key.startsWith('$id#'));
    await _saveOverrides();
    await _saveProgress();
    _assetCache.remove(id);
  }

  /// Hazır bir listeyi fabrika ayarlarına döndürür.
  Future<void> resetCollection(String id) async {
    final overrides = await _loadOverrides();
    overrides.removeWhere((key, _) => key.startsWith('$id#'));
    await _saveOverrides();
  }

  // ---------------------------------------------------------------------
  // Bulmacalar
  // ---------------------------------------------------------------------

  /// Bir listenin tüm bulmacalarını (düzenlemeler uygulanmış hâlde) döner.
  Future<List<Puzzle>> puzzlesOf(PuzzleCollection collection) async {
    final overrides = await _loadOverrides();

    List<Puzzle> base;
    if (collection.isBuiltIn) {
      base = await _loadAsset(collection);
    } else {
      base = collection.puzzles;
    }

    final result = <Puzzle>[];
    for (final puzzle in base) {
      final override = overrides[puzzle.id];
      if (override == null) {
        result.add(puzzle);
        continue;
      }
      if (override['deleted'] == true) continue;
      result.add(
        puzzle.copyWith(
          fen: override['fen'] as String?,
          title: override['title'] as String?,
          note: override['note'] as String?,
          tags: (override['tags'] as List?)?.map((e) => e.toString()).toList(),
        ),
      );
    }

    // Hazır listeye kullanıcı tarafından eklenen bulmacalar.
    if (collection.isBuiltIn) {
      for (final entry in overrides.entries) {
        if (!entry.key.startsWith('${collection.id}#u')) continue;
        if (entry.value['deleted'] == true) continue;
        if (entry.value['added'] != true) continue;
        result.add(
          Puzzle(
            id: entry.key,
            fen: entry.value['fen'] as String,
            title: entry.value['title'] as String?,
            note: entry.value['note'] as String?,
            tags: (entry.value['tags'] as List?)
                ?.map((e) => e.toString())
                .toList(),
            solution: (entry.value['solution'] as List?)
                ?.map((e) => e.toString())
                .toList(),
            custom: true,
          ),
        );
      }
    }
    return result;
  }

  Future<List<Puzzle>> _loadAsset(PuzzleCollection collection) async {
    final cached = _assetCache[collection.id];
    if (cached != null) return cached;

    String text;
    try {
      text = await rootBundle.loadString(collection.assetPath!);
    } catch (_) {
      // Varlık paketten çıkarılmışsa liste boş görünsün; ekran açılmalı.
      _assetCache[collection.id] = const [];
      return const [];
    }
    final puzzles = <Puzzle>[];
    int index = 0;
    for (final line in const LineSplitter().convert(text)) {
      final puzzle = Puzzle.fromAssetLine(line, '${collection.id}#$index');
      if (puzzle == null) continue;
      puzzles.add(puzzle);
      index++;
    }
    _assetCache[collection.id] = puzzles;
    return puzzles;
  }

  /// Bir bulmacayı düzenler. Hazır listelerde varlık dosyası değişmez;
  /// yalnızca değişiklik katmanına yazılır.
  Future<void> updatePuzzle(
    PuzzleCollection collection,
    Puzzle puzzle, {
    required String fen,
    String? title,
    String? note,
    List<String>? tags,
  }) async {
    if (collection.isBuiltIn || puzzle.id.startsWith('${collection.id}#')) {
      final overrides = await _loadOverrides();
      final existing = overrides[puzzle.id] ?? <String, dynamic>{};
      overrides[puzzle.id] = {
        ...existing,
        'fen': fen,
        'title': title,
        'note': note,
        'tags': tags ?? puzzle.tags,
      };
      await _saveOverrides();
    } else {
      puzzle
        ..fen = fen
        ..title = title
        ..note = note
        ..tags = tags ?? puzzle.tags;
      await _saveCollections();
    }
  }

  Future<Puzzle> addPuzzle(
    PuzzleCollection collection, {
    required String fen,
    String? title,
    String? note,
    List<String>? tags,
  }) async {
    final id = '${collection.id}#u${DateTime.now().microsecondsSinceEpoch}';
    final puzzle = Puzzle(
      id: id,
      fen: fen,
      title: title,
      note: note,
      tags: tags,
      custom: true,
    );

    if (collection.isBuiltIn) {
      final overrides = await _loadOverrides();
      overrides[id] = {
        'added': true,
        'fen': fen,
        'title': title,
        'note': note,
        'tags': tags ?? const <String>[],
      };
      await _saveOverrides();
    } else {
      collection.puzzles.add(puzzle);
      await _saveCollections();
    }
    return puzzle;
  }

  Future<void> deletePuzzle(PuzzleCollection collection, Puzzle puzzle) async {
    if (collection.isBuiltIn) {
      final overrides = await _loadOverrides();
      final existing = overrides[puzzle.id] ?? <String, dynamic>{};
      overrides[puzzle.id] = {...existing, 'deleted': true};
      await _saveOverrides();
    } else {
      collection.puzzles.removeWhere((p) => p.id == puzzle.id);
      await _saveCollections();
    }
  }

  /// Metin içeriğinden toplu bulmaca ekler.
  ///
  /// Her satırda bir FEN beklenir; şu biçimler tanınır:
  ///   `fen`
  ///   `numara<TAB>fen`
  ///   `fen|etiketler|çözüm|numara`   (dışa aktarma biçimi)
  /// `#` ile başlayan satırlar ve boş satırlar atlanır.
  ///
  /// Binlerce satırlık dosyalarda arayüzün donmaması için her
  /// [_importChunk] satırda bir olay döngüsüne yol verilir ve [onProgress]
  /// çağrılır. Geçerli olan pozisyon sayısını döner.
  Future<int> importFens(
    PuzzleCollection collection,
    String content, {
    List<String>? tags,
    void Function(int done, int total)? onProgress,
  }) async {
    final lines = const LineSplitter().convert(content);
    final total = lines.length;
    int added = 0;
    final overrides = collection.isBuiltIn ? await _loadOverrides() : null;
    // Kimlikler tek bir zaman damgasından türetilir: her satırda
    // `DateTime.now()` çağırmak büyük dosyalarda gereksiz yere pahalıdır.
    final stamp = DateTime.now().microsecondsSinceEpoch;

    for (int i = 0; i < total; i++) {
      var text = lines[i].trim();
      if (text.isNotEmpty && !text.startsWith('#')) {
        if (text.contains('\t')) text = text.split('\t').last.trim();
        final parts = text.split('|');
        final fen = parts.first.trim();
        if (engine.ChessGame.validateFen(fen) == null) {
          final lineTags = tags ??
              (parts.length > 1 && parts[1].trim().isNotEmpty
                  ? parts[1]
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList()
                  : null);
          final solution = parts.length > 2 && parts[2].trim().isNotEmpty
              ? parts[2].split(' ').where((e) => e.isNotEmpty).toList()
              : null;
          final id = '${collection.id}#u${stamp}_$added';
          if (collection.isBuiltIn) {
            overrides![id] = {
              'added': true,
              'fen': fen,
              'tags': lineTags ?? const <String>[],
              if (solution != null) 'solution': solution,
            };
          } else {
            collection.puzzles.add(
              Puzzle(
                id: id,
                fen: fen,
                tags: lineTags,
                solution: solution,
                custom: true,
              ),
            );
          }
          added++;
        }
      }

      if ((i + 1) % _importChunk == 0) {
        onProgress?.call(i + 1, total);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(total, total);

    if (collection.isBuiltIn) {
      await _saveOverrides();
    } else {
      await _saveCollections();
    }
    return added;
  }

  /// Listedeki bulmacaları metin olarak dışa aktarır.
  ///
  /// Biçim `fen|etiketler|çözüm|sıra` olup [importFens] tarafından aynen
  /// geri okunabilir; `#` ile başlayan başlık satırları atlanır.
  Future<String> exportText(PuzzleCollection collection) async {
    final puzzles = await puzzlesOf(collection);
    final buffer = StringBuffer()
      ..writeln('# ${collection.name}')
      ..writeln('# fen|etiketler|cozum|sira');
    for (int i = 0; i < puzzles.length; i++) {
      final p = puzzles[i];
      buffer.writeln(
        '${p.fen}|${p.tags.join(',')}|'
        '${p.solution.join(' ')}|${i + 1}',
      );
    }
    return buffer.toString();
  }

  /// Toplu alma sırasında kaç satırda bir arayüze yol verileceği.
  static const int _importChunk = 250;

  // ---------------------------------------------------------------------
  // Değişiklik katmanı
  // ---------------------------------------------------------------------

  Future<Map<String, Map<String, dynamic>>> _loadOverrides() async {
    if (_overrides != null) return _overrides!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_overridesKey);
    _overrides = raw == null
        ? <String, Map<String, dynamic>>{}
        : (jsonDecode(raw) as Map).map(
            (key, value) => MapEntry(
              key as String,
              Map<String, dynamic>.from(value as Map),
            ),
          );
    return _overrides!;
  }

  Future<void> _saveOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_overridesKey, jsonEncode(_overrides));
  }

  // ---------------------------------------------------------------------
  // İlerleme
  // ---------------------------------------------------------------------

  Future<Map<String, PuzzleProgress>> _loadProgress() async {
    if (_progress != null) return _progress!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    _progress = raw == null
        ? <String, PuzzleProgress>{}
        : (jsonDecode(raw) as Map).map(
            (key, value) => MapEntry(
              key as String,
              PuzzleProgress.fromJson(Map<String, dynamic>.from(value as Map)),
            ),
          );
    return _progress!;
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressKey,
      jsonEncode(_progress!.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  Future<Map<String, PuzzleProgress>> progressMap() => _loadProgress();

  Future<PuzzleProgress> progressOf(String puzzleId) async {
    final progress = await _loadProgress();
    return progress[puzzleId] ?? PuzzleProgress();
  }

  Future<void> markSolved(String puzzleId, {bool solved = true}) async {
    final progress = await _loadProgress();
    final entry = progress.putIfAbsent(puzzleId, PuzzleProgress.new);
    entry
      ..solved = solved
      ..lastAttempt = DateTime.now();
    await _saveProgress();
  }

  Future<void> registerAttempt(String puzzleId) async {
    final progress = await _loadProgress();
    final entry = progress.putIfAbsent(puzzleId, PuzzleProgress.new);
    entry.attempts++;
    entry.lastAttempt = DateTime.now();
    await _saveProgress();
  }

  Future<bool> toggleFavorite(String puzzleId) async {
    final progress = await _loadProgress();
    final entry = progress.putIfAbsent(puzzleId, PuzzleProgress.new);
    entry.favorite = !entry.favorite;
    await _saveProgress();
    return entry.favorite;
  }

  Future<void> resetProgress(String collectionId) async {
    final progress = await _loadProgress();
    progress.removeWhere((key, _) => key.startsWith('$collectionId#'));
    await _saveProgress();
  }
}
