// Cài đặt và đăng nhập Claude CLI ngay trong app, chỉ khi người dùng bấm và xác nhận.
//
// Cách cài chính thức theo tài liệu của Anthropic (https://code.claude.com/docs/en/setup):
//  - macOS/Linux: `curl -fsSL https://claude.ai/install.sh | bash`
//  - Windows (PowerShell): `irm https://claude.ai/install.ps1 | iex`
//  - hoặc `npm install -g @anthropic-ai/claude-code` (cần Node.js)
// App tải đúng script đó (chỉ từ claude.ai hoặc tên miền con của claude.ai), lưu vào thư mục tạm rồi chạy, thay cho lệnh "tải rồi chạy luôn".

import 'dart:io';

import 'package:http/http.dart' as http;

import 'claude_cli.dart';

class InstallOption {
  final String id, title, detail, command;
  const InstallOption(this.id, this.title, this.detail, this.command);
}

/// Các cách cài khả dụng trên máy này. [hasNpm]: máy đã có npm.
List<InstallOption> claudeInstallOptions({required bool windows, required bool hasNpm}) => [
      if (windows)
        const InstallOption(
          'script',
          'Trình cài đặt chính thức (khuyên dùng)',
          'Tải script cài đặt của Anthropic từ claude.ai rồi chạy bằng PowerShell. Không cần Node.js.',
          'irm https://claude.ai/install.ps1 | iex',
        )
      else
        const InstallOption(
          'script',
          'Trình cài đặt chính thức (khuyên dùng)',
          'Tải script cài đặt của Anthropic từ claude.ai rồi chạy bằng bash. Không cần Node.js, không cần quyền quản trị.',
          'curl -fsSL https://claude.ai/install.sh | bash',
        ),
      if (hasNpm)
        const InstallOption(
          'npm',
          'Cài bằng npm',
          'Cần Node.js. Trên một số máy cần quyền quản trị để cài toàn cục.',
          'npm install -g @anthropic-ai/claude-code',
        ),
    ];

bool isOfficialHost(Uri u) => u.scheme == 'https' && (u.host == 'claude.ai' || u.host.endsWith('.claude.ai'));

/// Có lệnh `npm` trong PATH không.
Future<bool> hasNpm({LineRun? run}) async {
  try {
    final lines = <String>[];
    final code = await (run ?? runStreaming)(
      Platform.isWindows ? 'npm.cmd' : 'npm',
      ['--version'],
      lines.add,
      timeout: const Duration(seconds: 15),
    );
    return code == 0;
  } catch (_) {
    return false;
  }
}

/// Cài Claude CLI theo [option]; [onLine] nhận từng dòng nhật ký. Ném [ClaudeCliException] nếu thất bại.
Future<void> installClaudeCli(
  InstallOption option, {
  required void Function(String line) onLine,
  CliJob? job,
  http.Client? client,
  LineRun? run,
  bool? windows,
  Directory? tempRoot,
}) async {
  final win = windows ?? Platform.isWindows;
  final runner = run ?? runStreaming;

  if (option.id == 'npm') {
    onLine('> ${option.command}');
    final code = await runner(win ? 'npm.cmd' : 'npm', ['install', '-g', '@anthropic-ai/claude-code'], onLine, job: job);
    if (code != 0) throw ClaudeCliException(code == -2 ? 'Đã hủy cài đặt.' : 'npm báo lỗi (mã $code). Xem nhật ký phía trên.');
    return;
  }

  final url = Uri.parse(win ? 'https://claude.ai/install.ps1' : 'https://claude.ai/install.sh');
  if (!isOfficialHost(url)) throw ClaudeCliException('Địa chỉ cài đặt không hợp lệ.');
  onLine('Đang tải script cài đặt chính thức: $url');
  final own = client == null;
  final c = client ?? http.Client();
  // `Client.get` làm mất địa chỉ cuối cùng sau chuyển hướng, nên gửi yêu cầu thô để kiểm tra được tên miền thật.
  final int status;
  final List<int> bytes;
  final Uri finalUrl;
  try {
    final streamed = await c.send(http.Request('GET', url)).timeout(const Duration(seconds: 60));
    finalUrl = streamed is http.BaseResponseWithUrl ? (streamed as http.BaseResponseWithUrl).url : url;
    status = streamed.statusCode;
    if (!isOfficialHost(finalUrl)) {
      throw ClaudeCliException('Script bị chuyển hướng tới ${finalUrl.host}, không phải tên miền của Anthropic. Đã dừng.');
    }
    bytes = await streamed.stream.toBytes().timeout(const Duration(seconds: 60));
  } finally {
    if (own) c.close();
  }
  if (status != 200) throw ClaudeCliException('Không tải được script cài đặt (HTTP $status).');
  if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
    throw ClaudeCliException('Script cài đặt có kích thước bất thường (${bytes.length} byte). Đã dừng.');
  }

  final dir = await (tempRoot ?? Directory.systemTemp).createTemp('claude-install');
  try {
    final file = File('${dir.path}${Platform.pathSeparator}${win ? 'install.ps1' : 'install.sh'}');
    await file.writeAsBytes(bytes);
    onLine('Đã tải ${bytes.length} byte từ ${finalUrl.host}. Đang chạy script…');
    final code = win
        ? await runner('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', file.path], onLine, job: job)
        : await runner('bash', [file.path], onLine, job: job);
    if (code != 0) throw ClaudeCliException(code == -2 ? 'Đã hủy cài đặt.' : 'Script cài đặt báo lỗi (mã $code). Xem nhật ký phía trên.');
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Đăng nhập bằng tài khoản Claude (gói đăng ký). CLI tự mở trình duyệt và in ra đường dẫn đăng nhập.
Future<int> claudeLogin(String path, {required void Function(String line) onLine, CliJob? job, LineRun? run}) async =>
    (run ?? runStreaming)(path, ['auth', 'login', '--claudeai'], onLine, job: job, timeout: const Duration(minutes: 5), cwd: await cliWorkDir());

final _urlPattern = RegExp(r'https://[^\s<>"]+');

/// Lấy đường dẫn đăng nhập đầu tiên (https) trong một dòng nhật ký, nếu có.
String? firstHttpsUrl(String line) => _urlPattern.firstMatch(line)?.group(0);
