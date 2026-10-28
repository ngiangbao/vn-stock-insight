import 'package:flutter/material.dart';

import '../services/fundamentals.dart';
import '../state.dart';
import 'analysis_page.dart';
import 'stock_dialog.dart';
import 'widgets.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final _input = TextEditingController();
  String? _error;
  final _profiles = <String, ({String name, String sector})>{};
  final _requested = <String>{};

  void _ensureProfiles(List<String> symbols) {
    for (final sym in symbols) {
      if (!_requested.add(sym)) continue;
      fetchCompanyProfile(sym).then((p) {
        if (p != null && mounted) setState(() => _profiles[sym] = p);
      });
    }
  }

  String? _readSymbol() {
    final s = _input.text.trim().toUpperCase();
    if (!AppState.symbolPattern.hasMatch(s)) {
      setState(() => _error = 'Nhập mã cổ phiếu gồm 3 chữ cái, ví dụ FPT, HPG, VNM.');
      return null;
    }
    setState(() => _error = null);
    return s;
  }

  Future<void> _confirmRemove(AppState state, String symbol) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Gỡ $symbol?'),
        content: Text('Gỡ $symbol khỏi danh sách theo dõi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Gỡ')),
        ],
      ),
    );
    if (ok == true) state.removeWatch(symbol);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureProfiles(state.watchlist));
    return PageFrame(
      title: 'Theo dõi',
      onRefresh: state.refresh,
      children: [
        _Heading(count: state.watchlist.length),
        const SizedBox(height: 12),
        if (state.watchlist.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Danh sách đang trống. Nhập mã ở ô tra cứu bên dưới rồi bấm "Theo dõi".'),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 900) {
              return _WatchTable(symbols: state.watchlist, profiles: _profiles, onRemove: (sym) => _confirmRemove(state, sym));
            }
            // Mọi thẻ có cùng kích thước cố định; số cột thay đổi theo chiều rộng cửa sổ
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (final sym in state.watchlist)
                  SizedBox(
                    width: _StockCard.width,
                    height: _StockCard.height,
                    child: _StockCard(sym, onRemove: () => _confirmRemove(state, sym)),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tra cứu cổ phiếu', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Nhập mã bất kỳ trên HOSE, HNX, UPCoM để AI phân tích chuyên sâu: luận điểm đầu tư, kết quả kinh doanh, '
                  'định giá, kỹ thuật, lịch sự kiện và bảng chấm điểm 8 tiêu chí.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _input,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(hintText: 'Mã cổ phiếu, ví dụ FPT', errorText: _error, errorMaxLines: 2),
                        onSubmitted: (_) {
                          final s = _readSymbol();
                          if (s != null) openStock(context, s);
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        final s = _readSymbol();
                        if (s != null) openStock(context, s);
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Phân tích AI'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final s = _readSymbol();
                        if (s != null) {
                          state.addWatch(s);
                          _input.clear();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Theo dõi'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('AI đang dùng: ${state.aiLabel}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StockCard extends StatelessWidget {
  static const width = 300.0, height = 330.0;
  final String symbol;
  final VoidCallback onRemove;
  const _StockCard(this.symbol, {required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.stocks[symbol];
    final saved = state.analyses[symbol];
    final result = saved?['result'] as Map<String, dynamic>?;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openStock(context, symbol),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tiêu đề: mã, nhận định, giá, nút gỡ
              SizedBox(
                height: 52,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(symbol, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          if (result != null) Tag(result['stance'] ?? '', color: Tone.stance(context, result['stance'])),
                        ],
                      ),
                    ),
                    if (s != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fmt(s.close), style: text.titleLarge),
                          Pct(s.num_('change_1d')),
                        ],
                      ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Gỡ khỏi danh sách',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Biểu đồ nhỏ: bấm để mở biểu đồ chi tiết
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Mở biểu đồ chi tiết',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => openStock(context, symbol),
                    child: s == null
                        ? SizedBox(
                            height: 64,
                            child: Center(child: Text(state.loading ? 'Đang tải giá…' : 'Chưa có dữ liệu giá', style: text.bodySmall)),
                          )
                        : Sparkline(s.spark, height: 64),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: s == null
                    ? null
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Kv('1 tháng', Pct(s.num_('change_1m'))),
                          Kv('RSI', Text(fmt(s.num_('rsi14'), 1))),
                          Kv('MA20', Text(fmt(s.num_('ma20')))),
                          Kv('KL/TB20', Text(s.num_('vol_ratio') == null ? '–' : 'x${fmt(s.num_('vol_ratio'))}')),
                          const SizedBox(width: 2),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              // Tín hiệu: tối đa 2 dòng, phần dư hiển thị dạng "+n"
              SizedBox(
                height: 50,
                child: s == null || s.signals.isEmpty
                    ? null
                    : ClipRect(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final sig in s.signals.take(2)) Tag(sig),
                            if (s.signals.length > 2) Tag('+${s.signals.length - 2}'),
                          ],
                        ),
                      ),
              ),
              Expanded(
                child: result == null
                    ? const SizedBox()
                    : Text(
                        result['headline'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => openStock(context, symbol),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(result == null ? 'Phân tích AI' : 'Xem phân tích'),
                  ),
                  TextButton.icon(
                    onPressed: () => openStock(context, symbol),
                    icon: const Icon(Icons.candlestick_chart, size: 18),
                    label: const Text('Biểu đồ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final int count;
  const _Heading({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: Tone.flat(context)),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Danh mục Theo dõi Cá nhân', style: text.titleLarge)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Theo dõi sát sao biến động giá, xu hướng ngắn hạn và luận điểm đầu tư các mã cổ phiếu mục tiêu',
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Đang theo dõi: ',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                TextSpan(
                  text: '$count',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' mã',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Điểm kỹ thuật quy về thang 0–5 từ điểm thô (−6…+6) của bộ chỉ báo.
int techScore5(int raw) => ((raw + 6) / 12 * 5).round().clamp(0, 5);

/// Bảng danh mục theo dõi: mã, tên, ngành, biểu đồ 30 phiên, giá, biến động, điểm kỹ thuật, thao tác.
class _WatchTable extends StatelessWidget {
  final List<String> symbols;
  final Map<String, ({String name, String sector})> profiles;
  final ValueChanged<String> onRemove;
  const _WatchTable({required this.symbols, required this.profiles, required this.onRemove});

  static const _symW = 68.0, _chartW = 130.0, _numW = 84.0, _scoreW = 92.0, _actW = 232.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    final head = text.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700);

    Widget cell(double? w, Widget child, {int flex = 0, Alignment align = Alignment.centerLeft}) {
      final box = Align(alignment: align, child: child);
      return w != null ? SizedBox(width: w, child: box) : Expanded(flex: flex, child: box);
    }

    Widget header() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          cell(_symW, Text('Mã CK', style: head)),
          cell(null, Text('Tên doanh nghiệp', style: head), flex: 3),
          cell(null, Text('Ngành', style: head), flex: 3),
          cell(
            _chartW,
            Text('Biểu đồ 30 phiên', style: head, textAlign: TextAlign.center),
            align: Alignment.center,
          ),
          cell(_numW, Text('Giá khớp', style: head), align: Alignment.centerRight),
          cell(_numW, Text('Biến động 1D', style: head), align: Alignment.centerRight),
          cell(_numW, Text('Biến động 1M', style: head), align: Alignment.centerRight),
          cell(_scoreW, Text('Điểm kỹ thuật', style: head), align: Alignment.center),
          cell(_actW, Text('Thao tác', style: head), align: Alignment.center),
        ],
      ),
    );

    Widget row(String sym) {
      final s = state.stocks[sym];
      final profile = profiles[sym];
      final score = s == null ? null : techScore5(s.techScore);
      return InkWell(
        onTap: () => openStock(context, sym),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              cell(_symW, Text(sym, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              cell(null, Text(profile?.name ?? '…', maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium), flex: 3),
              cell(null, profile == null || profile.sector.isEmpty ? const Text('–') : Tag(profile.sector), flex: 3),
              cell(
                _chartW,
                s == null
                    ? Text('–', style: text.bodySmall)
                    : Semantics(
                        label: 'Biểu đồ giá 30 phiên gần nhất của $sym',
                        child: SizedBox(
                          width: 130,
                          child: Sparkline(s.spark.length > 30 ? s.spark.sublist(s.spark.length - 30) : s.spark, height: 36),
                        ),
                      ),
                align: Alignment.center,
              ),
              cell(
                _numW,
                Text(
                  s == null ? '–' : fmt(s.close),
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Tone.of(context, s?.num_('change_1d')),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                align: Alignment.centerRight,
              ),
              cell(_numW, Pct(s?.num_('change_1d')), align: Alignment.centerRight),
              cell(_numW, Pct(s?.num_('change_1m')), align: Alignment.centerRight),
              cell(
                _scoreW,
                score == null
                    ? const Text('–')
                    : Tooltip(
                        message: 'Điểm kỹ thuật tổng hợp từ xu hướng MA, RSI, MACD và khối lượng (thang 0–5)',
                        child: Tag('$score/5', color: cs.primary),
                      ),
                align: Alignment.center,
              ),
              cell(
                _actW,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Xem biểu đồ $sym',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        visualDensity: VisualDensity.standard,
                        icon: const Icon(Icons.bar_chart),
                        onPressed: () => openStock(context, sym),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
                        onPressed: () => openAnalysis(context, sym),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('AI Report'),
                      ),
                      IconButton(
                        tooltip: 'Gỡ $sym khỏi danh sách',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        visualDensity: VisualDensity.standard,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onRemove(sym),
                      ),
                    ],
                  ),
                ),
                align: Alignment.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [header(), for (final sym in symbols) row(sym)]),
    );
  }
}
