// Tổng quan: dashboard thị trường 3 cột vừa một màn hình (chỉ số + biểu đồ | dòng tiền + bản đồ nhiệt | trong phiên).
// Màn hình hẹp (< 760) xếp thành 1 cột và cho cuộn.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/board.dart';
import '../services/market.dart';
import '../state.dart';
import 'analysis_page.dart';
import 'chart.dart';
import 'dash_widgets.dart';
import 'widgets.dart';

const _minHeight = 600.0;

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dash = state.dash;
    final stamp = dash.updatedAt;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: Row(
          children: [
            const Text('Tổng quan'),
            const SizedBox(width: 12),
            if (stamp != null)
              Flexible(
                child: Text('Cập nhật lúc ${timeLocal(stamp)}',
                    overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width < 760)
            IconButton(onPressed: () => _showBrief(context), icon: const Icon(Icons.auto_awesome), tooltip: 'Nhận định AI')
          else
            TextButton.icon(
              onPressed: () => _showBrief(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Nhận định AI'),
            ),
          dash.loading || state.loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(onPressed: state.refresh, icon: const Icon(Icons.refresh), tooltip: 'Làm mới dữ liệu'),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          // Ba cột chỉ dùng khi mỗi panel còn đủ bề rộng để giữ số liệu và nhãn
          // trên cùng một dòng. Cửa sổ trung bình chuyển sang bố cục cuộn linh hoạt.
          if (c.maxWidth < 1100) {
            return ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (dash.error != null) _Notice(dash.error!),
                SizedBox(height: 360, child: _ChartCard(dash)),
                _IndexList(dash, shrink: true),
                _selector(dash),
                SizedBox(height: 230, child: _FlowCard(dash)),
                SizedBox(height: 440, child: _HeatCard(dash)),
                _IndexHeader(dash),
                SizedBox(height: 240, child: _IntradayCard(dash)),
                _SideInfo(dash),
              ],
            );
          }
          final h = math.max(c.maxHeight, _minHeight);
          final body = SizedBox(
            height: h,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 27,
                    child: Column(
                      children: [
                        Expanded(flex: 11, child: _ChartCard(dash)),
                        Expanded(flex: 9, child: _IndexList(dash)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 46,
                    child: Column(
                      children: [
                        if (dash.error != null) _Notice(dash.error!),
                        _selector(dash),
                        Expanded(flex: 7, child: _FlowCard(dash)),
                        Expanded(flex: 13, child: _HeatCard(dash)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 27,
                    child: Column(
                      children: [
                        _IndexHeader(dash),
                        Expanded(flex: 8, child: _IntradayCard(dash)),
                        Expanded(flex: 11, child: _SideInfo(dash, fit: true)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          return h > c.maxHeight ? SingleChildScrollView(child: body) : body;
        },
      ),
    );
  }

  static void _showBrief(BuildContext context) => showDialog(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(child: _BriefCard()),
          ),
        ),
      );

  static Widget _selector(MarketDashboard dash) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const ChoiceChip(label: Text('Biến động'), selected: true, visualDensity: VisualDensity.compact),
          const SizedBox(width: 12),
          for (final (label, group) in heatExchanges)
            ChoiceChip(
              label: Text(label),
              selected: dash.exchange == group,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => dash.setExchange(group),
            ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsets padding;
  const _Panel({required this.child, this.title, this.padding = const EdgeInsets.all(8)});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(3),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    margin: const EdgeInsets.all(3),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    ),
  );
}

// ---------- Cột trái ----------

const _chartIndicators = {Indicator.ma10, Indicator.ma50, Indicator.volume};

class _ChartCard extends StatelessWidget {
  final MarketDashboard dash;
  const _ChartCard(this.dash);

  @override
  Widget build(BuildContext context) {
    final q = dash.quote;
    final m = dash.meta;
    return _Panel(
      padding: const EdgeInsets.all(6),
      child: q == null || q.bars.length < 2
          ? Center(child: dash.loading ? const CircularProgressIndicator() : const Text('Chưa có dữ liệu biểu đồ'))
          : StockChart(
              m.symbol,
              q.bars,
              expand: true,
              key: ValueKey(m.symbol),
              fixedIndicators: _chartIndicators,
              rangeList: dashboardRanges,
              initialRange: 2,
              onFullscreen: () => openChart(context, m.symbol, title: 'Biểu đồ ${m.name}', kind: m.kind),
            ),
    );
  }
}

class _IndexList extends StatelessWidget {
  final MarketDashboard dash;
  final bool shrink;
  const _IndexList(this.dash, {this.shrink = false});

  @override
  Widget build(BuildContext context) {
    final tiles = [for (final m in indexMetas) _IndexTile(dash, m)];
    return Card(
      margin: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [for (final t in tiles) shrink ? SizedBox(height: 60, child: t) : Expanded(child: t)],
      ),
    );
  }
}

class _IndexTile extends StatelessWidget {
  final MarketDashboard dash;
  final IndexMeta meta;
  const _IndexTile(this.dash, this.meta);

  @override
  Widget build(BuildContext context) {
    final q = dash.quotes[meta.symbol];
    final sel = dash.selected == meta.symbol;
    final tone = Tone.of(context, q?.change);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => dash.select(meta.symbol),
      child: Container(
        color: sel ? cs.primary.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: tone, fontSize: 13),
                  ),
                  Text(
                    meta.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (q != null) SizedBox(width: 56, height: 26, child: Sparkline(q.spark, height: 26)),
            const SizedBox(width: 8),
            SizedBox(
              width: 108,
              child: q?.last == null
                  ? const Text('–', textAlign: TextAlign.right)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fmt(q!.last), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(
                            '${q.change! >= 0 ? '+' : ''}${fmt(q.change)} / ${q.pct! >= 0 ? '+' : ''}${fmt(q.pct)}%',
                            style: TextStyle(fontSize: 10.5, color: tone),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Cột giữa ----------

class _FlowCard extends StatelessWidget {
  final MarketDashboard dash;
  const _FlowCard(this.dash);

  @override
  Widget build(BuildContext context) {
    final rows = dash.heatRows;
    final st = BoardStats(rows);
    return _Panel(
      title: 'Dòng tiền',
      child: !st.hasData
          ? const Center(child: Text('Chưa có dữ liệu'))
          : Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Số lượng CP Tăng, Giảm, Không đổi',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: BreadthPie(up: st.up, down: st.down, flat: st.flat),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Phân bổ dòng tiền', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      Expanded(
                        child: FlowBars(
                          up: st.upValueMn / 1000,
                          down: st.downValueMn / 1000,
                          flat: st.flatValueMn / 1000,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeatCard extends StatelessWidget {
  final MarketDashboard dash;
  const _HeatCard(this.dash);

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(3),
    child: HeatMap(rows: dash.heatRows, sectors: dash.sectors, onOpen: (s) => openAnalysis(context, s)),
  );
}

// ---------- Cột phải ----------

class _IndexHeader extends StatelessWidget {
  final MarketDashboard dash;
  const _IndexHeader(this.dash);

  @override
  Widget build(BuildContext context) {
    final q = dash.quote;
    final tone = Tone.of(context, q?.change);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chỉ số ${dash.meta.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(_sessionLabel(dash), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt(q?.last), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
              if (q?.change != null)
                Text(
                  '${q!.change! >= 0 ? '+' : ''}${fmt(q.change)} / ${q.pct! >= 0 ? '+' : ''}${fmt(q.pct)}%',
                  style: TextStyle(color: tone, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _sessionLabel(MarketDashboard dash) {
    if (dash.intraday.isEmpty) return '';
    final d = vnDate(dash.intraday.last.t);
    final live = isTradingTime(DateTime.now()) && d == vnDate(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return live ? 'Đang giao dịch · $d' : 'Phiên gần nhất · $d';
  }
}

/// Tham chiếu của phiên trong biểu đồ: đóng cửa phiên liền trước theo nến ngày.
double? sessionRef(List<Bar> daily, List<Bar> intraday) {
  if (daily.isEmpty || intraday.isEmpty) return null;
  final day = vnDate(intraday.last.t);
  final prior = daily.where((b) => vnDate(b.t).compareTo(day) < 0);
  return prior.isEmpty ? null : prior.last.c;
}

class _IntradayCard extends StatelessWidget {
  final MarketDashboard dash;
  const _IntradayCard(this.dash);

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.fromLTRB(6, 6, 2, 2),
    child: IntradayChart(bars: dash.intraday, ref: sessionRef(dash.quote?.bars ?? const [], dash.intraday)),
  );
}

String _vol(double? v) => v == null ? '–' : fmt(v, 0);

/// Các dòng "Tổng quan" và "Giao dịch NĐTNN"; mục không có nguồn dữ liệu thì ẩn.
List<(String, String, Color?)> overviewRows(IndexQuote? q, List<Bar> intraday, List<BoardRow>? board) {
  final out = <(String, String, Color?)>[];
  if (q == null) return out;
  final ref = sessionRef(q.bars, intraday) ?? q.prev;
  if (ref != null) out.add(('Tham chiếu', fmt(ref), null));
  final day = intraday.isEmpty ? null : vnDate(intraday.last.t);
  final today = q.bars.isNotEmpty && (day == null || vnDate(q.bars.last.t) == day) ? q.bars.last : null;
  final open = today?.o ?? (intraday.isEmpty ? null : intraday.first.o);
  final lo = today?.l ?? (intraday.isEmpty ? null : intraday.map((b) => b.l).reduce(math.min));
  final hi = today?.h ?? (intraday.isEmpty ? null : intraday.map((b) => b.h).reduce(math.max));
  if (open != null) out.add(('Mở cửa', fmt(open), null));
  if (lo != null && hi != null) out.add(('Thấp – Cao', '${fmt(lo)} – ${fmt(hi)}', null));
  if (board != null && board.isNotEmpty) {
    final st = BoardStats(board);
    out.add(('KL khớp', _vol(st.volume), null));
    out.add(('KL thỏa thuận', _vol(st.ptVolume), null));
    out.add(('Tổng KL', _vol(st.totalVolume), null));
    out.add(('Tổng giá trị', '${fmt(st.totalValueTy, 2)} tỷ', null));
  } else if (today != null && q.meta.group == null) {
    out.add(('Tổng KL', _vol(today.v), null));
  }
  return out;
}

List<(String, String, Color?)> foreignRows(List<BoardRow>? board, Color up, Color down) {
  if (board == null || board.isEmpty) return const [];
  final st = BoardStats(board);
  if (st.foreignBuy + st.foreignSell <= 0) return const [];
  final net = st.foreignBuy - st.foreignSell;
  return [
    ('KL mua', _vol(st.foreignBuy), up),
    ('KL bán', _vol(st.foreignSell), down),
    ('KL mua – bán', '${net >= 0 ? '+' : ''}${fmt(net, 0)}', net >= 0 ? up : down),
  ];
}

class _SideInfo extends StatelessWidget {
  final MarketDashboard dash;
  final bool fit;
  const _SideInfo(this.dash, {this.fit = false});

  @override
  Widget build(BuildContext context) {
    final rows = overviewRows(dash.quote, dash.intraday, dash.metaBoard);
    final fr = foreignRows(dash.metaBoard, Tone.up(context), Tone.down(context));
    final cs = Theme.of(context).colorScheme;
    Widget section(String title, List<(String, String, Color?)> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        for (final (k, v, color) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                Text(k, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      v,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty) section('TỔNG QUAN', rows),
        if (fr.isNotEmpty) section('GIAO DỊCH NĐTNN', fr),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Dữ liệu: DNSE, Vietcap. Khối ngoại tính theo KL.',
            style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
    if (!fit) {
      return Card(
        margin: const EdgeInsets.all(3),
        child: Padding(padding: const EdgeInsets.all(8), child: content),
      );
    }
    return Card(
      margin: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, c) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(width: c.maxWidth, child: content),
          ),
        ),
      ),
    );
  }
}

class _BriefCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final b = state.marketBrief;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Nhận định thị trường bằng AI', style: Theme.of(context).textTheme.titleMedium)),
                if (b != null) Tag(b['mood'] ?? '', color: Tone.stance(context, b['mood'])),
              ],
            ),
            const SizedBox(height: 6),
            if (state.briefLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (b != null) ...[
              Text(b['headline'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(b['summary'] ?? ''),
              const SectionLabel('Chủ đề nổi bật'),
              for (final t in (b['themes'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${t['theme']}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: t['detail']),
                        if ((t['tickers'] as List?)?.isNotEmpty ?? false)
                          TextSpan(text: '  (${(t['tickers'] as List).join(', ')})'),
                      ],
                    ),
                  ),
                ),
              const SectionLabel('Cần theo dõi'),
              Bullets(b['watch_list']),
            ] else
              Text(
                'Dùng AI đang chọn (${state.aiLabel}) để tóm tắt diễn biến VN-Index, rổ VN30 và tin tức 48 giờ qua.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (state.briefError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(state.briefError!, style: TextStyle(color: Tone.down(context))),
              ),
            const SizedBox(height: 10),
            if (!state.briefLoading)
              FilledButton.tonalIcon(
                onPressed: state.index == null ? null : state.runMarketBrief,
                icon: const Icon(Icons.auto_awesome),
                label: Text(b == null ? 'Tạo nhận định' : 'Tạo lại'),
              ),
          ],
        ),
      ),
    );
  }
}
