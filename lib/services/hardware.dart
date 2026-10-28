// Đánh giá cấu hình máy và đề xuất model chạy trên máy.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class Hardware {
  final String os, cpu;
  final int cores;
  final double ramGb;
  final String? gpu;
  final double? vramGb; // VRAM của GPU rời (NVIDIA); null nếu không đo được
  final bool appleSilicon; // bộ nhớ hợp nhất: GPU dùng chung RAM

  const Hardware(this.os, this.cpu, this.cores, this.ramGb, this.gpu, this.vramGb, this.appleSilicon);

  /// Dung lượng có thể dành cho model khi chạy bằng GPU. macOS cho GPU dùng khoảng 75% RAM hợp nhất.
  double get gpuBudgetGb => appleSilicon ? ramGb * 0.75 - 1.5 : (vramGb ?? 0) - 1;

  /// Dung lượng có thể dành cho model khi chạy bằng CPU + RAM.
  double get ramBudgetGb => ramGb - 4;
}

Future<String> _run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args).timeout(const Duration(seconds: 8));
    return r.exitCode == 0 ? r.stdout.toString().trim() : '';
  } catch (_) {
    return '';
  }
}

Future<(String?, double?)> _nvidia() async {
  final out = await _run('nvidia-smi', ['--query-gpu=name,memory.total', '--format=csv,noheader,nounits']);
  if (out.isEmpty) return (null, null);
  final parts = out.split('\n').first.split(',');
  return (parts.first.trim(), (double.tryParse(parts.last.trim()) ?? 0) / 1024);
}

Future<Hardware> detectHardware() async {
  final cores = Platform.numberOfProcessors;
  var cpu = 'Không rõ';
  var ram = 0.0;
  String? gpu;
  double? vram;
  var apple = false;

  if (Platform.isLinux || Platform.isAndroid) {
    try {
      final mem = await File('/proc/meminfo').readAsString();
      final kb = RegExp(r'MemTotal:\s+(\d+)').firstMatch(mem)?.group(1);
      ram = (int.tryParse(kb ?? '') ?? 0) / 1024 / 1024;
      final info = await File('/proc/cpuinfo').readAsString();
      cpu = RegExp(r'(?:model name|Hardware)\s*:\s*(.+)').firstMatch(info)?.group(1)?.trim() ?? cpu;
    } catch (_) {}
    if (Platform.isLinux) {
      (gpu, vram) = await _nvidia();
      if (gpu == null) {
        final lspci = await _run('sh', ['-c', 'lspci | grep -iE "vga|3d|display"']);
        if (lspci.isNotEmpty) gpu = lspci.split('\n').first.replaceFirst(RegExp(r'^.*?: '), '');
      }
    }
  } else if (Platform.isMacOS) {
    ram = (int.tryParse(await _run('sysctl', ['-n', 'hw.memsize'])) ?? 0) / 1024 / 1024 / 1024;
    cpu = await _run('sysctl', ['-n', 'machdep.cpu.brand_string']);
    apple = (await _run('uname', ['-m'])) == 'arm64';
    gpu = apple ? 'GPU tích hợp Apple Silicon (dùng chung RAM)' : null;
  } else if (Platform.isWindows) {
    final ps = await _run('powershell', [
      '-NoProfile',
      '-Command',
      r'$c=Get-CimInstance Win32_ComputerSystem; $p=Get-CimInstance Win32_Processor | Select-Object -First 1; '
          r'$g=(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join "; "; '
          r'"$($c.TotalPhysicalMemory)|$($p.Name)|$g"',
    ]);
    final parts = ps.split('|');
    if (parts.length == 3) {
      ram = (int.tryParse(parts[0].trim()) ?? 0) / 1024 / 1024 / 1024;
      cpu = parts[1].trim();
      gpu = parts[2].trim().isEmpty ? null : parts[2].trim();
    }
    final (nvName, nvVram) = await _nvidia();
    if (nvName != null) (gpu, vram) = (nvName, nvVram);
  }

  final os = Platform.isAndroid
      ? 'Android'
      : Platform.isMacOS
          ? 'macOS'
          : Platform.isWindows
              ? 'Windows'
              : 'Linux';
  return Hardware(os, cpu.isEmpty ? 'Không rõ' : cpu, cores, ram, gpu, vram, apple);
}

enum Fit { fast, slow, no }

class ModelInfo {
  final String name, ollama, search, note, hfRepo, hfFile;
  final double sizeGb;
  final int quality;

