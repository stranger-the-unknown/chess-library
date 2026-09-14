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
  ThemeMode _themeMode = ThemeMode.dark;
  AppLanguage _language = AppLanguage.system;
  static const String _defaultPieceSet = 'chessnut';

  String _pieceSet = _defaultPieceSet;

  /// Kare renkleri. Hazır tahta yoktur; kullanıcı ikisini de kendi seçer.
  int _boardLight = BoardAssets.defaultLight;
  int _boardDark = BoardAssets.defaultDark;

  /// Karelerin üstüne hafif bir ahşap damarı bindirilsin mi?
  bool _boardWood = false;
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
  int get boardLight => _boardLight;
  int get boardDark => _boardDark;

  bool get boardWood => _boardWood;

  /// Açık ve koyu kare rengi (0xAARRGGBB).
  (int, int) get squareColors => (_boardLight, _boardDark);
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
        (prefs.getInt('themeMode') ?? ThemeMode.dark.index)
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
    _boardLight = prefs.getInt('boardLight') ?? BoardAssets.defaultLight;
    _boardDark = prefs.getInt('boardDark') ?? BoardAssets.defaultDark;
    _boardWood = prefs.getBool('boardWood') ?? false;

    // 3.0'dan önce tahta bir adla saklanıyordu ('brown', 'walnut'...).
    // O kayıt duruyorsa karşılığı olan renk çiftine çevrilir; kullanıcı
    // güncellemeden sonra tahtasını değişmiş bulmaz.
    if (prefs.getInt('boardLight') == null) {
      final legacy = BoardAssets.legacyBoardColors(prefs.getString(
        'boardTheme',
      ));
      if (legacy != null) {
        _boardLight = legacy.$1;
        _boardDark = legacy.$2;
        await prefs.setInt('boardLight', _boardLight);
        await prefs.setInt('boardDark', _boardDark);
        await prefs.remove('boardTheme');
      }
    }
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

  set boardLight(int value) {
    _boardLight = value;
    _set('boardLight', value);
    notifyListeners();
  }

  set boardDark(int value) {
    _boardDark = value;
    _set('boardDark', value);
    notifyListeners();
  }

  set boardWood(bool value) {
    _boardWood = value;
    _set('boardWood', value);
    notifyListeners();
  }

  /// Kare renklerini başlangıç değerlerine döndürür.
  void resetBoardColors() {
    _boardLight = BoardAssets.defaultLight;
    _boardDark = BoardAssets.defaultDark;
    _boardWood = false;
    _set('boardLight', _boardLight);
    _set('boardDark', _boardDark);
    _set('boardWood', _boardWood);
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

/// Uygulamanın sürümü.
///
/// Tek kaynak burasıdır; `pubspec.yaml` ile aynı olduğu testle denetlenir.
/// Hakkında bölümünde ve yedek dosyasının başlığında görünür.
const String appVersionName = '3.0.0';

/// Tahta renkleri ve taş takımları.
///
/// Hazır tahta yoktur: kullanıcı açık ve koyu kare rengini [palette]
/// içinden kendi seçer, tahta da doğrudan o iki renkten çizilir. Böylece
/// tahta hiç yer kaplamaz, her ölçüde keskin çıkar ve kimsenin telifinde
/// olmayan bir dama deseninden ibaret kalır.
class BoardAssets {
  BoardAssets._();

  /// Başlangıç renkleri: klasik kahve tahta.
  static const int defaultLight = 0xFFF0D9B5;
  static const int defaultDark = 0xFFB58863;

  /// Kare renkleri için seçenekler (100 renk).
  ///
  /// Açıktan koyuya sıralanmıştır: seçim ızgarasının üst
  /// satırları açık kare, alt satırları koyu kare için uygundur.
  /// Önceki hazır tahtaların bütün kare renkleri buranın
  /// içindedir; eski görünümlerden hiçbiri kaybolmadı.
  static const List<int> palette = [
    0xFFF5F5F5, 0xFFF2EDE3, 0xFFF3DFE2, 0xFFE6E0EC, 0xFFEFDFDC,
    0xFFEFE7DC, 0xFFEFEEDC, 0xFFE4EFDC, 0xFFDCEFE2, 0xFFDCEFEF,
    0xFFDCE4EF, 0xFFE4DCEF, 0xFFEFDCEA, 0xFFDEE3E6, 0xFFEEEED2,
    0xFFD8E8E6, 0xFFDEDEDE, 0xFFDCDCDC, 0xFFE8E9CC, 0xFFEDDCBE,
    0xFFF0D9B5, 0xFFC6CDD6, 0xFFD9B9E2, 0xFFDFBFB9, 0xFFDFCFB9,
    0xFFDFDCB9, 0xFFC9DFB9, 0xFFB9DFC6, 0xFFB9DFDF, 0xFFB9C9DF,
    0xFFC9B9DF, 0xFFC4C4C4, 0xFFAEB7C4, 0xFFDCBF92, 0xFFC3B7A4,
    0xFFD09F95, 0xFFD0B795, 0xFFD0CB95, 0xFFAED095, 0xFF95D0A9,
    0xFF95D0D0, 0xFF95AED0, 0xFFAE95D0, 0xFFD095C1, 0xFFA8A8A8,
    0xFFBE8A96, 0xFF9B8BB4, 0xFFC0A47B, 0xFF8CA2AD, 0xFFC2A076,
    0xFFBD796B, 0xFFBD9B6B, 0xFFBDB66B, 0xFF8DBD6B, 0xFF6BBD86,
    0xFF6BBDBD, 0xFF6B8DBD, 0xFF8D6BBD, 0xFFBD6BA8, 0xFF8F8F8F,
    0xFFB79062, 0xFFB58863, 0xFF8C8C8C, 0xFF74A09B, 0xFF854AAF,
    0xFF69788A, 0xFF769656, 0xFFA25849, 0xFFA27D49, 0xFFA29A49,
    0xFF6EA249, 0xFF49A266, 0xFF49A2A2, 0xFF496EA2, 0xFFA2498C,
    0xFF986D45, 0xFF5E8A4E, 0xFF696969, 0xFF4B5A72, 0xFF784136,
    0xFF785C36, 0xFF787236, 0xFF517836, 0xFF36784C, 0xFF367878,
    0xFF365178, 0xFF513678, 0xFF783667, 0xFF654328, 0xFF424242,
    0xFF53331F, 0xFF4D2A23, 0xFF4D3C23, 0xFF4D4A23, 0xFF354D23,
    0xFF234D31, 0xFF234D4D, 0xFF23354D, 0xFF35234D, 0xFF4D2343,
  ];

  /// 3.0 öncesindeki hazır tahtaların kare renkleri.
  ///
  /// Yalnızca eski ayarı çevirmek için durur; arayüzde görünmez.
  static const Map<String, (int, int)> _legacyBoards = {
    'brown': (0xFFF0D9B5, 0xFFB58863),
    'green': (0xFFEEEED2, 0xFF769656),
    'tournament': (0xFFE8E9CC, 0xFF5E8A4E),
    'blue': (0xFFDEE3E6, 0xFF8CA2AD),
    'gray': (0xFFDCDCDC, 0xFF8F8F8F),
    'slate': (0xFFC6CDD6, 0xFF69788A),
    'sand': (0xFFEDDCBE, 0xFFC0A47B),
    'purple': (0xFFE6E0EC, 0xFF9B8BB4),
    'ivory': (0xFFF2EDE3, 0xFFC3B7A4),
    'rose': (0xFFF3DFE2, 0xFFBE8A96),
    'teal': (0xFFD8E8E6, 0xFF74A09B),
    'midnight': (0xFFAEB7C4, 0xFF4B5A72),
    'dark_wood': (0xFFB79062, 0xFF53331F),
    'walnut': (0xFFC2A076, 0xFF654328),
    'oak': (0xFFDCBF92, 0xFF986D45),
  };

  /// Eski tahta adının renk karşılığı; tanınmayan ad için `null`.
  static (int, int)? legacyBoardColors(String? name) =>
      name == null ? null : _legacyBoards[name];

  // -------------------------------------------------------------------
  // Renk hesapları
  // -------------------------------------------------------------------

  /// Bir rengin göreli parlaklığı (WCAG).
  static double _luminance(int argb) {
    double channel(int value) {
      final c = value / 255.0;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((argb >> 16) & 0xFF) +
        0.7152 * channel((argb >> 8) & 0xFF) +
        0.0722 * channel(argb & 0xFF);
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
  /// alışılmış görünüm değişmesin, yalnızca gerçekten okunmaz duruma
  /// düşen renk çiftlerinde devreye girsin.
  static const double _minCoordinateContrast = 2.0;

  /// Kare adlarının rengi.
  ///
  /// Yazı, üzerinde durduğu karenin karşıt kare rengini alır; tahta ne
  /// olursa olsun uyumlu görünür. İki renk birbirine çok yakın seçilirse
  /// bu yazı kaybolurdu, o yüzden karşıtlık ölçülür ve gerekirse siyah
  /// ya da beyaza düşülür. Böylece kullanıcı hangi ikiliyi seçerse seçsin
  /// kare adları okunur kalır.
  static int coordinateColor({
    required int light,
    required int dark,
    required bool onLightSquare,
  }) {
    final background = onLightSquare ? light : dark;
    final opposite = onLightSquare ? dark : light;
    if (contrastRatio(opposite, background) >= _minCoordinateContrast) {
      return opposite;
    }
    const black = 0xFF000000;
    const white = 0xFFFFFFFF;
    return contrastRatio(black, background) >= contrastRatio(white, background)
        ? black
        : white;
  }

  /// `assets/pieces/<ad>/<w|b><p|n|b|r|q|k>.svg`
  ///
  /// Takımlar dışarıdan alınmıştır; kaynak ve lisansları `ASSETS.md`
  /// içinde listelenir.
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

  /// İşaretleme rengi (0xAARRGGBB).
  ///
  /// Sağ tıkla konan işaretler ve çizilen oklar her tahtada seçilebilsin
  /// diye renk tahtadan türetilir: koyu karenin renk tonundan en uzak
  /// ton seçilir. Böylece yeşil tahtada yeşil, mavi tahtada mavi işaret
  /// konmaz ve tek bir sabit renk aramak gerekmez.
  static int markColor(int dark) {
    const options = <int>[
      0xFFE2571E, // turuncu
      0xFF2E9E3F, // yeşil
      0xFF1E6FD9, // mavi
      0xFF9B27B0, // mor
    ];
    final boardHue = HSVColor.fromColor(Color(dark)).hue;

    int best = options.first;
    double bestDistance = -1;
    for (final candidate in options) {
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

  static String label(String name) =>
      _pieceSetLabels[name] ??
      name[0].toUpperCase() + name.substring(1).replaceAll('_', ' ');

  static String piecePath(String set, String code) =>
      'assets/pieces/$set/$code.svg';
}
