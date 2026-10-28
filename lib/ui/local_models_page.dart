import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/downloads.dart';
import '../services/hardware.dart';
import '../services/huggingface.dart';
import '../services/llama_runtime.dart';
import '../state.dart';
import 'widgets.dart';

class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

/// Một lượt tải đang chạy.
class _Job {
  final CancelToken cancel = CancelToken();
  int received = 0;
  int? total;
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  Hardware? _hw;
  List<ModelInfo> _catalog = [];
  List<File> _downloaded = [];
  final Map<String, _Job> _jobs = {}; // tên file → lượt tải
  Map<String, dynamic>? _engine;
  bool _engineBusy = false;

  // Tìm trên Hugging Face
  final _query = TextEditingController();
  bool _searching = false;
  List<HfRepo> _repos = [];
  String? _openRepo;
  List<HfFile> _repoFiles = [];
  String? _searchError;

  // Ollama
  Set<String> _ollamaModels = {};
  bool _ollamaUp = false;
  final Map<String, (String, double?)> _pulling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  AppState get _state => AppScope.of(context);
  String get _ollamaUrl => _state.baseUrlOf('ollama');

  Future<void> _load() async {
    final results = await Future.wait([detectHardware(), loadModelCatalog()]);
    if (!mounted) return;
    setState(() {
      _hw = results[0] as Hardware;
      _catalog = results[1] as List<ModelInfo>;
    });
    await Future.wait([_refreshDownloaded(), _refreshEngine(), _refreshOllama()]);
  }

  Future<void> _refreshDownloaded() async {
    final dir = _state.modelsDir;
    final files = await dir.exists()
        ? (await dir.list().where((e) => e is File && e.path.endsWith('.gguf')).cast<File>().toList())
        : <File>[];
    files.sort((a, b) => a.path.compareTo(b.path));
    if (mounted) setState(() => _downloaded = files);
  }

  Future<void> _refreshEngine() async {
    if (!embeddedSupported) return;
    final info = await _state.runtime.installed();
    if (mounted) setState(() => _engine = info);
  }

