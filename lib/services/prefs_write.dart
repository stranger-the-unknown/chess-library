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

/// Son yazma hatasından beri geçen süre (hata yoksa çalışmıyor).
final Stopwatch _sinceFailure = Stopwatch();
int _acknowledgedFailures = 0;

/// Yazma hatasını duyurur (uygulama kökü "Kaydedilemedi" der).
void reportWriteFailure() {
  _sinceFailure
    ..reset()
    ..start();
  diskWriteFailures.value++;
}

/// Az önce bir yazma başarısız oldu ve henüz başka bir bildirim
/// gösterilmedi mi?
///
/// Servisler hatayı fırlatmadan duyuruyor; çağıran ekran işi bitmiş sayıp
/// hemen "3 işaretlendi" gibi bir bildirim gösteriyor ve o bildirim
/// "Kaydedilemedi" uyarısını bir kare içinde kapatıyordu. Bildirim
/// gösteren yer buna bakıyor: `true` dönerse kendi mesajını göstermiyor.
/// Her hata için bir kez `true` döner; hatadan çok sonra gelen ilgisiz
/// bir bildirim yutulmasın diye yalnızca birkaç saniye içinde.
bool takeRecentWriteFailure() {
  if (diskWriteFailures.value == _acknowledgedFailures) return false;
  _acknowledgedFailures = diskWriteFailures.value;
  return _sinceFailure.isRunning &&
      _sinceFailure.elapsed < const Duration(seconds: 3);
}

/// Metni yazar; başarısız olursa bir kez daha dener.
///
/// Yazma cihazda yer kalmadığında `false` dönüyor. Eskiden bu değere
/// hiç bakılmıyordu: ekran "kaydedildi" diyor, veri diske hiç
/// ulaşmıyordu.
Future<bool> writeString(String key, String value) async {
  final store = AppStore.instance;
  var ok = await store.setString(key, value);
  if (!ok) ok = await store.setString(key, value);
  if (!ok) reportWriteFailure();
  return ok;
}

/// [writeString]'in metin listesi için olanı.
Future<bool> writeStringList(String key, List<String> value) async {
  final store = AppStore.instance;
  var ok = await store.setStringList(key, value);
  if (!ok) ok = await store.setStringList(key, value);
  if (!ok) reportWriteFailure();
  return ok;
}
