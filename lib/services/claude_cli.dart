// Dùng chương trình `claude` (Claude Code CLI) đã đăng nhập trên máy làm nhà cung cấp AI:
// tính vào gói Claude của người dùng, không cần API key. Chỉ có trên máy tính.
//
// Cách gọi (đã kiểm tra với claude 2.1.x): `claude -p --output-format json --json-schema ...`, nội dung câu hỏi truyền qua stdin.
// Chạy trong thư mục tạm, tắt toàn bộ công cụ (`--tools=`) và không nạp cấu hình dự án/người dùng (`--setting-sources=`)
// nên CLI chỉ trả lời, không đọc hay sửa file nào.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Kết quả của một lần chạy tiến trình.
class CliResult {
  final int exitCode;
  final String stdout, stderr;
  final bool timedOut;
  const CliResult(this.exitCode, this.stdout, this.stderr, {this.timedOut = false});
}

typedef CliRun = Future<CliResult> Function(
  String exe,
  List<String> args, {
  String? stdin,
  Duration timeout,
  Map<String, String>? env,
  String? cwd,
});

/// Chạy tiến trình streaming từng dòng (stdout + stderr gộp), dùng cho cài đặt và đăng nhập. Trả về mã thoát.
typedef LineRun = Future<int> Function(
  String exe,
  List<String> args,
  void Function(String line) onLine, {
  CliJob? job,
  Duration timeout,
  String? cwd,
});

/// Một tác vụ dài có thể hủy (bấm "Hủy" thì tắt tiến trình đang chạy).
class CliJob {
  Process? _process;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _process?.kill();
  }
}

class ClaudeCliException implements Exception {
  final String message;
  final bool retryable, notLoggedIn;
  ClaudeCliException(this.message, {this.retryable = false, this.notLoggedIn = false});
  @override
  String toString() => message;
}

class CliAuth {
  final bool loggedIn;
  final String? method, email;
  const CliAuth(this.loggedIn, {this.method, this.email});
}

class CliReply {
  final Map<String, dynamic>? structured;
  final String text;
  final double? costUsd;
  const CliReply(this.structured, this.text, this.costUsd);
}

/// Thư mục làm việc tạm để CLI không nạp CLAUDE.md hay cấu hình của một dự án nào.
Future<String> cliWorkDir() async {
  final d = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}vnsi-claude-cli');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d.path;
}

Future<CliResult> runProcess(
  String exe,
  List<String> args, {
  String? stdin,
  Duration timeout = const Duration(minutes: 6),
  Map<String, String>? env,
  String? cwd,
}) async {
  final lower = exe.toLowerCase();
  // .cmd/.bat (bản cài bằng npm trên Windows) phải chạy qua cmd.exe
  final viaShell = Platform.isWindows && (lower.endsWith('.cmd') || lower.endsWith('.bat'));
  final p = await Process.start(exe, args, environment: env, workingDirectory: cwd, runInShell: viaShell);
  final out = StringBuffer(), err = StringBuffer();
  final so = p.stdout.transform(utf8.decoder).listen(out.write);
  final se = p.stderr.transform(utf8.decoder).listen(err.write);
  try {
    p.stdin.encoding = utf8;
    if (stdin != null) p.stdin.write(stdin);
    await p.stdin.close();
  } catch (_) {
    // tiến trình đã thoát trước khi nhận hết dữ liệu: kết quả lỗi sẽ nằm ở stdout/stderr
  }
  var timedOut = false;
  final code = await p.exitCode.timeout(timeout, onTimeout: () {
    timedOut = true;
    p.kill();
    return -1;
  });
  await Future.wait([so.asFuture<void>(), se.asFuture<void>()]).timeout(const Duration(seconds: 5), onTimeout: () => []);
  return CliResult(code, out.toString(), err.toString(), timedOut: timedOut);
}

Future<int> runStreaming(
  String exe,
  List<String> args,
  void Function(String line) onLine, {
  CliJob? job,
  Duration timeout = const Duration(minutes: 10),
  String? cwd,
}) async {
  final lower = exe.toLowerCase();
  final viaShell = Platform.isWindows && (lower.endsWith('.cmd') || lower.endsWith('.bat') || lower == 'npm');
  final p = await Process.start(exe, args, workingDirectory: cwd, runInShell: viaShell);
  job?._process = p;
  final subs = [
    for (final s in [p.stdout, p.stderr])
      s.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) onLine(l);
      }),
  ];
  unawaited(p.stdin.close().catchError((_) {}));
  var timedOut = false;
  final code = await p.exitCode.timeout(timeout, onTimeout: () {
    timedOut = true;
    p.kill();
    return -1;
  });
  await Future.wait([for (final s in subs) s.asFuture<void>()]).timeout(const Duration(seconds: 5), onTimeout: () => []);
  if (timedOut) onLine('Quá thời gian chờ, đã dừng.');
  return job?.cancelled == true ? -2 : code;
}

