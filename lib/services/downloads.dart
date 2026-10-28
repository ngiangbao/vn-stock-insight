// Tải file lớn có báo tiến độ, tiếp tục được khi bị ngắt (Range), hủy được, kiểm tra SHA-256.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class CancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Đã hủy tải';
}

/// Tải [url] về [dest]. Phần đang tải lưu ở `dest.part`, lần sau tải tiếp từ chỗ dừng.
/// [onProgress] nhận (số byte đã có, tổng số byte nếu biết).
Future<File> downloadFile(
  String url,
  File dest, {
  void Function(int received, int? total)? onProgress,
  CancelToken? cancel,
  String? sha256Hex,
}) async {
  await dest.parent.create(recursive: true);
  final part = File('${dest.path}.part');
  var start = await part.exists() ? await part.length() : 0;

  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'vn-stock-insight'
      ..followRedirects = true;
    if (start > 0) req.headers['Range'] = 'bytes=$start-';
    final resp = await client.send(req);
    if (resp.statusCode == 200) {
      start = 0; // máy chủ không hỗ trợ tải tiếp: tải lại từ đầu
    } else if (resp.statusCode != 206) {
      throw HttpException('Máy chủ trả về HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    final total = resp.contentLength == null ? null : resp.contentLength! + start;
    final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
    var received = start;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in resp.stream) {
        if (cancel?.cancelled ?? false) throw DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 200) {
          lastReport = now;
          onProgress?.call(received, total);
        }
      }
    } finally {
      await sink.close();
    }
    onProgress?.call(received, total);
  } finally {
    client.close();
  }

  if (sha256Hex != null) {
    final digest = await sha256.bind(part.openRead()).first;
    if (digest.toString() != sha256Hex.toLowerCase()) {
      await part.delete();
      throw Exception('File tải về bị lỗi (sai mã SHA-256). Hãy thử tải lại.');
    }
  }
  if (await dest.exists()) await dest.delete();
  return part.rename(dest.path);
}

String formatBytes(num bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1e3).toStringAsFixed(0)} KB';
}
