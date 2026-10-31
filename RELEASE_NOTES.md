## VN Stock Insight v2.11.0

- **Hỗ trợ Claude CLI:** trong Cài đặt → AI chọn “Claude CLI” để dùng tài khoản Claude (Pro/Max) qua lệnh `claude`, không cần API key. Phân tích mã, bản tin thị trường, chat và CFA đều dùng được.
- **Chọn model của Claude CLI:** mặc định của CLI, Fable, Opus, Sonnet, Haiku hoặc nhập tên model đầy đủ; có chọn mức suy luận và nút thử model.
- **Cài Claude CLI từ app nếu chưa có:** hộp xác nhận hiện lệnh tương đương, tải script chính thức từ claude.ai (từ chối nếu bị chuyển hướng sang tên miền khác), hiển thị nhật ký cài đặt; có cách cài bằng npm và nút đăng nhập tài khoản Claude.
- Claude CLI chạy ở thư mục tạm, tắt mọi công cụ, không nạp cấu hình hay dự án nào. Chỉ có trên Windows, macOS, Linux. Các đường cài trên Windows/macOS chưa được thử trên máy thật.
- README có thêm ảnh chụp màn hình.

### Cài đặt

- Linux: giải nén `-linux-x64.tar.gz`, chạy `./vn-stock-insight/install.sh`.
- Windows: bộ cài `-setup.exe` hoặc bản `-portable.zip`.
- macOS: gói `.pkg` hoặc `.zip` cho cập nhật trong app.
- Android: cài `.apk`.
- Mã kiểm tra: `SHA256SUMS.txt`.
