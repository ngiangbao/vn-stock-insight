import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_stock_insight/ai/providers.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/claude_cli.dart';
import 'package:vn_stock_insight/services/claude_cli_install.dart';
import 'package:vn_stock_insight/ui/claude_cli_section.dart';

// ---------- Công cụ giả ----------
class Call {
  final String exe;
  final List<String> args;
  final String? stdin, cwd;
  Call(this.exe, this.args, this.stdin, this.cwd);
}

/// Chạy tiến trình giả: ghi lại lệnh gọi và trả kết quả do [reply] quyết định.
CliRun fakeRun(List<Call> log, CliResult Function(String exe, List<String> args) reply) =>
    (exe, args, {String? stdin, Duration? timeout, Map<String, String>? env, String? cwd}) async {
      log.add(Call(exe, args, stdin, cwd));
      return reply(exe, args);
    };

CliResult ok(Map<String, dynamic> m) => CliResult(0, jsonEncode(m), '');

CliResult cliReply(String exe, List<String> args, {bool loggedIn = true, Map<String, dynamic>? generate}) {
  if (args.contains('--version')) return const CliResult(0, '2.1.314 (Claude Code)\n', '');
  if (args.length >= 2 && args[0] == 'auth') {
    return ok({'loggedIn': loggedIn, 'authMethod': loggedIn ? 'claude.ai' : 'none', if (loggedIn) 'email': 'me@example.com'});
  }
  return ok(generate ?? {'is_error': false, 'result': '{"ok":true}', 'structured_output': {'ok': true}, 'total_cost_usd': 0.0005});
}

ClaudeCli cliFound(List<Call> log, {bool loggedIn = true, Map<String, dynamic>? generate}) => ClaudeCli(
      run: fakeRun(log, (e, a) => cliReply(e, a, loggedIn: loggedIn, generate: generate)),
      exists: (p) => p == '/fake/bin/claude',
      env: {'PATH': '/fake/bin'},
      home: '/home/u',
      isWindows: false,
      workDir: () async => '/tmp',
    );

ClaudeCli cliMissing() => ClaudeCli(
      run: fakeRun([], (e, a) => const CliResult(1, '', '')),
      exists: (_) => false,
      env: {'PATH': '/fake/bin'},
      home: '/home/u',
      isWindows: false,
      workDir: () async => '/tmp',
    );

LineRun fakeLines(List<List<String>> calls, {List<String> emit = const [], int code = 0, Future<void>? waitFor}) =>
    (exe, args, onLine, {CliJob? job, Duration? timeout, String? cwd}) async {
      calls.add([exe, ...args]);
      emit.forEach(onLine);
      if (waitFor != null) await waitFor;
      return code;
    };

const schema = {
  'type': 'object',
  'properties': {'a': {'type': 'string'}},
  'required': ['a'],
};

class _Streamed extends http.StreamedResponse implements http.BaseResponseWithUrl {
  @override
  final Uri url;
  _Streamed(String body, int status, this.url) : super(Stream.value(utf8.encode(body)), status);
}

/// Giả lập máy chủ chuyển hướng: trả phản hồi mang địa chỉ cuối cùng như `IOClient` thật.
class _RedirectClient extends http.BaseClient {
  final String body;
  final int status;
  final Uri finalUrl;
  _RedirectClient(this.body, this.status, this.finalUrl);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => _Streamed(body, status, finalUrl);
}

