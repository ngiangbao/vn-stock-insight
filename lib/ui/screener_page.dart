import 'package:flutter/material.dart';

import '../services/market.dart';
import '../state.dart';
import 'stock_dialog.dart';
import 'widgets.dart';

class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key});

  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage> {
  String _sortKey = 'tech_score';
  bool _asc = false;

  static const _cols = [
    ('symbol', 'Mã'),
    ('close', 'Giá'),
    ('change_1d', '1 ngày'),
    ('change_1w', '1 tuần'),
    ('change_1m', '1 tháng'),
    ('change_3m', '3 tháng'),
    ('rsi14', 'RSI'),
    ('vol_ratio', 'KL/TB20'),
    ('from_high_52w', 'Từ đỉnh 52T'),
    ('tech_score', 'Điểm KT'),
  ];

  num? _value(Snapshot s, String k) => k == 'tech_score' ? s.techScore : s.data[k] as num?;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rows = state.vn30Stocks.toList()
      ..sort((a, b) {
        final int r;
        if (_sortKey == 'symbol') {
          r = a.symbol.compareTo(b.symbol);
        } else {
          r = (_value(a, _sortKey) ?? -1e9).compareTo(_value(b, _sortKey) ?? -1e9);
        }
        return _asc ? r : -r;
      });
    final sortIndex = _cols.indexWhere((c) => c.$1 == _sortKey);

    return PageFrame(
      title: 'Bộ lọc kỹ thuật VN30',
      onRefresh: state.refresh,
      children: [
        Text('Bấm tiêu đề cột để sắp xếp, bấm vào dòng để phân tích chuyên sâu. "Điểm KT" là tổng điểm từ các tín hiệu '
            'xu hướng MA, RSI, MACD và khối lượng (càng cao càng tích cực).',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: sortIndex,
              sortAscending: _asc,
              columnSpacing: 22,
              showCheckboxColumn: false,
              columns: [
                for (final c in _cols)
                  DataColumn(
                    label: Text(c.$2),
                    numeric: c.$1 != 'symbol',
                    onSort: (_, _) => setState(() {
                      _asc = _sortKey == c.$1 ? !_asc : false;
                      _sortKey = c.$1;
                    }),
                  ),
                const DataColumn(label: Text('Tín hiệu')),
              ],
              rows: [
                for (final s in rows)
                  DataRow(
                    onSelectChanged: (_) => openStock(context, s.symbol),
                    cells: [
                      DataCell(Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(fmt(s.close))),
                      for (final k in ['change_1d', 'change_1w', 'change_1m', 'change_3m']) DataCell(Pct(s.num_(k))),
                      DataCell(Text(fmt(s.num_('rsi14'), 1))),
                      DataCell(Text(s.num_('vol_ratio') == null ? '–' : 'x${fmt(s.num_('vol_ratio'))}')),
                      DataCell(Pct(s.num_('from_high_52w'))),
                      DataCell(Tag('${s.techScore > 0 ? '+' : ''}${s.techScore}', color: Tone.of(context, s.techScore))),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(s.signals.isEmpty ? '–' : s.signals.join(' · '), style: Theme.of(context).textTheme.bodySmall),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
