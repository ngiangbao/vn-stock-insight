// Dashboard thị trường ưu tiên chỉ số, điểm nhấn phiên, dòng tiền và bản đồ nhiệt.
// Biểu đồ chi tiết vẫn nằm bên dưới để giữ nguyên luồng phân tích hiện có.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/board.dart';
import '../services/market.dart';
import '../state.dart';
import 'chart.dart';
import 'dash_widgets.dart';
import 'stock_dialog.dart';
import 'widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dash = state.dash;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('Tổng quan'),
        actions: [
          if (MediaQuery.sizeOf(context).width < 760)
            IconButton(
              onPressed: () => _showBrief(context),
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Nhận định AI',
            )
          else
            TextButton.icon(
              onPressed: () => _showBrief(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Nhận định AI'),
            ),
          dash.loading || state.loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: state.refresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Làm mới dữ liệu',
                ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1120;
          final gutter = c.maxWidth >= 1500 ? 24.0 : (wide ? 16.0 : 12.0);
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 20),
            children: [
              if (dash.error != null) _Notice(dash.error!),
              _OverviewHeading(dash: dash, wide: wide),
              _RegionBar(dash),
              _IndexStrip(dash),
              const SizedBox(height: 12),
              _SectionHeading(
                title: 'Biểu đồ thị trường',
                subtitle: 'Chọn một chỉ số ở phía trên để đổi dữ liệu biểu đồ',
              ),
              if (wide)
                SizedBox(
                  height: 420,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            _IndexHeader(dash),
                            Expanded(child: _ChartCard(dash)),
                          ],
                        ),
                      ),
                      // Bảng số liệu chi tiết cao bằng biểu đồ nến, lấp đầy phần ngang còn lại
                      Expanded(flex: 5, child: _SideInfo(dash, fit: true)),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: c.maxWidth < 600 ? 310 : 360,
                  child: _ChartCard(dash),
                ),
                _IndexHeader(dash),
                _SideInfo(dash),
              ],
              const SizedBox(height: 12),
              _MarketMovers(dash),
              const SizedBox(height: 12),
              if (wide)
                SizedBox(
                  height: c.maxWidth >= 1500 ? 470 : 430,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: _FlowCard(dash)),
                      Expanded(flex: 10, child: _HeatCard(dash)),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: c.maxWidth < 600 ? 390 : 300,
                  child: _FlowCard(dash),
                ),
                SizedBox(
                  height: c.maxWidth < 600 ? 430 : 470,
                  child: _HeatCard(dash),
                ),
              ],
            ],
          );
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
}

class _OverviewHeading extends StatelessWidget {
  final MarketDashboard dash;
  final bool wide;
  const _OverviewHeading({required this.dash, required this.wide});

  @override
  Widget build(BuildContext context) {
    final stamp = dash.updatedAt;
    final details = Text(
      !wide && stamp != null
          ? 'Cập nhật lúc ${timeLocal(stamp)}'
          : 'Diễn biến thị trường chứng khoán Việt Nam',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng quan thị trường',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                details,
              ],
            ),
          ),
          if (wide && stamp != null) ...[
            Icon(
              Icons.circle,
              size: 8,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 7),
            Text(
              'Cập nhật ${timeLocal(stamp)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title, subtitle;
  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 680)
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsets padding;
  const _Panel({
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(6),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
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
          ? Center(
              child: dash.loading
                  ? const CircularProgressIndicator()
                  : const Text('Chưa có dữ liệu biểu đồ'),
            )
          : StockChart(
              m.symbol,
              q.bars,
              expand: true,
              key: ValueKey(m.symbol),
              fixedIndicators: _chartIndicators,
              rangeList: dashboardRanges,
              initialRange: 2,
              onFullscreen: () => openChart(
                context,
                m.symbol,
                title: 'Biểu đồ ${m.name}',
                kind: m.kind,
              ),
            ),
    );
  }
}

/// Chọn khu vực của dải chỉ số: Việt Nam, Châu Mỹ, Châu Âu, Châu Á.
class _RegionBar extends StatelessWidget {
  final MarketDashboard dash;
  const _RegionBar(this.dash);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
    child: LayoutBuilder(
      builder: (context, c) {
        final chips = [
          for (final (id, label) in indexRegions)
            ChoiceChip(
              label: Text(label),
              selected: dash.region == id,
              onSelected: (_) => dash.setRegion(id),
            ),
        ];
        final label = Text(
          'Thị trường',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
        if (c.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              Wrap(spacing: 6, runSpacing: 0, children: chips),
            ],
          );
        }
        return Row(children: [label, const SizedBox(width: 8), ...chips]);
      },
    ),
  );
}

