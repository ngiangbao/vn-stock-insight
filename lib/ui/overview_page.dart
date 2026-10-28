import 'package:flutter/material.dart';

import '../services/market.dart';
import '../state.dart';
import 'chart.dart';
import 'widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final ix = state.index;
    final all = state.vn30Stocks.where((s) => s.data['change_1d'] != null).toList()
      ..sort((a, b) => (b.data['change_1d'] as num).compareTo(a.data['change_1d'] as num));
    final up = all.where((s) => (s.data['change_1d'] as num) > 0).length;
    final down = all.where((s) => (s.data['change_1d'] as num) < 0).length;

    return PageFrame(
      title: 'Tổng quan',
      onRefresh: state.refresh,
      children: [
        if (state.loadError != null) _Notice(state.loadError!),
        if (ix == null && state.loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (ix != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('VN-Index · ${ix.data['date']}', style: Theme.of(context).textTheme.bodySmall),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmt(ix.close), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Pct(ix.num_('change_1d'))),
                ]),
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Mở biểu đồ VN-Index',
                  child: InkWell(
                    onTap: () => openChart(context, 'VNINDEX', title: 'Biểu đồ VN-Index'),
                    child: Sparkline(ix.spark, height: 72),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 22, runSpacing: 8, children: [
                  Kv('1 tuần', Pct(ix.num_('change_1w'))),
                  Kv('1 tháng', Pct(ix.num_('change_1m'))),
                  Kv('3 tháng', Pct(ix.num_('change_3m'))),
                  Kv('RSI 14', Text(fmt(ix.num_('rsi14'), 1))),
                  Kv('VN30 tăng / giảm', Text.rich(TextSpan(children: [
                    TextSpan(text: '$up', style: TextStyle(color: Tone.up(context))),
                    const TextSpan(text: ' / '),
                    TextSpan(text: '$down', style: TextStyle(color: Tone.down(context))),
                  ]))),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        _BriefCard(),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          LayoutBuilder(builder: (context, c) {
            final gainers = _Movers('Tăng mạnh nhất (VN30)', all.take(5).toList());
            final losers = _Movers('Giảm mạnh nhất (VN30)', all.reversed.take(5).toList());
            return c.maxWidth > 640
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: gainers),
                    const SizedBox(width: 14),
                    Expanded(child: losers),
                  ])
                : Column(children: [gainers, const SizedBox(height: 14), losers]);
          }),
        const SizedBox(height: 16),
        Text('Dữ liệu giá: DNSE/VNDirect (nghìn đồng). $disclaimer',
            style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
      );
}

class _Movers extends StatelessWidget {
  final String title;
  final List<Snapshot> items;
  const _Movers(this.title, this.items);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final s in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 60, child: Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Text(fmt(s.close), textAlign: TextAlign.right)),
                  SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: Pct(s.num_('change_1d')))),
                ]),
              ),
          ]),
        ),
      );
}

class _BriefCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final b = state.marketBrief;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Nhận định thị trường bằng AI', style: Theme.of(context).textTheme.titleMedium)),
            if (b != null) Tag(b['mood'] ?? '', color: Tone.stance(context, b['mood'])),
          ]),
          const SizedBox(height: 6),
          if (state.briefLoading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (b != null) ...[
            Text(b['headline'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(b['summary'] ?? ''),
            const SectionLabel('Chủ đề nổi bật'),
            for (final t in (b['themes'] as List? ?? []))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${t['theme']}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: t['detail']),
                  if ((t['tickers'] as List?)?.isNotEmpty ?? false) TextSpan(text: '  (${(t['tickers'] as List).join(', ')})'),
                ])),
              ),
            const SectionLabel('Cần theo dõi'),
            Bullets(b['watch_list']),
          ] else
            Text('Dùng AI đang chọn (${state.aiLabel}) để tóm tắt diễn biến VN-Index, rổ VN30 và tin tức 48 giờ qua.',
                style: Theme.of(context).textTheme.bodyMedium),
          if (state.briefError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(state.briefError!, style: TextStyle(color: Tone.down(context)))),
          const SizedBox(height: 10),
          if (!state.briefLoading)
            FilledButton.tonalIcon(
              onPressed: state.index == null ? null : state.runMarketBrief,
              icon: const Icon(Icons.auto_awesome),
              label: Text(b == null ? 'Tạo nhận định' : 'Tạo lại'),
            ),
        ]),
      ),
    );
  }
}
