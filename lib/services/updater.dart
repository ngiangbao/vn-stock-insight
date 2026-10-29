// Kiểm tra phiên bản mới trên GitHub Releases.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const repo = 'ngiangbao/vn-stock-insight';

class UpdateInfo {
  final String current, latest, notes, pageUrl;
  final String? downloadUrl; // file cài đặt cho nền tảng đang chạy (tải thủ công)

  /// File dùng để cập nhật tự động (Windows: bộ cài -setup.exe; macOS: .app nén -macos.zip; Linux: .tar.gz), null nếu nền tảng không hỗ trợ.
  final String? autoUrl;

  /// File SHA256SUMS.txt của bản phát hành, dùng kiểm tra toàn vẹn file tải về.
  final String? checksumsUrl;
  const UpdateInfo(this.current, this.latest, this.notes, this.pageUrl, this.downloadUrl, {this.autoUrl, this.checksumsUrl});
  bool get hasUpdate => compareVersions(latest, current) > 0;
}

/// So sánh "1.2.10" với "1.2.9" (bỏ tiền tố "v" và phần "+build").
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

String _platformTag() {
  if (Platform.isAndroid) return '.apk';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  return 'linux';
}

Future<String> currentVersion() async => (await PackageInfo.fromPlatform()).version;

Future<UpdateInfo> checkForUpdate() async {
  final current = await currentVersion();
  final resp = await http
      .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'Accept': 'application/vnd.github+json'})
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode == 404) return UpdateInfo(current, current, '', 'https://github.com/$repo/releases', null);
  if (resp.statusCode != 200) throw Exception('GitHub trả về HTTP ${resp.statusCode}');
  final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  final assets = [
    for (final a in (j['assets'] as List? ?? []).cast<Map<String, dynamic>>()) (a['name'].toString(), a['browser_download_url'].toString()),
  ];
  final picked = pickAssets(assets, platform: _platformTag());
  return UpdateInfo(
    current,
    j['tag_name']?.toString().replaceFirst('v', '') ?? current,
    j['body']?.toString() ?? '',
    j['html_url']?.toString() ?? 'https://github.com/$repo/releases',
    picked.manual,
    autoUrl: picked.auto,
    checksumsUrl: picked.checksums,
  );
}

/// Chọn file cho từng nền tảng từ danh sách (tên, url): file tải thủ công, file cập nhật tự động và file SHA256SUMS.txt.
({String? manual, String? auto, String? checksums}) pickAssets(List<(String, String)> assets, {required String platform}) {
  String? find(bool Function(String n) test) => assets.where((a) => test(a.$1.toLowerCase())).map((a) => a.$2).firstOrNull;
  final checksums = find((n) => n == 'sha256sums.txt');
  switch (platform) {
    case 'windows':
      final setup = find((n) => n.contains('windows') && n.endsWith('-setup.exe'));
      return (manual: setup ?? find((n) => n.contains('windows')), auto: setup, checksums: checksums);
    case 'macos':
      return (
        manual: find((n) => n.contains('macos') && n.endsWith('.pkg')) ?? find((n) => n.contains('macos')),
        auto: find((n) => n.contains('macos') && n.endsWith('.zip')),
        checksums: checksums,
      );
    case 'linux':
      final tar = find((n) => n.contains('linux') && n.endsWith('.tar.gz'));
      return (manual: tar ?? find((n) => n.contains('linux')), auto: tar, checksums: checksums);
    default:
      return (manual: find((n) => n.contains(platform)), auto: null, checksums: checksums);
  }
}
