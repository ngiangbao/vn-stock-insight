// Mục "Claude CLI" trong Cài đặt → AI: tìm CLI, cài nếu chưa có, đăng nhập, chọn model, thử kết nối.
// Theo skill ui-ux-pro-max: trạng thái luôn có biểu tượng + chữ (không chỉ màu), vùng thông báo live-region, nhãn luôn hiện,
// mục tiêu chạm ≥ 48 px, hành động có tác dụng phụ (cài đặt) phải qua hộp thoại xác nhận nói rõ lệnh sẽ chạy, có phản hồi tiến trình.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../ai/providers.dart' show cliModelSuggestions;
import '../services/claude_cli.dart';
import '../services/claude_cli_install.dart';

const _modelLabels = {
  'default': 'Mặc định của CLI',
  'fable': 'Fable (mới nhất, mạnh nhất)',
  'opus': 'Opus (mới nhất)',
  'sonnet': 'Sonnet (mới nhất, cân bằng)',
  'haiku': 'Haiku (nhanh, tiết kiệm)',
};
const _customChoice = '__custom__';

enum _Phase { checking, notFound, ready }

class ClaudeCliSection extends StatefulWidget {
  /// Ô đường dẫn tới `claude` (để trống = tự tìm) và ô model (để trống = mặc định); thuộc trang Cài đặt để nút "Lưu" dùng chung.
  final TextEditingController pathController, modelController;
  final VoidCallback onChanged;

  /// Chỉ dùng khi kiểm thử.
  final ClaudeCli? cli;
  final Future<bool> Function()? checkNpm;
  final LineRun? lineRun;
  final http.Client? httpClient;

  const ClaudeCliSection({
    super.key,
    required this.pathController,
    required this.modelController,
    required this.onChanged,
    this.cli,
    this.checkNpm,
    this.lineRun,
    this.httpClient,
  });

  @override
  State<ClaudeCliSection> createState() => _ClaudeCliSectionState();
}

class _ClaudeCliSectionState extends State<ClaudeCliSection> {
  _Phase _phase = _Phase.checking;
  String? _path, _version;
  CliAuth? _auth;
  bool _testing = false, _testOk = false;
  String? _testMsg;
  late String _choice;

  ClaudeCli get _cli => widget.cli ?? claudeCli;

  @override
  void initState() {
    super.initState();
    _choice = _choiceFor(widget.modelController.text);
    if (ClaudeCli.supported) _check();
  }

  String _choiceFor(String model) {
    final m = model.trim();
    if (m.isEmpty) return 'default';
    return cliModelSuggestions.contains(m) ? m : _customChoice;
  }

