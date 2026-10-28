import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/board.dart';
import '../services/market.dart';
import '../state.dart';
import 'stock_dialog.dart';
import 'widgets.dart';

/// Accepts comma, semicolon, space, or line separated symbols and removes duplicates.
List<String> parseTickerCodes(String input) {
  final seen = <String>{};
  for (final part in input.toUpperCase().split(RegExp(r'[,;\s]+'))) {
    final code = part.trim();
    if (AppState.symbolPattern.hasMatch(code)) seen.add(code);
  }
  return seen.toList();
}

class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key});

  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage> {
  final _query = TextEditingController();
  final Set<String> _symbols = {};
  Map<String, List<BoardRow>> _boards = {};
  bool _loading = false;
  String? _error;
  String? _selected = 'HPG';
  String _exchange = 'Tất cả';
  String _move = 'Tất cả';
  String _sort = 'change';
  bool _descending = true;
  DateTime? _updatedAt;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBoards());
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (isTradingTime(DateTime.now())) _refreshBoards();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _refreshBoards() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final groups = ['HOSE', 'HNX', 'UPCOM', 'VN30'];
    final values = await Future.wait(
      groups.map((group) async {
        try {
          return await fetchBoard(group);
        } catch (_) {
          return <BoardRow>[];
        }
      }),
    );
    if (!mounted) return;
    final next = <String, List<BoardRow>>{
      for (final (i, group) in groups.indexed)
        if (values[i].isNotEmpty) group: values[i],
    };
    setState(() {
      if (next.isNotEmpty) _boards = next;
      _loading = false;
      _updatedAt = DateTime.now();
      if (next.isEmpty) {
        _error = 'Chưa lấy được bảng giá. Kiểm tra kết nối mạng rồi thử lại.';
      }
      final symbols = _allRows.map((row) => row.symbol).toSet();
      if (_selected == null || !symbols.contains(_selected)) {
        _selected = symbols.contains('HPG')
            ? 'HPG'
            : _allRows.firstOrNull?.symbol;
      }
    });
  }

  List<BoardRow> get _allRows {
    final unique = <String, BoardRow>{};
    for (final group in ['HOSE', 'HNX', 'UPCOM', 'VN30']) {
      for (final row in _boards[group] ?? const <BoardRow>[]) {
        unique.putIfAbsent(row.symbol, () => row);
      }
    }
    return unique.values.toList();
  }

  List<BoardRow> get _visibleRows {
    final codes = _symbols;
    final rows = _allRows.where((row) {
      if (_exchange != 'Tất cả' &&
          row.exchange != _exchange &&
          !(_exchange == 'VN30' &&
              (_boards['VN30'] ?? []).any((r) => r.symbol == row.symbol))) {
        return false;
      }
      if (codes.isNotEmpty && !codes.contains(row.symbol)) return false;
      if (_move == 'Tăng' && row.dir <= 0) return false;
      if (_move == 'Giảm' && row.dir >= 0) return false;
      if (_move == 'Đứng giá' && row.dir != 0) return false;
      return true;
    }).toList();
    rows.sort((a, b) {
      final comparison = switch (_sort) {
        'price' => a.price.compareTo(b.price),
        'volume' => a.volume.compareTo(b.volume),
        'symbol' => a.symbol.compareTo(b.symbol),
        _ => a.pct.compareTo(b.pct),
      };
      return _descending ? -comparison : comparison;
    });
    return rows;
  }

  void _applyCodes() {
    final codes = parseTickerCodes(_query.text);
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập mã hợp lệ, ví dụ HPG, FPT, VCB.')),
      );
      return;
    }
    setState(() {
      _symbols.addAll(codes);
      _query.clear();
      _selected = codes.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bộ lọc thị trường'),
          actions: [
            if (_updatedAt != null && MediaQuery.sizeOf(context).width >= 760)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    'Giá lúc ${timeVN(_updatedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: _refreshBoards,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Làm mới bảng giá',
                  ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Bảng giá realtime'),
              Tab(text: 'Bộ lọc kỹ thuật'),
            ],
          ),
        ),
        body: Column(
          children: [
            _MarketIndexStrip(dash: state.dash),
            Expanded(
              child: TabBarView(
                children: [
                  _RealtimeFilterTab(
                    rows: _visibleRows,
                    allRows: _allRows,
                    selected: _selected,
                    codes: _symbols,
                    query: _query,
                    exchange: _exchange,
                    move: _move,
                    sort: _sort,
                    descending: _descending,
                    error: _error,
                    loading: _loading,
                    updatedAt: _updatedAt,
                    onAddCodes: _applyCodes,
                    onRemoveCode: (code) =>
                        setState(() => _symbols.remove(code)),
                    onClearCodes: () => setState(_symbols.clear),
                    onExchangeChanged: (value) =>
                        setState(() => _exchange = value),
                    onMoveChanged: (value) => setState(() => _move = value),
                    onSort: (value) => setState(() {
                      if (_sort == value) {
                        _descending = !_descending;
                      } else {
                        _sort = value;
                        _descending = value != 'symbol';
                      }
                    }),
                    onSelect: (symbol) => setState(() => _selected = symbol),
                    onRetry: _refreshBoards,
                  ),
                  const _TechnicalFilterTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketIndexStrip extends StatelessWidget {
  final MarketDashboard dash;
  const _MarketIndexStrip({required this.dash});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 102,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final meta in indexMetas.where((m) => m.kind != 'derivative'))
            _IndexMiniCard(meta: meta, quote: dash.quotes[meta.symbol]),
        ];
        const gap = 8.0, minCard = 200.0, pad = 14.0;
        final inner = constraints.maxWidth - pad * 2;
        // Đủ chỗ: mọi thẻ chia đều chiều rộng, không cuộn. Quá hẹp mới cuộn ngang.
        if (inner >= cards.length * minCard + (cards.length - 1) * gap) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(pad, 9, pad, 7),
            child: Row(
              children: [
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(child: card),
                ],
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(pad, 9, pad, 7),
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) =>
              SizedBox(width: minCard + 30, child: cards[index]),
          separatorBuilder: (_, _) => const SizedBox(width: gap),
          itemCount: cards.length,
        );
      },
    ),
  );
}

