## VN Stock Insight v2.10.0

- Thêm Trái phiếu: đường cong lợi suất Chính phủ, công cụ định giá theo giả định và tra cứu HNX.
- Thêm Chứng chỉ quỹ: giá/biểu đồ ETF và sổ NAV quỹ mở nhập thủ công, lưu trên máy.
- Thêm Phái sinh: các chuỗi kỳ hạn VN30, biểu đồ và basis khi cùng ngày dữ liệu.
- Gom Vĩ mô, Tin tức, Cài đặt vào menu Thêm mở bằng hover, nhấp hoặc bàn phím; điện thoại dùng chạm.
- Thêm nút chat AI chỉ có icon, kéo tự do và tự bám cạnh trái/phải gần nhất.
- Giới hạn chat trong tài chính/chứng khoán; kiểm tra đầu vào và đầu ra, từ chối khi không kiểm tra được. Chat không có công cụ hay chức năng đặt lệnh. Bảo vệ prompt injection là giảm thiểu nhiều lớp, không bảo đảm tuyệt đối.

### Phạm vi dữ liệu

NAV quỹ mở nhập thủ công; chưa tích hợp bảng giá trái phiếu doanh nghiệp. Danh sách quỹ có mã mẫu dự phòng, không bảo đảm bao phủ toàn thị trường. Chat chưa có nguồn giá trực tiếp và chỉ giữ lịch sử trong phiên. Mỗi câu hỏi hợp lệ dùng tối đa ba lượt AI để kiểm tra và trả lời.

### Cài đặt

- Linux: giải nén `-linux-x64.tar.gz`, chạy `./vn-stock-insight/install.sh`.
- Windows: bộ cài `-setup.exe` hoặc giải nén bản `-portable.zip`.
- macOS: mở gói `.pkg`, hoặc dùng `.zip` cho cập nhật trong app.
- Android: tải và cài `.apk`.
- Kiểm tra tính toàn vẹn bằng `SHA256SUMS.txt`.
