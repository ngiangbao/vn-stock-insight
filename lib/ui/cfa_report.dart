// Báo cáo phân tích theo khung CFA: các chỉ số định lượng tính cục bộ ở đầu, rồi từng nhóm kiến thức
// (định lượng, kinh tế, báo cáo tài chính, doanh nghiệp, định giá, danh mục, kịch bản, đạo đức).
// Biểu đồ có chú giải, giá trị khi rê chuột/chạm và phân biệt bằng nét liền/nét đứt, không chỉ bằng màu.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'analysis_report.dart' show ReportSection, ScenarioRow;
import 'widgets.dart';

double? _n(dynamic x) => x is num ? x.toDouble() : null;

String _pct(dynamic x, [int d = 1]) => _n(x) == null ? '–' : '${fmt(_n(x)! * 100, d)}%';
String _num(dynamic x, [int d = 2]) => _n(x) == null ? '–' : fmt(_n(x), d);

class CfaReport extends StatelessWidget {
  final Map<String, dynamic> record;
  const CfaReport(this.record, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from(record['result'] as Map);
    final inputs = Map<String, dynamic>.from(record['inputs'] as Map);
    final q = Map<String, dynamic>.from((inputs['quant'] as Map?) ?? const {});
    final v = Map<String, dynamic>.from((inputs['valuation'] as Map?) ?? const {});
    final a = Map<String, dynamic>.from((record['assumptions'] as Map?) ?? const {});
    final series = Map<String, dynamic>.from((record['series'] as Map?) ?? const {});
    final created = DateTime.parse(record['created_at']);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final brand = Tone.up(context);
    final stance = '${r['stance']}';
    final symbol = '${record['symbol']}';
    final name = '${record['name'] ?? symbol}';

    Map<String, dynamic> m(String k) => Map<String, dynamic>.from((r[k] as Map?) ?? const {});
    Widget para(dynamic t) => (t == null || '$t'.trim().isEmpty)
        ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('$t'));
    Widget sub(String label, dynamic t) => (t == null || '$t'.trim().isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '$t'),
                ],
              ),
            ),
          );

    final econ = m('economics'), fsa = m('fsa'), corp = m('corporate'), quant = m('quant'), val = m('valuation'), pf = m('portfolio');
    final scenarios = ((r['scenarios'] as List?) ?? const []).cast<Map>();

    final tiles = <(String, String)>[
      ('Giá', record['price'] == null ? '–' : '${fmt(_n(record['price'])! * 1000, 0)} đ'),
      ('Lợi suất 1 năm', _pct(q['loi_suat_nam'])),
      ('Biến động năm', _pct(q['bien_dong_nam'])),
      ('Sharpe', _num(q['sharpe'])),
      ('Beta so với VN-Index', _num(q['beta'])),
      ('Sụt giảm tối đa', _pct(q['sut_giam_toi_da'])),
      ('VaR 95% 1 ngày', _pct(q['var95_1_ngay'], 2)),
      ('Chi phí vốn (CAPM)', _pct(v['chi_phi_von_chu_so_huu_capm'])),
      ('P/B hiện tại', _num(v['pb_hien_tai'])),
      ('P/B chính đáng', _num(v['pb_chinh_dang'])),
      (
        'Giá nội tại ước tính',
        v['gia_noi_tai_uoc_tinh_nghin_dong'] == null ? '–' : '${fmt(_n(v['gia_noi_tai_uoc_tinh_nghin_dong'])! * 1000, 0)} đ',
      ),
      ('Chênh lệch so với giá', _n(v['chenh_lech_so_voi_gia_pct']) == null ? '–' : '${fmt(_n(v['chenh_lech_so_voi_gia_pct']), 1)}%'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BÁO CÁO PHÂN TÍCH THEO KHUNG CFA',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${name.toUpperCase()} – $symbol',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: brand),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tag(stance, color: Tone.stance(context, stance)),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 3, color: brand),
        const SizedBox(height: 12),
        Text(
          '${r['headline'] ?? ''}'.toUpperCase(),
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: brand),
        ),
        const SizedBox(height: 6),
        Text('${r['summary'] ?? ''}'),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Độ tin cậy: ${r['confidence'] ?? '–'}', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) _Tile(t.$1, t.$2)]),
        ReportSection(
          '1. Phương pháp định lượng',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((series['dates'] as List?)?.isNotEmpty ?? false) RelChart(series),
              const SizedBox(height: 10),
              _QuantTable(q),
              const SizedBox(height: 10),
              para(quant['summary']),
              sub('Lợi suất và rủi ro', quant['risk_return']),
              sub('Hồi quy so với VN-Index', quant['regression']),
              sub('Rủi ro đuôi', quant['tail_risk']),
              if ((quant['cautions'] as List?)?.isNotEmpty ?? false) Bullets(quant['cautions']),
            ],
          ),
        ),
        ReportSection(
          '2. Kinh tế học',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [para(econ['context']), Bullets(econ['implications'])]),
        ),
        ReportSection(
          '3. Phân tích báo cáo tài chính',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              para(fsa['summary']),
              if (v['dupont'] is Map) _DuPont(Map<String, dynamic>.from(v['dupont'] as Map)),
              sub('Phân tách DuPont', fsa['dupont']),
              sub('Chất lượng lợi nhuận', fsa['earnings_quality']),
              if ((fsa['red_flags'] as List?)?.isNotEmpty ?? false) ...[
                Text('Dấu hiệu cảnh báo', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(fsa['red_flags']),
              ],
            ],
          ),
        ),
        ReportSection(
          '4. Doanh nghiệp phát hành',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sub('Cấu trúc vốn', corp['capital_structure']),
              sub('Chi phí vốn', corp['cost_of_capital']),
              sub('Quản trị', corp['governance']),
            ],
          ),
        ),
        ReportSection(
          '5. Định giá cổ phiếu',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((v['bang_do_nhay'] as List?)?.isNotEmpty ?? false) _Sensitivity(v),
              const SizedBox(height: 10),
              para(val['summary']),
              sub('Góc nhìn giá trị nội tại', val['intrinsic_view']),
              sub('Biên an toàn', val['margin_of_safety']),
              sub('Độ nhạy', val['sensitivity']),
              sub('Đối chiếu chéo', val['cross_check']),
              if ((v['ghi_chu'] as List?)?.isNotEmpty ?? false) Bullets(v['ghi_chu']),
            ],
          ),
        ),
        ReportSection(
          '6. Quản lý danh mục',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sub('Vai trò trong danh mục', pf['role']),
              sub('Đa dạng hóa', pf['diversification']),
              sub('Ngân sách rủi ro', pf['risk_budget']),
              sub('Mức phù hợp', pf['suitability']),
              if ((pf['behavioral_biases'] as List?)?.isNotEmpty ?? false) ...[
                Text('Sai lệch hành vi cần tránh', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(pf['behavioral_biases']),
              ],
            ],
          ),
        ),
        if (scenarios.isNotEmpty)
          ReportSection('7. Kịch bản có xác suất', ScenarioRow([for (final s in scenarios) _Scenario(Map<String, dynamic>.from(s))])),
        if ((r['monitoring'] as List?)?.isNotEmpty ?? false) ReportSection('8. Chỉ tiêu cần theo dõi', Bullets(r['monitoring'])),
        if ((r['risks'] as List?)?.isNotEmpty ?? false) ReportSection('9. Rủi ro', Bullets(r['risks'])),
        ReportSection('10. Đạo đức và giới hạn của phân tích', para(r['ethics'])),
        if ((r['data_gaps'] as List?)?.isNotEmpty ?? false) ReportSection('Hạn chế dữ liệu', Bullets(r['data_gaps'])),
        Divider(height: 28, color: cs.outlineVariant),
        Text(
          'Giả định: lãi suất phi rủi ro ${_pct(a['rf'])}, phần bù rủi ro vốn ${_pct(a['erp'])}, tăng trưởng dài hạn ${_pct(a['g'])}. '
          'Chỉ số định lượng tính cục bộ từ giá DNSE và VN-Index 1 năm gần nhất; phần diễn giải do AI viết. '
          'Phân tích lúc ${timeVN(created)} · ${record['ai']}. $disclaimer Đây không phải sản phẩm của CFA Institute và không phải lời khuyên mua/bán.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label, value;
  const _Tile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(
            value,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// Bảng hai cột nhãn / giá trị.
class _KV extends StatelessWidget {
  final List<(String, String)> rows;
  const _KV(this.rows);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final (i, row) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: i.isEven ? cs.surfaceContainerHighest.withValues(alpha: 0.5) : null,
            child: Row(
              children: [
                Expanded(child: Text(row.$1)),
                Text(
                  row.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuantTable extends StatelessWidget {
  final Map<String, dynamic> q;
  const _QuantTable(this.q);

  @override
  Widget build(BuildContext context) {
    if (q['sharpe'] == null && q['beta'] == null) {
      return Text('${q['ghi_chu'] ?? 'Chưa đủ dữ liệu để tính chỉ số định lượng.'}');
    }
    final left = <(String, String)>[
      ('Lợi suất năm (CAGR)', _pct(q['loi_suat_nam'])),
      ('Lợi suất VN-Index', _pct(q['loi_suat_vnindex_nam'])),
      ('Biến động năm', _pct(q['bien_dong_nam'])),
      ('Biến động VN-Index', _pct(q['bien_dong_vnindex_nam'])),
      ('Sharpe', _num(q['sharpe'])),
      ('Sortino', _num(q['sortino'])),
      ('Động lượng 12-1', _pct(q['dong_luong_12_1'])),
      ('Số phiên tính', _num(q['so_phien'], 0)),
    ];
    final right = <(String, String)>[
      ('Beta', _num(q['beta'])),
      ('Alpha Jensen (năm)', _pct(q['alpha_jensen_nam'])),
      ('Tương quan / R²', '${_num(q['tuong_quan_vnindex'])} / ${_num(q['r_binh_phuong'])}'),
      ('Tracking error', _pct(q['tracking_error'])),
      ('Information ratio', _num(q['information_ratio'])),
      ('Sụt giảm tối đa / hiện tại', '${_pct(q['sut_giam_toi_da'])} / ${_pct(q['sut_giam_hien_tai'])}'),
      ('VaR / CVaR 95% 1 ngày', '${_pct(q['var95_1_ngay'], 2)} / ${_pct(q['cvar95_1_ngay'], 2)}'),
      ('Skew / Kurtosis vượt chuẩn', '${_num(q['do_lech_skew'])} / ${_num(q['kurtosis_vuot_chuan'])}'),
      ('Capture tăng / giảm', '${_num(q['capture_tang'])} / ${_num(q['capture_giam'])}'),
    ];
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 700
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _KV(left)),
                const SizedBox(width: 16),
                Expanded(child: _KV(right)),
              ],
            )
          : _KV([...left, ...right]),
    );
  }
}

class _DuPont extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DuPont(this.d);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _KV([
      ('ROE', _pct(d['roe'])),
      ('= Biên lợi nhuận ròng', _pct(d['bien_loi_nhuan_rong'])),
      ('× Vòng quay tài sản (suy ra)', _num(d['vong_quay_tai_san_suy_ra'])),
      ('× Đòn bẩy tài chính (xấp xỉ)', _num(d['don_bay_tai_chinh_xap_xi'])),
    ]),
  );
}

