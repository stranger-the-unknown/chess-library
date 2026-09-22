#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Pencere kapatılırken Dart'a kaydedilmemiş iş olup olmadığını sorar.
  //
  // Flutter motoru kapatma isteğini yalnızca sürecin son üst düzey
  // penceresi kapanırken Dart'a iletiyor; ses eklentisinin gizli
  // "MediaPlayer SMTC" pencereleri yüzünden bu uygulamada hiç
  // iletmiyordu ve kaydedilmemiş oyun sormadan kayboluyordu. İstek
  // burada, motordan önce yakalanıyor.
  void RequestClose(HWND hwnd);

  // Dart onay verdi: pencereyi mesaj kuyruğu üzerinden kapat. Motorun
  // kendi geri çağrısının içinde pencereyi (ve motoru) yok etmemek için.
  void ApproveClose(HWND hwnd);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Soru ekranda; yeni kapatma istekleri yalnızca pencereyi öne getirir.
  bool close_pending_ = false;

  // Kapatma onaylandı; sıradaki WM_CLOSE pencereyi gerçekten kapatır.
  bool close_approved_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
