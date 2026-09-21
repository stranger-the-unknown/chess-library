import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bozuk bir kayıt bulunduğunda artan sayaç.
///
/// Uygulama kökü bunu dinleyip kullanıcıya söylüyor. Eskiden karantina
/// sessizdi: o sekme boş açılıyor, kullanıcı verisinin tamamen gittiğini
/// sanıyordu. Veri duruyor, yalnızca `<anahtar>_bozuk` altında.
final ValueNotifier<int> corruptRecords = ValueNotifier<int>(0);

/// Bozuk bir kaydın uygulamanın o bölümünü tamamen açılmaz hâle
/// getirmesini engeller.
///
/// Yarım yazılmış ya da elle bozulmuş bir JSON kaydında `jsonDecode`
/// (ya da sonraki `fromJson`) hata fırlatıyor; hata yükleme yordamından
/// çıkıp ekrana kadar gidince o sekme hiç açılmıyordu. Burada ham veri
/// `<anahtar>_bozuk` altına kopyalanıyor — silinmiyor, elle
/// kurtarılabilsin diye — ve çağıran boş/varsayılan veriyle açılıyor.
///
/// Oyun listelerinde bu düzen 9.0.3'te kurulmuştu; açılışlar, bulmacalar
/// ve eski liste anahtarı dışarıda kalmıştı.
Future<T> readOrQuarantine<T>(
  SharedPreferences prefs,
  String key,
  String raw,
  T Function(dynamic decoded) parse,
  T Function() fallback,
) async {
  try {
    return parse(jsonDecode(raw));
  } catch (_) {
    await prefs.setString('${key}_bozuk', raw);
    corruptRecords.value++;
    return fallback();
  }
}
