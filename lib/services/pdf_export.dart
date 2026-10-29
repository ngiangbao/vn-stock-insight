// Xuất báo cáo phân tích thành file PDF: chụp phần báo cáo đang hiển thị rồi cắt thành các trang A4.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Cắt ảnh dài [image] thành các lát có tỉ lệ vừa trang A4 (chừa lề) và ghép thành PDF.
Future<Uint8List> pdfFromImage(ui.Image image, {String? title, String? author}) async {
  const margin = 24.0;
  final format = PdfPageFormat.a4;
  final contentW = format.width - 2 * margin, contentH = format.height - 2 * margin;
  final sliceH = (image.width * contentH / contentW).floor();
  final doc = pw.Document(title: title, author: author, creator: 'VN Stock Insight');
  for (var top = 0; top < image.height; top += sliceH) {
    final h = top + sliceH > image.height ? image.height - top : sliceH;
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
