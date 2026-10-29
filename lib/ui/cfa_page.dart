// Tab "CFA": phân tích một cổ phiếu theo khung kiến thức CFA, lưu kết quả trên máy và xuất PDF.
// Bố cục theo trang Vĩ mô: thanh tiêu đề có tab, lưới thẻ cùng kích thước cho các bản đã lưu, ghi chú nguồn ở cuối.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show appTheme;
import '../services/cfa.dart';
import '../services/quant.dart';
import '../state.dart';
import 'cfa_report.dart';
import 'pdf_capture.dart';
import 'portfolio_page.dart';
import 'widgets.dart';

class CfaPage extends StatefulWidget {
  const CfaPage({super.key});

  @override
  State<CfaPage> createState() => _CfaPageState();
}

class _CfaPageState extends State<CfaPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _symbol = TextEditingController();
  final _rf = TextEditingController(text: '4,5');
  final _erp = TextEditingController(text: '7');
  final _g = TextEditingController(text: '4');
  bool _running = false;
  String? _error;
  String _step = '';

  @override
  void dispose() {
    _tabs.dispose();
    _symbol.dispose();
    _rf.dispose();
    _erp.dispose();
    _g.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _run() async {
    final symbol = _symbol.text.trim().toUpperCase();
    final rf = _parse(_rf), erp = _parse(_erp), g = _parse(_g);
    if (!RegExp(r'^[A-Z0-9]{3,5}$').hasMatch(symbol)) {
      setState(() => _error = 'Nhập mã cổ phiếu gồm 3 đến 5 ký tự, ví dụ FPT.');
      return;
    }
    if (rf == null || erp == null || g == null || rf < 0 || erp <= 0 || g < 0 || rf > 30 || erp > 30 || g > 15) {
      setState(() => _error = 'Giả định phải là số phần trăm hợp lệ (lãi suất 0–30, phần bù rủi ro 1–30, tăng trưởng 0–15).');
      return;
    }
    final state = AppScope.of(context);
    setState(() {
      _running = true;
      _error = null;
      _step = 'Tính chỉ số định lượng, định giá và thu thập dữ liệu…';
    });
    try {
      final rec = await state.analyzeCfa(
        symbol,
        assumptions: CfaAssumptions(rf: rf / 100, erp: erp / 100, g: g / 100),
      );
      if (!mounted) return;
      _tabs.animateTo(1);
      openCfaReport(context, rec);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([state.cfa, state.portfolios]),
      builder: (context, _) {
        final reports = state.cfa.reports;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phân tích theo khung CFA'),
                Text('${reports.length} bản phân tích, ${state.portfolios.portfolios.length} danh mục lưu trên máy', style: text.bodySmall),
              ],
            ),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Phân tích mới'),
                Tab(text: 'Đã lưu'),
                Tab(text: 'Danh mục'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [_form(context, state), _saved(context, state, reports), const PortfolioTab()],
          ),
        );
      },
    );
  }

  Widget _form(BuildContext context, AppState state) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget field(TextEditingController c, String label, String hint) => SizedBox(
      width: 200,
      child: TextField(
        controller: c,
        enabled: !_running,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: hint, suffixText: '%', border: const OutlineInputBorder()),
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            LayoutBuilder(
              builder: (context, box) {
                Widget card(List<Widget> children) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                  ),
                );
                final left = card([
                  Text('Chọn cổ phiếu cần phân tích', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Áp dụng các nhóm kiến thức CFA: định lượng (lợi suất, rủi ro, beta, VaR), kinh tế, báo cáo tài chính, doanh nghiệp, '
                    'định giá (CAPM, P/B chính đáng, độ nhạy), quản lý danh mục, kịch bản và đạo đức nghề nghiệp. '
                    'Các chỉ số được tính trên máy bạn từ giá thật, AI chỉ diễn giải.',
                    style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _symbol,
                      enabled: !_running,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(5)],
                      decoration: const InputDecoration(labelText: 'Mã cổ phiếu', hintText: 'Ví dụ FPT', border: OutlineInputBorder()),
                      onSubmitted: (_) => _running ? null : _run(),
                    ),
                  ),
                  if (state.watchlist.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Hoặc chọn từ danh sách theo dõi', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in state.watchlist.take(24))
                          ActionChip(
                            label: Text(s),
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onPressed: _running ? null : () => setState(() => _symbol.text = s),
                          ),
                      ],
                    ),
                  ],
                ]);
                final right = card([
                  Text('Giả định thị trường (có thể chỉnh)', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(_rf, 'Lãi suất phi rủi ro', 'Lãi suất trái phiếu dài hạn'),
                      field(_erp, 'Phần bù rủi ro vốn', 'Lợi suất đòi hỏi vượt rf'),
                      field(_g, 'Tăng trưởng dài hạn', 'Danh nghĩa, hằng năm'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _running ? null : _run,
                    icon: _running
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.school_outlined),
                    label: Text(_running ? 'Đang phân tích…' : 'Phân tích CFA'),
                  ),
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('$_step Thường mất 30–90 giây; model chạy trên máy có thể lâu hơn.', style: text.bodySmall),
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
                ]);
                // Màn hình rộng: hai thẻ cạnh nhau, giãn hết chiều ngang; màn hình hẹp: xếp dọc
                return box.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 16),
                          Expanded(child: right),
                        ],
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 12), right]);
              },
            ),
            const SizedBox(height: 12),
            Text(_note, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  static const _note =
      'Khung phân tích dựa trên các nhóm kiến thức của chương trình CFA, được viết lại và áp dụng cho cổ phiếu Việt Nam. '
      'Đây không phải sản phẩm của CFA Institute. Số liệu: DNSE (giá), Vietcap IQ (cơ bản), World Bank/IMF/Yahoo (vĩ mô), tin RSS. '
      'Chỉ mang tính tham khảo, không phải lời khuyên mua/bán.';

  Widget _saved(BuildContext context, AppState state, List<Map<String, dynamic>> reports) {
    final text = Theme.of(context).textTheme;
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              const Text('Chưa có bản phân tích CFA nào được lưu.'),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _tabs.animateTo(0),
                child: const Text('Phân tích cổ phiếu đầu tiên'),
              ),
            ],
          ),
        ),
      );
    }
    // Cỡ chữ hệ thống lớn thì thẻ cao hơn tương ứng nên các thẻ vẫn bằng nhau
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 520,
                  mainAxisExtent: 330 * scale,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => CfaCard(reports[i], onRemoved: () => state.cfa.remove(reports[i]['id'] as String)),
                  childCount: reports.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  'Các bản phân tích được lưu trên máy này (tối đa ${CfaStore.maxReports} bản gần nhất), không gửi đi đâu ngoài nhà cung cấp AI bạn chọn. $_note',
                  style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ một bản phân tích đã lưu.
class CfaCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onRemoved;
  const CfaCard(this.record, {super.key, required this.onRemoved});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = Map<String, dynamic>.from(record['result'] as Map);
    final inputs = Map<String, dynamic>.from(record['inputs'] as Map);
    final q = Map<String, dynamic>.from((inputs['quant'] as Map?) ?? const {});
    final v = Map<String, dynamic>.from((inputs['valuation'] as Map?) ?? const {});
    final stance = '${r['stance']}';
    final created = DateTime.parse(record['created_at']);
    String n(dynamic x, [int d = 2]) => x is num ? fmt(x, d) : '–';
    final gap = v['chenh_lech_so_voi_gia_pct'];
    Widget metric(String l, String val) => Expanded(
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
            val,
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
                  Text('${record['symbol']}', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Tag(stance, color: Tone.stance(context, stance)),
                  Expanded(
                    child: Text(
                      timeVN(created),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                '${record['name'] ?? ''}',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${r['headline'] ?? ''}', style: text.titleSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  metric('Sharpe', n(q['sharpe'])),
                  metric('Beta', n(q['beta'])),
                  metric('Chênh lệch giá trị', gap is num ? '${gap > 0 ? '+' : ''}${n(gap, 1)}%' : '–'),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Phân tích bởi ${record['ai']}',
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
                  onPressed: () => openCfaReport(context, record),
                  child: const Text('Xem báo cáo'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Xuất PDF',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => openCfaReport(context, record, exportNow: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'Xóa bản lưu',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Xóa bản phân tích ${record['symbol']}?'),
                        content: const Text('Bản lưu trên máy sẽ bị xóa và không khôi phục được.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Giữ lại')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa')),
                        ],
                      ),
                    );
                    if (ok == true) onRemoved();
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

Future<void> openCfaReport(BuildContext context, Map<String, dynamic> record, {bool exportNow = false}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CfaReportPage(record, exportNow: exportNow)));

/// Trang xem một bản phân tích CFA đầy đủ, có nút xuất PDF.
class CfaReportPage extends StatefulWidget {
  final Map<String, dynamic> record;
  final bool exportNow;
  const CfaReportPage(this.record, {super.key, this.exportNow = false});

  @override
  State<CfaReportPage> createState() => _CfaReportPageState();
}

class _CfaReportPageState extends State<CfaReportPage> {
  final _key = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.exportNow) WidgetsBinding.instance.addPostFrameCallback((_) => _export());
  }

  Future<void> _export() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      // Lúc chụp, báo cáo hiện theo giao diện sáng để in cho rõ
      await settleFrames();
      final r = widget.record;
      final file = await capturePdf(
        _key,
        title: 'Phân tích CFA ${r['symbol']} ${r['day']}',
        fileName: 'cfa-${r['symbol']}-${r['day']}.pdf',
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

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      appBar: AppBar(
        title: Text('CFA · ${r['symbol']}'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _exporting ? null : _export,
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
              RepaintBoundary(
                key: _key,
                child: Theme(
                  data: _exporting ? appTheme(Brightness.light) : Theme.of(context),
                  child: Material(
                    // Material đặt kiểu chữ mặc định theo theme sáng; thiếu nó, chữ vẫn lấy màu của giao diện tối và bị nhạt khi in
                    color: _exporting ? Colors.white : Colors.transparent,
                    child: Padding(padding: const EdgeInsets.all(4), child: CfaReport(r)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
