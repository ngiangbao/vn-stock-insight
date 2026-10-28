# VN Stock Insight

Trợ lý phân tích cổ phiếu Việt Nam bằng AI. Hệ thống tự gom tin tức, tính chỉ báo kỹ thuật, dùng Claude để tóm tắt tin và phân tích từng mã, rồi đăng kết quả lên một trang web tĩnh (GitHub Pages) mà bạn mở được ở bất cứ đâu.

> Đây là công cụ tham khảo. Hệ thống **không đặt lệnh** và phân tích của AI **không phải khuyến nghị đầu tư**.

## Cách hoạt động

```
GitHub Actions (8:30, 12:00, 15:15 các ngày giao dịch)
  │
  ├─ pipeline/market.py  Giá ngày từ DNSE (dự phòng VNDirect) → MA, RSI, MACD, khối lượng, đỉnh/đáy 52 tuần
  ├─ pipeline/news.py    Tin RSS 48 giờ gần nhất từ CafeF, Vietstock, VnExpress, VnEconomy, Tin nhanh CK
  ├─ pipeline/ai.py      Claude Haiku 5.5: phân loại tin, gắn mã, chấm cảm xúc và mức độ quan trọng
  │                      Claude Opus 5.5: phân tích chi tiết từng mã theo dõi và nhận định thị trường
  └─ site/data/*.json    Kết quả, kèm bản lưu theo ngày để xem lại
        │
        └─ GitHub Pages: site/index.html (Tổng quan · Theo dõi · Bộ lọc · Tin tức)
```

## Cài đặt lần đầu

1. **Lấy API key Claude** tại [platform.claude.com](https://platform.claude.com) (mục API Keys) và nạp một ít credit.
2. **Thêm key vào repo**: Settings → Secrets and variables → Actions → New repository secret, đặt tên `ANTHROPIC_API_KEY`.
3. **Chạy lần đầu**: tab Actions → "Cập nhật dữ liệu" → Run workflow.
4. Mở trang web tại `https://<tên-github>.github.io/vn-stock-insight/`.

Nếu chưa có API key, hệ thống vẫn chạy và hiển thị giá, chỉ báo kỹ thuật, tin tức (chưa có phần AI).

## Tùy chỉnh

Sửa [`config.yml`](config.yml):

- `watchlist`: các mã được AI phân tích chi tiết.
- `universe`: rổ cổ phiếu cho bộ lọc kỹ thuật (mặc định VN30).
- `news_feeds`: nguồn tin RSS.
- `ai`: model và mức độ suy nghĩ (`analysis_effort`).

Lịch chạy nằm trong [`.github/workflows/update.yml`](.github/workflows/update.yml) (giờ UTC = giờ Việt Nam − 7).

## Chi phí ước tính

Với 6 mã theo dõi, khoảng 250 tin mỗi lần, chạy 3 lần mỗi ngày giao dịch:

- Haiku phân loại tin: rất nhỏ, vài cent mỗi tháng.
- Opus phân tích 6 mã và nhận định thị trường: là phần chính, khoảng vài USD mỗi tháng tùy độ dài phân tích.

Bạn theo dõi chi phí thực tế ở trang Usage của Claude Console. Muốn giảm, bạn có thể bớt mã trong `watchlist`, hạ `analysis_effort` xuống `medium`, hoặc bớt lịch chạy.

## Chạy trên máy

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export ANTHROPIC_API_KEY=...   # bỏ qua nếu chỉ muốn chạy phần không có AI
python -m pipeline.main        # hoặc: python -m pipeline.main --no-ai
python -m http.server 8000 --directory site
```

Rồi mở http://localhost:8000.
