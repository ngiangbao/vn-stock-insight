// Chụp một vùng đã dựng (RepaintBoundary) thành PDF nhiều trang A4 và lưu vào thư mục Tải xuống.

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../services/pdf_export.dart';

/// Chụp [key] (đã dựng xong) và lưu thành [fileName]. Ném chuỗi lỗi tiếng Việt nếu chưa dựng xong.
Future<File> capturePdf(GlobalKey key, {required String title, required String fileName}) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw 'Chưa dựng xong báo cáo, hãy thử lại.';
  const ratio = 2.0;
  final image = await boundary.toImage(pixelRatio: ratio);
  final bytes = await pdfFromImage(image, title: title, author: 'VN Stock Insight', atomic: unbreakableRanges(boundary, ratio));
  return savePdf(bytes, fileName);
}

/// Các khoảng dọc (px của ảnh chụp) không nên bị cắt ngang khi chia trang: từng dòng chữ và từng biểu đồ vẽ tay.
List<(double, double)> unbreakableRanges(RenderRepaintBoundary boundary, double ratio) {
  final out = <(double, double)>[];
  // Không đệm thêm: các dòng liền kề chạm nhau, đệm sẽ làm chúng chồng lên nhau và không còn chỗ cắt giữa hai dòng
  void add(double top, double bottom) => out.add((top * ratio, bottom * ratio));
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.hasSize) {
      final origin = o.localToGlobal(Offset.zero, ancestor: boundary);
      final len = o.text.toPlainText().length;
      final boxes = len == 0 ? const <TextBox>[] : o.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
      if (boxes.isEmpty) {
        add(origin.dy, origin.dy + o.size.height);
      } else {
        for (final b in boxes) {
          add(origin.dy + b.top, origin.dy + b.bottom);
        }
      }
    } else if (o is RenderCustomPaint && o.hasSize && o.painter != null && o.size.height > 4) {
      final origin = o.localToGlobal(Offset.zero, ancestor: boundary);
      add(origin.dy, origin.dy + o.size.height);
    }
    o.visitChildren(visit);
  }

  boundary.visitChildren(visit);
  return out;
}

/// Chờ hai khung hình để vùng được dựng lại (ví dụ sau khi đổi sang giao diện sáng để in).
Future<void> settleFrames() async {
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
}
