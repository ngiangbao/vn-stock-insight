// Soạn issue / pull request gửi lên GitHub của dự án. App không giữ khóa GitHub nào: nội dung được điền sẵn vào trang tạo issue của GitHub,
// người dùng xem lại và bấm gửi bằng chính tài khoản GitHub của mình (nội dung nằm công khai, nên app nhắc không đưa thông tin cá nhân).

const feedbackRepo = 'ngiangbao/vn-stock-insight';

enum FeedbackKind {
  bug('Báo lỗi', '[Lỗi]', 'bug'),
  idea('Góp ý tính năng', '[Góp ý]', 'enhancement'),
  pr('Đề xuất sửa mã (pull request)', '[Đề xuất]', 'pull-request');

  final String label, prefix, ghLabel;
  const FeedbackKind(this.label, this.prefix, this.ghLabel);
}

/// GitHub giới hạn độ dài URL khoảng 8 000 ký tự, nên phần mô tả được cắt về mức an toàn.
const maxBodyChars = 4500;

String feedbackBody(FeedbackKind kind, String detail, {String steps = '', required String version, required String platform}) {
  final b = StringBuffer()
    ..writeln(kind == FeedbackKind.bug ? '### Mô tả lỗi' : '### Nội dung')
    ..writeln(detail.trim().isEmpty ? '(chưa mô tả)' : detail.trim())
    ..writeln();
  if (kind == FeedbackKind.bug && steps.trim().isNotEmpty) {
    b
      ..writeln('### Các bước tái hiện')
      ..writeln(steps.trim())
      ..writeln();
  }
  b
    ..writeln('### Môi trường')
    ..writeln('- Phiên bản app: $version')
    ..writeln('- Hệ điều hành: $platform')
    ..writeln()
    ..writeln('_Gửi từ mục Đóng góp ý kiến trong app._');
  final s = b.toString();
  return s.length <= maxBodyChars ? s : '${s.substring(0, maxBodyChars)}\n\n_(đã cắt bớt cho vừa độ dài cho phép)_';
}

/// Trang tạo issue của GitHub đã điền sẵn tiêu đề và nội dung. Với [FeedbackKind.pr] là trang so sánh nhánh để mở pull request.
Uri feedbackUri(FeedbackKind kind, String title, String body) {
  if (kind == FeedbackKind.pr) return Uri.https('github.com', '/$feedbackRepo/compare');
  final t = title.trim().isEmpty ? '(chưa có tiêu đề)' : title.trim();
  return Uri.https('github.com', '/$feedbackRepo/issues/new', {'title': '${kind.prefix} $t', 'body': body, 'labels': kind.ghLabel});
}
