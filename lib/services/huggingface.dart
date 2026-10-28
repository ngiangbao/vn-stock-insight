// Tìm và lấy link tải trực tiếp file model GGUF từ Hugging Face.

import 'dart:convert';

import 'package:http/http.dart' as http;

const _api = 'https://huggingface.co/api';

class HfRepo {
  final String id;
  final int downloads, likes;
  const HfRepo(this.id, this.downloads, this.likes);
}

class HfFile {
  final String repo, name;
  final int size;
  const HfFile(this.repo, this.name, this.size);

  String get url => 'https://huggingface.co/$repo/resolve/main/${Uri.encodeComponent(name).replaceAll('%2F', '/')}';
  double get sizeGb => size / 1e9;

  /// Mức lượng tử hóa đọc từ tên file, ví dụ "Q4_K_M".
  String get quant => RegExp(r'(I?Q\d[_A-Z0-9]*|BF16|F16|F32|MXFP4)', caseSensitive: false).firstMatch(name)?.group(0) ?? '';
}

Future<dynamic> _get(String url) async {
  final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) throw Exception('Hugging Face trả về HTTP ${resp.statusCode}');
  return jsonDecode(utf8.decode(resp.bodyBytes));
}

/// Tìm repo có file GGUF, sắp theo lượt tải.
Future<List<HfRepo>> searchGgufRepos(String query) async {
  final q = Uri.encodeQueryComponent(query.trim());
  final list = await _get('$_api/models?search=$q&filter=gguf&sort=downloads&direction=-1&limit=25') as List;
  return [
    for (final m in list.cast<Map<String, dynamic>>())
      HfRepo(m['id'] ?? m['modelId'], (m['downloads'] as num?)?.toInt() ?? 0, (m['likes'] as num?)?.toInt() ?? 0),
  ];
}

/// Các file GGUF chạy được (một file, không phải file chia nhỏ hay file projector cho ảnh).
Future<List<HfFile>> listGgufFiles(String repo) async {
  final d = await _get('$_api/models/$repo?blobs=true') as Map<String, dynamic>;
  if (d['gated'] != null && d['gated'] != false) {
    throw Exception('Repo $repo yêu cầu đăng nhập Hugging Face để tải. Hãy chọn repo khác (ví dụ của unsloth, bartowski).');
  }
  final files = [
    for (final s in (d['siblings'] as List? ?? []).cast<Map<String, dynamic>>())
      if ((s['rfilename'] as String).toLowerCase().endsWith('.gguf'))
        HfFile(repo, s['rfilename'], (s['size'] as num?)?.toInt() ?? 0),
  ].where((f) {
    final n = f.name.toLowerCase();
    return !n.contains('mmproj') && !RegExp(r'-\d{5}-of-\d{5}').hasMatch(n);
  }).toList()
    ..sort((a, b) => a.size.compareTo(b.size));
  return files;
}

/// Chọn file mặc định: ưu tiên Q4_K_M (cân bằng chất lượng/dung lượng), rồi các bản 4-bit khác.
HfFile? pickDefault(List<HfFile> files) {
  for (final pattern in ['Q4_K_M', 'MXFP4', 'Q4_K_S', 'Q4_0', 'Q5_K_M']) {
    final f = files.where((f) => f.name.toUpperCase().contains(pattern)).firstOrNull;
    if (f != null) return f;
  }
  return files.firstOrNull;
}
