#!/usr/bin/env bash
# Tạo GitHub Release dưới tài khoản gh đang đăng nhập trên máy (danh tính của bạn),
# dùng các file đã được workflow "Build & phát hành" build cho tag đó.
# Dùng: tool/publish_release.sh v1.2.0
# Nếu tag đã có release (ví dụ do github-actions[bot] tạo), release đó được thay bằng release mới của bạn; tag giữ nguyên.
set -euo pipefail

TAG="${1:?Dùng: tool/publish_release.sh <tag, ví dụ v1.2.0>}"
REPO="${REPO:-ngiangbao/vn-stock-insight}"

RUN=$(gh run list -R "$REPO" --workflow release.yml --branch "$TAG" --limit 20 \
  --json databaseId,status,conclusion \
  -q '[.[] | select(.status == "completed" and .conclusion == "success")][0].databaseId')
[[ -n "$RUN" ]] || { echo "Chưa có lượt build thành công cho $TAG" >&2; exit 1; }

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
gh run download "$RUN" -R "$REPO" -D "$DIR"
mapfile -t FILES < <(find "$DIR" -type f | sort)
[[ ${#FILES[@]} -gt 0 ]] || { echo "Lượt build $RUN không có file nào" >&2; exit 1; }

(cd "$DIR" && find . -type f ! -name SHA256SUMS.txt -exec sha256sum {} + | sed 's# \./.*/# #; s# \./# #' > "$DIR/SHA256SUMS.txt")
FILES+=("$DIR/SHA256SUMS.txt")

NOTES="Dashboard mới: thanh chỉ số nhanh, bố cục thị trường gọn hơn và bản đồ nhiệt theo biến động, khối ngoại hoặc thanh khoản.

Tải bản cho máy của bạn:
- Windows: tải file \`-windows-x64-setup.exe\` và làm theo trình cài đặt, hoặc \`-windows-x64-portable.zip\` để giải nén và chạy trực tiếp. Nếu SmartScreen cảnh báo, xem mục Windows trong README. Mã SHA-256 của từng file nằm trong \`SHA256SUMS.txt\`.
- macOS: tải file \`-macos.pkg\` để cài vào Applications. Gói chưa được ký/notarize bằng Apple Developer ID; macOS có thể yêu cầu xác nhận khi mở.
- Linux: file \`-linux-x64.tar.gz\`, giải nén rồi chạy \`./vn-stock-insight/install.sh\`.
- Android: file \`.apk\`, mở để cài (cho phép cài từ nguồn không xác định)."

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release delete "$TAG" -R "$REPO" --yes
fi
gh release create "$TAG" -R "$REPO" --verify-tag --title "VN Stock Insight $TAG" --notes "$NOTES" "${FILES[@]}"
echo "Đã phát hành $TAG dưới tài khoản $(gh api user --jq .login)"
