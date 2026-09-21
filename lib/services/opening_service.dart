import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'corrupt_data.dart';
import 'prefs_write.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/opening.dart';

/// Açılış varyantlarını saklar.
///
/// Liste bilerek boş başlar: varyantları kullanıcı kendi ekler (SAN ya da
/// PGN yapıştırarak). Eklenen satırlar, notlar ve ilerleme cihazda tutulur.
/// Metinden alma sonucu.
///
/// Atlananları da bildirmek gerekiyor: kullanıcı 10.000 satırlık bir
/// dosya verip "3 varyant eklendi" görünce bozuk sanıyor. Atlananlar
/// listede zaten bulunan hamle dizileridir.
class ImportResult {
  final int added;
  final int skipped;

  const ImportResult({required this.added, required this.skipped});
}

class OpeningService {
  static final OpeningService instance = OpeningService._();
  OpeningService._();

  static const _customKey = 'openings_custom_v1';
  static const _progressKey = 'openings_progress_v1';
  static const _notesKey = 'openings_notes_v1';
  static const _hiddenKey = 'openings_hidden_v1';

  List<Opening>? _custom;
  Map<String, OpeningProgress>? _progress;
  Map<String, String>? _notes;
  Set<String>? _hidden;

  // ---------------------------------------------------------------------

  /// Bellekteki önbelleği boşaltır.
  ///
  /// Yedek geri yüklendiğinde ve testlerde soğuk başlangıç için kullanılır.
  void resetCache() {
    _custom = null;
    _progress = null;
    _notes = null;
    _hidden = null;
  }

  Future<List<Opening>> all() async {
    final custom = await _loadCustom();
    final notes = await _loadNotes();
    for (final opening in custom) {
      opening.note = notes[opening.id] ?? opening.note;
    }
    return List<Opening>.from(custom);
  }

