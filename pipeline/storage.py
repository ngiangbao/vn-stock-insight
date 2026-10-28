"""Lưu kết quả: vào Supabase Storage (bucket riêng tư) nếu có cấu hình, luôn ghi thêm bản trên máy.

Chỉ người dùng đã đăng nhập (được mời) mới đọc được bucket này, nên dữ liệu không còn nằm công khai trong repo.
"""

import json
import os
from pathlib import Path

import requests

BUCKET = "data"


def _supabase() -> tuple[str, str] | None:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_KEY", "")
    return (url, key) if url and key else None


def _upload(url: str, key: str, path: str, body: bytes) -> None:
    resp = requests.post(
        f"{url}/storage/v1/object/{BUCKET}/{path}",
        headers={
            "Authorization": f"Bearer {key}",
            "apikey": key,
            "Content-Type": "application/json",
            "x-upsert": "true",
            "Cache-Control": "no-cache",
        },
        data=body,
        timeout=60,
    )
    resp.raise_for_status()


def _list_history(url: str, key: str) -> list[str]:
    resp = requests.post(
        f"{url}/storage/v1/object/list/{BUCKET}",
        headers={"Authorization": f"Bearer {key}", "apikey": key},
        json={"prefix": "history", "limit": 1000, "sortBy": {"column": "name", "order": "desc"}},
        timeout=30,
    )
    resp.raise_for_status()
    return [o["name"].removesuffix(".json") for o in resp.json() if o["name"].endswith(".json")]


def save(output: dict, day: str, local_dir: Path) -> None:
    payload = json.dumps(output, ensure_ascii=False, separators=(",", ":")).encode()

    # Bản trên máy: dùng khi chạy thử (thư mục này không được đưa lên GitHub)
    history_dir = local_dir / "history"
    history_dir.mkdir(parents=True, exist_ok=True)
    (local_dir / "latest.json").write_bytes(payload)
    (history_dir / f"{day}.json").write_bytes(payload)
    days = sorted((p.stem for p in history_dir.glob("*.json")), reverse=True)
    (local_dir / "history.json").write_text(json.dumps(days), encoding="utf-8")
    print(f"[storage] Đã ghi bản trên máy vào {local_dir}")

    remote = _supabase()
    if not remote:
        print("[storage] Chưa cấu hình SUPABASE_URL/SUPABASE_SERVICE_KEY, bỏ qua bước tải lên")
        return
    url, key = remote
    _upload(url, key, "latest.json", payload)
    _upload(url, key, f"history/{day}.json", payload)
    days = sorted(set(_list_history(url, key)) | {day}, reverse=True)
    _upload(url, key, "history.json", json.dumps(days).encode())
    print(f"[storage] Đã tải lên Supabase ({len(days)} ngày lịch sử)")
