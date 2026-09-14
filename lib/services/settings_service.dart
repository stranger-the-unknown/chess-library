import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

/// Uygulama tercihlerini tutar ve değiştiğinde dinleyicilere haber verir.
///
/// `main.dart` içinde bir [AnimatedBuilder] ile dinlendiği için tema, tahta
/// görünümü ya da ses ayarı değiştiğinde tüm ekranlar anında güncellenir.
class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  // Görünüm
  ThemeMode _themeMode = ThemeMode.dark;
  AppLanguage _language = AppLanguage.system;
  String _pieceSet = 'chessnut';
  String _boardTheme = 'brown';
  bool _showCoordinates = true;
  bool _showLegalMoves = true;
  bool _highlightLastMove = true;
  bool _animateMoves = true;

  // Davranış
  bool _soundEnabled = true;
  bool _confirmMoves = false;
  int _engineLevel = 2;
  bool _showEvaluationBar = true;

  /// Bulmaca listelerinde "bugün çözülen" sayısı gösterilsin mi?
  bool _showDailyCount = true;

  ThemeMode get themeMode => _themeMode;
  AppLanguage get language => _language;
  String get pieceSet => _pieceSet;
  String get boardTheme => _boardTheme;
  bool get showCoordinates => _showCoordinates;
  bool get showLegalMoves => _showLegalMoves;
  bool get highlightLastMove => _highlightLastMove;
  bool get animateMoves => _animateMoves;
  bool get soundEnabled => _soundEnabled;
  bool get confirmMoves => _confirmMoves;
  int get engineLevel => _engineLevel;
  bool get showEvaluationBar => _showEvaluationBar;
  bool get showDailyCount => _showDailyCount;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _themeMode = ThemeMode.values[
        (prefs.getInt('themeMode') ?? ThemeMode.dark.index)
            .clamp(0, ThemeMode.values.length - 1)];
    _language = AppLanguage.values[
        (prefs.getInt('language') ?? AppLanguage.system.index)
            .clamp(0, AppLanguage.values.length - 1)];
    Strings.language = _language;
    // Kayitli ad artik listede yoksa (eski surumden guncelleme) varsayilana
    // donulur; aksi halde bulunamayan bir varlik yuklenmeye calisilir.
    final storedPieceSet = prefs.getString('pieceSet');
    if (storedPieceSet != null &&
        BoardAssets.pieceSets.contains(storedPieceSet)) {
      _pieceSet = storedPieceSet;
    }
    final storedBoard = prefs.getString('boardTheme');
    if (storedBoard != null && BoardAssets.boards.contains(storedBoard)) {
      _boardTheme = storedBoard;
    }
    _showCoordinates = prefs.getBool('showCoordinates') ?? _showCoordinates;
    _showLegalMoves = prefs.getBool('showLegalMoves') ?? _showLegalMoves;
    _highlightLastMove =
        prefs.getBool('highlightLastMove') ?? _highlightLastMove;
    _animateMoves = prefs.getBool('animateMoves') ?? _animateMoves;
    _soundEnabled = prefs.getBool('soundEnabled') ?? _soundEnabled;
    _confirmMoves = prefs.getBool('confirmMoves') ?? _confirmMoves;
    _engineLevel = prefs.getInt('engineLevel') ?? _engineLevel;
    _showEvaluationBar =
        prefs.getBool('showEvaluationBar') ?? _showEvaluationBar;
    _showDailyCount = prefs.getBool('showDailyCount') ?? _showDailyCount;
    notifyListeners();
  }

  void _set(String key, Object value) {
    final prefs = _prefs;
    if (prefs == null) return;
    if (value is bool) prefs.setBool(key, value);
    if (value is int) prefs.setInt(key, value);
    if (value is String) prefs.setString(key, value);
  }

  set themeMode(ThemeMode value) {
    _themeMode = value;
    _set('themeMode', value.index);
    notifyListeners();
  }

  set language(AppLanguage value) {
    _language = value;
    Strings.language = value;
    _set('language', value.index);
    notifyListeners();
  }

  set pieceSet(String value) {
    _pieceSet = value;
    _set('pieceSet', value);
    notifyListeners();
  }

  set boardTheme(String value) {
    _boardTheme = value;
    _set('boardTheme', value);
    notifyListeners();
  }

  set showCoordinates(bool value) {
    _showCoordinates = value;
    _set('showCoordinates', value);
    notifyListeners();
  }

  set showLegalMoves(bool value) {
    _showLegalMoves = value;
    _set('showLegalMoves', value);
    notifyListeners();
  }

  set highlightLastMove(bool value) {
    _highlightLastMove = value;
    _set('highlightLastMove', value);
    notifyListeners();
  }

  set animateMoves(bool value) {
    _animateMoves = value;
    _set('animateMoves', value);
    notifyListeners();
  }

  set soundEnabled(bool value) {
    _soundEnabled = value;
    _set('soundEnabled', value);
    notifyListeners();
  }

  set confirmMoves(bool value) {
    _confirmMoves = value;
    _set('confirmMoves', value);
    notifyListeners();
  }

  set engineLevel(int value) {
    _engineLevel = value;
    _set('engineLevel', value);
    notifyListeners();
  }

  set showEvaluationBar(bool value) {
    _showEvaluationBar = value;
    _set('showEvaluationBar', value);
    notifyListeners();
  }

  set showDailyCount(bool value) {
    _showDailyCount = value;
    _set('showDailyCount', value);
    notifyListeners();
  }
}

