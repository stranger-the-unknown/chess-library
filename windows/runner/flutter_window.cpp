#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "chess_library/window",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Kapatma, motordan önce: onay yoksa Dart'a sor ve bekle. Onaydan sonra
  // motora uğramadan kapat; yoksa motor aynı soruyu bir kez daha
  // sordurabilirdi.
  if (message == WM_CLOSE) {
    if (close_approved_ || !window_channel_) {
      ::DestroyWindow(hwnd);
    } else {
      RequestClose(hwnd);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RequestClose(HWND hwnd) {
  // Pencere simge durumundaysa soru görünmez; kullanıcı onu bulabilsin.
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd);
  if (close_pending_) {
    return;
  }
  close_pending_ = true;

  // Kullanıcı pencerede hapsolmasın: Dart yanıt veremezse (hata, işleyici
  // yok) kapatmaya izin verilir. Yalnızca açık bir "false" pencereyi açık
  // tutar.
  auto result =
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [this, hwnd](const flutter::EncodableValue* value) {
            close_pending_ = false;
            const bool* allow =
                value == nullptr ? nullptr : std::get_if<bool>(value);
            if (allow == nullptr || *allow) {
              ApproveClose(hwnd);
            }
          },
          [this, hwnd](const std::string&, const std::string&,
                       const flutter::EncodableValue*) {
            close_pending_ = false;
            ApproveClose(hwnd);
          },
          [this, hwnd]() {
            close_pending_ = false;
            ApproveClose(hwnd);
          });
  window_channel_->InvokeMethod("requestClose", nullptr, std::move(result));
}

void FlutterWindow::ApproveClose(HWND hwnd) {
  close_approved_ = true;
  ::PostMessage(hwnd, WM_CLOSE, 0, 0);
}