class ClaudeCli {
  final CliRun _run;
  final Map<String, String> _env;
  final bool _windows;
  final String _home;
  final bool Function(String path) _exists;
  final Future<String> Function() _workDir;

  String? _found, _foundKey;

  ClaudeCli({CliRun? run, Map<String, String>? env, bool? isWindows, String? home, bool Function(String)? exists, Future<String> Function()? workDir})
      : _run = run ?? runProcess,
        _workDir = workDir ?? cliWorkDir,
        _env = env ?? Platform.environment,
        _windows = isWindows ?? Platform.isWindows,
        _home = home ?? (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''),
        _exists = exists ?? ((p) => File(p).existsSync());

  /// Chỉ chạy được trên máy tính.
  static bool get supported => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  String get _sep => _windows ? '\\' : '/';
  String _join(String a, String b) => '$a$_sep$b';

  /// Các thư mục thường chứa `claude`. Ứng dụng mở từ menu (không qua terminal) thường không có PATH của người dùng.
  List<String> _commonDirs() {
    if (_windows) {
      final appData = _env['APPDATA'], local = _env['LOCALAPPDATA'];
      return [
        _join(_join(_home, '.local'), 'bin'),
        if (appData != null) _join(appData, 'npm'),
        if (local != null) _join(_join(_join(local, 'Microsoft'), 'WinGet'), 'Links'),
      ];
    }
    return [
      '$_home/.local/bin',
      '$_home/.claude/local',
      '$_home/.npm-global/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/usr/bin',
      '$_home/.local/share/mise/shims',
      '$_home/.local/share/mise/installs/claude/latest',
      '$_home/.volta/bin',
      '$_home/.bun/bin',
      '$_home/.asdf/shims',
    ];
  }

  /// Tìm `claude`. [override] là đường dẫn người dùng nhập: nếu có mà sai thì trả null (không tự tìm chỗ khác để tránh nhầm).
  Future<String?> find({String override = '', bool refresh = false}) async {
    final key = override.trim();
    if (!refresh && _found != null && _foundKey == key && _exists(_found!)) return _found;
    final r = await _search(key);
    _found = r;
    _foundKey = key;
    return r;
  }

  Future<String?> _search(String override) async {
    if (override.isNotEmpty) return _exists(override) ? override : null;
    final names = _windows ? ['claude.exe', 'claude.cmd', 'claude.bat'] : ['claude'];
    final pathDirs = (_env['PATH'] ?? _env['Path'] ?? '').split(_windows ? ';' : ':').where((d) => d.isNotEmpty);
    for (final d in [...pathDirs, ..._commonDirs()]) {
      for (final n in names) {
        final p = _join(d, n);
        if (_exists(p)) return p;
      }
    }
    return _viaShell();
  }

  /// Hỏi shell đăng nhập của người dùng (nơi nvm, mise, asdf... thêm vào PATH).
  Future<String?> _viaShell() async {
    try {
      if (_windows) {
        final r = await _run('where', ['claude'], timeout: const Duration(seconds: 8));
        return _firstExisting(r.stdout);
      }
      final shell = _env['SHELL'] ?? '/bin/sh';
      for (final flag in ['-lc', '-ic']) {
        final r = await _run(shell, [flag, 'command -v claude'], timeout: const Duration(seconds: 8));
        final p = _firstExisting(r.stdout, mustBeAbsolute: true);
        if (p != null) return p;
      }
    } catch (_) {
      // không có shell hoặc không chạy được: coi như chưa tìm thấy
    }
    return null;
  }

  String? _firstExisting(String out, {bool mustBeAbsolute = false}) {
    for (final line in out.split('\n').reversed.map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      if (mustBeAbsolute && !line.startsWith('/')) continue;
      if (_exists(line)) return line;
    }
    return null;
  }

