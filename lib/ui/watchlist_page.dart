import 'package:flutter/material.dart';

import '../state.dart';
import 'analysis_page.dart';
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
                      if (s != null) openAnalysis(context, s);
                    },
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final s = _readSymbol();
                    if (s != null) openAnalysis(context, s);
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
        LayoutBuilder(builder: (context, c) {
          final columns = c.maxWidth > 1000 ? 3 : (c.maxWidth > 640 ? 2 : 1);
          final width = (c.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(spacing: 14, runSpacing: 14, children: [
            for (final sym in state.watchlist)
              SizedBox(width: width, child: _StockCard(sym, onRemove: () => _confirmRemove(state, sym))),
          ]);
        }),
      ],
    );
  }
}

class _StockCard extends StatelessWidget {
  final String symbol;
  final VoidCallback onRemove;
  const _StockCard(this.symbol, {required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.stocks[symbol];
    final saved = state.analyses[symbol];
    final result = saved?['result'] as Map<String, dynamic>?;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openAnalysis(context, symbol),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(symbol, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (result != null) Tag(result['stance'] ?? '', color: Tone.stance(context, result['stance'])),
              const Spacer(),
              if (s != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmt(s.close), style: Theme.of(context).textTheme.titleLarge),
                  Pct(s.num_('change_1d')),
                ]),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.close, size: 18), tooltip: 'Gỡ khỏi danh sách'),
            ]),
            if (s == null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Text(state.loading ? 'Đang tải giá…' : 'Chưa có dữ liệu giá cho mã này.', style: Theme.of(context).textTheme.bodySmall),
              )
            else ...[
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(right: 8), child: Sparkline(s.spark)),
              const SizedBox(height: 8),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Kv('1 tháng', Pct(s.num_('change_1m'))),
                Kv('RSI', Text(fmt(s.num_('rsi14'), 1))),
                Kv('MA20', Text(fmt(s.num_('ma20')))),
                Kv('MA50', Text(fmt(s.num_('ma50')))),
                Kv('KL/TB20', Text(s.num_('vol_ratio') == null ? '–' : 'x${fmt(s.num_('vol_ratio'))}')),
              ]),
              if (s.signals.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final sig in s.signals) Tag(sig)]),
              ],
            ],
            if (result != null) ...[
              const SizedBox(height: 10),
              Text(result['headline'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Phân tích lúc ${timeVN(DateTime.parse(saved!['created_at']))}', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openAnalysis(context, symbol),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(result == null ? 'Phân tích chuyên sâu' : 'Xem phân tích chuyên sâu'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
