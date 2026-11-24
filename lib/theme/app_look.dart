import 'package:flutter/material.dart';

/// Uygulamanın görünümü: vurgu rengi, zeminlerin tonu ve uygulama simgesi
/// (10.13.0, kullanıcının isteği).
///
/// Bir görünüm seçilince uygulamanın renkleri ([AppTheme.darkFor],
/// [AppTheme.lightFor]), ana menüdeki logo ve uygulamanın simgesi birlikte
/// değişir. Koyu / açık kip ayrı bir ayar olarak kalıyor: her görünümün iki
/// kipi de var.
///
/// Simgeler bu tablodan üretiliyor (`tools/make_look_icons.py` dosyayı
/// okuyor); bir renk değişince araç yeniden çalıştırılmalı. Biçimi koru:
/// her görünüm `AppLook(` ile başlayan, alanları satır satır yazılmış bir
/// blok.
@immutable
class AppLook {
  const AppLook({
    required this.id,
    required this.iconTop,
    required this.iconBottom,
    required this.knight,
    required this.accentDark,
    required this.accentLight,
    this.hue,
    this.saturation = 0,
  });

  /// Ayarda saklanan ad; simge dosyalarının ve Android takma adının adı da
  /// bundan türüyor. Değiştirilmemeli (eski ayarlar okunamaz olur).
  final String id;

  /// Simgenin zemini: sol üstten sağ alta geçiş.
  final Color iconTop;
  final Color iconBottom;

  /// Simgedeki atın rengi.
  final Color knight;

  /// Vurgu rengi (düğmeler, seçili öğeler): koyu kipte açık bir ton, açık
  /// kipte koyu bir ton; ikisi de zeminin üstünde okunmalı
  /// (`test/app_look_test.dart` karşıtlığı ölçüyor).
  final Color accentDark;
  final Color accentLight;

  /// Zeminlerin tonu (0–360) ve doygunluğu. `null`: uygulamanın kendi sıcak
  /// zeminleri olduğu gibi kalır (yalnızca [yesil]).
  final double? hue;
  final double saturation;

  /// Bugüne kadarki görünüm; varsayılan.
  static const yesil = AppLook(
    id: 'yesil',
    iconTop: Color(0xFF8FBB57),
    iconBottom: Color(0xFF4E7327),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFF7FA650),
    accentLight: Color(0xFF5C8032),
  );

  static const gece = AppLook(
    id: 'gece',
    iconTop: Color(0xFF3E547A),
    iconBottom: Color(0xFF0C1220),
    knight: Color(0xFFDBA753),
    accentDark: Color(0xFFDBA753),
    accentLight: Color(0xFF2B4170),
    hue: 220,
    saturation: 0.30,
  );

  static const gok = AppLook(
    id: 'gok',
    iconTop: Color(0xFF62B0EC),
    iconBottom: Color(0xFF1C68AE),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFF6CB6F0),
    accentLight: Color(0xFF1C68AE),
    hue: 208,
    saturation: 0.16,
  );

  static const petrol = AppLook(
    id: 'petrol',
    iconTop: Color(0xFF2FAEAA),
    iconBottom: Color(0xFF0A4950),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFF55C2B6),
    accentLight: Color(0xFF0E6E72),
    hue: 182,
    saturation: 0.16,
  );

  static const mor = AppLook(
    id: 'mor',
    iconTop: Color(0xFF9272D6),
    iconBottom: Color(0xFF2E1A5E),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFFB096E6),
    accentLight: Color(0xFF5B3FA8),
    hue: 262,
    saturation: 0.16,
  );

  static const bordo = AppLook(
    id: 'bordo',
    iconTop: Color(0xFFB04058),
    iconBottom: Color(0xFF3A0D16),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFFE08496),
    accentLight: Color(0xFF8C2E40),
    hue: 345,
    saturation: 0.14,
  );

  static const mercan = AppLook(
    id: 'mercan',
    iconTop: Color(0xFFF5946A),
    iconBottom: Color(0xFFBC4520),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFFF39A72),
    accentLight: Color(0xFFB5441E),
    hue: 16,
    saturation: 0.16,
  );

  static const altin = AppLook(
    id: 'altin',
    iconTop: Color(0xFFF0C674),
    iconBottom: Color(0xFFB57A28),
    knight: Color(0xFF1F3366),
    accentDark: Color(0xFFE6B860),
    accentLight: Color(0xFF8A5A12),
    hue: 40,
    saturation: 0.18,
  );

  static const kahve = AppLook(
    id: 'kahve',
    iconTop: Color(0xFFFAF2E0),
    iconBottom: Color(0xFFD9C4A0),
    knight: Color(0xFF5A3A22),
    accentDark: Color(0xFFD8AE84),
    accentLight: Color(0xFF74492A),
    hue: 28,
    saturation: 0.20,
  );

  static const antrasit = AppLook(
    id: 'antrasit',
    iconTop: Color(0xFF60646A),
    iconBottom: Color(0xFF141518),
    knight: Color(0xFFFFFFFF),
    accentDark: Color(0xFFCDD1D6),
    accentLight: Color(0xFF3A3D42),
    hue: 220,
    saturation: 0.03,
  );

  /// Seçme penceresindeki sırayla.
  static const List<AppLook> values = [
    yesil,
    gece,
    gok,
    petrol,
    mor,
    bordo,
    mercan,
    altin,
    kahve,
    antrasit,
  ];

  /// Ayardaki addan görünüm; bilinmeyen ad (eski ya da elle düzenlenmiş
  /// yedek) varsayılana düşer.
  static AppLook byId(String? id) {
    for (final look in values) {
      if (look.id == id) return look;
    }
    return yesil;
  }

  /// Simgenin zemin geçişi (logo ve seçme penceresi de kullanıyor).
  LinearGradient get iconGradient => LinearGradient(
        colors: [iconTop, iconBottom],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  String toString() => 'AppLook($id)';
}
