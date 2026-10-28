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
  └─ pipeline/storage.py Tải kết quả lên Supabase Storage (bucket riêng tư), kèm bản lưu theo ngày
        │
        └─ GitHub Pages: site/index.html
             Đăng nhập bằng link qua email (chỉ người được mời) → đọc dữ liệu từ Supabase
             Tổng quan · Theo dõi · Bộ lọc · Tin tức
```

Mã nguồn công khai, nhưng **dữ liệu phân tích chỉ nằm trong Supabase** và chỉ thành viên được mời mới đọc được.

## Cài đặt lần đầu

### 1. Supabase (đăng nhập và lưu dữ liệu, gói miễn phí là đủ)

1. Tạo tài khoản và một project mới tại [supabase.com](https://supabase.com).
2. **SQL Editor** → dán nội dung file [`supabase/setup.sql`](supabase/setup.sql) → Run.
3. **Authentication → Sign In / Providers**: **tắt** "Allow new users to sign up". Bước này bắt buộc: nó đảm bảo chỉ người được mời mới có tài khoản.
4. **Authentication → URL Configuration**: đặt *Site URL* là `https://<tên-github>.github.io/vn-stock-insight/`.
5. **Project Settings → API**: ghi lại *Project URL*, khóa *anon / publishable* và khóa *service_role / secret*.

### 2. GitHub (Settings → Secrets and variables → Actions)

| Loại | Tên | Giá trị |
|---|---|---|
| Variable | `SUPABASE_URL` | Project URL |
| Variable | `SUPABASE_ANON_KEY` | Khóa anon / publishable (khóa này công khai được) |
| Secret | `SUPABASE_SERVICE_KEY` | Khóa service_role / secret (**tuyệt đối không công khai**) |
| Secret | `ANTHROPIC_API_KEY` | API key lấy tại [platform.claude.com](https://platform.claude.com) |

### 3. Chạy lần đầu

Tab Actions → "Cập nhật dữ liệu" → Run workflow. Sau đó mở `https://<tên-github>.github.io/vn-stock-insight/`.

Nếu chưa có `ANTHROPIC_API_KEY`, hệ thống vẫn chạy và hiển thị giá, chỉ báo kỹ thuật, tin tức (chưa có phần AI).

## Mời thành viên

Supabase → **Authentication → Users → Invite user** → nhập email. Người được mời nhận email, bấm link là vào được trang. Những lần sau, họ nhập email ở trang đăng nhập để nhận link mới.

Muốn thu hồi quyền: xóa người đó trong danh sách Users. Gói miễn phí của Supabase giới hạn số email gửi mỗi giờ, đủ cho một nhóm nhỏ. Nếu cần gửi nhiều hơn, cấu hình SMTP riêng trong Authentication → Emails.

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

Rồi mở http://localhost:8000. Khi chạy trên máy, `site/config.js` để trống nên trang đọc thẳng thư mục `site/data/` và không yêu cầu đăng nhập. Thư mục này không được đưa lên GitHub.
