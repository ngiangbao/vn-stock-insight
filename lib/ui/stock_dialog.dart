// Cửa sổ pop-up chi tiết một cổ phiếu, hiện lên trên màn hình đang xem: thông tin chính, biểu đồ,
// chỉ số cơ bản, thông tin phiên và lối vào phân tích AI.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/board.dart';
import '../services/fundamentals.dart';
import '../services/market.dart';
import '../state.dart';
import 'analysis_page.dart';
import 'chart.dart';
import 'widgets.dart';

/// Mở cửa sổ chi tiết cổ phiếu (pop-up phía trên màn hình hiện tại).
Future<void> openStock(BuildContext context, String symbol) => showDialog<void>(context: context, builder: (_) => StockDialog(symbol));

class StockDialog extends StatefulWidget {
  final String symbol;
  const StockDialog(this.symbol, {super.key});

  @override
  State<StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<StockDialog> {
  List<Bar>? _bars;
  Snapshot? _snap;
  Map<String, dynamic>? _fund;
  BoardRow? _row;
  bool _barsFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    final cached = state.stocks[widget.symbol];
    if (cached != null) {
      setState(() {
        _snap = cached;
        _bars = cached.bars;
      });
    }
    for (final rows in state.dash.boards.values) {
      final hit = rows.where((r) => r.symbol == widget.symbol);
      if (hit.isNotEmpty) _row = hit.first;
    }
    fetchBars(widget.symbol, days: 1900).then((b) {
      if (!mounted) return;
      setState(() {
        if (b.length >= 2) {
          _bars = b;
          _snap = analyze(widget.symbol, b);
        } else if (_bars == null) {
          _barsFailed = true;
        }
      });
    });
    fetchFundamentals(widget.symbol).then((f) => mounted ? setState(() => _fund = f) : null).catchError((_) {});
    if (_row == null) {
      for (final group in ['HOSE', 'HNX', 'UPCOM']) {
        try {
          final hit = (await fetchBoard(group)).where((r) => r.symbol == widget.symbol);
          if (hit.isNotEmpty) {
            if (mounted) setState(() => _row = hit.first);
            break;
          }
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final symbol = widget.symbol;
    final watching = state.watchlist.contains(symbol);
    final company = (_fund?['company'] as Map?) ?? const {};
    final s = _snap;
    final bars = s?.bars ?? const <Bar>[];
    final close = s?.close;
    final prev = bars.length >= 2 ? bars[bars.length - 2].c : null;
    final diff = close == null || prev == null ? null : (close - prev) * 1000;
    return _PopupShell(
      leading: IconButton(
        tooltip: watching ? 'Bỏ theo dõi' : 'Thêm vào danh sách theo dõi',
        isSelected: watching,
        constraints: _hit,
        visualDensity: VisualDensity.standard,
        icon: const Icon(Icons.star_border),
        selectedIcon: Icon(Icons.star, color: Tone.flat(context)),
        onPressed: () => watching ? state.removeWatch(symbol) : state.addWatch(symbol),
      ),
      title: symbol,
      subtitle: company['ten'] as String?,
      tag: company['nganh'] as String?,
      price: close == null ? null : fmt(close * 1000, 0),
      amplitude: diff == null ? null : _amplitude(diff, s?.num_('change_1d'), 0),
      diff: diff,
      onAnalyze: () => openAnalysis(context, symbol),
      chart: _ChartPanel(symbol, _bars, _snap, _barsFailed),
      side: _Sidebar(symbol, _snap, _fund, _row),
    );
  }
}

/// "▲ +1.650  (+1,42%)": số tiền thay đổi và phần trăm, kèm mũi tên để không chỉ dựa vào màu.
String _amplitude(double diff, num? pct, int digits) {
  final sign = diff > 0 ? '+' : '';
  final arrow = diff > 0 ? '▲' : (diff < 0 ? '▼' : '■');
  final p = pct == null ? '' : '  ($sign${fmt(pct, 2)}%)';
  return '$arrow $sign${fmt(diff, digits)}$p';
}

/// Khung pop-up gần phủ hết cửa sổ: thanh trên (tên, giá và biên độ cùng một hàng, nút Phân tích AI và Đóng ở góc phải),
/// bên dưới là biểu đồ và cột thông tin (trên màn hình hẹp xếp dọc).
class _PopupShell extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle, tag, price, amplitude;
  final double? diff;
  final VoidCallback? onAnalyze;
  final Widget chart, side;
  const _PopupShell({
    this.leading,
    required this.title,
    this.subtitle,
    this.tag,
    this.price,
    this.amplitude,
    this.diff,
    this.onAnalyze,
    required this.chart,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 860;
    return Dialog(
      insetPadding: EdgeInsets.all(narrow ? 8 : 20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Cửa sổ lớn, gần phủ hết cửa sổ app đang mở
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 860;
            return Column(
              children: [
                _TopBar(
                  leading: leading,
                  title: title,
                  subtitle: subtitle,
                  tag: tag,
                  price: price,
                  amplitude: amplitude,
                  diff: diff,
                  onAnalyze: onAnalyze,
                  compact: !wide,
                ),
                const Divider(height: 1),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: chart),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 340,
                              child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: side),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(10),
                          children: [
                            SizedBox(height: 460, child: chart),
                            const SizedBox(height: 10),
                            side,
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Vùng chạm tối thiểu 48 px.
const _hit = BoxConstraints(minWidth: 48, minHeight: 48);

class _TopBar extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle, tag, price, amplitude;
  final double? diff;
  final VoidCallback? onAnalyze;
  final bool compact;
  const _TopBar({
    this.leading,
    required this.title,
    this.subtitle,
    this.tag,
    this.price,
    this.amplitude,
    this.diff,
    this.onAnalyze,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tone = Tone.of(context, diff);
    final nameStyle = text.bodyMedium?.copyWith(color: cs.onSurfaceVariant);
    final nums = const [FontFeature.tabularFigures()];

    // Tên: mã nổi bật, tên đầy đủ luôn hiện (cạnh mã trên màn hình rộng, bên dưới trên màn hình hẹp)
    final titleBlock = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                ),
              ],
              if (tag != null) ...[const SizedBox(width: 10), Tag(tag!)],
            ],
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      child: Row(
        children: [
          ?leading,
          Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerLeft, child: titleBlock),
          ),
          const SizedBox(width: 12),
          // Giá đầy đủ và biên độ nằm ngang hàng nhau, căn phải
          if (price != null)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    label: 'Giá $price, thay đổi ${amplitude ?? ''}',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            price!,
                            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: tone, fontFeatures: nums),
                          ),
                          if (amplitude != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              amplitude!,
                              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: tone, fontFeatures: nums),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          if (onAnalyze != null)
            (compact
                ? IconButton(
                    tooltip: 'Phân tích AI',
                    constraints: _hit,
                    visualDensity: VisualDensity.standard,
                    icon: const Icon(Icons.auto_awesome),
                    onPressed: onAnalyze,
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: onAnalyze,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Phân tích AI'),
                    ),
                  )),
          IconButton(
            tooltip: 'Đóng',
            constraints: _hit,
            visualDensity: VisualDensity.standard,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final String symbol;
  final List<Bar>? bars;
  final Snapshot? snap;
  final bool failed;
  const _ChartPanel(this.symbol, this.bars, this.snap, this.failed);

  @override
  Widget build(BuildContext context) {
    final b = bars;
    if (b == null || b.length < 2) {
      return Center(child: failed ? Text('Không lấy được dữ liệu giá $symbol.') : const CircularProgressIndicator());
    }
    final last = b.last, prev = b[b.length - 2];
    final pct = prev.c == 0 ? null : (last.c / prev.c - 1) * 100;
    final cs = Theme.of(context).colorScheme;
    Widget kv(String k, String v) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k ',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(symbol, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(vnDate(last.t), style: TextStyle(color: cs.onSurfaceVariant)),
              kv('Mở', fmt(last.o)),
              kv('Cao', fmt(last.h)),
              kv('Thấp', fmt(last.l)),
              kv('Đóng', fmt(last.c)),
              Pct(pct),
              kv('KL', fmt(last.v, 0)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: StockChart(symbol, b, expand: true, key: ValueKey('$symbol-${b.length}'))),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String symbol;
  final Snapshot? snap;
  final Map<String, dynamic>? fund;
  final BoardRow? row;
  const _Sidebar(this.symbol, this.snap, this.fund, this.row);

  static Color _ceil(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFD0A8FF) : const Color(0xFF6A1FB0);
  static Color _floor(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF4DD0E1) : const Color(0xFF007082);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final company = (fund?['company'] as Map?) ?? const {};
    final ratios = ((fund?['chi_so_ttm_theo_quy'] as List?)?.lastOrNull as Map?) ?? const {};
    final cap = company['von_hoa_ty_dong'] as num?;
    final roe = ratios['roe'] as num?;
    final loading = fund == null;
    String f(num? v, [int d = 1]) => v == null ? (loading ? '…' : '–') : fmt(v, d);

    Widget mini(String label, String value, {Color? color}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.titleMedium?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );

    Widget line(String label, List<InlineSpan> value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Text.rich(
            TextSpan(children: value),
            style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
    TextSpan span(String t, [Color? c]) => TextSpan(
      text: t,
      style: TextStyle(color: c),
    );

    final r = row;
    final lastBar = snap?.bars.lastOrNull;
    final hi = r != null ? r.high / 1000 : lastBar?.h;
    final lo = r != null ? r.low / 1000 : lastBar?.l;
    final vol = r != null ? r.volume : lastBar?.v;
    final saved = AppScope.of(context).analysisForToday(symbol);
    final stance = (saved?['result'] as Map?)?['stance'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bar_chart, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'CHỈ SỐ CƠ BẢN',
              style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.6),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 66,
          children: [
            mini('P/E', f(ratios['pe'] as num?)),
            mini('P/B', f(ratios['pb'] as num?)),
            mini('ROE', roe == null ? f(null) : '${fmt(roe * 100, 1)}%', color: roe == null ? null : Tone.of(context, roe)),
            mini('Vốn hóa', cap == null ? f(null) : '${fmt(cap, 0)} tỷ'),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'THÔNG TIN PHIÊN',
                style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
              const SizedBox(height: 4),
              line(
                'Giá trần / sàn',
                r == null
                    ? [span('–')]
                    : [span(fmt(r.ceil / 1000), _ceil(context)), span(' / '), span(fmt(r.floor / 1000), _floor(context))],
              ),
              line('Cao / Thấp', [span(fmt(hi)), span(' / '), span(fmt(lo))]),
              line('Khối lượng khớp', [span(vol == null ? '–' : fmt(vol, 0))]),
              line(
                'NN Mua / Bán',
                r == null
                    ? [span('–')]
                    : [span(fmt(r.foreignBuy, 0), Tone.up(context)), span(' / '), span(fmt(r.foreignSell, 0), Tone.down(context))],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Phân tích AI cho $symbol',
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Nhận định, luận điểm, kịch bản và rủi ro dựa trên dữ liệu kỹ thuật, số liệu cơ bản và tin tức.',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
              if (stance != null) ...[
                const SizedBox(height: 8),
                Center(child: Tag('Hôm nay: $stance', color: Tone.stance(context, stance))),
              ],
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => openAnalysis(context, symbol),
                child: Text(saved == null ? 'Mở phân tích AI chi tiết' : 'Xem phân tích đã lưu'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mở cửa sổ chi tiết của một chỉ số (VNINDEX, HNX, UPCOM, VN30, phái sinh, chỉ số thế giới).
Future<void> openIndex(BuildContext context, IndexMeta meta) => showDialog<void>(context: context, builder: (_) => IndexDialog(meta));

class IndexDialog extends StatefulWidget {
  final IndexMeta meta;
  const IndexDialog(this.meta, {super.key});

  @override
  State<IndexDialog> createState() => _IndexDialogState();
}

class _IndexDialogState extends State<IndexDialog> {
  List<Bar>? _bars;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final m = widget.meta;
    final known = AppScope.of(context).dash.quotes[m.symbol]?.bars;
    if (known != null && known.length >= 2) setState(() => _bars = known);
    final b = await fetchBars(m.symbol, days: 1900, kind: m.kind);
    if (!mounted) return;
    setState(() {
      if (b.length >= 2) {
        _bars = b;
      } else if (_bars == null) {
        _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meta;
    final b = _bars;
    final last = b == null || b.length < 2 ? null : b.last;
    final prev = b == null || b.length < 2 ? null : b[b.length - 2];
    final diff = last == null || prev == null ? null : last.c - prev.c;
    final pct = diff == null || prev!.c == 0 ? null : diff / prev.c * 100;
    return _PopupShell(
      title: m.name,
      subtitle: m.desc,
      price: last == null ? null : fmt(last.c, 2),
      amplitude: diff == null ? null : _amplitude(diff, pct, 2),
      diff: diff,
      chart: _ChartPanel(m.symbol, b, null, _failed),
      side: _IndexSidebar(b),
    );
  }
}

class _IndexSidebar extends StatelessWidget {
  final List<Bar>? bars;
  const _IndexSidebar(this.bars);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final b = bars;
    if (b == null || b.length < 2) return const SizedBox.shrink();
    double? back(int n) => b.length > n ? (b.last.c / b[b.length - 1 - n].c - 1) * 100 : null;
    final year = b.skip(b.length > 250 ? b.length - 250 : 0);
    final hi = year.map((x) => x.h).reduce(math.max), lo = year.map((x) => x.l).reduce(math.min);
    final label = text.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.6);

    Widget line(String k, Widget v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          DefaultTextStyle.merge(
            style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
            child: v,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('THÔNG TIN PHIÊN', style: label),
        const SizedBox(height: 4),
        line('Mở cửa', Text(fmt(b.last.o, 2))),
        line('Cao / Thấp', Text('${fmt(b.last.h, 2)} / ${fmt(b.last.l, 2)}')),
        line('Khối lượng', Text(fmt(b.last.v, 0))),
        line('Đỉnh / đáy 52 tuần', Text('${fmt(hi, 2)} / ${fmt(lo, 2)}')),
        const Divider(height: 24),
        Text('BIẾN ĐỘNG', style: label),
        const SizedBox(height: 4),
        line('1 tuần', Pct(back(5))),
        line('1 tháng', Pct(back(20))),
        line('3 tháng', Pct(back(60))),
        line('1 năm', Pct(back(250))),
      ],
    );
  }
}
