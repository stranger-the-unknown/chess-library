import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_store.dart';
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
    final raw = await AppStore.instance.getString(_customKey);
    _custom = raw == null
        ? <Opening>[]
        : await readOrQuarantine<List<Opening>>(
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

  /// Kullanıcının açılışlarını yazar; başarısız olursa `false`.
  Future<bool> _saveCustom() async {
    return writeString(
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

  /// "Kendi varyantını ekle" formu: hamle kutusunda alt alta birden çok
  /// varyant olabilir.
  ///
  /// Eskiden kutunun tamamı tek bir oyun sayılıyordu: ikinci satırdaki
  /// "1. e4", birinci satırın bittiği konumda oynanamadığı için okuma
  /// orada duruyor, kalan satırlar **sessizce** atılıyor ve "N hamlelik
  /// varyant eklendi" deniyordu. Bölme kuralı [splitVariations]'da.
  ///
  /// Adlar: satırın kendi adı (`ad | hamleler`) önce gelir. Yoksa tek
  /// varyantta formdaki ad olduğu gibi, birden çok varyantta sonuna sıra
  /// numarası eklenerek kullanılır; o da boşsa "Varyant N".
  /// `skipped`: geçerli hamlesi olmayan varyant sayısı. `truncated`:
  /// geçersiz bir hamlede kesilen (o hamleye kadarı eklenen) varyant
  /// sayısı — eskiden bu da sessizce oluyordu.
  Future<({List<Opening> added, int skipped, int truncated})> addManyFromSan({
    required String family,
    required String variation,
    required String moveText,
  }) async {
    final drafts = splitVariations(moveText);
    final resolvedFamily = family.isEmpty ? t('openings.ownFamily') : family;
    final custom = await _loadCustom();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final added = <Opening>[];
    var skipped = 0;
    var truncated = 0;
    var numbered = 0;
    for (final draft in drafts) {
      final position = engine.ChessGame();
      final uci = <String>[];
      final san = <String>[];
      final tokens = _tokenize(draft.moves);
      for (final token in tokens) {
        final move = _matchSan(position, token);
        if (move == null) break;
        san.add(position.sanFor(move));
        uci.add(move.uci);
        position.makeMove(move);
      }
      if (uci.isEmpty) {
        skipped++;
        continue;
      }
      if (uci.length < tokens.length) truncated++;
      String name;
      final own = draft.name;
      if (own != null && own.isNotEmpty) {
        name = own;
      } else if (variation.isEmpty) {
        name = _autoVariationName(custom, resolvedFamily);
      } else if (drafts.length == 1) {
        name = variation;
      } else {
        numbered++;
        name = '$variation $numbered';
      }
      final opening = Opening(
        id: 'u_${stamp}_${added.length}',
        eco: '---',
        family: resolvedFamily,
        variation: name,
        uciMoves: uci,
        sanMoves: san,
        custom: true,
      );
      custom.add(opening);
      added.add(opening);
    }
    if (added.isNotEmpty) await _saveCustom();
    return (added: added, skipped: skipped, truncated: truncated);
  }

  /// Hamle metnini varyantlara böler.
  ///
  /// Yapıştırılan PGN'de uzun bir oyun satırlara bölünmüş olabilir
  /// ("12. Re1 ..." ile başlayan satır). Bu yüzden her satır yeni varyant
  /// sayılmıyor; bir satır yeni varyant başlatır, eğer:
  /// * 1. hamleden başlıyorsa (`1.` / `1...`),
  /// * başında bir ad varsa (`ad | hamleler`),
  /// * önünde boş bir satır varsa,
  /// * ya da ilk hamlesi üstteki satırın bittiği konumda oynanamıyorsa.
  /// Aksi hâlde üstteki satırın devamıdır. Hamlesi olmayan satırlar (PGN
  /// başlıkları) atlanır.
  @visibleForTesting
  static List<({String? name, String moves})> splitVariations(String text) {
    // Yorumlar ve başlıklar satır aşabiliyor; önce bütün metinden
    // çıkarılıyor.
    final clean = text
        .replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    final drafts = <({String? name, StringBuffer moves})>[];
    engine.ChessGame? position;
    var gap = true;
    for (final raw in const LineSplitter().convert(clean)) {
      var line = raw.trim();
      if (line.isEmpty) {
        gap = true;
        continue;
      }
      String? name;
      final bar = line.indexOf('|');
      if (bar >= 0) {
        name = line.substring(0, bar).trim();
        line = line.substring(bar + 1).trim();
      }
      final tokens = _tokenize(line);
      if (tokens.isEmpty && name == null) continue;

      final startsAtOne = RegExp(r'^1\s*\.').hasMatch(line);
      final current = position;
      final continues = !gap &&
          name == null &&
          !startsAtOne &&
          current != null &&
          drafts.isNotEmpty &&
          _matchSan(current, tokens.first) != null;
      if (!continues) {
        drafts.add((name: name, moves: StringBuffer()));
        position = engine.ChessGame();
      }
      drafts.last.moves.write(' $line');
      final board = position!;
      for (final token in tokens) {
        final move = _matchSan(board, token);
        if (move == null) break;
        board.makeMove(move);
      }
      gap = false;
    }
    return [
      for (final d in drafts) (name: d.name, moves: d.moves.toString().trim()),
    ];
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

    // Yazma başarısızsa "eklendi" denmesin.
    if (added > 0 && !await _saveCustom()) {
      throw StateError('açılışlar diske yazılamadı');
    }
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

  /// Bir ailenin (başlığın) bütün varyantlarını [to] adına taşır; kaç
  /// varyant taşındığını döner.
  ///
  /// [to] zaten var olan bir aileyse varyantlar ona katılır. Birleşen
  /// başlığın görünürlüğü kaynağınki olur: kullanıcı görünen bir başlığı
  /// taşıyorsa sonuç da görünür kalsın (hedef gizliyse açılır), gizli
  /// bir başlık taşınırsa gizli kalsın. İlerleme ve notlar varyant
  /// kimliğine bağlı olduğu için olduğu gibi kalır.
  Future<int> renameFamily(String from, String to) async {
    final target = to.trim();
    if (target.isEmpty || target == from) return 0;
    final custom = await _loadCustom();
    var moved = 0;
    for (final opening in custom) {
      if (opening.family != from) continue;
      opening.family = target;
      moved++;
    }
    if (moved == 0) return 0;
    await _saveCustom();

    final hidden = Set<String>.from(await hiddenFamilies());
    final wasHidden = hidden.remove(from);
    if (wasHidden) {
      hidden.add(target);
    } else {
      hidden.remove(target);
    }
    await setHiddenFamilies(hidden);
    return moved;
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

    _progress = <String, OpeningProgress>{};
    await _saveProgress();
    _notes = <String, String>{};
    await writeString(_notesKey, jsonEncode(_notes));
    _hidden = <String>{};
    await AppStore.instance.setStringList(_hiddenKey, const []);
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
    _hidden = (await AppStore.instance.getStringList(_hiddenKey) ??
            const <String>[])
        .toSet();
    return _hidden!;
  }

  Future<void> setHiddenFamilies(Set<String> families) async {
    _hidden = families;
    await AppStore.instance.setStringList(_hiddenKey, families.toList()..sort());
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
      await writeString(_notesKey, jsonEncode(notes));
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
    final raw = await AppStore.instance.getString(_notesKey);
    _notes = raw == null
        ? <String, String>{}
        : await readOrQuarantine<Map<String, String>>(
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
    await writeString(_notesKey, jsonEncode(notes));
  }

  // ---------------------------------------------------------------------
  // İlerleme
  // ---------------------------------------------------------------------

  Future<Map<String, OpeningProgress>> progressMap() async {
    if (_progress != null) return _progress!;
    final raw = await AppStore.instance.getString(_progressKey);
    _progress = raw == null
        ? <String, OpeningProgress>{}
        : await readOrQuarantine<Map<String, OpeningProgress>>(
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
    await writeString(
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
