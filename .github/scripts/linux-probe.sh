#!/bin/sh
# CI: uygulamayı sanal ekranda (xvfb + openbox) açar, ekran görüntüsü alır
# ve pencereyi pencere yöneticisi üzerinden kapatır (X düğmesiyle aynı yol:
# WM_DELETE_WINDOW → GTK delete-event → Dart'a "kapatılsın mı" sorusu).
#
#   linux-probe.sh <uygulama> <ekran-görüntüsü.png>
#
# Başarı: uygulama 15 saniye açık kalıyor ve kapatma isteğinden sonra
# 10 saniye içinde çıkıyor.
set -u
app="$1"
shot="$2"

openbox > /dev/null 2>&1 &
sleep 2

"$app" &
pid=$!
sleep 15

if ! kill -0 "$pid" 2> /dev/null; then
  echo "UYGULAMA ERKEN KAPANDI"
  exit 1
fi

import -window root "$shot"
wmctrl -l
wmctrl -c "Chess Library"

i=0
while [ "$i" -lt 20 ]; do
  if ! kill -0 "$pid" 2> /dev/null; then
    echo "kapatma isteğiyle kapandı"
    exit 0
  fi
  sleep 0.5
  i=$((i + 1))
done

echo "KAPANMADI"
kill "$pid"
exit 1
