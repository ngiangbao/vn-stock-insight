// Quản lý danh mục đầu tư trong tab CFA: lưới danh mục đã lưu (bố cục như trang Vĩ mô), trình soạn thảo (thêm/bớt/sửa vị thế),
// trang báo cáo có lịch sử các lần phân tích, phân tích lại và xuất PDF.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show appTheme;
import '../services/cfa.dart';
import '../services/portfolio.dart';
import '../state.dart';
import 'pdf_capture.dart';
import 'portfolio_report.dart';
import 'widgets.dart';

String _two(int x) => x.toString().padLeft(2, '0');
String _vnDay(DateTime t) {
  final v = t.toUtc().add(const Duration(hours: 7));
  return '${_two(v.day)}/${_two(v.month)}/${v.year}';
}

double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Phần thân của tab "Danh mục": danh sách danh mục đã lưu.
class PortfolioTab extends StatelessWidget {
  const PortfolioTab({super.key});

  Future<void> _create(BuildContext context) async {
    final res = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PortfolioEditorPage()));
    if (res == null || !context.mounted) return;
    final id = AppScope.of(context).portfolios.portfolios.firstOrNull?['id'] as String?;
    if (id != null && res == 'analyze') openPortfolio(context, id, autoAnalyze: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: state.portfolios,
      builder: (context, _) {
        final list = state.portfolios.portfolios;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => _create(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Tạo danh mục mới'),
                        ),
                        Text('${list.length} danh mục lưu trên máy', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pie_chart_outline, size: 40, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            const Text('Chưa có danh mục nào.', textAlign: TextAlign.center),
                            const SizedBox(height: 4),
                            Text(
                              'Tạo danh mục, nhập cổ phiếu và số lượng, rồi để AI phân tích theo khung quản lý danh mục của CFA.',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 520,
                        mainAxisExtent: 310 * scale,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate((context, i) => PortfolioCard(list[i]), childCount: list.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Text(
                        'Danh mục và các lần phân tích được lưu trên máy này (mỗi danh mục giữ ${PortfolioStore.maxAnalyses} lần phân tích gần nhất). '
                        'Sửa danh mục rồi phân tích lại để so sánh theo thời gian. Chỉ mang tính tham khảo, không phải lời khuyên mua/bán.',
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> openPortfolio(BuildContext context, String id, {bool autoAnalyze = false, bool exportNow = false}) => Navigator.of(context)
    .push(
      MaterialPageRoute(
        builder: (_) => PortfolioDetailPage(id, autoAnalyze: autoAnalyze, exportNow: exportNow),
      ),
    );

class PortfolioCard extends StatelessWidget {
  final Map<String, dynamic> p;
  const PortfolioCard(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final holdings = (p['holdings'] as List).length;
    final analyses = ((p['analyses'] as List?) ?? const []).cast<Map>();
    final last = analyses.isEmpty ? null : Map<String, dynamic>.from(analyses.first);
    final r = Map<String, dynamic>.from((last?['result'] as Map?) ?? const {});
    final st = Map<String, dynamic>.from(((last?['inputs'] as Map?)?['stats'] as Map?) ?? const {});
    final q = Map<String, dynamic>.from((st['chi_so_danh_muc'] as Map?) ?? const {});
    final div = Map<String, dynamic>.from((st['da_dang_hoa'] as Map?) ?? const {});
    String n(dynamic x, [int d = 2]) => x is num ? fmt(x, d) : '–';
    final rating = '${r['rating'] ?? ''}';
    final tone = switch (rating) {
      'Cân đối' => Tone.up(context),
      'Cần xem lại' => Tone.down(context),
      _ => Tone.flat(context),
    };
    Widget metric(String l, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            v,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p['name']}',
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rating.isNotEmpty) Tag(rating, color: tone),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                '$holdings mã · ${p['goal']} · rủi ro ${'${p['risk']}'.toLowerCase()} · sửa ${_vnDay(DateTime.parse(p['updated_at']))}',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                last == null ? 'Chưa phân tích. Mở danh mục để phân tích lần đầu.' : '${r['headline'] ?? ''}',
                style: text.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 10),
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    metric('Sharpe', n(q['sharpe'])),
                    metric('Beta', n(q['beta'])),
                    metric(
                      'Biến động',
                      div['bien_dong_danh_muc_nam'] is num ? '${n((div['bien_dong_danh_muc_nam'] as num) * 100, 1)}%' : '–',
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'Phân tích ${analyses.length} lần · gần nhất ${timeVN(DateTime.parse(last['created_at']))}',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => openPortfolio(context, p['id'] as String, autoAnalyze: last == null && holdings > 0),
                  child: Text(last == null ? 'Phân tích' : 'Mở báo cáo'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Sửa danh mục',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () async {
                    final res = await Navigator.of(context)
                        .push<String>(MaterialPageRoute(builder: (_) => PortfolioEditorPage(existingId: p['id'] as String)));
                    if (res == 'analyze' && context.mounted) openPortfolio(context, p['id'] as String, autoAnalyze: true);
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Xuất PDF',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: last == null ? null : () => openPortfolio(context, p['id'] as String, exportNow: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'Xóa danh mục',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Xóa danh mục "${p['name']}"?'),
                        content: const Text('Danh mục và toàn bộ lịch sử phân tích trên máy sẽ bị xóa, không khôi phục được.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Giữ lại')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa')),
                        ],
                      ),
                    );
                    if (ok == true) state.portfolios.remove(p['id'] as String);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  final symbol = TextEditingController();
  final shares = TextEditingController();
  final cost = TextEditingController();
  void dispose() {
    symbol.dispose();
    shares.dispose();
    cost.dispose();
  }
}

/// Soạn thảo danh mục: tên, chính sách đầu tư, tiền mặt và danh sách vị thế (thêm, bớt, sửa).
class PortfolioEditorPage extends StatefulWidget {
  final String? existingId;
  const PortfolioEditorPage({super.key, this.existingId});

  @override
  State<PortfolioEditorPage> createState() => _PortfolioEditorPageState();
}

class _PortfolioEditorPageState extends State<PortfolioEditorPage> {
  final _name = TextEditingController();
  final _cash = TextEditingController(text: '0');
  final _rows = <_Row>[];
  String _goal = portfolioGoals[1], _horizon = portfolioHorizons[1], _risk = portfolioRisks[1];
  String? _error;
  Map<String, dynamic>? _base;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = AppScope.of(context).portfolios;
      final p = widget.existingId == null ? null : store.byId(widget.existingId!);
      setState(() {
        _base = p ?? newPortfolio('');
        _name.text = '${_base!['name']}';
        _goal = '${_base!['goal']}';
        _horizon = '${_base!['horizon']}';
        _risk = '${_base!['risk']}';
        _cash.text = fmt((_base!['cash'] as num?) ?? 0, 2).replaceAll('.', '');
        for (final h in (_base!['holdings'] as List).cast<Map>()) {
          final r = _Row()
            ..symbol.text = '${h['symbol']}'
            ..shares.text = fmt(h['shares'] as num?, 0).replaceAll('.', '')
            ..cost.text = h['cost'] == null ? '' : fmt(h['cost'] as num, 2);
          _rows.add(r);
        }
        if (_rows.isEmpty) _rows.add(_Row());
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Kiểm tra dữ liệu nhập; trả về lỗi hoặc null và ghi vào [_base] khi hợp lệ.
  String? _collect() {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Hãy đặt tên cho danh mục.';
    final cash = _parse(_cash.text.isEmpty ? '0' : _cash.text);
    if (cash == null || cash < 0) return 'Tiền mặt phải là số không âm (đơn vị triệu đồng).';
    final holdings = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final (i, r) in _rows.indexed) {
      final s = r.symbol.text.trim().toUpperCase();
      if (s.isEmpty && r.shares.text.trim().isEmpty && r.cost.text.trim().isEmpty) continue;
      if (!RegExp(r'^[A-Z0-9]{3,5}$').hasMatch(s)) return 'Dòng ${i + 1}: mã cổ phiếu gồm 3 đến 5 ký tự.';
      if (!seen.add(s)) return 'Mã $s bị nhập hai lần. Hãy gộp thành một dòng.';
      final shares = _parse(r.shares.text);
      if (shares == null || shares <= 0) return 'Dòng ${i + 1} ($s): số lượng cổ phiếu phải lớn hơn 0.';
      final costText = r.cost.text.trim();
      final cost = costText.isEmpty ? null : _parse(costText);
      if (costText.isNotEmpty && (cost == null || cost <= 0)) {
        return 'Dòng ${i + 1} ($s): giá vốn phải là số lớn hơn 0 (nghìn đồng/cổ phiếu) hoặc để trống.';
      }
      holdings.add({'symbol': s, 'shares': shares, 'cost': ?cost});
    }
    _base!
      ..['name'] = name
      ..['goal'] = _goal
      ..['horizon'] = _horizon
      ..['risk'] = _risk
      ..['cash'] = cash
      ..['holdings'] = holdings;
    return null;
  }

  void _save({required bool analyze}) {
    final err = _collect();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (analyze && (_base!['holdings'] as List).isEmpty) {
      setState(() => _error = 'Cần ít nhất một cổ phiếu để phân tích.');
      return;
    }
    // Danh mục đã nằm trong bộ nhớ ngay khi gọi; việc ghi ra đĩa chạy nền (lỗi ghi được store bỏ qua), không bắt người dùng chờ
    unawaited(AppScope.of(context).portfolios.upsert(_base!));
    if (mounted) Navigator.pop(context, analyze ? 'analyze' : 'saved');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget dropdown(String label, String value, List<String> items, ValueChanged<String> onChanged) => SizedBox(
      width: 250,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i,
              child: Text(i, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
      ),
    );
    final loading = _base == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingId == null ? 'Tạo danh mục' : 'Sửa danh mục'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: loading ? null : () => _save(analyze: false),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Lưu'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Tên danh mục', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Text('Chính sách đầu tư (IPS)', style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'AI đối chiếu danh mục thực tế với mục tiêu, thời gian và mức chấp nhận rủi ro bạn khai báo.',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        dropdown('Mục tiêu', _goal, portfolioGoals, (v) => _goal = v),
                        dropdown('Khung thời gian', _horizon, portfolioHorizons, (v) => _horizon = v),
                        dropdown('Chấp nhận rủi ro', _risk, portfolioRisks, (v) => _risk = v),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Vị thế', style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Số lượng là số cổ phiếu đang nắm. Giá vốn (nghìn đồng/cổ phiếu) có thể để trống.',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    for (final (i, r) in _rows.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: r.symbol,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                                  LengthLimitingTextInputFormatter(5),
                                ],
                                decoration: InputDecoration(labelText: 'Mã ${i + 1}', border: const OutlineInputBorder()),
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: TextField(
                                controller: r.shares,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Số lượng', border: OutlineInputBorder()),
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              child: TextField(
                                controller: r.cost,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Giá vốn (nghìn đ)', border: OutlineInputBorder()),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Xóa dòng ${i + 1}',
                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                              onPressed: () => setState(() {
                                _rows.removeAt(i).dispose();
                                if (_rows.isEmpty) _rows.add(_Row());
                              }),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => setState(() => _rows.add(_Row())),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm cổ phiếu'),
                        ),
                        if (state.watchlist.isNotEmpty)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                            onPressed: () => setState(() {
                              final have = {for (final r in _rows) r.symbol.text.trim().toUpperCase()};
                              _rows.removeWhere((r) => r.symbol.text.isEmpty && r.shares.text.isEmpty && r.cost.text.isEmpty);
                              for (final s in state.watchlist) {
                                if (!have.contains(s)) _rows.add(_Row()..symbol.text = s);
                              }
                            }),
                            icon: const Icon(Icons.star_outline),
                            label: const Text('Thêm từ danh sách theo dõi'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 250,
                      child: TextField(
                        controller: _cash,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Tiền mặt (triệu đồng)', border: OutlineInputBorder()),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: cs.onErrorContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!, style: text.bodyMedium?.copyWith(color: cs.onErrorContainer)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => _save(analyze: true),
                      icon: const Icon(Icons.school_outlined),
                      label: const Text('Lưu và phân tích'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Báo cáo một danh mục: lịch sử các lần phân tích, phân tích lại, sửa danh mục, xuất PDF.
class PortfolioDetailPage extends StatefulWidget {
  final String id;
  final bool autoAnalyze, exportNow;
  const PortfolioDetailPage(this.id, {super.key, this.autoAnalyze = false, this.exportNow = false});

  @override
  State<PortfolioDetailPage> createState() => _PortfolioDetailPageState();
}

class _PortfolioDetailPageState extends State<PortfolioDetailPage> {
  final _key = GlobalKey();
  bool _running = false, _exporting = false;
  String? _error;
  String? _pickedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoAnalyze) {
        _run();
      } else if (widget.exportNow) {
        _export();
      }
    });
  }

  Future<void> _run() async {
    if (_running) return;
    final state = AppScope.of(context);
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final a = await state.analyzePortfolio(widget.id);
      if (mounted) _pickedId = a['id'] as String;
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    final p = AppScope.of(context).portfolios.byId(widget.id);
    setState(() => _exporting = true);
    try {
      await settleFrames();
      final safe = '${p?['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
      final day = _vnDay(DateTime.now()).split('/').reversed.join('-');
      final file = await capturePdf(
        _key,
        title: 'Phân tích danh mục ${p?['name']} $day',
        fileName: 'danh-muc-${safe.isEmpty ? widget.id : safe}-$day.pdf',
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Đã lưu ${file.path}'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Mở', onPressed: () => launchUrl(Uri.file(file.path))),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Không xuất được PDF: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Danh mục hiện tại đã khác với danh mục lúc phân tích?
  bool _changed(Map<String, dynamic> p, Map<String, dynamic> a) {
    String sig(List h, dynamic cash) => '${[for (final x in h.cast<Map>()) '${x['symbol']}:${x['shares']}'].toList()..sort()}|$cash';
    return sig(p['holdings'] as List, p['cash']) != sig((a['snapshot'] as List?) ?? const [], a['cash']);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: state.portfolios,
      builder: (context, _) {
        final p = state.portfolios.byId(widget.id);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Danh mục đã bị xóa.')),
          );
        }
        final analyses = ((p['analyses'] as List?) ?? const []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final picked = analyses.isEmpty ? null : analyses.firstWhere((a) => a['id'] == _pickedId, orElse: () => analyses.first);
        return Scaffold(
          appBar: AppBar(
            title: Text('${p['name']}'),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _running
                    ? null
                    : () async {
                        final res = await Navigator.of(context)
                            .push<String>(MaterialPageRoute(builder: (_) => PortfolioEditorPage(existingId: widget.id)));
                        if (res == 'analyze') _run();
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Sửa'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: picked == null || _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_exporting ? 'Đang xuất…' : 'Xuất PDF'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: _running ? null : _run,
                        icon: _running
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        label: Text(
                          _running ? 'Đang phân tích…' : (analyses.isEmpty ? 'Phân tích ngay' : 'Phân tích lại với giá mới nhất'),
                        ),
                      ),
                      if (analyses.length > 1)
                        Text('Lịch sử ${analyses.length} lần:', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      for (final a in analyses)
                        ChoiceChip(
                          label: Text(timeVN(DateTime.parse(a['created_at']))),
                          selected: a['id'] == picked?['id'],
                          onSelected: (_) => setState(() => _pickedId = a['id'] as String),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                        ),
                    ],
                  ),
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Đang tải giá, tính chỉ số và nhờ AI diễn giải. Thường mất 30–120 giây; model chạy trên máy có thể lâu hơn.',
                              style: text.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: text.bodyMedium?.copyWith(color: cs.onErrorContainer)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (picked != null && _changed(p, picked))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: cs.onSecondaryContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Danh mục đã được chỉnh sửa sau bản phân tích này. Bấm "Phân tích lại" để cập nhật theo danh mục hiện tại.',
                                  style: text.bodyMedium?.copyWith(color: cs.onSecondaryContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (picked == null && !_running)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Danh mục này chưa được phân tích. Bấm "Phân tích ngay".',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium,
                        ),
                      ),
                    )
                  else if (picked != null)
                    RepaintBoundary(
                      key: _key,
                      child: Theme(
                        data: _exporting ? appTheme(Brightness.light) : Theme.of(context),
                        child: Material(
                          // Material đặt kiểu chữ mặc định theo theme sáng; thiếu nó, chữ vẫn lấy màu của giao diện tối và bị nhạt khi in
                          color: _exporting ? Colors.white : Colors.transparent,
                          child: Padding(padding: const EdgeInsets.all(4), child: PortfolioReport(p, picked)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