class _Sensitivity extends StatelessWidget {
  final Map<String, dynamic> v;
  const _Sensitivity(this.v);

  @override
  Widget build(BuildContext context) {
    final grid = ((v['bang_do_nhay'] as List?) ?? const []).cast<Map>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ks = {for (final r in grid) r['chi_phi_von']}.toList()..sort((a, b) => (a as num).compareTo(b as num));
    final gs = {for (final r in grid) r['tang_truong']}.toList()..sort((a, b) => (a as num).compareTo(b as num));
    String cell(dynamic k, dynamic g) {
      final hit = grid.where((r) => r['chi_phi_von'] == k && r['tang_truong'] == g).firstOrNull;
      final price = hit?['gia_nghin_dong'];
      return price == null ? '–' : fmt(_n(price)! * 1000, 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Giá nội tại ước tính (đồng) theo chi phí vốn và tăng trưởng dài hạn',
          style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: cs.outlineVariant),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: cs.surfaceContainerHighest),
              children: [_cell('Chi phí vốn \\ g', bold: true), for (final g in gs) _cell(_pct(g), bold: true)],
            ),
            for (final k in ks)
              TableRow(
                children: [
                  _cell(_pct(k), bold: true),
                  for (final g in gs) _cell(cell(k, g), highlight: k == ks[ks.length ~/ 2] && g == gs[gs.length ~/ 2], context: context),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _cell(String t, {bool bold = false, bool highlight = false, BuildContext? context}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    child: Text(
      highlight ? '$t  (cơ sở)' : t,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: bold || highlight ? FontWeight.w800 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class _Scenario extends StatelessWidget {
  final Map<String, dynamic> s;
  const _Scenario(this.s);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = '${s['name']}';
    final tone = Tone.stance(context, name == 'Cơ sở' ? 'Trung lập' : name);
    Widget line(String l, dynamic t) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$l: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '$t'),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: tone, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: tone),
                ),
              ),
              Tag('${s['probability']}%', color: tone),
            ],
          ),
          // Thanh xác suất: chiều dài thể hiện xác suất, kèm số ở thẻ bên trên
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((_n(s['probability']) ?? 0) / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                color: tone,
                backgroundColor: cs.outlineVariant,
              ),
            ),
          ),
          line('Điều kiện', s['condition']),
          line('Tác động giá', s['price_effect']),
          line('Tín hiệu', s['signals']),
        ],
      ),
    );
  }
}

