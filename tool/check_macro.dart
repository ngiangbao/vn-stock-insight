// ignore_for_file: avoid_print
// Kiểm tra lớp dữ liệu vĩ mô với mạng thật: dart run tool/check_macro.dart
import 'dart:io';

import 'package:vn_stock_insight/services/macro.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('macro-real');
  final repo = MacroRepository(cacheFile: File('${dir.path}/cache.json'));
  final watch = Stopwatch()..start();
  final snap = await repo.load(force: true);
  print('Tải xong sau ${watch.elapsed.inSeconds}s: ${snap.series.length}/${macroDefs.length} chỉ tiêu, lỗi: ${snap.failed.isEmpty ? 'không' : snap.failed}');
  for (final d in macroDefs) {
    final s = snap.series[d.id];
    if (s == null) continue;
    final l = s.latest!;
    final f = s.points.where((p) => p.forecast).toList();
    print('${d.id.padRight(16)} ${s.points.length.toString().padLeft(3)} điểm ${s.points.first.period}→${s.points.last.period} | mới nhất ${l.label}: ${l.value.toStringAsFixed(d.decimals)} ${d.unit}${f.isEmpty ? '' : ' | dự báo ${f.first.period}–${f.last.period}'}');
  }
  final again = await repo.load();
  print('Lần 2 (đọc bản lưu đệm): fromCache=${again.fromCache}, ${again.series.length} chỉ tiêu');
  await dir.delete(recursive: true);
}
