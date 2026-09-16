import 'dart:math' as math;

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
  //
  // Tema varsayılanı **cihazın kendi ayarı**: telefon gece modundaysa
  // uygulama da gece modunda açılır. Kullanıcı ayarlardan açıkça birini
  // seçerse seçim kaydedilir ve cihazı izlemeyi bırakır.
  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.system;
  static const String _defaultPieceSet = 'cburnett';
  static const String _defaultBoardTheme = 'brown';

  String _pieceSet = _defaultPieceSet;
  String _boardTheme = _defaultBoardTheme;
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

  /// Ayarları diskten okur.
  ///
  /// Açılışta bir kez, yedek geri yüklendiğinde bir kez daha çağrılır.
  /// Bu yüzden eksik bir anahtar **bellekteki eski değeri korumaz**,
  /// varsayılana döner: yoksa ayarı içermeyen bir yedek geri
  /// yüklendiğinde cihazın eski tercihi sessizce yerinde kalırdı.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _themeMode = ThemeMode.values[
        (prefs.getInt('themeMode') ?? ThemeMode.system.index)
            .clamp(0, ThemeMode.values.length - 1)];
    _language = AppLanguage.values[
        (prefs.getInt('language') ?? AppLanguage.system.index)
            .clamp(0, AppLanguage.values.length - 1)];
    Strings.language = _language;
    // Kayitli ad artik listede yoksa (eski surumden guncelleme) varsayilana
    // donulur; aksi halde bulunamayan bir varlik yuklenmeye calisilir.
    final storedPieceSet = prefs.getString('pieceSet');
    _pieceSet = storedPieceSet != null &&
            BoardAssets.pieceSets.contains(storedPieceSet)
        ? storedPieceSet
        : _defaultPieceSet;
    final storedBoard = prefs.getString('boardTheme');
    _boardTheme = storedBoard != null &&
            BoardAssets.boards.contains(storedBoard)
        ? storedBoard
        : _defaultBoardTheme;
    _showCoordinates = prefs.getBool('showCoordinates') ?? true;
    _showLegalMoves = prefs.getBool('showLegalMoves') ?? true;
    _highlightLastMove = prefs.getBool('highlightLastMove') ?? true;
    _animateMoves = prefs.getBool('animateMoves') ?? true;
    _soundEnabled = prefs.getBool('soundEnabled') ?? true;
    _confirmMoves = prefs.getBool('confirmMoves') ?? false;
    _engineLevel = prefs.getInt('engineLevel') ?? 2;
    _showEvaluationBar = prefs.getBool('showEvaluationBar') ?? true;
    _showDailyCount = prefs.getBool('showDailyCount') ?? true;
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
const String appVersionName = '5.0.0';

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
    'wood',
    'wood2',
    'wood3',
    'wood4',
    'maple',
    'maple2',
    'marble',
    'blue_marble',
    'stone',
    'metal',
    'leather',
    'canvas',
    'olive',
    'green_plastic',
    'pink_pyramid',
    'purple_diag',
    'horsey',
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
    'cburnett',
    'chessnut',
    'rhosgfx',
    'fantasy',
    'spatial',
    'celtic',
    'kiwen-suwi',
    'firi',
    'totoy',
    'papercut',
    'merida',
    'mono',
    'letter',
    'pirouetti',
    'pixel',
    'mpchess',
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
    'wood': (0xD7A258, 0x965120),
    'wood2': (0x9D8355, 0x7F6435),
    'wood3': (0xBCB4AB, 0x8E6C46),
    'wood4': (0xC5A571, 0x7F5532),
    'maple': (0xDFBD92, 0xB97742),
    'maple2': (0xE0C69E, 0xAE775D),
    'marble': (0x829883, 0x647B63),
    'blue_marble': (0xE5E2D8, 0x959EAD),
    'stone': (0xA9A9A9, 0x878787),
    'metal': (0xC7C7C7, 0x8E8E8E),
    'leather': (0xCECEC6, 0xC08B12),
    'canvas': (0xD0D4E5, 0x7B8BA6),
    'olive': (0xADA694, 0x847B69),
    'green_plastic': (0xF1F6B2, 0x59935D),
    'pink_pyramid': (0xEFF0C2, 0xF27676),
    'purple_diag': (0xE6DBF1, 0x997DB5),
    'horsey': (0xF8ECD8, 0x8E6547),
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

  /// Bir rengin göreli parlaklığı (WCAG).
  static double _luminance(int rgb) {
    double channel(int value) {
      final c = value / 255.0;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((rgb >> 16) & 0xFF) +
        0.7152 * channel((rgb >> 8) & 0xFF) +
        0.0722 * channel(rgb & 0xFF);
  }

  /// İki rengin karşıtlık oranı (1 ile 21 arasında).
  @visibleForTesting
  static double contrastRatio(int a, int b) {
    final first = _luminance(a);
    final second = _luminance(b);
    final high = first > second ? first : second;
    final low = first > second ? second : first;
    return (high + 0.05) / (low + 0.05);
  }

  /// Kare adının okunabilir sayılması için gereken en düşük karşıtlık.
  ///
  /// Klasik kahve tahtanın kendi oranı 2,24; eşik onun altında tutuldu ki
  /// alışılmış tahtaların görünümü değişmesin.
  static const double _minCoordinateContrast = 2.0;

  static int coordinateColor(String board, {required bool onLightSquare}) {
    final pair = _squareColors[board] ?? _fallbackSquares;
    final background = onLightSquare ? pair.$1 : pair.$2;
    final opposite = onLightSquare ? pair.$2 : pair.$1;
    if (contrastRatio(opposite, background) >= _minCoordinateContrast) {
      return 0xFF000000 | opposite;
    }
    // Taş, mermer, zeytin gibi tahtalarda iki kare rengi birbirine çok
    // yakın; karşıt kare rengi yazıldığında koordinatlar zeminde
    // kayboluyor. Böyle tahtalarda siyah ya da beyaza düşülür.
    const black = 0xFF000000;
    const white = 0xFFFFFFFF;
    return contrastRatio(0x000000, background) >=
            contrastRatio(0xFFFFFF, background)
        ? black
        : white;
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
    'wood': 'Ahşap',
    'wood2': 'Ahşap II',
    'wood3': 'Ahşap III',
    'wood4': 'Ahşap IV',
    'maple': 'Akçaağaç',
    'maple2': 'Akçaağaç II',
    'blue_marble': 'Mavi Mermer',
    'stone': 'Taş',
    'metal': 'Metal',
    'leather': 'Deri',
    'canvas': 'Kanvas',
    'olive': 'Zeytin',
    'green_plastic': 'Yeşil Plastik',
    'pink_pyramid': 'Pembe Piramit',
    'purple_diag': 'Mor Çizgi',
    'horsey': 'Horsey',
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
    'wood': 'Wood',
    'wood2': 'Wood II',
    'wood3': 'Wood III',
    'wood4': 'Wood IV',
    'maple': 'Maple',
    'maple2': 'Maple II',
    'blue_marble': 'Blue marble',
    'stone': 'Stone',
    'metal': 'Metal',
    'leather': 'Leather',
    'canvas': 'Canvas',
    'olive': 'Olive',
    'green_plastic': 'Green plastic',
    'pink_pyramid': 'Pink pyramid',
    'purple_diag': 'Purple diagonal',
    'horsey': 'Horsey',
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
    'cburnett': 'Cburnett',
    'merida': 'Merida',
    'mono': 'Mono',
    'letter': 'Letter',
    'pirouetti': 'Pirouetti',
    'pixel': 'Pixel',
    'mpchess': 'MPChess',
  };

  static String label(String name) {
    final pieceSet = _pieceSetLabels[name];
    if (pieceSet != null) return pieceSet;
    final table = _labelTables[Strings.code] ?? _labelsEn;
    return table[name] ??
        _labelsEn[name] ??
        name[0].toUpperCase() + name.substring(1).replaceAll('_', ' ');
  }

  /// Görselli tahtaların dosya adları.
  ///
  /// Dosya uzantısı tahtadan tahtaya değişiyor: fotoğraf dokuları JPEG,
  /// düz desenli olanlar PNG olarak daha küçük duruyor. Uzantıyı burada
  /// tutmak, hepsini tek biçime çevirip boyut şişirmekten iyi.
  static const Map<String, String> _imageBoards = {
    'dark_wood': 'dark_wood.png',
    'walnut': 'walnut.png',
    'oak': 'oak.png',
    'wood': 'wood.jpg',
    'wood2': 'wood2.jpg',
    'wood3': 'wood3.jpg',
    'wood4': 'wood4.jpg',
    'maple': 'maple.jpg',
    'maple2': 'maple2.jpg',
    'marble': 'marble.jpg',
    'blue_marble': 'blue_marble.jpg',
    'stone': 'stone.jpg',
    'metal': 'metal.jpg',
    'leather': 'leather.jpg',
    'canvas': 'canvas.jpg',
    'olive': 'olive.jpg',
    'green_plastic': 'green_plastic.png',
    'pink_pyramid': 'pink_pyramid.png',
    'purple_diag': 'purple_diag.png',
    'horsey': 'horsey.jpg',
  };

  static String boardPath(String name) =>
      'assets/boards/${_imageBoards[name] ?? '$name.png'}';

  static String piecePath(String set, String code) =>
      'assets/pieces/$set/$code.svg';
}
