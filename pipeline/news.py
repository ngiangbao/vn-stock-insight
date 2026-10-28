"""Gom tin tức từ các nguồn RSS."""

import calendar
import hashlib
import html
import re
import time

import feedparser
import requests

HEADERS = {"User-Agent": "Mozilla/5.0 (vn-stock-insight)"}
TAG_RE = re.compile(r"<[^>]+>")


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(TAG_RE.sub(" ", text or ""))).strip()


def fetch_news(feeds: list[dict], max_age_hours: int) -> list[dict]:
    cutoff = time.time() - max_age_hours * 3600
    items: dict[str, dict] = {}
    for feed in feeds:
        try:
            resp = requests.get(feed["url"], headers=HEADERS, timeout=20)
            resp.raise_for_status()
        except requests.RequestException as exc:
            print(f"[news] Bỏ qua {feed['name']}: {exc}")
            continue
        for entry in feedparser.parse(resp.content).entries:
            parsed = entry.get("published_parsed") or entry.get("updated_parsed")
            published = calendar.timegm(parsed) if parsed else time.time()
            if published < cutoff:
                continue
            title = clean(entry.get("title", ""))
            if not title:
                continue
            # Cùng một tin hay được đăng lại ở nhiều chuyên mục: khử trùng theo tiêu đề
            key = hashlib.sha1(title.lower().encode()).hexdigest()[:12]
            if key in items:
                continue
            items[key] = {
                "id": key,
                "title": title,
                "summary": clean(entry.get("summary", ""))[:400],
                "link": entry.get("link", ""),
                "source": feed["name"],
                "published": int(published),
            }
        print(f"[news] {feed['name']}: tổng {len(items)} tin")
    return sorted(items.values(), key=lambda n: n["published"], reverse=True)