class _IndexMiniCard extends StatelessWidget {
  final IndexMeta meta;
  final IndexQuote? quote;
  const _IndexMiniCard({required this.meta, required this.quote});

  @override
  Widget build(BuildContext context) {
    final color = Tone.of(context, quote?.pct);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openIndex(context, meta),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.name,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    quote?.pct == null
                        ? '–'
                        : '${quote!.pct! >= 0 ? '+' : ''}${fmt(quote!.pct)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    fmt(quote?.last, 2),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Sparkline(quote?.spark ?? const [], height: 34),
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

class _RealtimeFilterTab extends StatelessWidget {
  final List<BoardRow> rows, allRows;
  final String? selected, error, sort;
  final Set<String> codes;
  final TextEditingController query;
  final String exchange, move;
  final bool descending, loading;
  final DateTime? updatedAt;
  final VoidCallback onAddCodes, onClearCodes, onRetry;
  final ValueChanged<String> onRemoveCode,
      onExchangeChanged,
      onMoveChanged,
      onSort,
      onSelect;

  const _RealtimeFilterTab({
    required this.rows,
    required this.allRows,
    required this.selected,
    required this.codes,
    required this.query,
    required this.exchange,
    required this.move,
    required this.sort,
    required this.descending,
    required this.error,
    required this.loading,
    required this.updatedAt,
    required this.onAddCodes,
    required this.onClearCodes,
    required this.onRemoveCode,
    required this.onExchangeChanged,
    required this.onMoveChanged,
    required this.onSort,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1120;
      final body = Column(
        children: [
          _MultiCodeSearch(
            controller: query,
            codes: codes,
            knownSymbols: allRows.map((r) => r.symbol).toSet(),
            onAdd: onAddCodes,
            onClear: onClearCodes,
            onRemove: onRemoveCode,
          ),
          _QuoteFilters(
            exchange: exchange,
            move: move,
            count: rows.length,
            updatedAt: updatedAt,
            onExchangeChanged: onExchangeChanged,
            onMoveChanged: onMoveChanged,
          ),
          if (error != null)
            MaterialBanner(
              content: Text(error!),
              leading: const Icon(Icons.wifi_off),
              actions: [
                TextButton(onPressed: onRetry, child: const Text('Thử lại')),
              ],
            ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 62,
                        child: _QuoteTable(
                          rows: rows,
                          selected: selected,
                          sort: sort,
                          descending: descending,
                          loading: loading,
                          onSort: onSort,
                          onSelect: onSelect,
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth * .36).clamp(360.0, 500.0),
                        child: _SelectedQuotePanel(
                          row: _findSelected(allRows, selected),
                          onAnalyze: selected == null
                              ? null
                              : () => openStock(context, selected!),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      SizedBox(
                        height: 390,
                        child: _QuoteTable(
                          rows: rows,
                          selected: selected,
                          sort: sort,
                          descending: descending,
                          loading: loading,
                          onSort: onSort,
                          onSelect: onSelect,
                        ),
                      ),
                      SizedBox(
                        height: 520,
                        child: _SelectedQuotePanel(
                          row: _findSelected(allRows, selected),
                          onAnalyze: selected == null
                              ? null
                              : () => openStock(context, selected!),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
      return body;
    },
  );

  BoardRow? _findSelected(List<BoardRow> rows, String? symbol) => symbol == null
      ? null
      : rows.where((row) => row.symbol == symbol).firstOrNull;
}

class _MultiCodeSearch extends StatelessWidget {
  final TextEditingController controller;
  final Set<String> codes, knownSymbols;
  final VoidCallback onAdd, onClear;
  final ValueChanged<String> onRemove;

  const _MultiCodeSearch({
    required this.controller,
    required this.codes,
    required this.knownSymbols,
    required this.onAdd,
    required this.onClear,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.manage_search, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Tìm nhiều mã cùng lúc',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ngăn cách bằng dấu phẩy, dấu cách hoặc xuống dòng',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onAdd(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Ví dụ: HPG, FPT, VCB',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm mã'),
                  ),
                ],
              ),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Đang lọc:', style: theme.textTheme.bodySmall),
                    for (final code in codes)
                      InputChip(
                        label: Text(code),
                        onDeleted: () => onRemove(code),
                        visualDensity: VisualDensity.compact,
                      ),
                    TextButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Xóa mã'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    for (final code in codes.where(
                      (code) => !knownSymbols.contains(code),
                    ))
                      Text(
                        '$code chưa có trong bảng giá',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteFilters extends StatelessWidget {
  final String exchange, move;
  final int count;
  final DateTime? updatedAt;
  final ValueChanged<String> onExchangeChanged, onMoveChanged;

  const _QuoteFilters({
    required this.exchange,
    required this.move,
    required this.count,
    required this.updatedAt,
    required this.onExchangeChanged,
    required this.onMoveChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 2, 14, 7),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final option in ['Tất cả', 'HOSE', 'HNX', 'UPCOM', 'VN30'])
          ChoiceChip(
            label: Text(option),
            selected: exchange == option,
            onSelected: (_) => onExchangeChanged(option),
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: move,
          underline: const SizedBox.shrink(),
          items: [
            for (final value in ['Tất cả', 'Tăng', 'Giảm', 'Đứng giá'])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (value) {
            if (value != null) onMoveChanged(value);
          },
        ),
        Text('$count mã', style: Theme.of(context).textTheme.bodySmall),
        if (updatedAt != null)
          Text(
            'Làm mới định kỳ 45 giây',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

class _QuoteTable extends StatelessWidget {
  final List<BoardRow> rows;
  final String? selected, sort;
  final bool descending, loading;
  final ValueChanged<String> onSort, onSelect;

  const _QuoteTable({
    required this.rows,
    required this.selected,
    required this.sort,
    required this.descending,
    required this.loading,
    required this.onSort,
    required this.onSelect,
  });

  static const _baseWidths = [118.0, 84.0, 88.0, 98.0, 86.0, 86.0];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 2, 6, 12),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = _baseWidths.fold<double>(
            0,
            (sum, width) => sum + width,
          );
          final totalWidth = math.max(minWidth, constraints.maxWidth);
          final scale = totalWidth / minWidth;
          final widths = [for (final width in _baseWidths) width * scale];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
                child: Row(
                  children: [
                    Text(
                      'Kết quả lọc',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tag('${rows.length} mã'),
                    const Spacer(),
                    if (loading)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      children: [
                        _QuoteRow(
                          widths: widths,
                          header: true,
                          values: const [
                            'MÃ',
                            'GIÁ',
                            'THAY ĐỔI',
                            'KL KHỚP',
                            'MUA 1',
                            'BÁN 1',
                          ],
                          sort: sort,
                          descending: descending,
                          onSort: onSort,
                        ),
                        Expanded(
                          child: rows.isEmpty
                              ? Center(
                                  child: Text(
                                    loading
                                        ? 'Đang tải bảng giá…'
                                        : 'Không tìm thấy mã phù hợp.',
                                    style: textTheme.bodyMedium,
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    return InkWell(
                                      onTap: () => onSelect(row.symbol),
                                      child: _QuoteRow(
                                        widths: widths,
                                        selected: row.symbol == selected,
                                        values: [
                                          row.symbol,
                                          fmt(row.price / 1000, 2),
                                          '${row.pct >= 0 ? '+' : ''}${fmt(row.pct)}%',
                                          fmt(row.volume, 0),
                                          row.bids.isEmpty
                                              ? '–'
                                              : fmt(
                                                  row.bids.first.price / 1000,
                                                  2,
                                                ),
                                          row.asks.isEmpty
                                              ? '–'
                                              : fmt(
                                                  row.asks.first.price / 1000,
                                                  2,
                                                ),
                                        ],
                                        tones: [
                                          null,
                                          Tone.of(context, row.dir),
                                          Tone.of(context, row.dir),
                                          null,
                                          Tone.up(context),
                                          Tone.down(context),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (rows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Chọn một mã để xem biểu đồ và sổ lệnh chi tiết.',
                                style: textTheme.bodySmall,
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _QuoteRow extends StatelessWidget {
  final List<double> widths;
  final List<String> values;
  final List<Color?>? tones;
  final bool header, selected, descending;
  final String? sort;
  final ValueChanged<String>? onSort;

  const _QuoteRow({
    required this.widths,
    required this.values,
    this.tones,
    this.header = false,
    this.selected = false,
    this.sort,
    this.descending = true,
    this.onSort,
  });

  static const _sortKeys = [
    'symbol',
    'price',
    'change',
    'volume',
    'bid',
    'ask',
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: header ? 40 : 50,
    color: selected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
        : (header
              ? Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: .48)
              : null),
    child: Row(
      children: [
        for (final (i, value) in values.indexed)
          SizedBox(
            width: widths[i],
            child: header
                ? TextButton(
                    onPressed: () => onSort?.call(_sortKeys[i]),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: i == 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                    ),
                    child: Row(
                      mainAxisAlignment: i == 0
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (sort == _sortKeys[i])
                          Icon(
                            descending
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 12,
                          ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: i == 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              tones?[i] ??
                              Theme.of(context).colorScheme.onSurface,
                          fontSize: i == 0 ? 13 : 12,
                          fontWeight: i < 3 ? FontWeight.w600 : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    ),
  );
}

class _SelectedQuotePanel extends StatefulWidget {
  final BoardRow? row;
  final VoidCallback? onAnalyze;
  const _SelectedQuotePanel({required this.row, required this.onAnalyze});

  @override
  State<_SelectedQuotePanel> createState() => _SelectedQuotePanelState();
}

class _SelectedQuotePanelState extends State<_SelectedQuotePanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    if (row == null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(6, 2, 14, 12),
        child: Center(
          child: Text(
            'Chọn một mã để xem thông tin chi tiết.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 2, 14, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name.isEmpty ? row.symbol : row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${row.symbol} · ${row.exchange}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Giá đầy đủ theo đồng và biên độ so với giá tham chiếu
                    Text(
                      fmt(row.price, 0),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Tone.of(context, row.dir),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${row.dir > 0
                          ? '▲ +'
                          : row.dir < 0
                          ? '▼ '
                          : '■ '}${fmt(row.price - row.ref, 0)}  (${row.pct >= 0 ? '+' : ''}${fmt(row.pct)}%)',
                      style: TextStyle(
                        color: Tone.of(context, row.dir),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (widget.onAnalyze != null)
                  IconButton(
                    onPressed: widget.onAnalyze,
                    icon: const Icon(Icons.auto_awesome),
                    tooltip: 'Phân tích mã này',
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Bốn lựa chọn cùng chiều rộng, trải đều trong khung; không đổi kích thước khi chọn (không có dấu tick)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
              segments: [
                for (final (i, label) in [
                  'Tổng hợp',
                  'Sổ lệnh',
                  'Mức giá',
                  'Thống kê',
                ].indexed)
                  ButtonSegment(
                    value: i,
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: switch (_tab) {
                0 => _SummaryDetails(row: row),
                1 => _OrderBookDetails(row: row),
                2 => _PriceLevelsDetails(row: row),
                _ => _StatisticsDetails(row: row),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDetails extends StatefulWidget {
  final BoardRow row;
  const _SummaryDetails({required this.row});

  @override
  State<_SummaryDetails> createState() => _SummaryDetailsState();
}

/// Giá đóng cửa gần đây của các mã chưa có trong dữ liệu của app, tải một lần rồi dùng lại.
final _sparkCache = <String, List<double>>{};

class _SummaryDetailsState extends State<_SummaryDetails> {
  List<double>? _fetched;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadSpark();
  }

  @override
  void didUpdateWidget(_SummaryDetails old) {
    super.didUpdateWidget(old);
    if (old.row.symbol != widget.row.symbol) {
      _fetched = null;
      _failed = false;
      _loadSpark();
    }
  }

  Future<void> _loadSpark() async {
    final symbol = widget.row.symbol;
    final known =
        context
            .getInheritedWidgetOfExactType<AppScope>()!
            .notifier!
            .stocks[symbol] !=
        null;
    if (known) return;
    final cached = _sparkCache[symbol];
    if (cached != null) {
      _fetched = cached;
      return;
    }
    final bars = await fetchBars(symbol, days: 120);
    if (!mounted || widget.row.symbol != symbol) return;
    final closes = [
      for (final b in bars.skip(bars.length > 60 ? bars.length - 60 : 0)) b.c,
    ];
    setState(() {
      if (closes.length >= 2) {
        _fetched = _sparkCache[symbol] = closes;
      } else {
        _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final state = AppScope.of(context);
    final snap = state.stocks[row.symbol];
    final spark = snap?.spark ?? _fetched ?? _sparkCache[row.symbol];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mọi mã đều có biểu đồ đường: mã chưa có dữ liệu sẵn được tải riêng
        SizedBox(
          height: 80,
          child: spark != null
              ? Sparkline(spark, height: 80)
              : Center(
                  child: Text(
                    _failed
                        ? 'Không tải được biểu đồ giá.'
                        : 'Đang tải biểu đồ…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        _DetailMetric(label: 'Giá tham chiếu', value: fmt(row.ref / 1000, 2)),
        _DetailMetric(label: 'Giá mở cửa', value: fmt(row.open / 1000, 2)),
        _DetailMetric(
          label: 'Cao nhất / thấp nhất',
          value: '${fmt(row.high / 1000, 2)} / ${fmt(row.low / 1000, 2)}',
        ),
        _DetailMetric(label: 'Tổng khối lượng khớp', value: fmt(row.volume, 0)),
        _DetailMetric(
          label: 'Giá trị giao dịch',
          value: '${fmt((row.valueMn + row.ptValueMn) / 1000, 1)} tỷ',
        ),
        const Spacer(),
        Text(
          'Dữ liệu bảng giá được làm mới định kỳ; biểu đồ nhỏ dùng lịch sử có sẵn trong ứng dụng.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _OrderBookDetails extends StatelessWidget {
  final BoardRow row;
  const _OrderBookDetails({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bidTotal = row.bids.fold<double>(
      0,
      (sum, level) => sum + level.volume,
    );
    final askTotal = row.asks.fold<double>(
      0,
      (sum, level) => sum + level.volume,
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'BÊN MUA',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Tone.up(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'BÊN BÁN',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Tone.down(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('KL đặt', style: theme.textTheme.labelSmall)),
            Expanded(
              child: Text(
                'Giá mua',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text('Giá bán', style: theme.textTheme.labelSmall)),
            Expanded(
              child: Text(
                'KL đặt',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
        const Divider(height: 13),
        for (var i = 0; i < 3; i++)
          _DepthRow(
            bid: i < row.bids.length ? row.bids[i] : null,
            ask: i < row.asks.length ? row.asks[i] : null,
            maxVolume: [bidTotal, askTotal].reduce((a, b) => a > b ? a : b),
          ),
        const Spacer(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('Dư mua 3 mức', style: theme.textTheme.bodySmall),
              ),
              Text(
                fmt(bidTotal, 0),
                style: TextStyle(
                  color: Tone.up(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dư bán 3 mức',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                fmt(askTotal, 0),
                style: TextStyle(
                  color: Tone.down(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sổ lệnh hiển thị tối đa 3 mức giá mua và bán được nguồn dữ liệu cung cấp.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DepthRow extends StatelessWidget {
  final PriceLevel? bid, ask;
  final double maxVolume;
  const _DepthRow({
    required this.bid,
    required this.ask,
    required this.maxVolume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (bid != null)
                  FractionallySizedBox(
                    widthFactor: maxVolume == 0
                        ? 0
                        : (bid!.volume / maxVolume).clamp(0.0, 1.0),
                    child: Container(
                      height: 25,
                      decoration: BoxDecoration(
                        color: Tone.up(context).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    fmt(bid?.volume, 0),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              bid == null ? '–' : fmt(bid!.price / 1000, 2),
              textAlign: TextAlign.end,
              style: TextStyle(
                color: Tone.up(context),
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              ask == null ? '–' : fmt(ask!.price / 1000, 2),
              style: TextStyle(
                color: Tone.down(context),
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                if (ask != null)
                  FractionallySizedBox(
                    widthFactor: maxVolume == 0
                        ? 0
                        : (ask!.volume / maxVolume).clamp(0.0, 1.0),
                    child: Container(
                      height: 25,
                      decoration: BoxDecoration(
                        color: Tone.down(context).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      fmt(ask?.volume, 0),
                      style: theme.textTheme.bodySmall,
                    ),
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

class _PriceLevelsDetails extends StatelessWidget {
  final BoardRow row;
  const _PriceLevelsDetails({required this.row});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PriceBand(label: 'Trần', price: row.ceil, color: Tone.down(context)),
      _PriceBand(label: 'Cao nhất', price: row.high, color: Tone.up(context)),
      _PriceBand(
        label: 'Tham chiếu',
        price: row.ref,
        color: Tone.flat(context),
      ),
      _PriceBand(
        label: 'Mở cửa',
        price: row.open,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      _PriceBand(label: 'Thấp nhất', price: row.low, color: Tone.down(context)),
      _PriceBand(label: 'Sàn', price: row.floor, color: Tone.up(context)),
      const Spacer(),
      Text(
        'Giá được quy đổi sang nghìn đồng/cổ phiếu.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _PriceBand extends StatelessWidget {
  final String label;
  final double price;
  final Color color;
  const _PriceBand({
    required this.label,
    required this.price,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          fmt(price / 1000, 2),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _StatisticsDetails extends StatelessWidget {
  final BoardRow row;
  const _StatisticsDetails({required this.row});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DetailMetric(label: 'Khối lượng khớp', value: fmt(row.volume, 0)),
      _DetailMetric(
        label: 'Khối lượng thỏa thuận',
        value: fmt(row.ptVolume, 0),
      ),
      _DetailMetric(
        label: 'GTGD toàn phiên',
        value: '${fmt((row.valueMn + row.ptValueMn) / 1000, 1)} tỷ',
      ),
      _DetailMetric(
        label: 'Khối ngoại mua',
        value: fmt(row.foreignBuy, 0),
        color: Tone.up(context),
      ),
      _DetailMetric(
        label: 'Khối ngoại bán',
        value: fmt(row.foreignSell, 0),
        color: Tone.down(context),
      ),
      _DetailMetric(
        label: 'Mua ròng nước ngoài',
        value: fmt(row.foreignBuy - row.foreignSell, 0),
        color: Tone.of(context, row.foreignBuy - row.foreignSell),
      ),
      const Spacer(),
      Text(
        'Số liệu tổng hợp trong ngày, không phải lịch sử từng lệnh khớp.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _DetailMetric extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _DetailMetric({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _TechnicalFilterTab extends StatefulWidget {
  const _TechnicalFilterTab();

  @override
  State<_TechnicalFilterTab> createState() => _TechnicalFilterTabState();
}

class _TechnicalFilterTabState extends State<_TechnicalFilterTab> {
  String _sortKey = 'tech_score';
  bool _asc = false;
  String _query = '';

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

  num? _value(Snapshot s, String k) =>
      k == 'tech_score' ? s.techScore : s.data[k] as num?;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final searchCodes = parseTickerCodes(_query);
    final rows =
        state.vn30Stocks
            .where(
              (s) => searchCodes.isEmpty
                  ? s.symbol.contains(_query.trim().toUpperCase())
                  : searchCodes.contains(s.symbol),
            )
            .toList()
          ..sort((a, b) {
            final int result = _sortKey == 'symbol'
                ? a.symbol.compareTo(b.symbol)
                : (_value(a, _sortKey) ?? -1e9).compareTo(
                    _value(b, _sortKey) ?? -1e9,
                  );
            return _asc ? result : -result;
          });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Lọc kỹ thuật VN30 theo nhiều mã: HPG, FPT, VCB',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Dữ liệu kỹ thuật VN30 · Bấm tiêu đề cột để sắp xếp, chọn dòng để phân tích sâu.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            clipBehavior: Clip.antiAlias,
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      state.loading
                          ? 'Đang tải dữ liệu…'
                          : 'Không có mã phù hợp trong VN30.',
                    ),
                  )
                : SingleChildScrollView(
                    child: FlexTable(
                      minWidth: 1250,
                      rowHeight: 56,
                      columns: [
                        for (final column in _cols)
                          FlexCol(
                            column.$2,
                            column.$1 == 'symbol'
                                ? 10
                                : (column.$1 == 'from_high_52w' ? 14 : 12),
                            align: column.$1 == 'symbol'
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            ascending: _sortKey == column.$1 ? _asc : null,
                            onSort: () => setState(() {
                              _asc = _sortKey == column.$1 ? !_asc : false;
                              _sortKey = column.$1;
                            }),
                          ),
                        const FlexCol('Tín hiệu', 30),
                      ],
                      rows: [
                        for (final snapshot in rows)
                          FlexRow(
                            onTap: () => openStock(context, snapshot.symbol),
                            [
                              Text(
                                snapshot.symbol,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(fmt(snapshot.close)),
                              for (final key in [
                                'change_1d',
                                'change_1w',
                                'change_1m',
                                'change_3m',
                              ])
                                Pct(snapshot.num_(key)),
                              Text(fmt(snapshot.num_('rsi14'), 1)),
                              Text(
                                snapshot.num_('vol_ratio') == null
                                    ? '–'
                                    : 'x${fmt(snapshot.num_('vol_ratio'))}',
                              ),
                              Pct(snapshot.num_('from_high_52w')),
                              Tag(
                                '${snapshot.techScore > 0 ? '+' : ''}${snapshot.techScore}',
                                color: Tone.of(context, snapshot.techScore),
                              ),
                              Text(
                                snapshot.signals.isEmpty
                                    ? '–'
                                    : snapshot.signals.join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
