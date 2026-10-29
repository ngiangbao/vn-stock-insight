// Cập nhật tự động trong app: tải bản mới từ GitHub Releases, kiểm tra SHA-256, thay bản đang chạy rồi mở lại.
//  - Windows: chạy bộ cài Inno Setup ở chế độ ngầm (cài theo người dùng, không cần quyền admin).
//  - macOS: tải file .app nén, thay đúng bản .app đang chạy (cần thư mục chứa app ghi được), mở lại.
//  - Linux: tải .tar.gz, chép đè vào thư mục cài đặt đang chạy, mở lại.
// File do chính app tải về không mang dấu "tải từ Internet", nên SmartScreen và Gatekeeper không chặn lần chạy này.
// Toàn vẹn: bắt buộc khớp SHA-256 trong SHA256SUMS.txt của cùng bản phát hành. Đây là kiểm tra toàn vẹn, không thay cho chữ ký số.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'updater.dart';

enum UpdateStage { downloading, verifying, installing }

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Tham số chạy bộ cài Inno Setup ngầm: không hộp thoại, không khởi động lại máy, tự đóng app đang chạy.
const windowsInstallerArgs = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'];

/// Đọc SHA256SUMS.txt (định dạng `sha256sum`: mã SHA-256, hai dấu cách, tên file) thành tên file → mã (chữ thường).
Map<String, String> parseChecksums(String body) {
  final out = <String, String>{};
  for (final line in const LineSplitter().convert(body)) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line);
    if (m != null) out[m.group(2)!.split('/').last] = m.group(1)!.toLowerCase();
  }
  return out;
}

Future<String> sha256Of(File f) async => (await sha256.bind(f.openRead()).first).toString();

/// Tải [url] về [dest], báo tiến độ 0..1 (null nếu máy chủ không cho biết dung lượng).
Future<File> downloadTo(Uri url, File dest, {void Function(double? progress)? onProgress, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final resp = await c.send(http.Request('GET', url)..followRedirects = true).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw UpdateException('Máy chủ trả về HTTP ${resp.statusCode} khi tải bản cập nhật.');
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    var got = 0;
    final total = resp.contentLength;
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(total == null || total <= 0 ? null : got / total);
      }
    } finally {
      await sink.close();
    }
    return dest;
  } finally {
    if (client == null) c.close();
  }
}

/// Tải SHA256SUMS.txt và trả về mã của file tên [fileName]; ném lỗi nếu thiếu (không cài file không kiểm tra được).
Future<String> expectedChecksum(String? checksumsUrl, String fileName, {http.Client? client}) async {
  if (checksumsUrl == null) throw UpdateException('Bản phát hành không có SHA256SUMS.txt nên không thể kiểm tra toàn vẹn.');
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(checksumsUrl)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw UpdateException('Không tải được SHA256SUMS.txt (HTTP ${r.statusCode}).');
    final sum = parseChecksums(utf8.decode(r.bodyBytes))[fileName];
    if (sum == null) throw UpdateException('SHA256SUMS.txt không có mã cho $fileName.');
    return sum;
  } finally {
    if (client == null) c.close();
  }
}

/// Chuỗi shell thoát an toàn trong dấu nháy đơn.
String shQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// Script macOS: đợi app thoát, thay bản .app (có sao lưu và khôi phục nếu lỗi), bỏ cờ cách ly, mở lại.
String macosUpdateScript({required int pid, required String newApp, required String targetApp}) =>
    '''#!/bin/sh
PID=$pid
NEW=${shQuote(newApp)}
TARGET=${shQuote(targetApp)}
OLD="\$TARGET.old-update"
while kill -0 "\$PID" 2>/dev/null; do sleep 0.5; done
rm -rf "\$OLD"
if mv "\$TARGET" "\$OLD" && ditto "\$NEW" "\$TARGET"; then
  xattr -cr "\$TARGET" 2>/dev/null
  rm -rf "\$OLD" "\$NEW"
else
  rm -rf "\$TARGET"
  [ -e "\$OLD" ] && mv "\$OLD" "\$TARGET"
fi
open "\$TARGET"
''';

/// Script Linux: đợi app thoát, chép đè bản mới vào thư mục cài đặt, mở lại.
String linuxUpdateScript({required int pid, required String newDir, required String targetDir, required String exe}) =>
    '''#!/bin/sh
PID=$pid
NEW=${shQuote(newDir)}
TARGET=${shQuote(targetDir)}
EXE=${shQuote(exe)}
while kill -0 "\$PID" 2>/dev/null; do sleep 0.5; done
cp -a "\$NEW"/. "\$TARGET"/
rm -rf "\$NEW"
nohup setsid "\$EXE" >/dev/null 2>&1 &
''';

