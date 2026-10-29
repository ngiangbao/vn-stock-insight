# VN Stock Insight

App phân tích cổ phiếu Việt Nam bằng AI cho **Windows, macOS, Linux và Android**. App tự lấy giá, chỉ báo kỹ thuật, số liệu tài chính và tin tức, rồi dùng AI do bạn chọn để phân tích chuyên sâu. AI có thể chạy qua API hoặc ngay trên máy bạn. Không cần tài khoản, không có máy chủ trung gian: mọi dữ liệu và API key nằm trên máy bạn.

> Công cụ tham khảo. App **không đặt lệnh**, và phân tích của AI **không phải khuyến nghị đầu tư**.

## Tính năng

- **Tổng quan:** dashboard thị trường với các chỉ số, biểu đồ, độ rộng thị trường và bản đồ nhiệt có thể xem theo biến động, giao dịch khối ngoại hoặc thanh khoản.
- **Theo dõi:** tra cứu mã bất kỳ (HOSE, HNX, UPCoM), thêm hoặc gỡ mã khỏi danh sách theo dõi, phân tích chuyên sâu từng mã:
  - luận điểm đầu tư và điều kiện làm luận điểm sai;
  - kết quả kinh doanh 8 quý; với ngân hàng thì xem NIM, nợ xấu, CASA;
  - định giá so với lịch sử, vị thế cạnh tranh;
  - kỹ thuật (MA, RSI, MACD, Bollinger, Stochastic, ATR, khối lượng);
  - lịch sự kiện sắp tới, 3 kịch bản, bảng chấm điểm 8 tiêu chí.
- **Bộ lọc:** bảng kỹ thuật VN30 sắp xếp được, có điểm kỹ thuật tổng hợp.
- **Tin tức:** tin 48 giờ từ CafeF, Vietstock, VnExpress, VnEconomy, Tin nhanh chứng khoán, gắn mã liên quan.
- **Giao diện sáng/tối** (hoặc theo hệ thống).
- **Kiểm tra cập nhật** từ GitHub Releases (tự động khi mở app, hoặc bấm trong Cài đặt).