  Future<void> _refreshOllama() async {
    final up = await ollamaRunning(_ollamaUrl);
    final installed = up ? await ollamaInstalled(_ollamaUrl) : <String>{};
    if (mounted) {
      setState(() {
        _ollamaUp = up;
        _ollamaModels = installed;
      });
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  File _fileFor(String name) => File('${_state.modelsDir.path}${Platform.pathSeparator}${name.split('/').last}');

  Future<void> _download(HfFile f, {bool useAfter = true}) async {
    final key = f.name;
    if (_jobs.containsKey(key)) return;
    final job = _Job();
    setState(() => _jobs[key] = job);
    try {
      final dest = await downloadFile(f.url, _fileFor(f.name), cancel: job.cancel, onProgress: (got, total) {
        if (mounted) {
          setState(() {
            job.received = got;
            job.total = total;
          });
        }
      });
      _snack('Đã tải xong ${f.name}.');
      if (useAfter) _use(dest.path);
    } on DownloadCancelled {
      _snack('Đã tạm dừng tải ${f.name}. Bấm tải lại để tiếp tục từ chỗ dừng.');
    } catch (e) {
      _snack('Không tải được ${f.name}: $e');
    } finally {
      if (mounted) setState(() => _jobs.remove(key));
      await _refreshDownloaded();
    }
  }

  void _use(String path) {
    _state.setEmbeddedModel(path);
    _state.setProvider('embedded');
    _snack('Đang dùng ${path.split(Platform.pathSeparator).last} (chạy trong app).');
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa model?'),
        content: Text('Xóa ${f.path.split(Platform.pathSeparator).last} khỏi máy để giải phóng dung lượng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    if (_state.runtime.loadedModel == f.path) await _state.runtime.stop();
    if (_state.embeddedModel == f.path) _state.setEmbeddedModel(null);
    await f.delete();
    await _refreshDownloaded();
  }

  Future<void> _installEngine() async {
    setState(() => _engineBusy = true);
    try {
      await _state.runtime.ensureInstalled(onStatus: (s, p) {
        if (mounted) setState(() => _state.engineStatus = s);
      });
      _snack('Engine llama.cpp đã sẵn sàng.');
    } catch (e) {
      _snack('Không cài được engine: $e');
    } finally {
      _state.engineStatus = null;
      if (mounted) setState(() => _engineBusy = false);
      await _refreshEngine();
    }
  }

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _openRepo = null;
    });
    try {
      final repos = await searchGgufRepos(_query.text);
      setState(() => _repos = repos);
    } catch (e) {
      setState(() => _searchError = e.toString());
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _openRepoFiles(String repo) async {
    setState(() {
      _openRepo = repo;
      _repoFiles = [];
      _searchError = null;
    });
    try {
      final files = await listGgufFiles(repo);
      if (mounted && _openRepo == repo) setState(() => _repoFiles = files);
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString());
    }
  }

  Future<void> _pullOllama(ModelInfo m) async {
    setState(() => _pulling[m.ollama] = ('Bắt đầu tải…', null));
    try {
      await ollamaPull(_ollamaUrl, m.ollama, (status, progress) {
        if (mounted) setState(() => _pulling[m.ollama] = (status, progress));
      });
      _snack('Đã tải xong ${m.name} bằng Ollama.');
    } catch (e) {
      _snack('Không tải được ${m.name}: $e');
    } finally {
      if (mounted) setState(() => _pulling.remove(m.ollama));
      await _refreshOllama();
    }
  }

  Future<void> _useOllama(ModelInfo m) async {
    await _state.setProviderConfig('ollama', model: m.ollama);
    _state.setProvider('ollama');
    _snack('Đã chuyển sang Ollama · ${m.ollama}');
  }

  // ---------- Giao diện ----------
  @override
  Widget build(BuildContext context) {
    final hw = _hw;
    final text = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    final best = hw == null ? null : recommend(_catalog, hw);

    Widget card(String title, List<Widget> children, {Widget? trailing}) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(title, style: text.titleMedium)), ?trailing]),
              const SizedBox(height: 10),
              ...children,
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Model trên máy')),
      body: hw == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    card('Cấu hình máy', [
                      Wrap(spacing: 24, runSpacing: 10, children: [
                        Kv('Hệ điều hành', Text(hw.os)),
                        Kv('CPU', Text('${hw.cpu} (${hw.cores} luồng)')),
                        Kv('RAM', Text('${fmt(hw.ramGb, 1)} GB')),
                        Kv('GPU', Text(hw.gpu ?? 'Không phát hiện GPU rời')),
                        if (hw.vramGb != null) Kv('VRAM', Text('${fmt(hw.vramGb, 1)} GB')),
                      ]),
                      const SizedBox(height: 12),
                      Text(_verdict(hw)),
                      if (best != null) ...[
                        const SizedBox(height: 8),
                        Text.rich(TextSpan(children: [
                          const TextSpan(text: 'Đề xuất: ', style: TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: '${best.name} (${fmt(best.sizeGb, 1)} GB). ${best.note}'),
                        ])),
                      ],
                    ]),
                    const SizedBox(height: 14),
                    if (embeddedSupported) ...[
                      _engineCard(card, state, text),
                      const SizedBox(height: 14),
                      if (_downloaded.isNotEmpty) ...[
                        card('Model đã tải', [for (final f in _downloaded) _downloadedTile(f, state)]),
                        const SizedBox(height: 14),
                      ],
                      card('Model đề xuất (tải từ Hugging Face)', [
                        Text('Bấm "Tải" để tải file GGUF trực tiếp từ Hugging Face và chạy ngay trong app. '
                            'Tải bị ngắt thì bấm lại để tải tiếp.', style: text.bodySmall),
                        const SizedBox(height: 10),
                        for (final m in _catalog) _catalogTile(m, hw, m == best),
                      ]),
                      const SizedBox(height: 14),
                      _searchCard(card, hw, text),
                      const SizedBox(height: 14),
                    ] else ...[
                      card('Chạy trong app', [
                        Text('Android chưa hỗ trợ chạy model ngay trong app. Hãy dùng AI qua API, hoặc trỏ tới Ollama/LM Studio '
                            'trên máy tính trong cùng mạng Wi-Fi (Cài đặt → AI → địa chỉ http://<IP máy tính>:11434/v1).'),
                      ]),
                      const SizedBox(height: 14),
                    ],
                    _ollamaCard(card, hw, text),
                    const SizedBox(height: 12),
                    Text('Model chạy trên máy cho chất lượng phân tích thấp hơn các model lớn qua API. '
                        'Danh sách đề xuất và phiên bản engine được cập nhật tự động từ GitHub.', style: text.bodySmall),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _engineCard(Widget Function(String, List<Widget>, {Widget? trailing}) card, AppState state, TextTheme text) {
    final installed = _engine;
    final status = state.engineStatus;
    return card('Engine chạy model (llama.cpp)', [
      if (installed != null)
        Text('Đã cài llama.cpp ${installed['build']} (${installed['variant']}). Engine tự cập nhật khi có phiên bản mới.')
      else
        const Text('Chưa cài. Engine (~15–35 MB) sẽ tự tải khi bạn chạy model lần đầu, hoặc bấm "Cài engine".'),
      if (state.runtime.running)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Đang chạy: ${state.runtime.loadedModel?.split(Platform.pathSeparator).last}',
              style: TextStyle(color: Tone.up(context))),
        ),
      if (status != null) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(value: state.engineProgress),
        const SizedBox(height: 4),
        Text(status, style: text.bodySmall),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        if (installed == null)
          FilledButton.tonal(onPressed: _engineBusy ? null : _installEngine, child: const Text('Cài engine')),
        if (state.runtime.running)
          OutlinedButton(
            onPressed: () async {
              await state.runtime.stop();
              setState(() {});
            },
            child: const Text('Dừng model (giải phóng bộ nhớ)'),
          ),
      ]),
    ]);
  }

  Widget _progress(_Job job) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LinearProgressIndicator(value: job.total == null ? null : job.received / job.total!),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: Text(
              '${formatBytes(job.received)}${job.total == null ? '' : ' / ${formatBytes(job.total!)} · ${(job.received / job.total! * 100).toStringAsFixed(0)}%'}',
              style: text.bodySmall),
        ),
        TextButton(onPressed: () => setState(job.cancel.cancel), child: const Text('Tạm dừng')),
      ]),
    ]);
  }

  (String, Color) _fitLabel(Fit fit) => switch (fit) {
        Fit.fast => ('Chạy tốt', Tone.up(context)),
        Fit.slow => ('Chạy được, chậm', Tone.flat(context)),
        Fit.no => ('Không đủ bộ nhớ', Tone.down(context)),
      };

  Widget _downloadedTile(File f, AppState state) {
    final name = f.path.split(Platform.pathSeparator).last;
    final active = state.providerId == 'embedded' && state.embeddedModel == f.path;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(active ? Icons.check_circle : Icons.memory, color: active ? Tone.up(context) : null),
      title: Text(name),
      subtitle: Text(formatBytes(f.lengthSync())),
      trailing: Wrap(spacing: 4, children: [
        if (!active) FilledButton.tonal(onPressed: () => _use(f.path), child: const Text('Dùng')),
        IconButton(onPressed: () => _delete(f), icon: const Icon(Icons.delete_outline), tooltip: 'Xóa'),
      ]),
    );
  }

  Widget _catalogTile(ModelInfo m, Hardware hw, bool recommended) {
    final text = Theme.of(context).textTheme;
    final (label, color) = _fitLabel(m.fitFor(hw));
    final file = _fileFor(m.hfFile);
    final have = file.existsSync();
    final job = _jobs[m.hfFile];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: recommended ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
          width: recommended ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(m.name, style: text.titleSmall),
          Tag(label, color: color),
          if (recommended) Tag('Đề xuất', color: Theme.of(context).colorScheme.primary),
          if (have) Tag('Đã tải', color: Tone.up(context)),
          Text('${fmt(m.sizeGb, 1)} GB · chất lượng ${'★' * m.quality}${'☆' * (5 - m.quality)}', style: text.bodySmall),
        ]),
        const SizedBox(height: 4),
        Text(m.note, style: text.bodySmall),
        Text('${m.hfRepo} / ${m.hfFile}', style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (job != null)
          _progress(job)
        else
          Wrap(spacing: 8, children: [
            if (have)
              FilledButton.tonal(onPressed: () => _use(file.path), child: const Text('Dùng model này'))
            else
              FilledButton.tonalIcon(
                onPressed: () => _download(HfFile(m.hfRepo, m.hfFile, (m.sizeGb * 1e9).round())),
                icon: const Icon(Icons.download),
                label: Text('Tải (${fmt(m.sizeGb, 1)} GB)'),
              ),
          ]),
      ]),
    );
  }

  Widget _searchCard(Widget Function(String, List<Widget>, {Widget? trailing}) card, Hardware hw, TextTheme text) {
    return card('Tìm model khác trên Hugging Face', [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(hintText: 'Ví dụ: qwen3, gemma 3, llama 3.1, vistral', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _searching ? null : _search, child: const Text('Tìm')),
      ]),
      if (_searching) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (_searchError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_searchError!, style: TextStyle(color: Tone.down(context)))),
      if (_openRepo != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          IconButton(onPressed: () => setState(() => _openRepo = null), icon: const Icon(Icons.arrow_back), tooltip: 'Quay lại kết quả'),
          Expanded(child: Text(_openRepo!, style: text.titleSmall)),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('https://huggingface.co/$_openRepo'), mode: LaunchMode.externalApplication),
            child: const Text('Xem trên Hugging Face'),
          ),
        ]),
        if (_repoFiles.isEmpty && _searchError == null) const LinearProgressIndicator(),
        for (final f in _repoFiles) _fileTile(f, hw, f == pickDefault(_repoFiles)),
      ] else
        for (final r in _repos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.id),
            subtitle: Text('${fmt(r.downloads, 0)} lượt tải · ${fmt(r.likes, 0)} lượt thích'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openRepoFiles(r.id),
          ),
    ]);
  }

  Widget _fileTile(HfFile f, Hardware hw, bool suggested) {
    final (label, color) = _fitLabel(ModelInfo.size(f.sizeGb).fitFor(hw));
    final file = _fileFor(f.name);
    final job = _jobs[f.name];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(f.name.split('/').last, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (f.quant.isNotEmpty) Tag(f.quant),
          Tag(label, color: color),
          if (suggested) Tag('Nên chọn', color: Theme.of(context).colorScheme.primary),
          Text(formatBytes(f.size), style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 6),
        if (job != null)
          _progress(job)
        else if (file.existsSync())
          FilledButton.tonal(onPressed: () => _use(file.path), child: const Text('Dùng model này'))
        else
          OutlinedButton.icon(onPressed: () => _download(f), icon: const Icon(Icons.download), label: const Text('Tải')),
      ]),
    );
  }

  Widget _ollamaCard(Widget Function(String, List<Widget>, {Widget? trailing}) card, Hardware hw, TextTheme text) {
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: const Text('Dùng Ollama hoặc LM Studio (tùy chọn)'),
        subtitle: Text(_ollamaUp ? 'Ollama đang chạy tại ${ollamaHost(_ollamaUrl)}' : 'Chưa phát hiện Ollama', style: text.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_ollamaUp)
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://ollama.com/download'), mode: LaunchMode.externalApplication),
                child: const Text('Tải Ollama'),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://lmstudio.ai'), mode: LaunchMode.externalApplication),
                child: const Text('Tải LM Studio'),
              ),
              TextButton(onPressed: _refreshOllama, child: const Text('Kiểm tra lại')),
            ]),
          for (final m in _catalog)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${m.name} (${m.ollama})'),
              subtitle: _pulling[m.ollama] == null
                  ? null
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      LinearProgressIndicator(value: _pulling[m.ollama]!.$2),
                      Text(_pulling[m.ollama]!.$1, style: text.bodySmall),
                    ]),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: 'Chép tên để tìm trong LM Studio',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: m.search));
                    _snack('Đã chép "${m.search}". Dán vào ô tìm kiếm (Discover) của LM Studio.');
                  },
                ),
                if (_ollamaModels.contains(m.ollama))
                  TextButton(onPressed: () => _useOllama(m), child: const Text('Dùng'))
                else
                  TextButton(onPressed: _ollamaUp && _pulling[m.ollama] == null ? () => _pullOllama(m) : null, child: const Text('Tải bằng Ollama')),
              ]),
            ),
        ],
      ),
    );
  }

  String _verdict(Hardware hw) {
    if (hw.os == 'Android') {
      return 'Điện thoại chỉ chạy được model rất nhỏ và chậm. Nên dùng AI qua API hoặc Ollama/LM Studio trên máy tính.';
    }
    if (hw.appleSilicon) {
      return 'Apple Silicon dùng chung RAM cho GPU: khoảng ${fmt(hw.gpuBudgetGb, 0)} GB có thể dành cho model, chạy nhanh.';
    }
    if ((hw.vramGb ?? 0) >= 6) {
      return 'GPU ${fmt(hw.vramGb, 0)} GB VRAM: model vừa VRAM chạy nhanh; model lớn hơn tự chia một phần sang RAM và chậm hơn.';
    }
    if ((hw.vramGb ?? 0) > 0) {
      return 'GPU ${fmt(hw.vramGb, 0)} GB VRAM: model nhỏ (≤ 4B) chạy nhanh; model lớn hơn tự chia sang RAM/CPU, chậm hơn.';
    }
    return 'Không có GPU rời đủ mạnh: model chạy bằng CPU. Nên chọn model ≤ 8B để có tốc độ chấp nhận được.';
  }
}