  Future<List<Opening>> _loadCustom() async {
    if (_custom != null) return _custom!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    _custom = raw == null
        ? <Opening>[]
        : await readOrQuarantine<List<Opening>>(
            prefs,
            _customKey,
            raw,
            (decoded) => (decoded as List)
                .map((e) =>
                    Opening.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
            () => <Opening>[],
          );
    return _custom!;
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await writeString(
      prefs,
      _customKey,
      jsonEncode(_custom!.map((o) => o.toJson()).toList()),
    );
  }

  /// Açılışları aile adına göre gruplar (görüntüleme sırası korunur).
  Future<Map<String, List<Opening>>> byFamily() async {
    final openings = await all();
    final grouped = <String, List<Opening>>{};
    for (final opening in openings) {
      grouped.putIfAbsent(opening.family, () => <Opening>[]).add(opening);
    }
    return grouped;
  }

  // ---------------------------------------------------------------------
  // Kullanıcının kendi varyantları
  // ---------------------------------------------------------------------

  /// SAN ya da PGN gövdesinden yeni bir varyant ekler.
  ///
  /// Hamleler motorla doğrulanır; ilk kural dışı hamlede durulur.
  /// Hiç geçerli hamle yoksa `null` döner.
  Future<Opening?> addFromSan({
    required String family,
    required String variation,
    required String moveText,
    String eco = '---',
    String? note,
  }) async {
    final position = engine.ChessGame();
    final uci = <String>[];
    final san = <String>[];

    for (final token in _tokenize(moveText)) {
      final move = _matchSan(position, token);
      if (move == null) break;
      san.add(position.sanFor(move));
      uci.add(move.uci);
      position.makeMove(move);
    }
    if (uci.isEmpty) return null;

    final custom = await _loadCustom();
    final opening = Opening(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      eco: eco,
      family: family.isEmpty ? t('openings.ownFamily') : family,
      variation: variation.isEmpty
          ? _autoVariationName(
              custom, family.isEmpty ? t('openings.ownFamily') : family)
          : variation,
      uciMoves: uci,
      sanMoves: san,
      note: note,
      custom: true,
    );
    custom.add(opening);
    await _saveCustom();
    return opening;
  }

  Future<void> updateCustom(Opening opening) async {
    final custom = await _loadCustom();
    final index = custom.indexWhere((o) => o.id == opening.id);
    if (index == -1) return;
    custom[index] = opening;
    await _saveCustom();
  }

  /// Varyant adı boş bırakıldığında aile içinde sıra numarası verir.
  ///
  /// Bulmaca listelerindeki gibi: aynı ailedeki kaçıncı varyant olduğuna
  /// bakılır, böylece "Varyant 1", "Varyant 2" diye ilerler. Var olan
  /// numaralar atlanmaz; her zaman en büyük numaranın bir fazlası verilir
  /// ki silme sonrası çakışma olmasın.
  static String _autoVariationName(List<Opening> existing, String family) {
    final prefix = t('openings.defaultVariation');
    int highest = 0;
    for (final o in existing) {
      if (o.family != family) continue;
      // Düzenli ifade yerine düz ayrıştırma: desen kaçışları burada
      // sessizce yanlış çalışabiliyor, bu hâli hem okunaklı hem kesin.
      if (!o.variation.startsWith('$prefix ')) continue;
      final n = int.tryParse(o.variation.substring(prefix.length + 1).trim());
      if (n != null && n > highest) highest = n;
    }
    return '$prefix ${highest + 1}';
  }

  /// Eklenmiş bir varyantı düzenler: ad ve hamleler yeniden okunur.
  ///
  /// Hamleler yine kurallara göre doğrulanır; hiçbir geçerli hamle
  /// çıkmazsa `false` döner ve kayıt değişmez.
  Future<bool> editCustom({
    required String id,
    required String family,
    required String variation,
    required String moveText,
  }) async {
    final custom = await _loadCustom();
    final index = custom.indexWhere((o) => o.id == id);
    if (index == -1) return false;

    final position = engine.ChessGame();
    final uci = <String>[];
    final san = <String>[];
    for (final token in _tokenize(moveText)) {
      final move = _matchSan(position, token);
      if (move == null) break;
      san.add(position.sanFor(move));
      uci.add(move.uci);
      position.makeMove(move);
    }
    if (uci.isEmpty) return false;

    final previous = custom[index];
    final resolvedFamily = family.isEmpty ? t('openings.ownFamily') : family;
    custom[index] = Opening(
      id: previous.id,
      eco: previous.eco,
      family: resolvedFamily,
      variation: variation.isEmpty
          ? _autoVariationName(
              custom.where((o) => o.id != id).toList(), resolvedFamily)
          : variation,
      uciMoves: uci,
      sanMoves: san,
      note: previous.note,
      custom: true,
    );
    await _saveCustom();
    return true;
  }

  /// Metinden toplu varyant ekler.
  ///
  /// Her satır bir varyanttır; şu biçimler tanınır:
  ///   `aile|varyant|hamleler`
  ///   `eco|aile|varyant|hamleler`
  ///   `eco|aile|varyant|uci|san`   (eski varlık biçimi)
  /// `#` ile başlayan satırlar ve boş satırlar atlanır. Hamleler
  /// kurallara göre doğrulanır; hiç geçerli hamle içermeyen satır atlanır.
  Future<ImportResult> importText(
    String content, {
    void Function(int done, int total)? onProgress,
  }) async {
    final lines = const LineSplitter().convert(content);
    final custom = await _loadCustom();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    int added = 0;
    int skipped = 0;

    // Aynı dosya ikinci kez alındığında her şey ikiye katlanıyordu.
    // Ölçüt hamle dizisi: ad değil, çünkü kullanıcı adı değiştirmiş
    // olabilir ve kitaplar aynı adı farklı hatlara veriyor. Farklı
    // sırayla aynı pozisyona varanlar (transpozisyon) ayrı dizi
    // oldukları için ayrı varyant sayılır.
    final known = custom.map((o) => o.uciMoves.join(' ')).toSet();

    for (int i = 0; i < lines.length; i++) {
      final text = lines[i].trim();
      if (text.isNotEmpty && !text.startsWith('#')) {
        final parts = text.split('|');
        String eco = '---';
        String family = '';
        String variation = '';
        String moves = '';
        if (parts.length == 3) {
          family = parts[0].trim();
          variation = parts[1].trim();
          moves = parts[2];
        } else if (parts.length == 4) {
          eco = parts[0].trim();
          family = parts[1].trim();
          variation = parts[2].trim();
          moves = parts[3];
        } else if (parts.length >= 5) {
          eco = parts[0].trim();
          family = parts[1].trim();
          variation = parts[2].trim();
          // Eski biçimde SAN beşinci alandadır; UCI'yi yeniden üretiyoruz.
          moves = parts[4];
        }

        if (moves.trim().isNotEmpty) {
          final position = engine.ChessGame();
          final uci = <String>[];
          final san = <String>[];
          for (final token in _tokenize(moves)) {
            final move = _matchSan(position, token);
            if (move == null) break;
            san.add(position.sanFor(move));
            uci.add(move.uci);
            position.makeMove(move);
          }
          if (uci.isNotEmpty && !known.add(uci.join(' '))) {
            skipped++;
          } else if (uci.isNotEmpty) {
            final resolvedFamily =
                family.isEmpty ? t('openings.ownFamily') : family;
            custom.add(Opening(
              id: 'u_${stamp}_$added',
              eco: eco.isEmpty ? '---' : eco,
              family: resolvedFamily,
              variation: variation.isEmpty
                  ? _autoVariationName(custom, resolvedFamily)
                  : variation,
              uciMoves: uci,
              sanMoves: san,
              custom: true,
            ));
            added++;
          }
        }
      }

      if ((i + 1) % _importChunk == 0) {
        onProgress?.call(i + 1, lines.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(lines.length, lines.length);

    if (added > 0) await _saveCustom();
    return ImportResult(added: added, skipped: skipped);
  }

  /// Eklenmiş varyantları metin olarak verir.
  ///
  /// Biçim `eco|aile|varyant|hamleler` olup [importText] tarafından aynen
  /// geri okunabilir.
  Future<String> exportText() async {
    final custom = await _loadCustom();
    final buffer = StringBuffer()
      ..writeln('# ${t('openings.title')}')
      ..writeln('# eco|aile|varyant|hamleler');
    for (final o in custom) {
      buffer.writeln(
          '${o.eco}|${o.family}|${o.variation}|${o.sanMoves.join(' ')}');
    }
    return buffer.toString();
  }

  /// Toplu alma sırasında kaç satırda bir arayüze yol verileceği.
  static const int _importChunk = 100;

  Future<void> deleteCustom(String id) async {
    final custom = await _loadCustom();
    custom.removeWhere((o) => o.id == id);
    await _saveCustom();
    await _forget([id]);
  }

  /// Bir açılış ailesinin bütün varyantlarını siler; kaç tanesini
  /// sildiğini döner.
  ///
  /// Tek tek silmek, bir kitaptan alınmış yüzlerce varyantta iş göremez
  /// hâle geliyordu.
  Future<int> deleteFamily(String family) async {
    final custom = await _loadCustom();
    final doomed = custom
        .where((o) => o.family == family)
        .map((o) => o.id)
        .toList();
    if (doomed.isEmpty) return 0;
    custom.removeWhere((o) => o.family == family);
    await _saveCustom();
    await _forget(doomed);
    return doomed.length;
  }

  /// Bütün açılışları ve onlara bağlı her şeyi siler; kaç varyant
  /// sildiğini döner.
  ///
  /// Binlerce varyant alındıktan sonra listeyi temizlemenin başka yolu
  /// yoktu; başlık başlık silmek 1400 başlıkta iş görmüyor.
  Future<int> deleteAll() async {
    final custom = await _loadCustom();
    final count = custom.length;
    custom.clear();
    await _saveCustom();

    final prefs = await SharedPreferences.getInstance();
    _progress = <String, OpeningProgress>{};
    await _saveProgress();
    _notes = <String, String>{};
    await writeString(prefs, _notesKey, jsonEncode(_notes));
    _hidden = <String>{};
    await prefs.setStringList(_hiddenKey, const []);
    return count;
  }

  // ---------------------------------------------------------------------
  // Gizleme
  // ---------------------------------------------------------------------

  /// Gizlenen açılış aileleri.
  ///
  /// Gizlilik açılış kimliğine değil **aile adına** bağlı: kimlikler her
  /// almada yeniden üretiliyor, kimliğe bağlasaydık dosya yeniden
  /// alındığında bütün gizlilikler dağılırdı.
  Future<Set<String>> hiddenFamilies() async {
    if (_hidden != null) return _hidden!;
    final prefs = await SharedPreferences.getInstance();
    _hidden = (prefs.getStringList(_hiddenKey) ?? const <String>[]).toSet();
    return _hidden!;
  }

  Future<void> setHiddenFamilies(Set<String> families) async {
    _hidden = families;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenKey, families.toList()..sort());
  }

  Future<void> setFamilyHidden(String family, bool hidden) async {
    final current = Set<String>.from(await hiddenFamilies());
    if (hidden) {
      current.add(family);
    } else {
      current.remove(family);
    }
    await setHiddenFamilies(current);
  }

  /// Verilenler dışındaki bütün aileleri gizler. [keep] boşsa hepsi
  /// gizlenir.
  Future<void> hideAllExcept(Set<String> keep) async {
    final families = (await all()).map((o) => o.family).toSet();
    await setHiddenFamilies(families.difference(keep));
  }

  /// Verilenler dışındaki bütün gizlilikleri kaldırır. [keep] boşsa
  /// hiçbir aile gizli kalmaz.
  Future<void> showAllExcept(Set<String> keep) async {
    final hidden = await hiddenFamilies();
    await setHiddenFamilies(hidden.intersection(keep));
  }

  /// Silinen açılışların ilerlemesini ve notunu da temizler; yoksa
  /// artık hiçbir açılışa bağlı olmayan kayıtlar birikiyor.
  Future<void> _forget(Iterable<String> ids) async {
    final progress = await progressMap();
    final notes = await _loadNotes();
    bool progressChanged = false, notesChanged = false;
    for (final id in ids) {
      if (progress.remove(id) != null) progressChanged = true;
      if (notes.remove(id) != null) notesChanged = true;
    }
    if (progressChanged) await _saveProgress();
    if (notesChanged) {
      final prefs = await SharedPreferences.getInstance();
      await writeString(prefs, _notesKey, jsonEncode(notes));
    }
  }

  static List<String> _tokenize(String text) {
    var clean = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ');
    clean = clean.replaceAll(RegExp(r'\$\d+'), ' ');
    clean = clean.replaceAll(RegExp(r'\b\d+\.(\.\.)?'), ' ');
    clean = clean
        .replaceAll('1-0', ' ')
        .replaceAll('0-1', ' ')
        .replaceAll('1/2-1/2', ' ')
        .replaceAll('*', ' ');
    return clean
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static engine.ChessMove? _matchSan(engine.ChessGame position, String token) {
    final wanted = _normalize(token);
    if (wanted.isEmpty) return null;
    for (final move in position.allLegalMoves()) {
      if (_normalize(position.sanFor(move)) == wanted) return move;
    }
    return null;
  }

  /// Karşılaştırma için SAN'ı sadeleştirir; **harf büyüklüğü korunur**.
  ///
  /// Eskiden her harf büyütülüyordu: `bxc3` (b piyonu) ile `Bxc3` (fil)
  /// aynı görünüyor ve ikisi de oynanabilirken yanlış taş seçilebiliyordu.
  /// PGN okuyucuda aynı hata 72 hamle kaybettirmişti; burada da sessizce
  /// yanlış varyant kaydedilebiliyordu. Hoşgörü yalnızca harfin anlam
  /// taşımadığı iki yerde sürüyor: rok (`o-o`, `0-0`) ve terfi taşı
  /// (`e8=q`).
  static String _normalize(String san) {
    final buffer = StringBuffer();
    for (final rune in san.runes) {
      final char = String.fromCharCode(rune);
      if ('+#!?-xX'.contains(char)) continue;
      buffer.write(char == '0' ? 'O' : char);
    }
    final text = buffer.toString();
    final upper = text.toUpperCase();
    if (upper == 'OO' || upper == 'OOO') return upper;
    final equals = text.indexOf('=');
    if (equals >= 0 && equals < text.length - 1) {
      return text.substring(0, equals + 1) +
          text.substring(equals + 1).toUpperCase();
    }
    return text;
  }

  // ---------------------------------------------------------------------
  // Notlar
  // ---------------------------------------------------------------------

  Future<Map<String, String>> _loadNotes() async {
    if (_notes != null) return _notes!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    _notes = raw == null
        ? <String, String>{}
        : await readOrQuarantine<Map<String, String>>(
            prefs,
            _notesKey,
            raw,
            (decoded) => Map<String, String>.from(decoded as Map),
            () => <String, String>{},
          );
    return _notes!;
  }

  Future<void> setNote(String openingId, String note) async {
    final notes = await _loadNotes();
    if (note.trim().isEmpty) {
      notes.remove(openingId);
    } else {
      notes[openingId] = note;
    }
    final prefs = await SharedPreferences.getInstance();
    await writeString(prefs, _notesKey, jsonEncode(notes));
  }

  // ---------------------------------------------------------------------
  // İlerleme
  // ---------------------------------------------------------------------

  Future<Map<String, OpeningProgress>> progressMap() async {
    if (_progress != null) return _progress!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    _progress = raw == null
        ? <String, OpeningProgress>{}
        : await readOrQuarantine<Map<String, OpeningProgress>>(
            prefs,
            _progressKey,
            raw,
            (decoded) => (decoded as Map).map(
              (key, value) => MapEntry(
                key as String,
                OpeningProgress.fromJson(
                    Map<String, dynamic>.from(value as Map)),
              ),
            ),
            () => <String, OpeningProgress>{},
          );
    return _progress!;
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await writeString(
      prefs,
      _progressKey,
      jsonEncode(_progress!.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<OpeningProgress> progressOf(String id) async {
    final progress = await progressMap();
    return progress[id] ?? OpeningProgress();
  }

  Future<void> markLearned(String id, {bool learned = true}) async {
    final progress = await progressMap();
    final entry = progress.putIfAbsent(id, OpeningProgress.new);
    entry.learned = learned;
    await _saveProgress();
  }

  Future<void> registerSuccess(String id) async {
    final progress = await progressMap();
    final entry = progress.putIfAbsent(id, OpeningProgress.new);
    entry.streak++;
    if (entry.streak >= 2) entry.learned = true;
    await _saveProgress();
  }

  Future<void> registerFailure(String id) async {
    final progress = await progressMap();
    final entry = progress.putIfAbsent(id, OpeningProgress.new);
    entry.streak = 0;
    await _saveProgress();
  }

  Future<bool> toggleFavorite(String id) async {
    final progress = await progressMap();
    final entry = progress.putIfAbsent(id, OpeningProgress.new);
    entry.favorite = !entry.favorite;
    await _saveProgress();
    return entry.favorite;
  }

  Future<void> resetProgress() async {
    final progress = await progressMap();
    progress.clear();
    await _saveProgress();
  }
}
