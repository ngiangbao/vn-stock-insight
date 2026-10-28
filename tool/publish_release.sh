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

NOTES="Tải bản cho máy của bạn:
- Windows: file \`-windows-x64.zip\`, giải nén rồi chạy \`vn_stock_insight.exe\`.
- macOS: file \`-macos.zip\`, giải nén, kéo app vào Applications. Lần đầu mở: chuột phải → Open (app chưa được Apple ký).
- Linux: file \`-linux-x64.tar.gz\`, giải nén rồi chạy \`./vn-stock-insight/install.sh\`.
- Android: file \`.apk\`, mở để cài (cho phép cài từ nguồn không xác định)."

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release delete "$TAG" -R "$REPO" --yes
fi
gh release create "$TAG" -R "$REPO" --verify-tag --title "VN Stock Insight $TAG" --notes "$NOTES" "${FILES[@]}"
echo "Đã phát hành $TAG dưới tài khoản $(gh api user --jq .login)"