  ModelInfo.fromJson(Map<String, dynamic> j)
      : name = j['name'],
        ollama = j['ollama'],
        search = j['search'],
        note = j['note'] ?? '',
        hfRepo = j['hf_repo'] ?? '',
        hfFile = j['hf_file'] ?? '',
        sizeGb = (j['size_gb'] as num).toDouble(),
        quality = j['quality'] ?? 3;

  /// Chỉ dùng để đánh giá mức phù hợp của một file có dung lượng cho trước.
  ModelInfo.size(this.sizeGb)
      : name = '',
        ollama = '',
        search = '',
        note = '',
        hfRepo = '',
        hfFile = '',
        quality = 3;

  /// Model cần thêm ~15% bộ nhớ cho ngữ cảnh (context ~8K token) khi chạy.
  double get needGb => sizeGb * 1.15 + 0.5;

  Fit fitFor(Hardware hw) {
    if (hw.os == 'Android') return needGb <= hw.ramBudgetGb * 0.6 ? Fit.slow : Fit.no;
    if (needGb <= hw.gpuBudgetGb) return Fit.fast;
    if (needGb <= hw.ramBudgetGb) return Fit.slow;
    return Fit.no;
  }
}

const _remote = 'https://raw.githubusercontent.com/ngiangbao/vn-stock-insight/main/assets/models.json';

/// Đọc danh sách model đề xuất: ưu tiên bản mới nhất trên GitHub, dự phòng bản kèm theo app.
Future<List<ModelInfo>> loadModelCatalog() async {
  String raw;
  try {
    final resp = await http.get(Uri.parse(_remote)).timeout(const Duration(seconds: 8));
    raw = resp.statusCode == 200 ? utf8.decode(resp.bodyBytes) : await rootBundle.loadString('assets/models.json');
  } catch (_) {
    raw = await rootBundle.loadString('assets/models.json');
  }
  final list = (jsonDecode(raw) as Map<String, dynamic>)['models'] as List;
  return [for (final m in list) ModelInfo.fromJson(m as Map<String, dynamic>)];
}

/// Chọn model đề xuất: chất lượng cao nhất chạy nhanh được; nếu không có thì model chạy được bằng CPU
/// nhưng không quá lớn (tránh quá chậm).
ModelInfo? recommend(List<ModelInfo> models, Hardware hw) {
  int byQuality(ModelInfo a, ModelInfo b) =>
      b.quality != a.quality ? b.quality.compareTo(a.quality) : a.sizeGb.compareTo(b.sizeGb);
  final fast = models.where((m) => m.fitFor(hw) == Fit.fast).toList()..sort(byQuality);
  if (fast.isNotEmpty) return fast.first;
  final slow = models.where((m) => m.fitFor(hw) == Fit.slow && m.sizeGb <= 6).toList()..sort(byQuality);
  return slow.isEmpty ? null : slow.first;
}

// ---------- Ollama: liệt kê và tải model ----------
String ollamaHost(String baseUrl) => baseUrl.replaceFirst(RegExp(r'/v1/?$'), '');

Future<bool> ollamaRunning(String baseUrl) async {
  try {
    final resp = await http.get(Uri.parse('${ollamaHost(baseUrl)}/api/version')).timeout(const Duration(seconds: 5));
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<Set<String>> ollamaInstalled(String baseUrl) async {
  try {
    final resp = await http.get(Uri.parse('${ollamaHost(baseUrl)}/api/tags')).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) return {};
    final models = (jsonDecode(resp.body) as Map)['models'] as List? ?? [];
    return {for (final m in models) (m as Map)['name'].toString()};
  } catch (_) {
    return {};
  }
}

/// Tải model qua Ollama, báo tiến độ (0..1) qua [onProgress].
Future<void> ollamaPull(String baseUrl, String model, void Function(String status, double? progress) onProgress) async {
  final client = http.Client();
  try {
    final req = http.Request('POST', Uri.parse('${ollamaHost(baseUrl)}/api/pull'))
      ..body = jsonEncode({'model': model, 'stream': true});
    final resp = await client.send(req);
    if (resp.statusCode != 200) throw Exception('Ollama trả về HTTP ${resp.statusCode}');
    await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, dynamic>;
      if (j['error'] != null) throw Exception(j['error']);
      final total = (j['total'] as num?)?.toDouble();
      final done = (j['completed'] as num?)?.toDouble();
      onProgress(j['status']?.toString() ?? '', total != null && done != null && total > 0 ? done / total : null);
    }
  } finally {
    client.close();
  }
}
