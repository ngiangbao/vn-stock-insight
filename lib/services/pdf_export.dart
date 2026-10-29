// Xuất báo cáo phân tích thành file PDF: chụp phần báo cáo đang hiển thị rồi cắt thành các trang A4.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Chọn các vị trí cắt trang cho ảnh cao [total] px, mỗi trang tối đa [pageH] px. [atomic] là các khoảng (top, bottom) không
/// được cắt ngang (dòng chữ, biểu đồ): vị trí cắt dời lên đầu khoảng đó. Nếu phải dời quá 65% trang thì cắt cứng tại [pageH].
/// Trả về điểm bắt đầu của từng trang, kèm điểm kết thúc [total].
List<int> planCuts(int total, int pageH, List<(double, double)> atomic) {
  final cuts = <int>[0];
  var y0 = 0;
  while (total - y0 > pageH) {
    var c = (y0 + pageH).toDouble();
    for (var i = 0; i < 64; i++) {
      final hit = atomic.where((a) => a.$1 < c - 0.5 && a.$2 > c + 0.5).toList();
      if (hit.isEmpty) break;
      c = hit.map((a) => a.$1).reduce((a, b) => a < b ? a : b);
    }
    if (c <= y0 + pageH * 0.35) c = (y0 + pageH).toDouble();
    y0 = c.floor();
    cuts.add(y0);
  }
  cuts.add(total);
  return cuts;
}

/// Cắt ảnh dài [image] thành các trang A4 (chừa lề) và ghép thành PDF. [atomic] tính theo px của ảnh (xem [planCuts]).
Future<Uint8List> pdfFromImage(ui.Image image, {String? title, String? author, List<(double, double)> atomic = const []}) async {
  const margin = 24.0;
  final format = PdfPageFormat.a4;
  final contentW = format.width - 2 * margin, contentH = format.height - 2 * margin;
  final sliceH = (image.width * contentH / contentW).floor();
  final doc = pw.Document(title: title, author: author, creator: 'VN Stock Insight');
  final cuts = planCuts(image.height, sliceH, atomic);
  for (var k = 0; k + 1 < cuts.length; k++) {
    final top = cuts[k];
    final h = cuts[k + 1] - top;
    if (h <= 0) continue;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, top.toDouble(), image.width.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final piece = await recorder.endRecording().toImage(image.width, h);
    final png = (await piece.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final img = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Align(
          alignment: pw.Alignment.topCenter,
          child: pw.Image(img, width: contentW, height: contentW * h / image.width, fit: pw.BoxFit.fill),
        ),
      ),
    );
  }
  return doc.save();
}

/// Thư mục lưu file: Tải xuống nếu có, không thì thư mục tài liệu của app.
Future<Directory> exportDirectory() async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  return dir ?? await getApplicationDocumentsDirectory();
}

Future<File> savePdf(Uint8List bytes, String fileName, {Directory? dir}) async {
  final d = dir ?? await exportDirectory();
  await d.create(recursive: true);
  return File('${d.path}${Platform.pathSeparator}$fileName').writeAsBytes(bytes, flush: true);
}