Khung phân tích được chuyển thể từ các plugin **equity-research** và **financial-analysis** của Anthropic ([anthropics/financial-services](https://github.com/anthropics/financial-services), Apache-2.0). Xem [`lib/ai/prompts.dart`](lib/ai/prompts.dart).

## Nhà cung cấp AI

| Loại | Nhà cung cấp |
|---|---|
| Qua API | Claude (Anthropic), OpenAI, Google Gemini, OpenRouter, Groq, Mistral, DeepSeek, xAI Grok, Together AI |
| Chạy trên máy | LM Studio, Ollama |
| Tùy chỉnh | Mọi dịch vụ có API tương thích OpenAI (llama.cpp server, vLLM, Azure…) |

Cấu hình trong **Cài đặt → AI**: chọn nhà cung cấp, nhập API key (lưu trong kho bảo mật của hệ điều hành), rồi bấm **Tải danh sách** để chọn model.

### Model trên máy

**Cài đặt → Model trên máy** đánh giá cấu hình máy bạn (RAM, CPU, GPU/VRAM, Apple Silicon) và đề xuất model phù hợp. Mỗi model được gắn nhãn *Chạy tốt*, *Chạy được nhưng chậm*, hoặc *Không đủ bộ nhớ*.

- Nếu dùng Ollama, bạn tải model ngay trong app bằng một nút bấm, có thanh tiến độ.
- Nếu dùng LM Studio, app chép tên model để bạn tìm trong mục Discover.
- Danh sách đề xuất nằm ở [`assets/models.json`](assets/models.json). App đọc bản mới nhất từ GitHub, nên sửa file này là cập nhật được danh sách cho mọi người dùng.
- Trên Android, bạn trỏ địa chỉ tới Ollama/LM Studio đang chạy trên máy tính trong cùng mạng Wi-Fi, ví dụ `http://192.168.1.10:11434/v1`.

## Cài đặt

Tải bản mới nhất tại [Releases](https://github.com/ngiangbao/vn-stock-insight/releases):

- **Windows:** `…-windows-x64-setup.exe`, mở trình cài đặt và làm theo hướng dẫn (cài cho riêng người dùng, không cần quyền quản trị). Cũng có `…-windows-x64-portable.zip` để giải nén và chạy thẳng `vn_stock_insight.exe`. Xem thêm mục [Cảnh báo SmartScreen và diệt virus](#cảnh-báo-smartscreen-và-diệt-virus-trên-windows).
- **macOS:** `…-macos.pkg`, mở gói cài đặt để cài vào Applications. Gói chưa được ký/notarize bằng Apple Developer ID; macOS có thể yêu cầu xác nhận khi mở. File `…-macos.zip` dùng cho cập nhật tự động trong app.
- **Linux:** `…-linux-x64.tar.gz`, giải nén rồi chạy `./vn-stock-insight/install.sh`. Gỡ bằng `install.sh --uninstall`.
- **Android:** `….apk`, mở file để cài.

### Cập nhật tự động

Chỉ cần cài một lần. Khi có bản mới, app báo trong hộp thoại; bấm **Cập nhật ngay** để app tự tải, kiểm tra SHA-256 theo `SHA256SUMS.txt` của cùng bản phát hành, cài bản mới và mở lại (Windows chạy bộ cài ngầm, macOS và Linux thay đúng thư mục ứng dụng đang chạy). Dữ liệu và cài đặt của bạn được giữ nguyên. Nếu máy không cập nhật tự động được (ví dụ thư mục cài đặt không ghi được), hộp thoại vẫn có nút tải thủ công. Android cập nhật bằng cách tải file `.apk` mới.

### Cảnh báo SmartScreen và diệt virus trên Windows

App chưa được ký số (đang chuẩn bị xin chứng chỉ miễn phí của SignPath Foundation, xem [Chính sách ký số](#chính-sách-ký-số)), nên Windows SmartScreen hiện "Windows protected your PC" và một số phần mềm diệt virus có thể chặn file mới, ít người tải. Đây là cảnh báo về file chưa có uy tín, không phải kết quả phát hiện mã độc. Cách cài an toàn:

1. Tải file từ trang Releases của repo này và đối chiếu SHA-256 với `SHA256SUMS.txt` đính kèm (PowerShell: `Get-FileHash .\tên-file`).
2. Khi SmartScreen hiện cảnh báo: chọn **More info** rồi **Run anyway**. Với file đã tải: chuột phải file, **Properties**, tick **Unblock**, **OK** rồi mở lại.
3. Nếu phần mềm diệt virus chặn, thêm thư mục `%LOCALAPPDATA%\Programs\VN Stock Insight` (hoặc thư mục giải nén bản portable) vào danh sách loại trừ, hoặc gửi file cho nhà cung cấp để báo nhận diện nhầm. Windows Defender: <https://www.microsoft.com/wdsi/filesubmission>.

Mã nguồn đầy đủ nằm trong repo, bạn có thể tự build bằng `flutter build windows --release`.

## Chính sách ký số

Các bản phát hành Windows được ký số: *Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).* Trạng thái: đang chuẩn bị hồ sơ; đến khi được cấp chứng chỉ, các file Windows trên Releases có thể chưa được ký (xem [docs/CODE_SIGNING.md](docs/CODE_SIGNING.md)).

- Vai trò: người viết mã và duyệt thay đổi (committer, reviewer) và người duyệt ký (approver) hiện là chủ dự án, [@ngiangbao](https://github.com/ngiangbao).
- Chỉ ký file do GitHub Actions của repo này build từ mã nguồn công khai ở đây; không ký file của bên thứ ba.
- Tài khoản có quyền phát hành bật xác thực hai lớp.

## Quyền riêng tư

App chỉ kết nối mạng để thực hiện chức năng bạn dùng: lấy giá và dữ liệu thị trường (DNSE, VNDirect, Vietcap, Yahoo, World Bank, IMF, TradingEconomics qua TradingView, CafeF), tin tức qua RSS, kiểm tra và tải bản cập nhật từ GitHub, và gửi dữ liệu phân tích tới nhà cung cấp AI do bạn chọn (hoặc model chạy trên máy bạn, không gửi đi đâu). Khóa API, danh mục đầu tư và kết quả phân tích lưu trên máy bạn; app không có tài khoản, không thu thập dữ liệu sử dụng và không gửi thông tin cá nhân cho tác giả.

## Phát triển

```bash
flutter pub get
flutter run -d linux        # hoặc windows, macos, hoặc thiết bị Android
flutter test
```

Phát hành bản mới:

1. Tăng `version` trong `pubspec.yaml`.
2. Tạo tag trùng tên, ví dụ `git tag v1.0.1 && git push origin v1.0.1`.
3. GitHub Actions sẽ build cả 4 nền tảng và tạo Release. App đang chạy sẽ thấy bản mới khi kiểm tra cập nhật.

Muốn APK được ký ổn định (để cài bản mới đè lên bản cũ), thêm các secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## Nguồn dữ liệu

Giá: DNSE (dự phòng VNDirect). Số liệu tài chính: Vietcap IQ. Tin tức: RSS của các báo nói trên. Đây là các API công khai không chính thức, có thể thay đổi bất cứ lúc nào. App chỉ phục vụ mục đích cá nhân.

Bản web cũ (GitHub Pages + Supabase) được lưu ở tag [`web-v1`](https://github.com/ngiangbao/vn-stock-insight/tree/web-v1).
