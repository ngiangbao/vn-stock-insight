import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show appTheme;
import '../services/pdf_export.dart';

import '../state.dart';
import 'analysis_report.dart';
import 'chart.dart';

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
      if (AppScope.of(context).analysisForToday(widget.symbol) == null) _run();
    });
  }

  Future<void> _run({bool force = false}) async {
    final state = AppScope.of(context);
    setState(() {
      _running = true;
      _error = null;
    });
    _clock
      ..reset()
      ..start();
    try {
      await state.analyzeStock(widget.symbol, force: force);
    } catch (e) {
      _error = e.toString();
    } finally {
      _clock.stop();
      if (mounted) setState(() => _running = false);
    }
  }

  /// Cột đang được chụp để xuất PDF ('past' hoặc 'today'); lúc chụp báo cáo hiện theo giao diện sáng để in cho rõ.
  String? _exporting;
  final _boundaries = {'past': GlobalKey(), 'today': GlobalKey()};

  Future<void> _exportPdf(String which, String dayKey) async {
    if (_exporting != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = which);
    try {
      // Chờ hai khung hình để báo cáo dựng xong theo giao diện sáng
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundaries[which]!.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw 'Chưa dựng xong báo cáo, hãy thử lại.';
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await pdfFromImage(
        image,
        title: 'Báo cáo phân tích ${widget.symbol} $dayKey',
        author: 'VN Stock Insight',
      );
      final file = await savePdf(bytes, 'bao-cao-${widget.symbol}-$dayKey.pdf');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Đã lưu ${file.path}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Mở', onPressed: () => launchUrl(Uri.file(file.path))),
        ));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Không xuất được PDF: $e')));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Widget _report(AppState state, Map<String, dynamic> record, Key key, String which) {
    final board = [for (final rows in state.dash.boards.values) ...rows].where((r) => r.symbol == widget.symbol).firstOrNull;
    final printing = _exporting == which;
    return RepaintBoundary(
      key: _boundaries[which],
      child: Theme(
        data: printing ? appTheme(Brightness.light) : Theme.of(context),
        child: ColoredBox(
          color: printing ? Colors.white : Colors.transparent,
          child: ResearchReport(
            record,
            key: key,
            bars: state.stocks[widget.symbol]?.bars ?? const [],
            indexBars: state.index?.bars ?? const [],
            exchange: board?.exchange,
          ),
        ),
      ),
    );
  }

  /// Ngày đang xem ở cột trái; null = ngày gần nhất trước hôm nay.
  String? _compareDay;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = state.analysisForToday(widget.symbol);
    final saved = state.analyses[widget.symbol];
    final watching = state.watchlist.contains(widget.symbol);
    final todayKey = vietnamDayKey(DateTime.now());
    final past = [for (final h in state.historyFor(widget.symbol)) if (h.$1 != todayKey) h];
    final picked = past.isEmpty
        ? null
        : past.firstWhere((h) => h.$1 == _compareDay, orElse: () => past.first);

    final left = _DayColumn(
      title: picked == null ? 'Hôm qua' : dayLabel(picked.$1, todayKey),
      subtitle: picked?.$1,
      days: past,
      selected: picked?.$1,
      todayKey: todayKey,
      onPick: (d) => setState(() => _compareDay = d),
      onExport: picked == null ? null : () => _exportPdf('past', picked.$1),
      exporting: _exporting == 'past',
      child: picked == null
          ? const _Empty('Chưa có nhận định của các ngày trước. Nhận định mỗi ngày được lưu lại tối đa ${AppState.historyDays} ngày.')
          : _report(state, picked.$2, ValueKey('past-${picked.$1}'), 'past'),
    );
    final right = _DayColumn(
      title: 'Hôm nay',
      subtitle: todayKey,
      todayKey: todayKey,
      onExport: today == null || _running ? null : () => _exportPdf('today', todayKey),
      exporting: _exporting == 'today',
      child: _running
          ? _Loading(widget.symbol, state.aiLabel, state.provider.local, state.engineStatus, state.engineProgress)
          : _error != null
              ? Card(
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
                )
              : today != null
                  ? _report(state, today, const ValueKey('today'), 'today')
                  : _Empty('Chưa có nhận định hôm nay.', action: FilledButton(onPressed: _run, child: const Text('Phân tích ngay'))),
    );

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
            IconButton(onPressed: () => _run(force: true), icon: const Icon(Icons.refresh), tooltip: 'Phân tích lại'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
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
          LayoutBuilder(
            builder: (context, cons) => cons.maxWidth >= 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: left),
                    const SizedBox(width: 16),
                    Expanded(child: right),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 16), right]),
          ),
        ],
      ),
    );
  }
}

/// "Hôm qua", "dd/MM" cho nhãn của một ngày yyyy-MM-dd so với hôm nay.
String dayLabel(String key, String todayKey) {
  final d = DateTime.parse(key), t = DateTime.parse(todayKey);
  final diff = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (diff == 1) return 'Hôm qua';
  return 'Ngày ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Một cột của trang: tiêu đề ngày, (cột trái) chọn ngày so sánh, rồi nội dung.
class _DayColumn extends StatelessWidget {
  final String title;
  final String? subtitle, selected;
  final String todayKey;
  final List<(String, Map<String, dynamic>)> days;
  final ValueChanged<String>? onPick;
  final VoidCallback? onExport;
  final bool exporting;
  final Widget child;
  const _DayColumn({
    required this.title,
    required this.todayKey,
    required this.child,
    this.subtitle,
    this.days = const [],
    this.selected,
    this.onPick,
    this.onExport,
    this.exporting = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String vn(String k) {
      final d = DateTime.parse(k);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
            Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) Text(vn(subtitle!), style: text.bodyMedium),
          ]),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: exporting ? null : onExport,
          icon: exporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(exporting ? 'Đang xuất…' : 'Xuất PDF'),
        ),
      ]),
      if (days.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, _) in days)
            ChoiceChip(
              label: Text(dayLabel(k, todayKey) == 'Hôm qua' ? 'Hôm qua · ${vn(k).substring(0, 5)}' : vn(k).substring(0, 5)),
              selected: k == selected,
              onSelected: (_) => onPick?.call(k),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
        ]),
      ],
      const SizedBox(height: 10),
      child,
    ]);
  }
}

class _Empty extends StatelessWidget {
  final String message;
  final Widget? action;
  const _Empty(this.message, {this.action});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
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