class _IndexStrip extends StatelessWidget {
  final MarketDashboard dash;
  const _IndexStrip(this.dash);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = dash.regionMetas.length;
      final cols = constraints.maxWidth < 560
          ? 2
          : (count > 4 ? 4 : count.clamp(1, 4));
      final gap = 8.0;
      final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final meta in dash.regionMetas)
              SizedBox(
                width: width,
                height: 84,
                child: _IndexQuoteCard(dash: dash, meta: meta),
              ),
          ],
        ),
      );
    },
  );
}

class _IndexQuoteCard extends StatelessWidget {
  final MarketDashboard dash;
  final IndexMeta meta;
  const _IndexQuoteCard({required this.dash, required this.meta});

  @override
  Widget build(BuildContext context) {
    final quote = dash.quotes[meta.symbol];
    final selected = dash.selected == meta.symbol;
    final tone = Tone.of(context, quote?.change);
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? cs.primary.withValues(alpha: 0.055) : null,
      child: InkWell(
        onTap: () => dash.select(meta.symbol),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      meta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fmt(quote?.last),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      quote?.change == null
                          ? 'Chưa có dữ liệu'
                          : '${quote!.change! >= 0 ? '+' : ''}${fmt(quote.change)}  ·  ${quote.pct! >= 0 ? '+' : ''}${fmt(quote.pct)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: quote?.change == null
                            ? cs.onSurfaceVariant
                            : tone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (quote != null) ...[
                const SizedBox(width: 6),
                SizedBox(width: 64, child: Sparkline(quote.spark, height: 38)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Cột giữa ----------

class _MarketMovers extends StatelessWidget {
  final MarketDashboard dash;
  const _MarketMovers(this.dash);

  @override
  Widget build(BuildContext context) {
    final rows = dash.heatRows;
    final gainers = [...rows]..sort((a, b) => b.pct.compareTo(a.pct));
    final losers = [...rows]..sort((a, b) => a.pct.compareTo(b.pct));
    final active = [...rows]
      ..sort(
        (a, b) => (b.valueMn + b.ptValueMn).compareTo(a.valueMn + a.ptValueMn),
      );
    final cards = [
      _MoverCard(
        title: 'Tăng mạnh nhất',
        icon: Icons.trending_up,
        tone: Tone.up(context),
        rows: gainers.take(3).toList(),
      ),
      _MoverCard(
        title: 'Giảm mạnh nhất',
        icon: Icons.trending_down,
        tone: Tone.down(context),
        rows: losers.take(3).toList(),
      ),
      _MoverCard(
        title: 'Thanh khoản nổi bật',
        icon: Icons.bar_chart,
        tone: Theme.of(context).colorScheme.primary,
        rows: active.take(3).toList(),
        showValue: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: 'Điểm nhấn phiên',
          subtitle: 'Các mã nổi bật trong ${dash.exchange}',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1000
                ? 3
                : (constraints.maxWidth >= 640 ? 2 : 1);
            const gap = 10.0;
            final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  SizedBox(width: width, height: 200, child: card),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MoverCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tone;
  final List<BoardRow> rows;
  final bool showValue;
  const _MoverCard({
    required this.title,
    required this.icon,
    required this.tone,
    required this.rows,
    this.showValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: tone),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.7)),
            if (rows.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Chưa có dữ liệu bảng giá',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    for (final row in rows)
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => openStock(context, row.symbol),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      row.symbol,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      showValue
                                          ? '${fmt((row.valueMn + row.ptValueMn) / 1000, 1)} tỷ'
                                          : fmt(row.price / 1000, 2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${row.pct >= 0 ? '+' : ''}${fmt(row.pct, 2)}%',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Tone.of(context, row.pct),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
          : LayoutBuilder(
              builder: (context, c) {
                final pie = Column(
                  children: [
                    const Text(
                      'Tỷ trọng dòng tiền',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: FlowPie(
                        up: st.upValueMn / 1000,
                        down: st.downValueMn / 1000,
                        flat: st.flatValueMn / 1000,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        _FlowKey(label: 'Tăng ${st.up}', color: heatUp),
                        _FlowKey(label: 'Giảm ${st.down}', color: heatDown),
                        _FlowKey(label: 'Đứng ${st.flat}', color: heatFlat),
                      ],
                    ),
                  ],
                );
                final bars = Column(
                  children: [
                    const Text(
                      'Giá trị giao dịch theo nhóm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: FlowBars(
                        up: st.upValueMn / 1000,
                        down: st.downValueMn / 1000,
                        flat: st.flatValueMn / 1000,
                      ),
                    ),
                  ],
                );
                if (c.maxWidth < 480) {
                  return Column(
                    children: [
                      Expanded(child: pie),
                      const SizedBox(height: 6),
                      Expanded(child: bars),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: pie),
                    const SizedBox(width: 8),
                    Expanded(child: bars),
                  ],
                );
              },
            ),
    );
  }
}

class _FlowKey extends StatelessWidget {
  final String label;
  final Color color;
  const _FlowKey({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _HeatCard extends StatefulWidget {
  final MarketDashboard dash;
  const _HeatCard(this.dash);

  @override
  State<_HeatCard> createState() => _HeatCardState();
}

class _HeatCardState extends State<_HeatCard> {
  String _sector = 'ALL';

  @override
  Widget build(BuildContext context) {
    final dash = widget.dash;
    final industries =
        dash.heatRows
            .map((r) => dash.sectors[r.symbol]?.name)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedSector = _sector == 'ALL' || industries.contains(_sector)
        ? _sector
        : 'ALL';
    final rows = selectedSector == 'ALL'
        ? dash.heatRows
        : dash.heatRows
              .where((r) => dash.sectors[r.symbol]?.name == selectedSector)
              .toList();
    final cs = Theme.of(context).colorScheme;
    return _Panel(
      title: 'Bản đồ nhiệt theo ngành',
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _HeatFilter<String>(
                label: 'Ngành',
                value: selectedSector,
                options: [
                  ('ALL', 'Tất cả ngành'),
                  for (final industry in industries) (industry, industry),
                ],
                onChanged: (value) => setState(() => _sector = value),
                width: 190,
              ),
              _HeatFilter<HeatMetric>(
                label: 'Chỉ số màu',
                value: dash.heatMetric,
                options: const [
                  (HeatMetric.change, 'Biến động'),
                  (HeatMetric.liquidity, 'Thanh khoản'),
                  (HeatMetric.foreignNet, 'Khối ngoại'),
                ],
                onChanged: dash.setHeatMetric,
                width: 150,
              ),
              _HeatFilter<String>(
                label: 'Sàn',
                value: dash.exchange,
                options: const [
                  ('HOSE', 'HOSE'),
                  ('HNX', 'HNX'),
                  ('UPCOM', 'UPCOM'),
                ],
                onChanged: dash.setExchange,
                width: 126,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: HeatMap(
                rows: rows,
                sectors: dash.sectors,
                metric: dash.heatMetric,
                onOpen: (s) => openStock(context, s),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(switch (dash.heatMetric) {
                HeatMetric.change => 'Biến động giá',
                HeatMetric.liquidity => 'Giá trị khớp lệnh',
                HeatMetric.foreignNet => 'Mua ròng / bán ròng',
              }, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(
                'Giảm',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 5),
              _HeatLegend(metric: dash.heatMetric),
              const SizedBox(width: 5),
              Text(
                'Tăng',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatFilter<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double width;
  const _HeatFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Rộng vừa đủ để hiện đầy đủ chữ của nhãn và của lựa chọn dài nhất, không bị cắt bằng "…"
    double measure(String t, TextStyle st) => (TextPainter(
      text: TextSpan(text: t, style: st),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout()).width;
    const labelStyle = TextStyle(fontSize: 12);
    const valueStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    final needed =
        18 +
        measure(label, labelStyle) +
        6 +
        options.map((o) => measure(o.$2, valueStyle)).reduce(math.max) +
        17 +
        16;
    return Container(
      width: math.max(width, needed),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                style: valueStyle.copyWith(color: cs.onSurface),
                icon: Icon(
                  Icons.expand_more,
                  size: 17,
                  color: cs.onSurfaceVariant,
                ),
                items: [
                  for (final (option, title) in options)
                    DropdownMenuItem<T>(
                      value: option,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  final HeatMetric metric;
  const _HeatLegend({required this.metric});

  @override
  Widget build(BuildContext context) {
    final colors = switch (metric) {
      HeatMetric.change => [heatDown, heatFlat, heatUp],
      HeatMetric.foreignNet => [const Color(0xFF663C3B), heatFlat, heatUp],
      HeatMetric.liquidity => [
        const Color(0xFF26384A),
        const Color(0xFF315B78),
        const Color(0xFF2584B8),
      ],
    };
    return SizedBox(
      width: 94,
      height: 8,
      child: Row(
        children: [
          for (final color in colors)
            Expanded(
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
        ],
      ),
    );
  }
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
                Text(
                  'Chỉ số ${dash.meta.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _sessionLabel(dash),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmt(q?.last),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
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
    final live =
        isTradingTime(DateTime.now()) &&
        d == vnDate(DateTime.now().millisecondsSinceEpoch ~/ 1000);
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

String _vol(double? v) => v == null ? '–' : fmt(v, 0);

/// Các dòng "Tổng quan" và "Giao dịch NĐTNN"; mục không có nguồn dữ liệu thì ẩn.
List<(String, String, Color?)> overviewRows(
  IndexQuote? q,
  List<Bar> intraday,
  List<BoardRow>? board,
) {
  final out = <(String, String, Color?)>[];
  if (q == null) return out;
  final ref = sessionRef(q.bars, intraday) ?? q.prev;
  if (ref != null) out.add(('Tham chiếu', fmt(ref), null));
  final day = intraday.isEmpty ? null : vnDate(intraday.last.t);
  final today =
      q.bars.isNotEmpty && (day == null || vnDate(q.bars.last.t) == day)
      ? q.bars.last
      : null;
  final open = today?.o ?? (intraday.isEmpty ? null : intraday.first.o);
  final lo =
      today?.l ??
      (intraday.isEmpty ? null : intraday.map((b) => b.l).reduce(math.min));
  final hi =
      today?.h ??
      (intraday.isEmpty ? null : intraday.map((b) => b.h).reduce(math.max));
  if (open != null) out.add(('Mở cửa', fmt(open), null));
  if (lo != null && hi != null) {
    out.add(('Thấp – Cao', '${fmt(lo)} – ${fmt(hi)}', null));
  }
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

List<(String, String, Color?)> foreignRows(
  List<BoardRow>? board,
  Color up,
  Color down,
) {
  if (board == null || board.isEmpty) return const [];
  final st = BoardStats(board);
  if (st.foreignBuy + st.foreignSell <= 0) return const [];
  final net = st.foreignBuy - st.foreignSell;
  return [
    ('KL mua', _vol(st.foreignBuy), up),
    ('KL bán', _vol(st.foreignSell), down),
    (
      'KL mua – bán',
      '${net >= 0 ? '+' : ''}${fmt(net, 0)}',
      net >= 0 ? up : down,
    ),
  ];
}

class _SideInfo extends StatelessWidget {
  final MarketDashboard dash;
  final bool fit;
  const _SideInfo(this.dash, {this.fit = false});

  @override
  Widget build(BuildContext context) {
    final rows = overviewRows(dash.quote, dash.intraday, dash.metaBoard);
    final fr = foreignRows(
      dash.metaBoard,
      Tone.up(context),
      Tone.down(context),
    );
    final cs = Theme.of(context).colorScheme;
    Widget section(String title, List<(String, String, Color?)> items) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            for (final (k, v, color) in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
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
        margin: const EdgeInsets.all(6),
        child: Padding(padding: const EdgeInsets.all(8), child: content),
      );
    }
    // Chế độ phóng to: các dòng chia đều chiều cao khung, chữ lớn hơn để lấp đầy bảng
    final blocks = [
      if (rows.isNotEmpty) ('TỔNG QUAN', rows),
      if (fr.isNotEmpty) ('GIAO DỊCH NĐTNN', fr),
    ];
    return Card(
      margin: const EdgeInsets.all(6),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          final lines = blocks.fold<int>(0, (int n, b) => n + b.$2.length);
          const headH = 34.0, noteH = 30.0;
          final double rowH = math.max(
            26.0,
            (c.maxHeight - 24 - headH * blocks.length - noteH) /
                math.max(1, lines),
          );
          final size = (rowH * 0.46).clamp(12.0, 16.0);
          return ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              for (final (title, items) in blocks) ...[
                SizedBox(
                  height: headH,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: size,
                        color: cs.primary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                for (final (k, v, color) in items)
                  Container(
                    height: rowH,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          k,
                          style: TextStyle(
                            fontSize: size,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              v,
                              style: TextStyle(
                                fontSize: size,
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              SizedBox(
                height: noteH,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Dữ liệu: DNSE, Vietcap. Khối ngoại tính theo KL.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          );
        },
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
                Expanded(
                  child: Text(
                    'Nhận định thị trường bằng AI',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (b != null)
                  Tag(b['mood'] ?? '', color: Tone.stance(context, b['mood'])),
              ],
            ),
            const SizedBox(height: 6),
            if (state.briefLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (b != null) ...[
              Text(
                b['headline'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
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
                          TextSpan(
                            text: '  (${(t['tickers'] as List).join(', ')})',
                          ),
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
                child: Text(
                  state.briefError!,
                  style: TextStyle(color: Tone.down(context)),
                ),
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
