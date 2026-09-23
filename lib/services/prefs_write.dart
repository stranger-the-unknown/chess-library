import 'package:flutter/foundation.dart';
import 'app_store.dart';

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
/// Yazma cihazda yer kalmadığında `false` dönüyor. Eskiden bu değere
/// hiç bakılmıyordu: ekran "kaydedildi" diyor, veri diske hiç
/// ulaşmıyordu.
Future<bool> writeString(String key, String value) async {
  final store = AppStore.instance;
  var ok = await store.setString(key, value);
  if (!ok) ok = await store.setString(key, value);
  if (!ok) diskWriteFailures.value++;
  return ok;
}