  Future<void> _check({bool refresh = false}) async {
    setState(() {
      _phase = _Phase.checking;
      _testMsg = null;
    });
    final path = await _cli.find(override: widget.pathController.text, refresh: refresh);
    if (!mounted) return;
    if (path == null) {
      setState(() => _phase = _Phase.notFound);
      return;
    }
    final results = await Future.wait([_cli.version(path), _cli.authStatus(path)]);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ready;
      _path = path;
      _version = results[0] as String?;
      _auth = results[1] as CliAuth;
    });
  }

  Future<void> _install() async {
    final npm = await (widget.checkNpm ?? hasNpm)();
    if (!mounted) return;
    final chosen = await showDialog<InstallOption>(
      context: context,
      builder: (_) => _InstallConfirm(claudeInstallOptions(windows: Platform.isWindows, hasNpm: npm)),
    );
    if (chosen == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LogDialog(
        title: 'Cài Claude CLI',
        doneText: 'Đã cài xong. App sẽ tự tìm lại Claude CLI.',
        task: (log, job) => installClaudeCli(chosen, onLine: log, job: job, run: widget.lineRun, client: widget.httpClient),
      ),
    );
    if (mounted) await _check(refresh: true);
  }

  Future<void> _login() async {
    final path = _path;
    if (path == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LogDialog(
        title: 'Đăng nhập tài khoản Claude',
        doneText: 'Đăng nhập xong.',
        showLoginLink: true,
        task: (log, job) async {
          final code = await claudeLogin(path, onLine: log, job: job, run: widget.lineRun);
          if (code != 0) throw ClaudeCliException(code == -2 ? 'Đã hủy đăng nhập.' : 'Đăng nhập chưa hoàn tất (mã $code).');
        },
      ),
    );
    if (mounted) await _check(refresh: true);
  }

  Future<void> _test() async {
    final path = _path;
    if (path == null) return;
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    final watch = Stopwatch()..start();
    try {
      await _cli.generate(
        path: path,
        system: 'Trả lời ngắn gọn.',
        prompt: 'Trả về {"ok": true}.',
        schema: {
          'type': 'object',
          'properties': {'ok': {'type': 'boolean'}},
          'required': ['ok'],
          'additionalProperties': false,
        },
        model: widget.modelController.text,
        timeout: const Duration(seconds: 90),
      );
      final m = widget.modelController.text.trim();
      _testOk = true;
      _testMsg = 'Hoạt động tốt: model ${m.isEmpty ? 'mặc định' : m} trả lời sau ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} giây.';
    } on ClaudeCliException catch (e) {
      _testOk = false;
      _testMsg = e.message;
    } catch (e) {
      _testOk = false;
      _testMsg = 'Không thử được: $e';
    }
    if (mounted) setState(() => _testing = false);
  }

  void _chooseModel(String? v) {
    if (v == null) return;
    setState(() => _choice = v);
    if (v == 'default') {
      widget.modelController.text = '';
    } else if (v != _customChoice) {
      widget.modelController.text = v;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (!ClaudeCli.supported) {
      return Text('Claude CLI chỉ dùng được trên máy tính (Windows, macOS, Linux). Hãy chọn nhà cung cấp khác trên thiết bị này.', style: text.bodyMedium);
    }

    Widget statusRow(IconData icon, String title, {String? detail, Color? color}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color ?? cs.onSurface, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.titleSmall),
              if (detail != null) SelectableText(detail, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]);

    final loggedIn = _auth?.loggedIn ?? false;
    final ready = _phase == _Phase.ready;
    final status = switch (_phase) {
      _Phase.checking => Row(children: [
          const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Text('Đang tìm Claude CLI…', style: text.titleSmall),
        ]),
      _Phase.notFound => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statusRow(
            Icons.error_outline,
            'Chưa tìm thấy Claude CLI',
            detail: widget.pathController.text.trim().isEmpty
                ? 'Máy này chưa cài, hoặc cài ở nơi app không tìm thấy. Bấm "Cài Claude CLI" để cài, hoặc nhập đường dẫn bên dưới.'
                : 'Không có chương trình nào tại đường dẫn bạn đã nhập.',
            color: cs.error,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _install,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.download),
              label: const Text('Cài Claude CLI'),
            ),
            OutlinedButton.icon(
              onPressed: () => _check(refresh: true),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh),
              label: const Text('Kiểm tra lại'),
            ),
          ]),
        ]),
      _Phase.ready => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statusRow(Icons.check_circle_outline, 'Đã tìm thấy Claude CLI${_version == null ? '' : ' · $_version'}', detail: _path, color: cs.primary),
          const SizedBox(height: 12),
          if (loggedIn)
            statusRow(Icons.verified_user_outlined, 'Đã đăng nhập${_auth!.email == null ? '' : ': ${_auth!.email}'}',
                detail: _auth!.method == null ? null : 'Hình thức: ${_auth!.method}', color: cs.primary)
          else ...[
            statusRow(Icons.warning_amber_outlined, 'Chưa đăng nhập tài khoản Claude',
                detail: 'Cần đăng nhập để Claude CLI trả lời được. Dùng gói Claude Pro/Max của bạn, không cần API key.', color: cs.error),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _login,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.login),
                label: const Text('Đăng nhập tài khoản Claude'),
              ),
            ),
          ],
        ]),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        liveRegion: true,
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(padding: const EdgeInsets.all(14), child: status),
        ),
      ),
      const SizedBox(height: 14),
      Focus(
        onFocusChange: (f) {
          if (!f) {
            widget.onChanged();
            _check(refresh: true);
          }
        },
        child: TextField(
          controller: widget.pathController,
          decoration: const InputDecoration(
            labelText: 'Đường dẫn tới claude (tùy chọn)',
            helperText: 'Để trống để app tự tìm. Chỉ cần nhập nếu đã cài ở chỗ khác.',
          ),
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: ValueKey('cli-model-$_choice'),
        initialValue: _choice,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Model của Claude CLI', helperText: 'Bí danh luôn trỏ tới bản mới nhất của dòng model đó'),
        items: [
          for (final m in cliModelSuggestions)
            DropdownMenuItem(value: m, child: Text(_modelLabels[m] ?? m, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(value: _customChoice, child: Text('Khác… (nhập tên model)', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _chooseModel,
      ),
      if (_choice == _customChoice) ...[
        const SizedBox(height: 12),
        Focus(
          onFocusChange: (f) => f ? null : widget.onChanged(),
          child: TextField(
            controller: widget.modelController,
            decoration: const InputDecoration(labelText: 'Tên model', helperText: 'Ví dụ: claude-opus-5-5. CLI sẽ báo nếu tên không đúng.'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
      const SizedBox(height: 14),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: ready && loggedIn && !_testing ? _test : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: _testing ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt_outlined),
          label: Text(_testing ? 'Đang thử…' : 'Thử model đã chọn'),
        ),
        Text('Gửi một câu hỏi rất ngắn, tốn không đáng kể trong gói của bạn.', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
      if (_testMsg != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Semantics(
            liveRegion: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_testOk ? Icons.check_circle_outline : Icons.error_outline, size: 20, color: _testOk ? cs.primary : cs.error),
              const SizedBox(width: 8),
              Expanded(child: Text(_testMsg!, style: text.bodyMedium?.copyWith(color: _testOk ? null : cs.error))),
            ]),
          ),
        ),
    ]);
  }
}

/// Hộp thoại xác nhận trước khi cài: nói rõ nguồn và lệnh tương đương sẽ chạy.
class _InstallConfirm extends StatefulWidget {
  final List<InstallOption> options;
  const _InstallConfirm(this.options);

  @override
  State<_InstallConfirm> createState() => _InstallConfirmState();
}

class _InstallConfirmState extends State<_InstallConfirm> {
  late InstallOption _chosen = widget.options.first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Cài Claude CLI?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('App sẽ tải chương trình cài đặt chính thức của Anthropic từ claude.ai rồi chạy trên máy bạn. Chỉ tiếp tục nếu bạn tin tưởng.'),
            const SizedBox(height: 12),
            RadioGroup<InstallOption>(
              groupValue: _chosen,
              onChanged: (v) => setState(() => _chosen = v ?? _chosen),
              child: Column(children: [
                for (final o in widget.options)
                  RadioListTile<InstallOption>(
                    value: o,
                    contentPadding: EdgeInsets.zero,
                    title: Text(o.title),
                    subtitle: Text(o.detail),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Lệnh tương đương:', style: text.labelLarge),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SelectableText(_chosen.command, style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context, _chosen),
          child: const Text('Cài đặt'),
        ),
      ],
    );
  }
}

/// Hộp thoại chạy một tác vụ dài và hiện nhật ký từng dòng; có nút Hủy, báo kết quả bằng biểu tượng + chữ.
class _LogDialog extends StatefulWidget {
  final String title, doneText;
  final bool showLoginLink;
  final Future<void> Function(void Function(String line) log, CliJob job) task;
  const _LogDialog({required this.title, required this.doneText, required this.task, this.showLoginLink = false});

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final _lines = <String>[];
  final _scroll = ScrollController();
  final _job = CliJob();
  bool _running = true;
  String? _error, _url;

  @override
  void initState() {
    super.initState();
    widget.task(_add, _job).then((_) {
      if (mounted) setState(() => _running = false);
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e is ClaudeCliException ? e.message : '$e';
        });
      }
    });
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() {
      _lines.add(line);
      if (widget.showLoginLink) _url ??= firstHttpsUrl(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final statusText = _running ? 'Đang chạy…' : (_error ?? widget.doneText);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 320,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            liveRegion: true,
            child: Row(children: [
              if (_running)
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                Icon(_error == null ? Icons.check_circle_outline : Icons.error_outline, size: 20, color: _error == null ? cs.primary : cs.error),
              const SizedBox(width: 10),
              Expanded(child: Text(statusText, style: text.titleSmall?.copyWith(color: _error == null ? null : cs.error))),
            ]),
          ),
          if (_url != null && _running) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Nếu trình duyệt không tự mở, bấm nút để đăng nhập:', style: text.bodySmall)),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication),
                child: const Text('Mở trang đăng nhập'),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: _lines.length,
                itemBuilder: (_, i) => SelectableText(_lines[i], style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        if (_running)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _job.cancel,
            child: const Text('Hủy'),
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
      ],
    );
  }
}
