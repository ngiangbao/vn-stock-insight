import 'package:flutter/material.dart';

import '../state.dart';
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
    return PageFrame(
      title: 'Theo dõi',
      onRefresh: state.refresh,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tra cứu cổ phiếu', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Nhập mã bất kỳ trên HOSE, HNX, UPCoM để AI phân tích chuyên sâu: luận điểm đầu tư, kết quả kinh doanh, '
                  'định giá, kỹ thuật, lịch sự kiện và bảng chấm điểm 8 tiêu chí.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
              ]),
              const SizedBox(height: 6),
              Text('AI đang dùng: ${state.aiLabel}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        if (state.watchlist.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Danh sách đang trống. Nhập mã ở ô phía trên rồi bấm "Theo dõi".'))),
        // Mọi thẻ có cùng kích thước cố định; số cột thay đổi theo chiều rộng cửa sổ
        Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
          for (final sym in state.watchlist)
            SizedBox(
              width: _StockCard.width,
              height: _StockCard.height,
              child: _StockCard(sym, onRemove: () => _confirmRemove(state, sym)),
            ),
        ]),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tiêu đề: mã, nhận định, giá, nút gỡ
            SizedBox(
              height: 52,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(symbol, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (result != null) Tag(result['stance'] ?? '', color: Tone.stance(context, result['stance'])),
                  ]),
                ),
                if (s != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(fmt(s.close), style: text.titleLarge),
                    Pct(s.num_('change_1d')),
                  ]),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Gỡ khỏi danh sách',
                  visualDensity: VisualDensity.compact,
                ),
              ]),
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
                          child: Center(
                            child: Text(state.loading ? 'Đang tải giá…' : 'Chưa có dữ liệu giá', style: text.bodySmall),
                          ),
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
                  : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Kv('1 tháng', Pct(s.num_('change_1m'))),
                      Kv('RSI', Text(fmt(s.num_('rsi14'), 1))),
                      Kv('MA20', Text(fmt(s.num_('ma20')))),
                      Kv('KL/TB20', Text(s.num_('vol_ratio') == null ? '–' : 'x${fmt(s.num_('vol_ratio'))}')),
                      const SizedBox(width: 2),
                    ]),
            ),
            const SizedBox(height: 6),
            // Tín hiệu: tối đa 2 dòng, phần dư hiển thị dạng "+n"
            SizedBox(
              height: 50,
              child: s == null || s.signals.isEmpty
                  ? null
                  : ClipRect(
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final sig in s.signals.take(2)) Tag(sig),
                        if (s.signals.length > 2) Tag('+${s.signals.length - 2}'),
                      ]),
                    ),
            ),
            Expanded(
              child: result == null
                  ? const SizedBox()
                  : Text(result['headline'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Row(children: [
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
            ]),
          ]),
        ),
      ),
    );
  }
}