/// Uygulamayla birlikte gelen tahta ve taş takımları.
///
/// Görsellerin tamamı bu depo için üretilmiştir; dışarıdan alınmış,
/// telif kısıtı olan bir varlık içermez.
/// Uygulamanın sürümü.
///
/// Tek kaynak burasıdır; `pubspec.yaml` ile aynı olduğu testle denetlenir.
/// Hakkında bölümünde ve yedek dosyasının başlığında görünür.
const String appVersionName = '3.0.0';

class BoardAssets {
  BoardAssets._();

  /// Tahta görünümleri.
  ///
  /// [flatBoards] içindekiler doğrudan çizilir (görsel dosyası yoktur);
  /// kalanlar `assets/boards/<ad>.png` dosyasından gelir.
  static const List<String> boards = [
    'brown',
    'green',
    'tournament',
    'blue',
    'gray',
    'slate',
    'sand',
    'purple',
    'ivory',
    'rose',
    'teal',
    'midnight',
    'dark_wood',
    'walnut',
    'oak',
  ];

  /// Görsel dosyası olmayan, iki renkten çizilen tahtalar.
  ///
  /// Kareler doğrudan tuvale çizildiği için her ölçüde kusursuz keskin
  /// çıkar; ölçekleme bulanıklığı ya da JPEG halkalanması olmaz.
  static const Set<String> flatBoards = {
    'brown',
    'green',
    'tournament',
    'blue',
    'gray',
    'slate',
    'sand',
    'purple',
    'ivory',
    'rose',
    'teal',
    'midnight',
  };

  static bool isFlat(String name) => flatBoards.contains(name);

  /// `assets/pieces/<ad>/<w|b><p|n|b|r|q|k>.svg`
  ///
  /// Takımlar dışarıdan alınmıştır ve izin veren lisanslarla gelir;
  /// kaynak ve lisansları `ASSETS.md` içinde listelenir.
  static const List<String> pieceSets = [
    'chessnut',
    'rhosgfx',
    'fantasy',
    'spatial',
    'celtic',
    'kiwen-suwi',
    'firi',
    'totoy',
    'papercut',
  ];

  /// Her tahtanın açık ve koyu kare rengi.
  ///
  /// Kare adları bu renklere göre boyanır: yazı, üzerinde durduğu karenin
  /// karşıt kare rengini alır. Böylece koordinatlar her tahtayla uyumlu
  /// görünür ve ayrıca bir ayar gerekmez.
  static const Map<String, (int, int)> _squareColors = {
    'brown': (0xF0D9B5, 0xB58863),
    'green': (0xEEEED2, 0x769656),
    'tournament': (0xE8E9CC, 0x5E8A4E),
    'blue': (0xDEE3E6, 0x8CA2AD),
    'gray': (0xDCDCDC, 0x8F8F8F),
    'slate': (0xC6CDD6, 0x69788A),
    'sand': (0xEDDCBE, 0xC0A47B),
    'purple': (0xE6E0EC, 0x9B8BB4),
    'ivory': (0xF2EDE3, 0xC3B7A4),
    'rose': (0xF3DFE2, 0xBE8A96),
    'teal': (0xD8E8E6, 0x74A09B),
    'midnight': (0xAEB7C4, 0x4B5A72),
    'dark_wood': (0xB79062, 0x53331F),
    'walnut': (0xC2A076, 0x654328),
    'oak': (0xDCBF92, 0x986D45),
  };

