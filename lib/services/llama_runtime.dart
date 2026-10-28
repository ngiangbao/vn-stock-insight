// Engine chạy model trong app: tải bản build chính thức của llama.cpp phù hợp với máy,
// chạy `llama-server` ở 127.0.0.1 và gọi nó qua API chuẩn OpenAI.
//
// Phiên bản llama.cpp đọc từ assets/runtime.json (bản mới nhất trên GitHub, dự phòng bản kèm app),
// nên engine tự cập nhật khi file đó đổi số build. File tải về được kiểm tra SHA-256 từ GitHub.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'downloads.dart';

const _runtimeConfigUrl = 'https://raw.githubusercontent.com/ngiangbao/vn-stock-insight/main/assets/runtime.json';

/// Nền tảng có hỗ trợ chạy model trong app hay không (Android chặn chạy file thực thi tải về).
bool get embeddedSupported => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Tên cuối của đường dẫn, chấp nhận cả `/` và `\` (Windows trả về `\`, đường dẫn tự ghép có thể có `/`).
String baseName(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

class LlamaRuntime {
  final Directory baseDir; // thư mục dữ liệu của app
  final Future<String> Function() loadBundledConfig;

  LlamaRuntime(this.baseDir, this.loadBundledConfig);

  Directory get _engineDir => Directory(_join(baseDir.path, 'engine'));
  File get _installedFile => File(_join(_engineDir.path, 'installed.json'));
  File get _pidFile => File(_join(_engineDir.path, 'server.pid'));

  Process? _process;
  String? _modelPath;
  int? _port;
  final _log = <String>[];

  String? get baseUrl => _port == null ? null : 'http://127.0.0.1:$_port/v1';
  bool get running => _process != null;
  String? get loadedModel => _modelPath;

  // ---------- Phiên bản ----------
  Future<String> desiredBuild() async {
    String raw;
    try {
      final resp = await http.get(Uri.parse(_runtimeConfigUrl)).timeout(const Duration(seconds: 8));
      raw = resp.statusCode == 200 ? resp.body : await loadBundledConfig();
    } catch (_) {
      raw = await loadBundledConfig();
    }
    return (jsonDecode(raw) as Map<String, dynamic>)['llama_cpp_build'] as String;
  }

  Future<Map<String, dynamic>?> installed() async {
    try {
      final info = jsonDecode(await _installedFile.readAsString()) as Map<String, dynamic>;
      return await File(info['server'] as String).exists() ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Bản build phù hợp với máy: GPU dùng Vulkan (Windows/Linux) hoặc Metal (macOS, có sẵn).
  Future<String> variant() async {
    if (Platform.isMacOS) {
      final arch = (await Process.run('uname', ['-m'])).stdout.toString().trim();
      return arch == 'arm64' ? 'macos-arm64' : 'macos-x64';
    }
    if (Platform.isWindows) {
      final r = await Process.run('powershell', [
        '-NoProfile', '-Command', '(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ";"', //
      ]).catchError((_) => ProcessResult(0, 1, '', ''));
      final gpus = r.stdout.toString().toLowerCase();
      final hasGpu = RegExp(r'nvidia|geforce|rtx|radeon|amd|arc|intel').hasMatch(gpus) && !gpus.contains('basic display');
      return hasGpu ? 'win-vulkan-x64' : 'win-cpu-x64';
    }
    // Linux: dùng Vulkan nếu máy có thư viện Vulkan
    final vulkan = ['/usr/lib/libvulkan.so.1', '/usr/lib64/libvulkan.so.1', '/usr/lib/x86_64-linux-gnu/libvulkan.so.1']
        .any((p) => File(p).existsSync());
    return vulkan ? 'ubuntu-vulkan-x64' : 'ubuntu-x64';
  }

  /// Engine đang cài có cần tải mới không (chưa cài, hoặc khác phiên bản mong muốn).
  Future<bool> needsUpdate() async {
    final info = await installed();
    if (info == null) return true;
    return info['build'] != await desiredBuild() || info['variant'] != await variant();
  }

  /// Tải và cài engine nếu cần. Trả về đường dẫn llama-server.
  Future<String> ensureInstalled({void Function(String status, double? progress)? onStatus, CancelToken? cancel}) async {
    if (!embeddedSupported) throw Exception('Nền tảng này chưa hỗ trợ chạy model trong app.');
    final build = await desiredBuild();
    final v = await variant();
    final info = await installed();
    if (info != null && info['build'] == build && info['variant'] == v) return info['server'] as String;

    onStatus?.call('Đang tìm llama.cpp $build ($v)…', null);
    final release = jsonDecode((await http
            .get(Uri.parse('https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$build'),
                headers: {'Accept': 'application/vnd.github+json'})
            .timeout(const Duration(seconds: 20)))
        .body) as Map<String, dynamic>;
    final asset = (release['assets'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((a) => (a['name'] as String).startsWith('llama-$build-bin-$v.'))
        .firstOrNull;
    if (asset == null) throw Exception('Không tìm thấy bản llama.cpp $build cho $v.');
    final digest = (asset['digest'] as String?)?.replaceFirst('sha256:', '');

    final archive = File(_join(_engineDir.path, asset['name'] as String));
    await downloadFile(
      asset['browser_download_url'],
      archive,
      sha256Hex: digest,
      cancel: cancel,
      onProgress: (got, total) =>
          onStatus?.call('Đang tải engine llama.cpp (${formatBytes(got)}${total == null ? '' : ' / ${formatBytes(total)}'})',
              total == null ? null : got / total),
    );

    onStatus?.call('Đang giải nén engine…', null);
    await stop();
    final target = Directory(_join(_engineDir.path, '$build-$v'));
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    // tar có sẵn trên Linux, macOS và Windows 10+ (đọc được cả .zip)
    final r = await Process.run('tar', ['-xf', archive.path, '-C', target.path]);
    if (r.exitCode != 0) throw Exception('Không giải nén được engine: ${r.stderr}');
    await archive.delete();

    final exe = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
    final server = await target
        .list(recursive: true)
        .firstWhere((e) => e is File && baseName(e.path) == exe, orElse: () => File(''));
    if (server.path.isEmpty) throw Exception('Gói llama.cpp không có $exe.');
    if (!Platform.isWindows) await Process.run('chmod', ['+x', server.path]);

    // Dọn các bản cũ. So sánh theo tên thư mục: trên Windows, đường dẫn liệt kê ra dùng `\`
    // còn đường dẫn tự ghép có thể khác dạng, so cả chuỗi sẽ xóa nhầm chính bản vừa cài.
    final keep = baseName(target.path);
    await for (final e in _engineDir.list()) {
      if (e is Directory && baseName(e.path) != keep) await e.delete(recursive: true);
    }
    if (!await File(server.path).exists()) {
      throw Exception('Không tìm thấy $exe sau khi cài. Phần mềm diệt virus có thể đã chặn file này.');
    }
    await _installedFile.writeAsString(jsonEncode({'build': build, 'variant': v, 'server': server.path}));
    onStatus?.call('Đã cài llama.cpp $build', 1);
    return server.path;
  }

  // ---------- Chạy server ----------
  /// Chạy model [modelPath], trả về base URL. Nếu đang chạy đúng model đó thì dùng lại.
  Future<String> start(String modelPath, {void Function(String status, double? progress)? onStatus, int ctx = 16384}) async {
    if (_process != null && _modelPath == modelPath && baseUrl != null) return baseUrl!;
    final server = await ensureInstalled(onStatus: onStatus);
    await stop();
    await _killStale();

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    onStatus?.call('Đang nạp model vào bộ nhớ…', null);
    _log.clear();
    final dir = File(server).parent.path;
    final Process proc;
    try {
      proc = await Process.start(
        server,
        [
          '-m', modelPath, '--host', '127.0.0.1', '--port', '$port', //
          '-c', '$ctx', '--fit', 'on', '--no-webui', '--reasoning', 'off',
        ],
        workingDirectory: dir,
        environment: Platform.isLinux ? {'LD_LIBRARY_PATH': dir} : null,
      );
    } on ProcessException catch (e) {
      // Engine bị xóa hoặc bị chặn: bỏ thông tin cài đặt để lần sau tự cài lại
      if (await _installedFile.exists()) await _installedFile.delete();
      throw Exception('Không chạy được engine llama.cpp (${e.message}). Hãy thử lại để app cài lại engine; '
          'nếu vẫn lỗi, kiểm tra phần mềm diệt virus có chặn file llama-server không.');
    }
    _process = proc;
    _modelPath = modelPath;
    _port = port;
    await _pidFile.writeAsString('${proc.pid}');
    for (final s in [proc.stdout, proc.stderr]) {
      s.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        _log.add(l);
        if (_log.length > 60) _log.removeAt(0);
      });
    }
    var exited = false;
    unawaited(proc.exitCode.then((_) {
      exited = true;
      if (identical(_process, proc)) {
        _process = null;
        _port = null;
        _modelPath = null;
      }
    }));

    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        final tail = _log.where((l) => l.contains('error') || l.contains('failed')).take(3).join('\n');
        throw Exception('Engine dừng khi nạp model. ${tail.isEmpty ? 'Có thể máy không đủ bộ nhớ.' : tail}');
      }
      try {
        final r = await http.get(Uri.parse('http://127.0.0.1:$port/health')).timeout(const Duration(seconds: 2));
        if (r.statusCode == 200) {
          onStatus?.call('Model đã sẵn sàng', 1);
          return 'http://127.0.0.1:$port/v1';
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await stop();
    throw Exception('Nạp model quá lâu (hơn 4 phút).');
  }

  Future<void> stop() async {
    final p = _process;
    _process = null;
    _port = null;
    _modelPath = null;
    if (p != null) {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    if (await _pidFile.exists()) await _pidFile.delete();
  }

  /// Tắt server còn sót lại nếu lần trước app bị đóng đột ngột.
  /// Chỉ tắt khi PID đó đúng là llama-server (PID có thể đã được cấp cho chương trình khác).
  Future<void> _killStale() async {
    try {
      final pid = int.parse((await _pidFile.readAsString()).trim());
      final String name;
      if (Platform.isLinux) {
        name = await File('/proc/$pid/cmdline').readAsString();
      } else if (Platform.isMacOS) {
        name = (await Process.run('ps', ['-p', '$pid', '-o', 'comm='])).stdout.toString();
      } else {
        name = (await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH'])).stdout.toString();
      }
      if (name.contains('llama-server')) Process.killPid(pid);
    } catch (_) {
      // không còn tiến trình nào: bỏ qua
    }
  }

  /// Dừng ngay (đồng bộ), dùng khi app sắp thoát.
  void killNow() {
    _process?.kill();
    _process = null;
  }
}
