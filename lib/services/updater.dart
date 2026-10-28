// Kiểm tra phiên bản mới trên GitHub Releases.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const repo = 'ngiangbao/vn-stock-insight';

class UpdateInfo {
  final String current, latest, notes, pageUrl;
  final String? downloadUrl; // file cài đặt cho nền tảng đang chạy
  const UpdateInfo(this.current, this.latest, this.notes, this.pageUrl, this.downloadUrl);
  bool get hasUpdate => compareVersions(latest, current) > 0;
}

/// So sánh "1.2.10" với "1.2.9" (bỏ tiền tố "v" và phần "+build").
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
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
      .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'})
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode == 404) return UpdateInfo(current, current, '', 'https://github.com/$repo/releases', null);
  if (resp.statusCode != 200) throw Exception('GitHub trả về HTTP ${resp.statusCode}');
  final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  final tag = _platformTag();
  final assets = (j['assets'] as List? ?? []).cast<Map<String, dynamic>>();
  final asset = assets.where((a) => a['name'].toString().toLowerCase().contains(tag)).firstOrNull;
  return UpdateInfo(
    current,
    j['tag_name']?.toString().replaceFirst('v', '') ?? current,
    j['body']?.toString() ?? '',
    j['html_url']?.toString() ?? 'https://github.com/$repo/releases',
    asset?['browser_download_url']?.toString(),
  );
}