void main() {
  group('tìm Claude CLI', () {
    test('đường dẫn nhập tay: đúng thì dùng, sai thì báo không thấy (không tự tìm chỗ khác)', () async {
      final cli = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(1, '', '')), exists: (p) => p == '/opt/claude' || p == '/fake/bin/claude', env: {'PATH': '/fake/bin'}, isWindows: false, home: '/h');
      expect(await cli.find(override: '/opt/claude'), '/opt/claude');
      expect(await cli.find(override: '/sai/duong/dan'), isNull);
      expect(await cli.find(), '/fake/bin/claude');
    });

    test('tìm trong PATH rồi đến các thư mục thường gặp', () async {
      final a = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(1, '', '')), exists: (p) => p == '/b/claude', env: {'PATH': '/a:/b'}, isWindows: false, home: '/h');
      expect(await a.find(), '/b/claude');
      final b = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(1, '', '')), exists: (p) => p == '/h/.local/bin/claude', env: {'PATH': ''}, isWindows: false, home: '/h');
      expect(await b.find(), '/h/.local/bin/claude');
    });

    test('app mở từ menu không có PATH của người dùng: hỏi shell đăng nhập (mise, nvm...)', () async {
      final log = <Call>[];
      final cli = ClaudeCli(
        run: fakeRun(log, (e, a) => CliResult(0, 'nhiễu từ .bashrc\n/x/mise/claude\n', '')),
        exists: (p) => p == '/x/mise/claude',
        env: {'PATH': '/usr/bin', 'SHELL': '/bin/zsh'},
        isWindows: false,
        home: '/h',
      );
      expect(await cli.find(), '/x/mise/claude');
      expect(log.first.exe, '/bin/zsh');
      expect(log.first.args, ['-lc', 'command -v claude']);
    });

    test('không có thì trả null, kể cả khi shell lỗi; kết quả được nhớ và làm mới khi yêu cầu', () async {
      final bad = ClaudeCli(run: (e, a, {String? stdin, Duration timeout = const Duration(minutes: 1), Map<String, String>? env, String? cwd}) async => throw const ProcessException('x', []), exists: (_) => false, env: {'PATH': ''}, isWindows: false, home: '/h');
      expect(await bad.find(), isNull);

      var present = true;
      final log = <Call>[];
      final cli = ClaudeCli(run: fakeRun(log, (e, a) => const CliResult(1, '', '')), exists: (p) => present && p == '/fake/bin/claude', env: {'PATH': '/fake/bin'}, isWindows: false, home: '/h');
      expect(await cli.find(), '/fake/bin/claude');
      present = false;
      expect(await cli.find(), isNull, reason: 'file đã mất nên không dùng bản nhớ');
      present = true;
      expect(await cli.find(refresh: true), '/fake/bin/claude');
    });

    test('Windows: ưu tiên claude.exe, dùng `where` khi không thấy', () async {
      final a = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(1, '', '')), exists: (p) => p == r'C:\Tools\claude.exe', env: {'PATH': r'C:\Tools;C:\Other'}, isWindows: true, home: r'C:\Users\u');
      expect(await a.find(), r'C:\Tools\claude.exe');
      final log = <Call>[];
      final b = ClaudeCli(run: fakeRun(log, (e, a) => const CliResult(0, 'C:\\Users\\u\\AppData\\Roaming\\npm\\claude.cmd\r\n', '')), exists: (p) => p == 'C:\\Users\\u\\AppData\\Roaming\\npm\\claude.cmd', env: {'PATH': ''}, isWindows: true, home: r'C:\Users\u');
      expect(await b.find(), contains('claude.cmd'));
      expect(log.last.exe, 'where');
    });
  });

  group('gọi Claude CLI', () {
    test('dựng đúng lệnh: tắt công cụ, không nạp cấu hình, câu hỏi qua stdin, chạy ở thư mục tạm', () async {
      final log = <Call>[];
      final cli = cliFound(log);
      final r = await cli.generate(path: '/fake/bin/claude', system: 'Chỉ dẫn hệ thống', prompt: 'Câu hỏi "có nháy" & ký tự lạ', schema: schema, model: 'sonnet', effort: 'high');
      final c = log.single;
      expect(c.args, containsAllInOrder(['-p', '--output-format', 'json']));
      expect(c.args, containsAll(['--tools=', '--setting-sources=', '--no-session-persistence']));
      expect(c.args, containsAllInOrder(['--model', 'sonnet']));
      expect(c.args, containsAllInOrder(['--effort', 'high']));
      expect(c.args, containsAllInOrder(['--system-prompt', 'Chỉ dẫn hệ thống']));
      expect(c.args, containsAllInOrder(['--json-schema', jsonEncode(schema)]));
      expect(c.stdin, 'Câu hỏi "có nháy" & ký tự lạ');
      expect(c.cwd, '/tmp');
      expect(r.structured, {'ok': true});
      expect(r.costUsd, 0.0005);
    });

    test('model rỗng hoặc "default" thì không truyền --model', () async {
      for (final m in ['', 'default', '  ']) {
        final log = <Call>[];
        await cliFound(log).generate(path: '/fake/bin/claude', system: 's', prompt: 'p', schema: schema, model: m);
        expect(log.single.args, isNot(contains('--model')), reason: 'model="$m"');
        expect(log.single.args, isNot(contains('--effort')));
      }
    });

    test('không có structured_output thì trả về văn bản để app tự tách JSON', () async {
      final cli = cliFound([], generate: {'is_error': false, 'result': '```json\n{"a":"x"}\n```'});
      final r = await cli.generate(path: '/fake/bin/claude', system: 's', prompt: 'p', schema: schema);
      expect(r.structured, isNull);
      expect(extractJson(r.text), {'a': 'x'});
    });

    test('chưa đăng nhập: báo rõ cách khắc phục', () async {
      final cli = cliFound([], generate: {'is_error': true, 'subtype': 'success', 'result': 'Not logged in · Please run /login'});
      expect(
        () => cli.generate(path: '/fake/bin/claude', system: 's', prompt: 'p', schema: schema),
        throwsA(isA<ClaudeCliException>().having((e) => e.notLoggedIn, 'notLoggedIn', isTrue).having((e) => e.message, 'message', contains('Đăng nhập tài khoản Claude'))),
      );
    });

    test('sai tên model: nêu tên model; hết hạn mức: cho phép thử lại', () async {
      final bad = cliFound([], generate: {'is_error': true, 'result': "There's an issue with the selected model (xyz).", 'api_error_status': 404});
      expect(() => bad.generate(path: '/fake/bin/claude', system: 's', prompt: 'p', schema: schema, model: 'xyz'), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('"xyz"'))));
      final limited = cliFound([], generate: {'is_error': true, 'result': 'Claude AI usage limit reached', 'api_error_status': 429});
      expect(() => limited.generate(path: '/fake/bin/claude', system: 's', prompt: 'p', schema: schema), throwsA(isA<ClaudeCliException>().having((e) => e.retryable, 'retryable', isTrue)));
    });

    test('đầu ra không phải JSON và quá thời gian đều ném lỗi dễ hiểu', () async {
      final noJson = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(1, '', 'segfault')), exists: (_) => true, isWindows: false, workDir: () async => '/tmp');
      expect(() => noJson.generate(path: '/x', system: 's', prompt: 'p', schema: schema), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('Claude CLI báo lỗi: segfault'))));
      final slow = ClaudeCli(run: fakeRun([], (e, a) => const CliResult(-1, '', '', timedOut: true)), exists: (_) => true, isWindows: false, workDir: () async => '/tmp');
      expect(() => slow.generate(path: '/x', system: 's', prompt: 'p', schema: schema, timeout: const Duration(minutes: 2)), throwsA(isA<ClaudeCliException>().having((e) => e.retryable, 'retryable', isTrue).having((e) => e.message, 'message', contains('2 phút'))));
    });

    test('Windows + .cmd (qua cmd.exe): không để ký tự đặc biệt trong đối số, đưa chỉ dẫn và schema vào stdin', () async {
      final log = <Call>[];
      final cli = ClaudeCli(run: fakeRun(log, (e, a) => cliReply(e, a)), exists: (_) => true, isWindows: true, home: r'C:\u', workDir: () async => r'C:\tmp');
      await cli.generate(path: r'C:\npm\claude.cmd', system: 'Chỉ dẫn & "đặc biệt" | ^', prompt: 'Hỏi', schema: schema, model: 'haiku');
      final c = log.single;
      expect(c.args, isNot(contains('--system-prompt')));
      expect(c.args, isNot(contains('--json-schema')));
      expect(c.args.where((a) => a.contains('&') || a.contains('|') || a.contains('"')), isEmpty);
      expect(c.stdin, allOf(contains('Chỉ dẫn & "đặc biệt" | ^'), contains('Hỏi'), contains(jsonEncode(schema))));
    });

    test('đọc phiên bản và trạng thái đăng nhập', () async {
      final cli = cliFound([]);
      expect(await cli.version('/fake/bin/claude'), '2.1.314 (Claude Code)');
      final a = await cli.authStatus('/fake/bin/claude');
      expect([a.loggedIn, a.email, a.method], [true, 'me@example.com', 'claude.ai']);
      final out = await cliFound([], loggedIn: false).authStatus('/fake/bin/claude');
      expect(out.loggedIn, isFalse);
    });
  });

  group('chạy tiến trình thật (script giả thay cho claude)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fake-claude'));
    tearDown(() => dir.deleteSync(recursive: true));

    String script(String name, String body) {
      final f = File('${dir.path}/$name')..writeAsStringSync('#!/bin/bash\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    test('truyền stdin tiếng Việt và đối số đúng, đọc được JSON, version, auth', () async {
      final path = script('ok.sh', '''
case "\$1" in
  --version) echo "9.9.9 (Claude Code)"; exit 0;;
  auth) printf '{"loggedIn":true,"authMethod":"claude.ai","email":"a@b.c"}'; exit 0;;
esac
IN=\$(cat)
printf '{"is_error":false,"result":"{}","total_cost_usd":0.001,"structured_output":{"stdin":"%s","argc":%d}}' "\$IN" "\$#"
''');
      final cli = ClaudeCli();
      expect(await cli.version(path), '9.9.9 (Claude Code)');
      expect((await cli.authStatus(path)).email, 'a@b.c');
      final r = await cli.generate(path: path, system: 'hệ thống', prompt: 'xin chào Việt Nam', schema: schema, model: 'haiku', effort: 'low');
      expect(r.structured!['stdin'], 'xin chào Việt Nam');
      expect(r.structured!['argc'], 14);
    }, skip: Platform.isWindows);

    test('lỗi chưa đăng nhập (mã thoát 1 kèm JSON) được chuyển thành thông báo tiếng Việt', () async {
      final path = script('fail.sh', '''cat >/dev/null; echo '{"is_error":true,"result":"Not logged in · Please run /login"}'; exit 1''');
      expect(() => ClaudeCli().generate(path: path, system: 's', prompt: 'p', schema: schema), throwsA(isA<ClaudeCliException>().having((e) => e.notLoggedIn, 'notLoggedIn', isTrue)));
    }, skip: Platform.isWindows);

    test('quá thời gian thì dừng tiến trình, không treo app', () async {
      final path = script('slow.sh', 'sleep 30');
      final watch = Stopwatch()..start();
      await expectLater(
        ClaudeCli().generate(path: path, system: 's', prompt: 'p', schema: schema, timeout: const Duration(seconds: 1)),
        throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('quá lâu'))),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    }, skip: Platform.isWindows);

    test('runStreaming gửi từng dòng, bỏ dòng trống, hủy được giữa chừng', () async {
      final path = script('lines.sh', 'echo một; echo; echo hai >&2; sleep 30');
      final lines = <String>[];
      final job = CliJob();
      final run = runStreaming(path, const [], lines.add, job: job);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      job.cancel();
      expect(await run.timeout(const Duration(seconds: 10)), -2);
      expect(lines, containsAll(['một', 'hai']));
      expect(lines, isNot(contains('')));
    }, skip: Platform.isWindows);
  });

  group('trình cài đặt', () {
    test('các cách cài theo hệ điều hành; lệnh tương đương khớp tài liệu chính thức', () {
      final linux = claudeInstallOptions(windows: false, hasNpm: false);
      expect(linux.map((o) => o.command), ['curl -fsSL https://claude.ai/install.sh | bash']);
      expect(claudeInstallOptions(windows: false, hasNpm: true).map((o) => o.id), ['script', 'npm']);
      expect(claudeInstallOptions(windows: true, hasNpm: false).single.command, 'irm https://claude.ai/install.ps1 | iex');
      expect(claudeInstallOptions(windows: true, hasNpm: true).last.command, 'npm install -g @anthropic-ai/claude-code');
    });

    test('chỉ chấp nhận tên miền chính thức của Claude', () {
      for (final u in ['https://claude.ai/install.sh', 'https://downloads.claude.ai/claude-code-releases/bootstrap.sh']) {
        expect(isOfficialHost(Uri.parse(u)), isTrue, reason: u);
      }
      for (final u in ['http://claude.ai/install.sh', 'https://evilclaude.ai/x', 'https://claude.ai.evil.com/x', 'https://example.com/claude.ai']) {
        expect(isOfficialHost(Uri.parse(u)), isFalse, reason: u);
      }
    });

    test('tải script, ghi file tạm, chạy bằng bash rồi xóa file tạm', () async {
      final calls = <List<String>>[];
      String? content;
      final root = Directory.systemTemp.createTempSync('install-test');
      addTearDown(() => root.deleteSync(recursive: true));
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://claude.ai/install.sh');
        return http.Response('#!/bin/bash\necho cai-dat', 200);
      });
      final lines = <String>[];
      await installClaudeCli(
        claudeInstallOptions(windows: false, hasNpm: false).first,
        onLine: lines.add,
        client: client,
        windows: false,
        tempRoot: root,
        run: (exe, args, onLine, {CliJob? job, Duration? timeout, String? cwd}) async {
          calls.add([exe, ...args]);
          content = File(args.single).readAsStringSync();
          onLine('đang cài...');
          return 0;
        },
      );
      expect(calls.single.first, 'bash');
      expect(content, contains('cai-dat'));
      expect(lines.join('\n'), allOf(contains('claude.ai/install.sh'), contains('đang cài')));
      expect(root.listSync(), isEmpty, reason: 'đã xóa thư mục tạm');
    });

    test('Windows chạy bằng PowerShell; npm gọi đúng lệnh', () async {
      final calls = <List<String>>[];
      final root = Directory.systemTemp.createTempSync('install-test');
      addTearDown(() => root.deleteSync(recursive: true));
      await installClaudeCli(claudeInstallOptions(windows: true, hasNpm: false).first,
          onLine: (_) {}, client: MockClient((r) async => http.Response('Write-Host hi', 200)), windows: true, tempRoot: root, run: fakeLines(calls));
      expect(calls.single.take(5), ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']);

      final n = <List<String>>[];
      await installClaudeCli(claudeInstallOptions(windows: false, hasNpm: true).last, onLine: (_) {}, windows: false, run: fakeLines(n));
      expect(n.single, ['npm', 'install', '-g', '@anthropic-ai/claude-code']);
    });

    test('từ chối: chuyển hướng ra ngoài tên miền chính thức, HTTP lỗi, script rỗng hoặc quá lớn', () async {
      Future<void> run(http.Client c) => installClaudeCli(claudeInstallOptions(windows: false, hasNpm: false).first, onLine: (_) {}, client: c, windows: false, run: fakeLines([]));
      await expectLater(run(_RedirectClient('x', 200, Uri.parse('https://evil.example.com/a.sh'))), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('evil.example.com'))));
      await expectLater(run(MockClient((r) async => http.Response('error', 500))), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('HTTP 500'))));
      await expectLater(run(MockClient((r) async => http.Response('', 200))), throwsA(isA<ClaudeCliException>()));
      await expectLater(run(MockClient((r) async => http.Response('a' * (2 * 1024 * 1024 + 1), 200))), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('bất thường'))));
    });

    test('script lỗi hoặc bị hủy cho thông báo khác nhau', () async {
      Future<void> run(int code) => installClaudeCli(claudeInstallOptions(windows: false, hasNpm: false).first,
          onLine: (_) {}, client: MockClient((r) async => http.Response('echo', 200)), windows: false, run: fakeLines([], code: code));
      await expectLater(run(3), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('mã 3'))));
      await expectLater(run(-2), throwsA(isA<ClaudeCliException>().having((e) => e.message, 'message', contains('hủy'))));
    });

    test('đăng nhập gọi `claude auth login --claudeai`; tách đường dẫn đăng nhập từ nhật ký', () async {
      final calls = <List<String>>[];
      await claudeLogin('/fake/bin/claude', onLine: (_) {}, run: fakeLines(calls));
      expect(calls.single, ['/fake/bin/claude', 'auth', 'login', '--claudeai']);
      expect(firstHttpsUrl('Nếu trình duyệt không mở: https://claude.ai/oauth/authorize?code=1&x=2 nhé'), 'https://claude.ai/oauth/authorize?code=1&x=2');
      expect(firstHttpsUrl('http://không-https.example'), isNull);
    });
  });

  group('tích hợp nhà cung cấp', () {
    tearDown(() => claudeCli = ClaudeCli());
    AiConfig cfg({String path = '', String model = 'sonnet'}) => AiConfig(presetById('claude_cli'), path, model, '', effort: 'medium');

    test('có trong danh sách trên máy tính, không cần API key, nhãn model mặc định', () {
      expect(availableProviders.map((p) => p.id), contains('claude_cli'));
      final p = presetById('claude_cli');
      expect([p.needsKey, p.local, p.style], [false, false, ApiStyle.claudeCli]);
      expect(cliModelSuggestions, containsAll(['default', 'opus', 'sonnet', 'haiku']));
    });

    test('generateJson dùng Claude CLI, bỏ qua kiểm tra API key và model rỗng', () async {
      final log = <Call>[];
      claudeCli = cliFound(log, generate: {'is_error': false, 'result': '', 'structured_output': {'a': 'xin chào'}});
      final out = await generateJson(cfg(model: ''), system: 'sys', prompt: 'hỏi', schema: schema);
      expect(out, {'a': 'xin chào'});
      expect(log.single.args, isNot(contains('--model')));
    });

    test('tự tách JSON từ văn bản khi CLI không trả structured_output', () async {
      claudeCli = cliFound([], generate: {'is_error': false, 'result': 'Kết quả: {"a":"b"}'});
      expect(await generateJson(cfg(), system: 's', prompt: 'p', schema: schema), {'a': 'b'});
    });

    test('báo lỗi tiếng Việt khi chưa cài, sai đường dẫn, chưa đăng nhập', () async {
      claudeCli = cliMissing();
      await expectLater(generateJson(cfg(), system: 's', prompt: 'p', schema: schema), throwsA(isA<AiException>().having((e) => e.message, 'message', contains('Cài đặt → AI → Claude CLI để cài đặt'))));
      await expectLater(generateJson(cfg(path: '/sai'), system: 's', prompt: 'p', schema: schema), throwsA(isA<AiException>().having((e) => e.message, 'message', contains('"/sai"'))));
      claudeCli = cliFound([], generate: {'is_error': true, 'result': 'Not logged in · Please run /login'});
      await expectLater(generateJson(cfg(), system: 's', prompt: 'p', schema: schema), throwsA(isA<AiException>().having((e) => e.message, 'message', contains('chưa đăng nhập'))));
    });
  });

  group('giao diện mục Claude CLI', () {
    late TextEditingController path, model;
    var saved = 0;

    setUp(() {
      path = TextEditingController();
      model = TextEditingController();
      saved = 0;
    });

    Widget harness(Widget Function() section, {double scale = 1}) => MaterialApp(
          theme: appTheme(Brightness.light),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
          home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: section()))),
        );

    ClaudeCliSection section(ClaudeCli cli, {LineRun? lines, http.Client? client}) => ClaudeCliSection(
          pathController: path,
          modelController: model,
          onChanged: () => saved++,
          cli: cli,
          checkNpm: () async => false,
          lineRun: lines,
          httpClient: client,
        );

    Future<void> pumpSection(WidgetTester tester, ClaudeCliSection s, {Size size = const Size(800, 1000), double scale = 1}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(() => s, scale: scale));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('chưa cài: hiện nút cài, xác nhận nói rõ nguồn và lệnh, Hủy thì không chạy gì', (tester) async {
      final lines = <List<String>>[];
      await pumpSection(tester, section(cliMissing(), lines: fakeLines(lines)));
      expect(find.text('Chưa tìm thấy Claude CLI'), findsOneWidget);
      await tester.tap(find.text('Cài Claude CLI'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Cài Claude CLI?'), findsOneWidget);
      expect(find.textContaining('chính thức của Anthropic từ claude.ai'), findsOneWidget);
      expect(find.text(Platform.isWindows ? 'irm https://claude.ai/install.ps1 | iex' : 'curl -fsSL https://claude.ai/install.sh | bash'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Cài Claude CLI?'), findsNothing);
      expect(lines, isEmpty, reason: 'chưa xác nhận thì không được chạy lệnh nào');
    });

    testWidgets('cài thất bại: nhật ký hiện lý do rõ ràng và có nút Đóng', (tester) async {
      final client = MockClient((r) async => http.Response('error', 500));
      await pumpSection(tester, section(cliMissing(), lines: fakeLines([]), client: client));
      await tester.tap(find.text('Cài Claude CLI'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Cài đặt'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('đã cài và đăng nhập: hiện phiên bản, đường dẫn, tài khoản; chọn model lưu ngay', (tester) async {
      await pumpSection(tester, section(cliFound([])));
      expect(find.textContaining('2.1.314'), findsOneWidget);
      expect(find.text('/fake/bin/claude'), findsOneWidget);
      expect(find.textContaining('me@example.com'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sonnet (mới nhất, cân bằng)').last);
      await tester.pump();
      expect(model.text, 'sonnet');
      expect(saved, greaterThan(0));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Khác… (nhập tên model)').last);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Tên model'), 'claude-opus-5-5');
      expect(model.text, 'claude-opus-5-5');

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Mặc định của CLI').last);
      await tester.pump();
      expect(model.text, isEmpty, reason: 'rỗng nghĩa là dùng model mặc định của CLI');
    });

    testWidgets('thử model: báo thành công kèm thời gian, hoặc lý do lỗi', (tester) async {
      await pumpSection(tester, section(cliFound([])));
      await tester.tap(find.text('Thử model đã chọn'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Hoạt động tốt: model mặc định trả lời sau'), findsOneWidget);

      final bad = cliFound([], generate: {'is_error': true, 'result': "There's an issue with the selected model (xyz).", 'api_error_status': 404});
      await pumpSection(tester, section(bad));
      await tester.tap(find.text('Thử model đã chọn'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('không tồn tại hoặc tài khoản của bạn không được dùng'), findsOneWidget);
    });

    testWidgets('chưa đăng nhập: nút thử bị khóa; đăng nhập hiện nhật ký và nút mở trang đăng nhập', (tester) async {
      final done = Completer<void>();
      final lines = <List<String>>[];
      await pumpSection(
        tester,
        section(cliFound([], loggedIn: false), lines: fakeLines(lines, emit: ['Đang mở trình duyệt. Nếu không mở, vào https://claude.ai/oauth/authorize?x=1'], waitFor: done.future)),
      );
      expect(find.text('Chưa đăng nhập tài khoản Claude'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Thử model đã chọn')).onPressed, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập tài khoản Claude'));
      await tester.pump();
      await tester.pump();
      expect(lines.single, ['/fake/bin/claude', 'auth', 'login', '--claudeai']);
      expect(find.text('Mở trang đăng nhập'), findsOneWidget);
      expect(find.textContaining('Đang chạy'), findsOneWidget);

      done.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Đăng nhập xong.'), findsOneWidget);
      expect(find.text('Mở trang đăng nhập'), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pump();
    });

    testWidgets('không tràn bố cục ở điện thoại 375 px và cỡ chữ lớn, mọi trạng thái', (tester) async {
      final states = <ClaudeCli>[cliMissing(), cliFound([]), cliFound([], loggedIn: false)];
      for (final cli in states) {
        for (final scale in [1.0, 1.8]) {
          await pumpSection(tester, section(cli), size: const Size(375, 900), scale: scale);
          expect(tester.takeException(), isNull, reason: 'scale $scale');
        }
      }
    });

    testWidgets('mục tiêu chạm của các nút chính ≥ 48 px', (tester) async {
      await pumpSection(tester, section(cliMissing()), size: const Size(375, 900));
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Cài Claude CLI')).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Kiểm tra lại')).height, greaterThanOrEqualTo(48));
    });
  });
}
