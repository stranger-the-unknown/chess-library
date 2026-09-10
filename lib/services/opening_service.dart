import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/chess_engine.dart' as engine;
import '../models/opening.dart';

/// Açılış varyantlarını saklar.
///
/// Liste bilerek boş başlar: varyantları kullanıcı kendi ekler (SAN ya da
/// PGN yapıştırarak). Eklenen satırlar, notlar ve ilerleme cihazda tutulur.
class OpeningService {
  static final OpeningService instance = OpeningService._();
  OpeningService._();

  static const _customKey = 'openings_custom_v1';
  static const _progressKey = 'openings_progress_v1';
  static const _notesKey = 'openings_notes_v1';

  List<Opening>? _custom;
  Map<String, OpeningProgress>? _progress;
  Map<String, String>? _notes;

  // ---------------------------------------------------------------------

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
        : (jsonDecode(raw) as List)
            .map((e) => Opening.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    return _custom!;
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
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
      variation: variation.isEmpty ? t('openings.defaultVariation') : variation,
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

  Future<void> deleteCustom(String id) async {
    final custom = await _loadCustom();
    custom.removeWhere((o) => o.id == id);
    await _saveCustom();
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

  static String _normalize(String san) {
    final buffer = StringBuffer();
    for (final rune in san.runes) {
      final char = String.fromCharCode(rune);
      if ('+#!?-xX'.contains(char)) continue;
      buffer.write(char == '0' ? 'O' : char.toUpperCase());
    }
    return buffer.toString();
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
        : Map<String, String>.from(jsonDecode(raw) as Map);
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
    await prefs.setString(_notesKey, jsonEncode(notes));
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
        : (jsonDecode(raw) as Map).map(
            (key, value) => MapEntry(
              key as String,
              OpeningProgress.fromJson(Map<String, dynamic>.from(value as Map)),
            ),
          );
    return _progress!;
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
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