  Future<String?> version(String path) async {
    try {
      final r = await _run(path, ['--version'], timeout: const Duration(seconds: 20), cwd: await _workDir());
      return r.exitCode == 0 && r.stdout.trim().isNotEmpty ? r.stdout.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<CliAuth> authStatus(String path) async {
    try {
      final r = await _run(path, ['auth', 'status', '--json'], timeout: const Duration(seconds: 20), cwd: await _workDir());
      final j = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
      return CliAuth(j['loggedIn'] == true, method: j['authMethod']?.toString(), email: j['email']?.toString());
    } catch (_) {
      return const CliAuth(false);
    }
  }

  /// Hỏi [model] (bí danh như "sonnet", "opus", "haiku" hoặc tên đầy đủ; rỗng/"default" = mặc định của CLI) và nhận JSON theo [schema].
  Future<CliReply> generate({
    required String path,
    required String system,
    required String prompt,
    required Map<String, dynamic> schema,
    String model = '',
    String effort = '',
    Duration timeout = const Duration(minutes: 6),
  }) async {
    // Bản .cmd trên Windows chạy qua cmd.exe nên ký tự đặc biệt trong đối số dễ bị hiểu sai: đưa cả chỉ dẫn lẫn schema vào stdin.
    final shim = _windows && (path.toLowerCase().endsWith('.cmd') || path.toLowerCase().endsWith('.bat'));
    final args = ['-p', '--output-format', 'json', '--tools=', '--no-session-persistence', '--setting-sources='];
    final m = model.trim();
    if (m.isNotEmpty && m != 'default') args.addAll(['--model', m]);
    if (effort.isNotEmpty) args.addAll(['--effort', effort]);
    final String stdin;
    if (shim) {
      stdin = '<chi_dan>\n$system\n</chi_dan>\n\n$prompt\n\nTrả lời DUY NHẤT bằng một đối tượng JSON hợp lệ theo JSON Schema sau, không kèm giải thích:\n${jsonEncode(schema)}';
    } else {
      args.addAll(['--system-prompt', system, '--json-schema', jsonEncode(schema)]);
      stdin = prompt;
    }

    final CliResult r;
    try {
      r = await _run(path, args, stdin: stdin, timeout: timeout, cwd: await _workDir());
    } on ProcessException catch (e) {
      throw ClaudeCliException('Không chạy được Claude CLI (${e.message}). Kiểm tra lại đường dẫn trong Cài đặt → AI.');
    }
    if (r.timedOut) throw ClaudeCliException('Claude CLI phản hồi quá lâu (hơn ${timeout.inMinutes} phút).', retryable: true);

    Map<String, dynamic>? j;
    try {
      j = jsonDecode(r.stdout.trim()) as Map<String, dynamic>;
    } catch (_) {}
    if (j == null) {
      final msg = (r.stderr.trim().isNotEmpty ? r.stderr : r.stdout).trim();
      throw ClaudeCliException(msg.isEmpty ? 'Claude CLI không trả về kết quả (mã thoát ${r.exitCode}).' : _failure(msg, null, m));
    }
    final text = j['result']?.toString() ?? '';
    // "subtype" vẫn là "success" khi lỗi, nên chỉ dựa vào is_error
    if (j['is_error'] == true) throw _failureException(text, j['api_error_status'], m);
    final so = j['structured_output'];
    return CliReply(so is Map<String, dynamic> ? so : null, text, (j['total_cost_usd'] as num?)?.toDouble());
  }

  ClaudeCliException _failureException(String text, Object? status, String model) {
    final lower = text.toLowerCase();
    final loggedOut = lower.contains('not logged in') || lower.contains('/login') || lower.contains('invalid api key');
    final limited = lower.contains('usage limit') || lower.contains('rate limit') || status == 429;
    return ClaudeCliException(_failure(text, status, model), notLoggedIn: loggedOut, retryable: limited || status == 529 || lower.contains('overloaded'));
  }

  String _failure(String text, Object? status, String model) {
    final lower = text.toLowerCase();
    if (lower.contains('not logged in') || lower.contains('/login') || lower.contains('invalid api key')) {
      return 'Claude CLI chưa đăng nhập. Vào Cài đặt → AI → Claude CLI và bấm "Đăng nhập tài khoản Claude".';
    }
    if (lower.contains('selected model') || status == 404) {
      return 'Model "${model.isEmpty ? 'mặc định' : model}" không tồn tại hoặc tài khoản của bạn không được dùng. Chọn model khác trong Cài đặt → AI.';
    }
    if (lower.contains('usage limit') || lower.contains('rate limit') || status == 429) {
      return 'Gói Claude của bạn đã chạm giới hạn sử dụng. Hãy thử lại sau hoặc chọn model nhẹ hơn (ví dụ Haiku).';
    }
    if (status == 529 || lower.contains('overloaded')) return 'Claude đang quá tải, hãy thử lại sau ít phút.';
    final short = text.trim().length > 300 ? '${text.trim().substring(0, 300)}…' : text.trim();
    return 'Claude CLI báo lỗi: $short';
  }
}

/// Bản dùng chung của app; kiểm thử có thể thay bằng bản giả.
ClaudeCli claudeCli = ClaudeCli();
