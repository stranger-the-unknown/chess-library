import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Diske yazma başarısız olduğunda artan sayaç.
///
/// Uygulama kökü bunu dinliyor ve kullanıcıya bir kez söylüyor.
/// Servislerin hata fırlatmak yerine haber vermesinin sebebi: bu
/// yazmalar onlarca ekrandan çağrılıyor ve yakalanmayan bir hata
/// kullanıcıya kırmızı ekran olarak dönerdi. Oyun listeleri ayrı:
/// orada çağıran taraf hatayı zaten yakalıyor.
final ValueNotifier<int> diskWriteFailures = ValueNotifier<int>(0);

/// Metni yazar; başarısız olursa bir kez daha dener.
///
/// `SharedPreferences.setString` cihazda yer kalmadığında `false`
/// dönüyor. Eskiden bu değere hiç bakılmıyordu: ekran "kaydedildi"
/// diyor, veri diske hiç ulaşmıyordu.
Future<bool> writeString(
  SharedPreferences prefs,
  String key,
  String value,
) async {
  var ok = await prefs.setString(key, value);
  if (!ok) ok = await prefs.setString(key, value);
  if (!ok) diskWriteFailures.value++;
  return ok;
}