  static const (int, int) _fallbackSquares = (0xECD3AE, 0xAE815D);

  /// Kare adlarının rengi.
  ///
  /// [onLightSquare] yazının açık karede olup olmadığını söyler; renk
  /// olarak karşıt karenin rengi döner, böylece okunabilirlik korunur.
  /// Bir tahtanın açık ve koyu kare rengi (0xAARRGGBB).
  static (int, int) squareColors(String board) {
    final pair = _squareColors[board] ?? _fallbackSquares;
    return (0xFF000000 | pair.$1, 0xFF000000 | pair.$2);
  }

  static int coordinateColor(String board, {required bool onLightSquare}) {
    final pair = _squareColors[board] ?? _fallbackSquares;
    final value = onLightSquare ? pair.$2 : pair.$1;
    return 0xFF000000 | value;
  }

  /// İşaretleme rengi (0xAARRGGBB).
  ///
  /// Sağ tıkla konan işaretler ve çizilen oklar her tahtada seçilebilsin
  /// diye renk tahtadan türetilir: koyu karenin renk tonundan en uzak
  /// ton seçilir. Böylece yeşil tahtada yeşil, mavi tahtada mavi
  /// işaret konmaz ve tek bir sabit renk aramak gerekmez.
  static int markColor(String board) {
    const palette = <int>[
      0xFFE2571E, // turuncu
      0xFF2E9E3F, // yeşil
      0xFF1E6FD9, // mavi
      0xFF9B27B0, // mor
    ];
    final (_, dark) = squareColors(board);
    final boardHue = HSVColor.fromColor(Color(dark)).hue;

    int best = palette.first;
    double bestDistance = -1;
    for (final candidate in palette) {
      final hue = HSVColor.fromColor(Color(candidate)).hue;
      // Renk çemberi üzerinde kısa yoldan uzaklık.
      final raw = (hue - boardHue).abs();
      final distance = raw > 180 ? 360 - raw : raw;
      if (distance > bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  static const Map<String, String> _labels = {
    'purple': 'Mor',
    'ivory': 'Fildişi',
    'rose': 'Gül',
    'teal': 'Deniz Yeşili',
    'midnight': 'Gece Mavisi',
    'walnut': 'Ceviz',
    'oak': 'Meşe',
    'dark_wood': 'Koyu Ahşap',
    'brown': 'Kahve',
    'tournament': 'Turnuva',
    'green': 'Yeşil',
    'blue': 'Mavi',
    'gray': 'Gri',
    'slate': 'Arduvaz',
    'sand': 'Kum',
    'marble': 'Mermer',
  };

  static const Map<String, String> _labelsEn = {
    'purple': 'Purple',
    'ivory': 'Ivory',
    'rose': 'Rose',
    'teal': 'Teal',
    'midnight': 'Midnight',
    'walnut': 'Walnut',
    'oak': 'Oak',
    'dark_wood': 'Dark wood',
    'brown': 'Brown',
    'tournament': 'Tournament',
    'green': 'Green',
    'blue': 'Blue',
    'gray': 'Gray',
    'slate': 'Slate',
    'sand': 'Sand',
    'marble': 'Marble',
  };

  static const Map<String, Map<String, String>> _labelTables = {
    'tr': _labels,
    'en': _labelsEn,
  };

  /// Taş takımı adları özel isimdir; hiçbir dilde çevrilmez.
  static const Map<String, String> _pieceSetLabels = {
    'chessnut': 'Chessnut',
    'rhosgfx': 'RhosGFX',
    'fantasy': 'Fantasy',
    'spatial': 'Spatial',
    'celtic': 'Celtic',
    'kiwen-suwi': 'Kiwen Suwi',
    'firi': 'Firi',
    'totoy': 'Totoy',
    'papercut': 'Papercut',
  };

  static String label(String name) {
    final pieceSet = _pieceSetLabels[name];
    if (pieceSet != null) return pieceSet;
    final table = _labelTables[Strings.code] ?? _labelsEn;
    return table[name] ??
        _labelsEn[name] ??
        name[0].toUpperCase() + name.substring(1).replaceAll('_', ' ');
  }

  static String boardPath(String name) => 'assets/boards/$name.png';

  static String piecePath(String set, String code) =>
      'assets/pieces/$set/$code.svg';
}
