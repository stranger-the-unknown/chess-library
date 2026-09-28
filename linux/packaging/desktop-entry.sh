#!/bin/sh
# Chess Library'yi uygulama menüsüne ekler (masaüstü girdisi).
# Adds Chess Library to the application menu (desktop entry).
#
#   ./desktop-entry.sh           ekle / add
#   ./desktop-entry.sh --remove  kaldır / remove
#
# Girdi bu klasörü gösterir; klasörü taşırsan yeniden çalıştır.
# The entry points at this folder; run it again if you move the folder.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ID="io.github.strangertheunknown.ChessLibrary"
TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$ID.desktop"

if [ "$1" = "--remove" ]; then
  rm -f "$TARGET"
  echo "Kaldırıldı / removed: $TARGET"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
cat > "$TARGET" <<EOF
[Desktop Entry]
Type=Application
Name=Chess Library
Comment=Chess games, puzzles, openings and a human-like opponent
Comment[tr]=Satranç oyunları, bulmacalar, açılışlar ve insan gibi oynayan rakip
Exec="$DIR/chess_library"
Icon=$DIR/data/chess_library.png
Terminal=false
Categories=Game;BoardGame;
StartupWMClass=$ID
EOF
echo "Eklendi / added: $TARGET"