/// Thư mục [dir] có ghi được không (thử tạo rồi xóa một file).
bool writable(Directory dir) {
  try {
    final f = File('${dir.path}${Platform.pathSeparator}.vnsi-write-test-$pid');
    f.writeAsStringSync('x');
    f.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Đường dẫn gói .app đang chạy trên macOS (…/X.app/Contents/MacOS/exe), null nếu không phải gói .app.
String? runningAppBundle([String? exe]) {
  final parts = (exe ?? Platform.resolvedExecutable).split('/');
  final i = parts.lastIndexWhere((p) => p.endsWith('.app'));
  return i < 0 ? null : parts.sublist(0, i + 1).join('/');
}

/// Cập nhật tự động dùng được trên máy này cho bản [info] không?
bool canSelfUpdate(UpdateInfo info) {
  if (info.autoUrl == null) return false;
  if (Platform.isWindows) return true;
  if (Platform.isMacOS) {
    final app = runningAppBundle();
    return app != null && writable(Directory(File(app).parent.path));
  }
  if (Platform.isLinux) return writable(File(Platform.resolvedExecutable).parent);
  return false;
}

typedef Progress = void Function(UpdateStage stage, double? fraction);

/// Chạy script/bộ cài tách khỏi tiến trình app (không chết theo app).
typedef Launcher = Future<void> Function(String executable, List<String> args);

Future<void> _launchDetached(String executable, List<String> args) async {
  await Process.start(executable, args, mode: ProcessStartMode.detachedWithStdio);
}

/// Tải, kiểm tra, rồi cài và mở lại app. Gọi [exitApp] sau khi đã giao việc cho bộ cài/script; ném [UpdateException] nếu lỗi
/// (trước khi thay bất cứ thứ gì, nên app hiện tại vẫn nguyên vẹn).
Future<void> applyUpdate(
  UpdateInfo info, {
  required Future<void> Function() exitApp,
  Progress? onProgress,
  Directory? workDir,
  http.Client? client,
  Launcher launcher = _launchDetached,
  int? currentPid,
}) async {
  final url = info.autoUrl;
  if (url == null) throw UpdateException('Bản này không hỗ trợ cập nhật tự động trên hệ điều hành của bạn.');
  final fileName = Uri.parse(url).pathSegments.last;
  final work = workDir ?? await Directory.systemTemp.createTemp('vnsi-update');
  final file = File('${work.path}${Platform.pathSeparator}$fileName');

  onProgress?.call(UpdateStage.downloading, null);
  final expected = await expectedChecksum(info.checksumsUrl, fileName, client: client);
  await downloadTo(Uri.parse(url), file, client: client, onProgress: (p) => onProgress?.call(UpdateStage.downloading, p));

  onProgress?.call(UpdateStage.verifying, null);
  final actual = await sha256Of(file);
  if (actual != expected) {
    await file.delete().catchError((_) => file);
    throw UpdateException('Mã SHA-256 của file tải về không khớp, đã hủy cập nhật để an toàn.');
  }

  onProgress?.call(UpdateStage.installing, null);
  final me = currentPid ?? pid;
  if (Platform.isWindows) {
    await launcher(file.path, windowsInstallerArgs);
  } else if (Platform.isMacOS) {
    final target = runningAppBundle();
    if (target == null) throw UpdateException('Không xác định được vị trí ứng dụng đang chạy.');
    final out = Directory('${work.path}${Platform.pathSeparator}app')..createSync();
    final r = await Process.run('ditto', ['-x', '-k', file.path, out.path]);
    if (r.exitCode != 0) throw UpdateException('Không giải nén được bản cập nhật: ${r.stderr}');
    final app = out.listSync().whereType<Directory>().where((d) => d.path.endsWith('.app')).firstOrNull;
    if (app == null) throw UpdateException('File cập nhật không chứa ứng dụng .app.');
    final script = File('${work.path}${Platform.pathSeparator}update.sh')
      ..writeAsStringSync(macosUpdateScript(pid: me, newApp: app.path, targetApp: target));
    await launcher('/bin/sh', [script.path]);
  } else if (Platform.isLinux) {
    final out = Directory('${work.path}${Platform.pathSeparator}app')..createSync();
    final r = await Process.run('tar', ['-xzf', file.path, '-C', out.path]);
    if (r.exitCode != 0) throw UpdateException('Không giải nén được bản cập nhật: ${r.stderr}');
    final top = out.listSync().whereType<Directory>().firstOrNull;
    if (top == null) throw UpdateException('File cập nhật không có thư mục ứng dụng.');
    final exe = Platform.resolvedExecutable;
    final script = File('${work.path}${Platform.pathSeparator}update.sh')
      ..writeAsStringSync(linuxUpdateScript(pid: me, newDir: top.path, targetDir: File(exe).parent.path, exe: exe));
    await launcher('/bin/sh', [script.path]);
  } else {
    throw UpdateException('Hệ điều hành này chưa hỗ trợ cập nhật tự động.');
  }
  await exitApp();
}
