import 'package:flutter/material.dart';

import '../state.dart';
import 'chart.dart';
import 'widgets.dart';

void openAnalysis(BuildContext context, String symbol) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnalysisPage(symbol)));

class AnalysisPage extends StatefulWidget {
  final String symbol;
  const AnalysisPage(this.symbol, {super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool _running = false;
  String? _error;
  late final Stopwatch _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppScope.of(context).analyses[widget.symbol] == null) _run();
    });
  }

  Future<void> _run() async {
    final state = AppScope.of(context);
    setState(() {
      _running = true;
      _error = null;
    });
    _clock
      ..reset()
      ..start();
    try {
      await state.analyzeStock(widget.symbol);
    } catch (e) {
      _error = e.toString();
    } finally {
      _clock.stop();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saved = state.analyses[widget.symbol];
    final watching = state.watchlist.contains(widget.symbol);

    return Scaffold(
      appBar: AppBar(
        title: Text('Phân tích ${widget.symbol}'),
        actions: [
          if (!watching)
            TextButton.icon(
              onPressed: () => state.addWatch(widget.symbol),
              icon: const Icon(Icons.add),
              label: const Text('Theo dõi'),
            ),
          if (saved != null && !_running)
            IconButton(onPressed: _run, icon: const Icon(Icons.refresh), tooltip: 'Phân tích lại'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (state.stocks[widget.symbol] != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: StockChart(
                        widget.symbol,
                        state.stocks[widget.symbol]!.bars,
                        height: 380,
                        onFullscreen: () => openChart(context, widget.symbol),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_running) _Loading(widget.symbol, state.aiLabel, state.provider.local, state.engineStatus, state.engineProgress),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_error!),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          FilledButton(onPressed: _run, child: const Text('Thử lại')),
                          Text('Đổi AI hoặc model trong tab Cài đặt.', style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ]),
                    ),
                  ),
                if (saved != null && !_running) _Report(saved),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final String symbol, ai;
  final bool local;
  final String? engineStatus;
  final double? engineProgress;
  const _Loading(this.symbol, this.ai, this.local, this.engineStatus, this.engineProgress);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(engineStatus ?? 'Đang thu thập dữ liệu và phân tích $symbol…', textAlign: TextAlign.center),
          if (engineStatus != null && engineProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 8),
              child: LinearProgressIndicator(value: engineProgress),
            ),
          const SizedBox(height: 4),
          Text(local ? 'Model chạy trên máy có thể mất vài phút.' : 'Thường mất 30–90 giây.',
              style: Theme.of(context).textTheme.bodySmall),
          Text(ai, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _Report extends StatelessWidget {
  final Map<String, dynamic> saved;
  const _Report(this.saved);

  @override
  Widget build(BuildContext context) {
    final r = saved['result'] as Map<String, dynamic>;
    final inputs = saved['inputs'] as Map<String, dynamic>;
    final t = inputs['technicals'] as Map<String, dynamic>? ?? {};
    final f = inputs['fundamentals'] as Map<String, dynamic>? ?? {};
    final c = f['company'] as Map<String, dynamic>? ?? {};
    final ratios = (f['chi_so_ttm_theo_quy'] as List?) ?? [];
    final last = ratios.isEmpty ? <String, dynamic>{} : ratios.last as Map<String, dynamic>;
    final scorecard = (r['scorecard'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final avg = scorecard.isEmpty ? null : scorecard.map((x) => x['score'] as num).reduce((a, b) => a + b) / scorecard.length;
    String pct(dynamic x) => x is num ? '${fmt(x * 100, 1)}%' : '–';
    final text = Theme.of(context).textTheme;

    Widget block(String title, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(title),
          child,
        ]);
    Widget twoCols(Widget a, Widget b) => LayoutBuilder(
          builder: (context, cons) => cons.maxWidth > 620
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: a),
                  const SizedBox(width: 20),
                  Expanded(child: b),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [a, b]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([c['ten'], c['nganh']].whereType<String>().join(' · '), style: text.bodySmall),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(fmt(t['close'] as num?), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Pct(t['change_1d'] as num?)),
                  ]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Tag(r['stance'] ?? '', color: Tone.stance(context, r['stance'])),
                const SizedBox(height: 4),
                Text('độ tin cậy ${r['confidence'] ?? ''}', style: text.bodySmall),
                if (avg != null) Text('${fmt(avg, 1)}/5', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 20, runSpacing: 6, children: [
              Kv('P/E', Text(fmt(last['pe'] as num?, 1))),
              Kv('P/B', Text(fmt(last['pb'] as num?))),
              Kv('ROE', Text(pct(last['roe']))),
              Kv('Vốn hóa', Text(c['von_hoa_ty_dong'] == null ? '–' : '${fmt(c['von_hoa_ty_dong'] as num, 0)} tỷ')),
              Kv('1 năm', Pct(t['change_1y'] as num?)),
              Kv('RSI', Text(fmt(t['rsi14'] as num?, 1))),
            ]),
            const SizedBox(height: 12),
            Text(r['headline'] ?? '', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(r['summary'] ?? ''),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Bảng chấm điểm'),
            for (final x in scorecard)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 170, child: Text(x['dimension'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                  _ScoreBar((x['score'] as num?)?.toInt() ?? 0),
                  const SizedBox(width: 12),
                  Expanded(child: Text(x['reason'] ?? '', style: text.bodySmall)),
                ]),
              ),
            twoCols(
              block('Luận điểm đầu tư', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['thesis']?['statement'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Bullets(r['thesis']?['pillars']),
                const SectionLabel('Luận điểm sai nếu…'),
                Bullets(r['thesis']?['invalidation']),
              ])),
              block('Kết quả kinh doanh', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['earnings']?['summary'] ?? ''),
                const SizedBox(height: 4),
                Bullets(r['earnings']?['highlights']),
              ])),
            ),
            twoCols(block('Định giá', Text(r['valuation'] ?? '')), block('Vị thế cạnh tranh', Text(r['competition'] ?? ''))),
            block('Kỹ thuật', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['technical']?['summary'] ?? ''),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Vùng giá: ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: r['technical']?['key_levels'] ?? ''),
              ])),
            ])),
            block('Lịch sự kiện', Column(children: [
              for (final e in (r['catalysts'] as List? ?? []).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(e['timing'] ?? '', style: text.bodySmall)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e['event'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(e['why'] ?? '', style: text.bodySmall),
                      ]),
                    ),
                    Tag(e['impact'] ?? '', color: switch (e['impact']) {
                      'Cao' => Tone.down(context),
                      'Thấp' => Tone.up(context),
                      _ => Tone.flat(context),
                    }),
                  ]),
                ),
            ])),
            const SectionLabel('Kịch bản'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Scenario('Tích cực', r['scenarios']?['bull'], Tone.up(context)),
              _Scenario('Cơ sở', r['scenarios']?['base'], Tone.flat(context)),
              _Scenario('Tiêu cực', r['scenarios']?['bear'], Tone.down(context)),
            ]),
            twoCols(block('Rủi ro', Bullets(r['risks'])), block('Cần theo dõi', Bullets(r['watch_points']))),
            if ((r['data_gaps'] as List?)?.isNotEmpty ?? false) block('Hạn chế dữ liệu', Bullets(r['data_gaps'])),
            const Divider(height: 28),
            Text(
              'Phân tích lúc ${timeVN(DateTime.parse(saved['created_at']))} · ${saved['ai']}. '
              'Số liệu: DNSE, Vietcap IQ, tin RSS. $disclaimer',
              style: text.bodySmall,
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;
  const _ScoreBar(this.score);

  @override
  Widget build(BuildContext context) {
    final color = score >= 4 ? Tone.up(context) : (score <= 2 ? Tone.down(context) : Tone.flat(context));
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Container(
            width: 14,
            height: 8,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i <= score ? color : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ]),
    );
  }
}

class _Scenario extends StatelessWidget {
  final String title;
  final String? body;
  final Color color;
  const _Scenario(this.title, this.body, this.color);

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 290),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body ?? '', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
