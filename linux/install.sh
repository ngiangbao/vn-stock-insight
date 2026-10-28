#!/usr/bin/env bash
# Cài VN Stock Insight cho người dùng hiện tại (không cần sudo).
# Dùng: ./install.sh [thư mục bundle]   (mặc định: thư mục chứa script này, hoặc bản build release)
# Gỡ:   ./install.sh --uninstall
set -euo pipefail

APP=vn-stock-insight
DEST="$HOME/.local/share/$APP"
DESKTOP="$HOME/.local/share/applications/$APP.desktop"
ICON="$HOME/.local/share/icons/hicolor/scalable/apps/$APP.svg"
LINK="$HOME/.local/bin/$APP"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$DEST" "$DESKTOP" "$ICON" "$LINK"
  echo "Đã gỡ VN Stock Insight."
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  if [[ -x "$HERE/vn_stock_insight" ]]; then SRC="$HERE"; else SRC="$HERE/../build/linux/x64/release/bundle"; fi
fi
[[ -x "$SRC/vn_stock_insight" ]] || { echo "Không tìm thấy bản build tại $SRC" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST" "$(dirname "$DESKTOP")" "$(dirname "$ICON")" "$(dirname "$LINK")"
cp -r "$SRC/." "$DEST/"
for icon in "$SRC/icon.svg" "$HERE/../assets/icon.svg"; do
  if [[ -f "$icon" ]]; then cp "$icon" "$ICON"; break; fi
done
ln -sf "$DEST/vn_stock_insight" "$LINK"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=VN Stock Insight
Comment=Phân tích cổ phiếu Việt Nam bằng AI
Exec=$DEST/vn_stock_insight
Icon=$APP
Categories=Office;Finance;
StartupWMClass=vn.stockinsight.vn_stock_insight
Terminal=false
EOF

command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP")" || true
echo "Đã cài VN Stock Insight vào $DEST"
echo "Mở từ trình khởi chạy ứng dụng, hoặc chạy lệnh: $APP"
