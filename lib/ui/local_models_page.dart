import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hardware.dart';
import '../state.dart';
import 'widgets.dart';

class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  Hardware? _hw;
  List<ModelInfo> _models = [];
  Set<String> _installed = {};
  bool _ollamaUp = false;
  final Map<String, (String, double?)> _pulling = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _ollamaUrl => AppScope.of(context).baseUrlOf('ollama');

  Future<void> _load() async {
    final results = await Future.wait([detectHardware(), loadModelCatalog()]);
    if (!mounted) return;
    setState(() {
      _hw = results[0] as Hardware;
      _models = results[1] as List<ModelInfo>;
    });
    await _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    final url = _ollamaUrl;
    final up = await ollamaRunning(url);
    final installed = up ? await ollamaInstalled(url) : <String>{};
    if (mounted) {
      setState(() {
        _installed = installed;
        _ollamaUp = up;
      });
    }
  }

  bool _isInstalled(ModelInfo m) =>
      _installed.contains(m.ollama) || (!m.ollama.contains(':') && _installed.contains('${m.ollama}:latest'));

  Future<void> _pull(ModelInfo m) async {
    setState(() => _pulling[m.ollama] = ('Bắt đầu tải…', null));
    try {
      await ollamaPull(_ollamaUrl, m.ollama, (status, progress) {
        if (mounted) setState(() => _pulling[m.ollama] = (status, progress));
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tải xong ${m.name}.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tải được ${m.name}: $e')));
    } finally {
      if (mounted) setState(() => _pulling.remove(m.ollama));
      await _refreshInstalled();
    }
  }

  Future<void> _use(ModelInfo m) async {
    final state = AppScope.of(context);
    await state.setProviderConfig('ollama', model: m.ollama);
    state.setProvider('ollama');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã chuyển sang Ollama · ${m.ollama}')));
  }

  @override
  Widget build(BuildContext context) {
    final hw = _hw;
    final text = Theme.of(context).textTheme;
    final best = hw == null ? null : recommend(_models, hw);

    return Scaffold(
      appBar: AppBar(title: const Text('Model trên máy')),
      body: hw == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Cấu hình máy', style: text.titleMedium),
                          const SizedBox(height: 10),
                          Wrap(spacing: 24, runSpacing: 10, children: [
                            Kv('Hệ điều hành', Text(hw.os)),
                            Kv('CPU', Text('${hw.cpu} (${hw.cores} luồng)')),
                            Kv('RAM', Text('${fmt(hw.ramGb, 1)} GB')),
                            Kv('GPU', Text(hw.gpu ?? 'Không phát hiện GPU rời')),
                            if (hw.vramGb != null) Kv('VRAM', Text('${fmt(hw.vramGb, 1)} GB')),
                          ]),
                          const SizedBox(height: 12),
                          Text(_verdict(hw), style: text.bodyMedium),
                          if (best != null) ...[
                            const SizedBox(height: 10),
                            Text.rich(TextSpan(children: [
                              const TextSpan(text: 'Đề xuất: ', style: TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: '${best.name} (${fmt(best.sizeGb, 1)} GB). ${best.note}'),
                            ])),
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(_ollamaUp ? Icons.check_circle : Icons.error_outline,
                                color: _ollamaUp ? Tone.up(context) : Tone.flat(context), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_ollamaUp
                                  ? 'Ollama đang chạy tại ${ollamaHost(_ollamaUrl)}: bấm "Tải" để tải model trực tiếp.'
                                  : 'Chưa kết nối được Ollama tại ${ollamaHost(_ollamaUrl)}. Cài Ollama để tải model bằng một nút bấm, '
                                      'hoặc dùng LM Studio và tìm model theo tên gợi ý.'),
                            ),
                            IconButton(onPressed: _refreshInstalled, icon: const Icon(Icons.refresh), tooltip: 'Kiểm tra lại'),
                          ]),
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
                            ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final m in _models) ...[_modelTile(m, hw, m == best), const SizedBox(height: 10)],
                    Text(
                      'Model chạy trên máy cho chất lượng phân tích thấp hơn các model lớn qua API, và cần ngữ cảnh (context) ≥ 8192 token. '
                      'Danh sách đề xuất được cập nhật từ GitHub.',
                      style: text.bodySmall,
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  String _verdict(Hardware hw) {
    if (hw.os == 'Android') {
      return 'Điện thoại chỉ chạy được model rất nhỏ và chậm. Nên dùng AI qua API, hoặc trỏ tới Ollama/LM Studio '
          'trên máy tính trong cùng mạng Wi-Fi (Cài đặt → AI → địa chỉ http://<IP máy tính>:11434/v1).';
    }
    if (hw.appleSilicon) {
      return 'Apple Silicon dùng chung RAM cho GPU: khoảng ${fmt(hw.gpuBudgetGb, 0)} GB có thể dành cho model, chạy nhanh.';
    }
    if ((hw.vramGb ?? 0) >= 6) {
      return 'GPU ${fmt(hw.vramGb, 0)} GB VRAM: model vừa VRAM sẽ chạy nhanh; model lớn hơn sẽ dùng RAM và chậm hơn nhiều.';
    }
    return 'Không có GPU rời đủ mạnh: model chạy bằng CPU. Nên chọn model ≤ 8B để có tốc độ chấp nhận được.';
  }

  Widget _modelTile(ModelInfo m, Hardware hw, bool recommended) {
    final fit = m.fitFor(hw);
    final (label, color) = switch (fit) {
      Fit.fast => ('Chạy tốt', Tone.up(context)),
      Fit.slow => ('Chạy được, chậm', Tone.flat(context)),
      Fit.no => ('Không đủ bộ nhớ', Tone.down(context)),
    };
    final installed = _isInstalled(m);
    final pulling = _pulling[m.ollama];
    final text = Theme.of(context).textTheme;

    return Card(
      shape: recommended
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(m.name, style: text.titleMedium),
            Tag(label, color: color),
            if (recommended) Tag('Đề xuất', color: Theme.of(context).colorScheme.primary),
            if (installed) Tag('Đã tải', color: Tone.up(context)),
            Text('${fmt(m.sizeGb, 1)} GB · chất lượng ${'★' * m.quality}${'☆' * (5 - m.quality)}', style: text.bodySmall),
          ]),
          const SizedBox(height: 4),
          Text(m.note, style: text.bodySmall),
          const SizedBox(height: 8),
          if (pulling != null) ...[
            LinearProgressIndicator(value: pulling.$2),
            const SizedBox(height: 4),
            Text('${pulling.$1}${pulling.$2 == null ? '' : ' · ${(pulling.$2! * 100).toStringAsFixed(0)}%'}', style: text.bodySmall),
          ] else
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (installed)
                FilledButton.tonal(onPressed: () => _use(m), child: const Text('Dùng model này'))
              else
                FilledButton.tonal(
                  onPressed: _ollamaUp && fit != Fit.no ? () => _pull(m) : null,
                  child: Text('Tải bằng Ollama (${m.ollama})'),
                ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: m.search));
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Đã chép "${m.search}". Dán vào ô tìm kiếm (Discover) của LM Studio.')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Tên để tìm trong LM Studio'),
              ),
            ]),
        ]),
      ),
    );
  }
}