/// Lợi suất tích lũy 1 năm của cổ phiếu (nét liền) và VN-Index (nét đứt), rê chuột/chạm để xem từng ngày.
class RelChart extends StatefulWidget {
  final Map<String, dynamic> series;

  /// Khóa chuỗi chính trong [series] ('stock' hoặc 'danh_muc'), khóa chuỗi so sánh ('index' hoặc 'vnindex') và nhãn.
  final String mainKey, benchKey, mainLabel, title;
  const RelChart(
    this.series, {
    super.key,
    this.mainKey = 'stock',
    this.benchKey = 'index',
    this.mainLabel = 'Cổ phiếu',
    this.title = 'Lợi suất tích lũy 1 năm: cổ phiếu so với VN-Index',
  });

  @override
  State<RelChart> createState() => _RelChartState();
}

class _RelChartState extends State<RelChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final dates = (widget.series['dates'] as List).cast<String>();
    final stock = (widget.series[widget.mainKey] as List).map((e) => (e as num).toDouble()).toList();
    final index = (widget.series[widget.benchKey] as List).map((e) => (e as num).toDouble()).toList();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final c1 = Tone.up(context), c2 = cs.onSurfaceVariant;
    final h = _hover;
    String f(double v) => '${v >= 0 ? '+' : ''}${fmt(v, 1)}%';
    String d(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [_Key(c1, false, '${widget.mainLabel} ${f(stock.last)}'), _Key(c2, true, 'VN-Index ${f(index.last)}')],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            void track(Offset p) {
              final inner = box.maxWidth - 44 - 8;
              final i = (((p.dx - 44) / inner).clamp(0.0, 1.0) * (dates.length - 1)).round();
              if (i != _hover) setState(() => _hover = i);
            }

            return Semantics(
              label: 'Biểu đồ lợi suất tích lũy 1 năm. ${widget.mainLabel} ${f(stock.last)}, VN-Index ${f(index.last)}.',
              child: MouseRegion(
                onHover: (e) => track(e.localPosition),
                onExit: (_) => setState(() => _hover = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => track(e.localPosition),
                  onHorizontalDragUpdate: (e) => track(e.localPosition),
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: CustomPaint(painter: _RelPainter(dates, stock, index, c1, c2, cs.outlineVariant, cs.onSurfaceVariant, h)),
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            h == null
                ? 'Rê chuột hoặc chạm vào biểu đồ để xem từng ngày.'
                : '${d(dates[h])}  ·  ${widget.mainLabel} ${f(stock[h])}  ·  VN-Index ${f(index[h])}',
            style: text.bodySmall?.copyWith(fontWeight: h == null ? FontWeight.w400 : FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final bool dashed;
  final String label;
  const _Key(this.color, this.dashed, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyPainter(color, dashed))),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}

class _KeyPainter extends CustomPainter {
  final Color color;
  final bool dashed;
  _KeyPainter(this.color, this.dashed);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.color != color || old.dashed != dashed;
}

class _RelPainter extends CustomPainter {
  final List<String> dates;
  final List<double> a, b;
  final Color ca, cb, grid, label;
  final int? hover;
  _RelPainter(this.dates, this.a, this.b, this.ca, this.cb, this.grid, this.label, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 44.0, r = 8.0, t = 8.0, bt = 22.0;
    final w = size.width - l - r, h = size.height - t - bt;
    if (w <= 0 || h <= 0 || a.length < 2) return;
    final all = [...a, ...b, 0.0];
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if (hi - lo < 1) {
      hi += 0.5;
      lo -= 0.5;
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    double x(int i) => l + i / (a.length - 1) * w;
    double y(double v) => t + h - (v - lo) / (hi - lo) * h;

    void txt(String s, Offset at, {bool right = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 11, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = right ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx);
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = lo + (hi - lo) * i / 4;
      canvas.drawLine(Offset(l, y(v)), Offset(l + w, y(v)), gp);
      txt('${fmt(v, 0)}%', Offset(l - 6, y(v)), right: true);
    }
    // Đường 0%
    canvas.drawLine(
      Offset(l, y(0)),
      Offset(l + w, y(0)),
      Paint()
        ..color = label
        ..strokeWidth = 1,
    );
    // Nhãn tháng
    var lastMonth = '';
    for (var i = 0; i < dates.length; i++) {
      final mth = dates[i].substring(0, 7);
      if (mth != lastMonth) {
        lastMonth = mth;
        if (i == 0 || i > 8) txt('${mth.substring(5)}/${mth.substring(2, 4)}', Offset(x(i), size.height - 8), center: true);
      }
    }

    Path path(List<double> v) {
      final p = Path()..moveTo(x(0), y(v[0]));
      for (var i = 1; i < v.length; i++) {
        p.lineTo(x(i), y(v[i]));
      }
      return p;
    }

    final dash = Paint()
      ..color = cb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in path(b).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dash);
      }
    }
    canvas.drawPath(
      path(a),
      Paint()
        ..color = ca
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    final hv = hover;
    if (hv != null) {
      canvas.drawLine(
        Offset(x(hv), t),
        Offset(x(hv), t + h),
        Paint()
          ..color = label
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x(hv), y(a[hv])), 4, Paint()..color = ca);
      canvas.drawCircle(Offset(x(hv), y(b[hv])), 4, Paint()..color = cb);
    }
  }

  @override
  bool shouldRepaint(_RelPainter old) => old.hover != hover || old.a != a || old.b != b || old.ca != ca || old.cb != cb;
}

/// Cho các báo cáo khác dùng chung.
typedef ReportTile = _Tile;
typedef ReportKV = _KV;
typedef QuantTable = _QuantTable;
typedef ScenarioCard = _Scenario;
