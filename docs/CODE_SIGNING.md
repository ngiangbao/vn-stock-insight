# Ký số cho bản Windows (SignPath Foundation)

Tài liệu này là hướng dẫn cho chủ dự án để bật ký số Windows miễn phí bằng [SignPath Foundation](https://signpath.org/). Quy trình build đã sẵn sàng (xem job `windows` trong `.github/workflows/release.yml`); các bước ký chỉ chạy khi repo có secret `SIGNPATH_API_TOKEN`, nên chưa bật thì build vẫn chạy như cũ.

## 1. Điều kiện của SignPath Foundation (đã chuẩn bị trong repo)

- Mã nguồn mở với giấy phép OSI: đã thêm `LICENSE` (MIT). Đổi sang giấy phép khác tùy bạn trước khi nộp đơn.
- Repo công khai, có bản phát hành, đang được duy trì: đáp ứng.
- Trang dự án có mục **Chính sách ký số** và **Chính sách quyền riêng tư**: đã thêm vào `README.md`.
- Chỉ ký file do chính dự án build, từ GitHub Actions (nguồn build được xác minh): đáp ứng, các bước ký dùng `signpath/github-action-submit-signing-request`.
- Mọi người có quyền ghi/duyệt bản phát hành nên bật xác thực hai lớp (MFA) trên GitHub và SignPath.

## 2. Việc bạn cần làm (cần tài khoản của bạn)

1. Nộp đơn tại <https://signpath.org/apply>. Điền tên dự án `VN Stock Insight`, địa chỉ repo `https://github.com/ngiangbao/vn-stock-insight`, giấy phép, mô tả ngắn, và liên kết tới mục "Chính sách ký số" trong README. Thời gian duyệt thường từ vài ngày đến vài tuần.
2. Sau khi được duyệt, đăng nhập SignPath và tạo trong dự án:
   - Project slug: `vn-stock-insight`
   - Signing policy slug: `release-signing` (chính sách ký bản phát hành; nên bật bước bạn tự duyệt thủ công cho mỗi lần ký)
   - Hai artifact configuration, dán nội dung từ thư mục `docs/signpath/`:
     - slug `app-exe`: `artifact-config-app-exe.xml`
     - slug `installer`: `artifact-config-installer.xml`
   - Thêm GitHub làm trusted build system và liên kết với repo này (theo hướng dẫn của SignPath: <https://docs.signpath.io/trusted-build-systems/github>).
   - Tạo API token cho người dùng CI.
3. Trong GitHub, repo **Settings → Secrets and variables → Actions**:
   - Secret `SIGNPATH_API_TOKEN`: API token ở trên.
   - Variable `SIGNPATH_ORGANIZATION_ID`: ID tổ chức SignPath của bạn.
4. Tạo tag phát hành như bình thường. Workflow sẽ ký `vn_stock_insight.exe` trước khi đóng gói, rồi ký tiếp bộ cài `-setup.exe`. Mỗi lần ký có thể chờ bạn duyệt trên SignPath nếu chính sách yêu cầu.

Cấu hình XML ở `docs/signpath/` theo cú pháp artifact configuration của SignPath; nếu giao diện SignPath báo lỗi cú pháp, đối chiếu với <https://docs.signpath.io/artifact-configuration/syntax>.

## 3. Lưu ý

- Chứng chỉ do SignPath Foundation cấp nên nhà phát hành hiển thị là "SignPath Foundation". Chữ ký giúp giảm cảnh báo SmartScreen và Defender nhưng uy tín vẫn cần thời gian tích lũy theo lượt tải.
- Chỉ bản Windows được ký theo cách này. macOS cần Apple Developer ID (99 USD/năm) và công chứng (notarize), tài liệu riêng.
- Cập nhật tự động trong app kiểm tra SHA-256 từ `SHA256SUMS.txt`; đó là kiểm tra toàn vẹn, không thay cho chữ ký số.
