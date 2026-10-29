// Báo cáo phân tích cổ phiếu trình bày theo dạng báo cáo doanh nghiệp của công ty chứng khoán:
// tiêu đề, cột bên trái (khuyến nghị, thông tin cổ phiếu, diễn biến giá), nội dung chính bên phải,
// rồi các phần toàn chiều rộng (chấm điểm, kịch bản, số liệu tài chính). Màu lấy từ theme.
// Biểu đồ có chú giải và giá trị khi rê chuột/chạm; không chỉ phân biệt bằng màu (nét liền/nét đứt).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/market.dart' show Bar, vnDate;
import '../state.dart' show vietnamDayKey;
import 'widgets.dart';

double? _num(dynamic x) => x is num ? x.toDouble() : null;

/// Tỉ lệ có thể ở dạng phân số (0,12) hoặc phần trăm (12): trả về phần trăm.
double? _pctVal(dynamic x) {
  final v = _num(x);
  if (v == null) return null;
  return v.abs() <= 1.5 ? v * 100 : v;
}

double? _change(List<Bar> bars, int n) => bars.length > n ? (bars.last.c / bars[bars.length - 1 - n].c - 1) * 100 : null;

class ResearchReport extends StatelessWidget {
  final Map<String, dynamic> saved;
  final List<Bar> bars, indexBars;
  final String? exchange;
  const ResearchReport(this.saved, {super.key, this.bars = const [], this.indexBars = const [], this.exchange});

  @override
  Widget build(BuildContext context) {
    final r = saved['result'] as Map<String, dynamic>;
    final inputs = saved['inputs'] as Map<String, dynamic>;
    final t = inputs['technicals'] as Map<String, dynamic>? ?? {};
    final f = inputs['fundamentals'] as Map<String, dynamic>? ?? {};
    final c = f['company'] as Map<String, dynamic>? ?? {};
    final created = DateTime.parse(saved['created_at']);
    final day = vietnamDayKey(created);
    List<Bar> upTo(List<Bar> b) => [
      for (final x in b)
        if (vnDate(x.t).compareTo(day) <= 0) x,
    ];
    final history = upTo(bars), market = upTo(indexBars);
    final cs = Theme.of(context).colorScheme;
    final brand = Tone.up(context);
    final text = Theme.of(context).textTheme;
    final symbol = saved['symbol'] ?? '';
    final name = (c['ten'] as String?) ?? symbol;
    final scorecard = (r['scorecard'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final avg = scorecard.isEmpty ? null : scorecard.map((x) => x['score'] as num).reduce((a, b) => a + b) / scorecard.length;
    final stance = (r['stance'] ?? '').toString();

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BÁO CÁO DOANH NGHIỆP', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            const SizedBox(height: 2),
            Text('${name.toUpperCase()} – $symbol${exchange == null ? '' : ' ($exchange)'}',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: brand)),
          ]),
        ),
        const SizedBox(width: 12),
        Tag(stance, color: Tone.stance(context, stance)),
      ]),
      const SizedBox(height: 8),
      Container(height: 3, color: brand),
    ]);

    // ---------- Cột trái ----------
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Block(
        'Vài nét về doanh nghiệp',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c['nganh'] != null) Text('Ngành: ${c['nganh']}', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if ((r['competition'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r['competition'], style: text.bodySmall),
          ],
        ]),
      ),
      _Block('Khuyến nghị', _Recommendation(r, t, c, avg, stance)),
      _Block('Thông tin cổ phiếu', _StockInfo(t, f, c, day)),
      if (history.length > 2) _Block('Diễn biến giá', _PriceBlock(symbol, history, market)),
    ]);

    // ---------- Nội dung chính ----------
    final earnings = r['earnings'] as Map<String, dynamic>? ?? {};
    final thesis = r['thesis'] as Map<String, dynamic>? ?? {};
    final technical = r['technical'] as Map<String, dynamic>? ?? {};
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text((r['headline'] ?? '').toString().toUpperCase(), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: brand, height: 1.3)),
      const SizedBox(height: 10),
      _Lead('ĐÁNH GIÁ: ${stance.toUpperCase()}', r['summary']),
      _Lead('CẬP NHẬT KQKD', earnings['summary'], bullets: earnings['highlights']),
      _Lead('LUẬN ĐIỂM ĐẦU TƯ', null, children: [
        if ((thesis['statement'] ?? '').toString().isNotEmpty)
          Text(thesis['statement'], style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
        const SizedBox(height: 4),
        Bullets(thesis['pillars']),
        if ((thesis['invalidation'] as List?)?.isNotEmpty ?? false) ...[
          const SizedBox(height: 6),
          Text('Luận điểm sai nếu…', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          Bullets(thesis['invalidation']),
        ],
      ]),
      _Lead('ĐỊNH GIÁ', r['valuation']),
      _Lead('KỸ THUẬT', technical['summary'], extra: (technical['key_levels'] ?? '').toString().isEmpty ? null : 'Vùng giá: ${technical['key_levels']}'),
    ]);

    final top = LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth < 620) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [side, const SizedBox(height: 12), main]);
      }
      final sideW = (cons.maxWidth * 0.32).clamp(200.0, 280.0);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: sideW, child: side),
        const SizedBox(width: 20),
        Expanded(child: main),
      ]);
    });

    // ---------- Phần toàn chiều rộng ----------
    Widget twoCols(Widget a, Widget b) => LayoutBuilder(
          builder: (context, cons) => cons.maxWidth > 620
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: a),
                  const SizedBox(width: 20),
                  Expanded(child: b),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [a, const SizedBox(height: 8), b]),
        );

    final catalysts = (r['catalysts'] as List? ?? []).cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          const SizedBox(height: 14),
          top,
          if (scorecard.isNotEmpty)
            _Section('Bảng chấm điểm', trailing: avg == null ? null : 'Trung bình ${fmt(avg, 1)}/5', Column(children: [
              for (final x in scorecard)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(x['dimension'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                    _ScoreBar((x['score'] as num?)?.toInt() ?? 0),
                    const SizedBox(width: 12),
                    Expanded(child: Text(x['reason'] ?? '', style: text.bodySmall)),
                  ]),
                ),
            ])),
          if (catalysts.isNotEmpty)
            _Section('Lịch sự kiện', Column(children: [
              for (final e in catalysts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 130, child: Text(e['timing'] ?? '', style: text.bodySmall)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e['event'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(e['why'] ?? '', style: text.bodySmall),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Tag(e['impact'] ?? '', color: switch (e['impact']) {
                      'Cao' => Tone.down(context),
                      'Thấp' => Tone.up(context),
                      _ => Tone.flat(context),
                    }),
                  ]),
                ),
            ])),
          _Section('Kịch bản', LayoutBuilder(builder: (context, cons) {
            final cards = [
              _Scenario('Tích cực', r['scenarios']?['bull'], Tone.up(context)),
              _Scenario('Cơ sở', r['scenarios']?['base'], Tone.flat(context)),
              _Scenario('Tiêu cực', r['scenarios']?['bear'], Tone.down(context)),
            ];
            return cons.maxWidth > 620
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (i, w) in cards.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: w)],
                  ])
                : Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]);
          })),
          _Section(
            'Rủi ro và điểm cần theo dõi',
            twoCols(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rủi ro', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(r['risks']),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cần theo dõi', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(r['watch_points']),
              ]),
            ),
          ),
          _FinancialSection(f),
          if ((r['data_gaps'] as List?)?.isNotEmpty ?? false) _Section('Hạn chế dữ liệu', Bullets(r['data_gaps'])),
          Divider(height: 28, color: cs.outlineVariant),
          Text(
            'Phân tích lúc ${timeVN(created)} · ${saved['ai']}. Số liệu: DNSE, Vietcap IQ, tin RSS. $disclaimer',
            style: text.bodySmall,
          ),
        ]),
      ),
    );
  }
}

// ---------- Khối nhỏ ----------

class _Block extends StatelessWidget {
  final String title;
  final Widget child;
  const _Block(this.title, this.child);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Container(height: 1, margin: const EdgeInsets.only(top: 3, bottom: 8), color: Theme.of(context).colorScheme.outlineVariant),
          child,
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;
  const _Section(this.title, this.child, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(title.toUpperCase(), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Tone.up(context)))),
          if (trailing != null) Text(trailing!, style: text.bodySmall),
        ]),
        Container(height: 1.5, margin: const EdgeInsets.only(top: 3, bottom: 8), color: Theme.of(context).colorScheme.onSurface),
        child,
      ]),
    );
  }
}

/// Đoạn có nhãn in đậm màu chủ đạo ở đầu, như báo cáo của công ty chứng khoán.
class _Lead extends StatelessWidget {
  final String label;
  final dynamic body;
  final dynamic bullets;
  final String? extra;
  final List<Widget> children;
  const _Lead(this.label, this.body, {this.bullets, this.extra, this.children = const []});

  @override
  Widget build(BuildContext context) {
    final text = (body ?? '').toString();
    if (text.isEmpty && children.isEmpty && (bullets is! List || (bullets as List).isEmpty)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (children.isNotEmpty) ...[
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: Tone.up(context))),
          const SizedBox(height: 4),
          ...children,
        ] else
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w800, color: Tone.up(context))),
              TextSpan(text: text),
            ]),
            style: const TextStyle(height: 1.45),
          ),
        if (bullets is List && (bullets as List).isNotEmpty) ...[const SizedBox(height: 4), Bullets(bullets as List)],
        if (extra != null) ...[
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: extra!.substring(0, extra!.indexOf(':') + 1), style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: extra!.substring(extra!.indexOf(':') + 1)),
          ])),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 8),
          DefaultTextStyle.merge(
            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
            child: value,
          ),
        ]),
      );
}

class _Recommendation extends StatelessWidget {
  final Map<String, dynamic> r, t, c;
  final double? avg;
  final String stance;
  const _Recommendation(this.r, this.t, this.c, this.avg, this.stance);

  @override
  Widget build(BuildContext context) {
    final tone = Tone.stance(context, stance);
    final close = _num(t['close']);
    final target = _num(c['vietcap_gia_muc_tieu']);
    final upside = target != null && close != null && close > 0 ? (target / (close * 1000) - 1) * 100 : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Nhận định AI', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(stance.toUpperCase(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tone)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        _Row('Giá hiện tại', Text(close == null ? '–' : '${fmt(close * 1000, 0)} đ')),
        _Row('Độ tin cậy', Text('${r['confidence'] ?? '–'}')),
        if (avg != null) _Row('Điểm tổng hợp', Text('${fmt(avg, 1)}/5')),
        if (target != null) ...[
          const Divider(height: 14),
          _Row('Giá mục tiêu Vietcap', Text('${fmt(target, 0)} đ')),
          if (upside != null) _Row('Tiềm năng', Pct(upside)),
          if (c['vietcap_khuyen_nghi'] != null) _Row('Khuyến nghị Vietcap', Text('${c['vietcap_khuyen_nghi']}')),
          Text('Nguồn bên thứ ba, chỉ để tham chiếu.', style: Theme.of(context).textTheme.labelSmall),
        ],
      ]),
    );
  }
}

class _StockInfo extends StatelessWidget {
  final Map<String, dynamic> t, f, c;
  final String day;
  const _StockInfo(this.t, this.f, this.c, this.day);

  @override
  Widget build(BuildContext context) {
    final ratios = (f['chi_so_ttm_theo_quy'] as List?) ?? [];
    final last = ratios.isEmpty ? <String, dynamic>{} : ratios.last as Map<String, dynamic>;
    final d = DateTime.parse(day);
    final hi = _num(t['high_52w']), lo = _num(t['low_52w']), vol = _num(t['volume']);
    final foreign = _num(c['so_huu_nuoc_ngoai']);
    return Column(children: [
      _Row('Ngày dữ liệu', Text('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}')),
      _Row('Thị giá', Text(t['close'] == null ? '–' : fmt(_num(t['close'])! * 1000, 0))),
      _Row('Biến động 1 năm', Pct(_num(t['change_1y']))),
      _Row('Đỉnh – đáy 52 tuần', Text(hi == null || lo == null ? '–' : '${fmt(lo, 1)} – ${fmt(hi, 1)}')),
      _Row('KLGD phiên cuối', Text(vol == null ? '–' : fmt(vol, 0))),
      _Row('Vốn hóa (tỷ đồng)', Text(c['von_hoa_ty_dong'] == null ? '–' : fmt(_num(c['von_hoa_ty_dong']), 0))),
      _Row('P/E', Text(last['pe'] == null ? '–' : '${fmt(_num(last['pe']), 1)}x')),
      _Row('P/B', Text(last['pb'] == null ? '–' : '${fmt(_num(last['pb']), 2)}x')),
      _Row('ROE', Text(_pctVal(last['roe']) == null ? '–' : '${fmt(_pctVal(last['roe']), 1)}%')),
      _Row('% NN sở hữu', Text(foreign == null ? '–' : '${fmt(_pctVal(foreign), 1)}%')),
      _Row('RSI 14', Text(fmt(_num(t['rsi14']), 1))),
    ]);
  }
}

class _PriceBlock extends StatelessWidget {
  final String symbol;
  final List<Bar> bars, market;
  const _PriceBlock(this.symbol, this.bars, this.market);

  @override
  Widget build(BuildContext context) {
    final shown = bars.length > 250 ? bars.sublist(bars.length - 250) : bars;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    String p(double? v) => v == null ? '–' : '${v >= 0 ? '+' : ''}${fmt(v, 0)}%';
    Widget cell(String s, {bool head = false, double? v}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Text(s,
              textAlign: head ? TextAlign.center : TextAlign.right,
              style: text.bodySmall?.copyWith(fontWeight: head ? FontWeight.w700 : FontWeight.w600, color: v == null ? null : Tone.of(context, v))),
        );
    TableRow row(String name, List<Bar> b) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4), child: Text(name, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
          for (final n in const [22, 66, 250]) cell(p(_change(b, n)), v: _change(b, n)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _LineChart(
        lines: [_Line(symbol, [for (final b in shown) b.c], Tone.up(context))],
        labels: [for (final b in shown) vnDate(b.t).substring(5).split('-').reversed.join('/')],
        height: 150,
        decimals: 1,
        summary: 'Giá đóng cửa $symbol ${shown.length} phiên gần nhất, mới nhất ${fmt(shown.last.c, 2)} nghìn đồng.',
        compact: true,
      ),
      const SizedBox(height: 8),
      Table(
        columnWidths: const {0: FlexColumnWidth(1.4)},
        border: TableBorder(horizontalInside: BorderSide(color: cs.outlineVariant), bottom: BorderSide(color: cs.outlineVariant)),
        children: [
          TableRow(decoration: BoxDecoration(color: cs.surfaceContainerHighest), children: [cell(''), cell('1T', head: true), cell('3T', head: true), cell('12T', head: true)]),
          row(symbol, bars),
          if (market.length > 250) row('VN-Index', market),
        ],
      ),
    ]);
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;
  const _ScoreBar(this.score);

  @override
  Widget build(BuildContext context) {
    final color = score >= 4 ? Tone.up(context) : (score <= 2 ? Tone.down(context) : Tone.flat(context));
    return Semantics(
      label: 'Điểm $score trên 5',
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Container(
              width: 14,
              height: 8,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: i <= score ? color : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 4),
          Text('$score', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Scenario extends StatelessWidget {
  final String title;
  final String? body;
  final Color color;
  const _Scenario(this.title, this.body, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body ?? '', style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

// ---------- Số liệu tài chính ----------

class _FinancialSection extends StatelessWidget {
  final Map<String, dynamic> f;
  const _FinancialSection(this.f);

  @override
  Widget build(BuildContext context) {
    final income = ((f['ket_qua_kinh_doanh_theo_quy_ty_dong'] as List?) ?? []).cast<Map<String, dynamic>>();
    final ratios = ((f['chi_so_ttm_theo_quy'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (income.isEmpty && ratios.isEmpty) return const SizedBox.shrink();
    final periods = [...{for (final x in income) x['ky'] as String, for (final x in ratios) x['ky'] as String}];
    // Sắp theo năm rồi quý: Q1/2025 < Q2/2025
    int key(String p) => int.parse(p.split('/')[1]) * 10 + int.parse(p[1]);
    periods.sort((a, b) => key(a).compareTo(key(b)));
    final shown = periods.length > 8 ? periods.sublist(periods.length - 8) : periods;
    Map<String, dynamic>? at(List<Map<String, dynamic>> l, String p) => l.where((x) => x['ky'] == p).firstOrNull;
    List<double?> series(List<Map<String, dynamic>> l, String k, {bool pct = false}) => [
          for (final p in shown) pct ? _pctVal(at(l, p)?[k]) : _num(at(l, p)?[k]),
        ];

    final revenue = series(income, 'doanh_thu_thuan'), profit = series(income, 'loi_nhuan_sau_thue_cong_ty_me');
    final gross = series(income, 'loi_nhuan_gop');
    final grossM = series(ratios, 'grossMargin', pct: true), netM = series(ratios, 'afterTaxProfitMargin', pct: true);
    final roe = series(ratios, 'roe', pct: true);
    final rows = <(String, List<double?>, int)>[
      ('Doanh thu thuần (tỷ đồng)', revenue, 0),
      ('Lợi nhuận gộp (tỷ đồng)', gross, 0),
      ('LNST công ty mẹ (tỷ đồng)', profit, 0),
      ('Biên lợi nhuận gộp (%)', grossM, 1),
      ('Biên lợi nhuận ròng (%)', netM, 1),
      ('ROE TTM (%)', roe, 1),
      ('P/E (x)', series(ratios, 'pe'), 1),
      ('P/B (x)', series(ratios, 'pb'), 2),
      ('Nợ/VCSH (x)', series(ratios, 'debtToEquity'), 2),
      ('Thanh toán hiện thời (x)', series(ratios, 'currentRatio'), 2),
      // Chỉ số riêng cho ngân hàng
      ('NIM (%)', series(ratios, 'netInterestMargin', pct: true), 1),
      ('Nợ xấu NPL (%)', series(ratios, 'npl', pct: true), 2),
      ('CIR (%)', series(ratios, 'cir', pct: true), 1),
      ('Tăng trưởng tín dụng (%)', series(ratios, 'loansGrowth', pct: true), 1),
      ('CASA (%)', series(ratios, 'casaRatio', pct: true), 1),
    ].where((x) => x.$2.any((v) => v != null)).toList();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brand = Tone.up(context);
    final labels = [for (final p in shown) p];

    final charts = <Widget>[
      if (revenue.any((v) => v != null))
        _ChartCard(
          'Doanh thu và lợi nhuận (tỷ đồng)',
          _BarChart(
            labels: labels,
            series: [('Doanh thu thuần', revenue, brand), ('LNST công ty mẹ', profit, cs.onSurfaceVariant)],
            summary: 'Doanh thu thuần và lợi nhuận sau thuế theo quý, ${labels.first} đến ${labels.last}.',
          ),
        ),
      if (grossM.any((v) => v != null) || roe.any((v) => v != null))
        _ChartCard(
          'Biên lợi nhuận và ROE (%)',
          _LineChart(
            lines: [
              if (grossM.any((v) => v != null)) _Line('Biên gộp', grossM, brand),
              if (netM.any((v) => v != null)) _Line('Biên ròng', netM, cs.onSurfaceVariant, dashed: true),
              if (roe.any((v) => v != null)) _Line('ROE TTM', roe, Tone.flat(context), dotted: true),
            ],
            labels: labels,
            height: 170,
            decimals: 1,
            unit: '%',
            summary: 'Biên lợi nhuận gộp, biên ròng và ROE theo quý, ${labels.first} đến ${labels.last}.',
          ),
        ),
    ];

    Widget cell(String s, {bool head = false, bool first = false, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          child: Text(s,
              textAlign: first ? TextAlign.left : TextAlign.right,
              style: text.bodySmall?.copyWith(
                fontWeight: head || bold ? FontWeight.w700 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        );
    final table = LayoutBuilder(builder: (context, cons) {
      final minW = 190 + shown.length * 74.0;
      final t = Table(
        columnWidths: {0: const FixedColumnWidth(190), for (var i = 1; i <= shown.length; i++) i: const FlexColumnWidth()},
        border: TableBorder(horizontalInside: BorderSide(color: cs.outlineVariant), bottom: BorderSide(color: cs.outlineVariant)),
        children: [
          TableRow(decoration: BoxDecoration(color: cs.surfaceContainerHighest), children: [
            cell('Chỉ tiêu', head: true, first: true),
            for (final p in shown) cell(p, head: true),
          ]),
          for (final (name, vals, d) in rows)
            TableRow(children: [
              cell(name, first: true, bold: true),
              for (final v in vals) cell(v == null ? '–' : fmt(v, d)),
            ]),
        ],
      );
      return cons.maxWidth >= minW
          ? t
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minW, child: t));
    });

    return _Section(
      'Kết quả kinh doanh và chỉ số tài chính',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (charts.isNotEmpty)
          LayoutBuilder(
            builder: (context, cons) => cons.maxWidth > 620 && charts.length > 1
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (i, w) in charts.indexed) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: w)],
                  ])
                : Column(children: [for (final w in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]),
          ),
        if (rows.isNotEmpty) ...[const SizedBox(height: 8), table],
        const SizedBox(height: 6),
        Text('Nguồn: Vietcap IQ. Chỉ số TTM tính theo 4 quý gần nhất.', style: text.labelSmall),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;
  const _ChartCard(this.title, this.chart);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        chart,
      ]);
}

// ---------- Biểu đồ ----------

class _Line {
  final String name;
  final List<double?> values;
  final Color color;
  final bool dashed, dotted;
  const _Line(this.name, this.values, this.color, {this.dashed = false, this.dotted = false});
}

Widget _legend(BuildContext context, List<(String, Color, bool dashed, bool dotted)> items) => Wrap(spacing: 14, runSpacing: 4, alignment: WrapAlignment.center, children: [
      for (final (name, color, dashed, dotted) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(
            size: const Size(22, 10),
            painter: _SwatchPainter(color, dashed, dotted),
          ),
          const SizedBox(width: 5),
          Text(name, style: Theme.of(context).textTheme.labelSmall),
        ]),
    ]);

class _SwatchPainter extends CustomPainter {
  final Color color;
  final bool dashed, dotted;
  _SwatchPainter(this.color, this.dashed, this.dotted);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dotted) {
      for (var x = 2.0; x < size.width; x += 6) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    } else if (dashed) {
      canvas.drawLine(Offset(0, y), Offset(8, y), p);
      canvas.drawLine(Offset(13, y), Offset(size.width, y), p);
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.dashed != dashed || old.dotted != dotted;
}

class _LineChart extends StatefulWidget {
  final List<_Line> lines;
  final List<String> labels;
  final double height;
  final int decimals;
  final String unit, summary;
  final bool compact;
  const _LineChart({
    required this.lines,
    required this.labels,
    required this.height,
    required this.summary,
    this.decimals = 1,
    this.unit = '',
    this.compact = false,
  });

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _hover;

  void _set(Offset p, double width) {
    final n = widget.labels.length;
    if (n < 2) return;
    final left = _ChartPainter.left, plotW = width - left - _ChartPainter.right;
    final i = ((p.dx - left) / plotW * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.summary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.compact || widget.lines.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _legend(context, [for (final l in widget.lines) (l.name, l.color, l.dashed, l.dotted)]),
          ),
        LayoutBuilder(
          builder: (context, cons) => MouseRegion(
            onHover: (e) => _set(e.localPosition, cons.maxWidth),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _set(d.localPosition, cons.maxWidth),
              onHorizontalDragUpdate: (d) => _set(d.localPosition, cons.maxWidth),
              child: CustomPaint(
                size: Size(cons.maxWidth, widget.height),
                painter: _ChartPainter(
                  lines: widget.lines,
                  labels: widget.labels,
                  decimals: widget.decimals,
                  unit: widget.unit,
                  hover: _hover,
                  grid: cs.outlineVariant,
                  textColor: cs.onSurfaceVariant,
                  surface: cs.surface,
                  onSurface: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const left = 40.0, right = 8.0, top = 8.0, bottom = 20.0;
  final List<_Line> lines;
  final List<String> labels;
  final int decimals;
  final String unit;
  final int? hover;
  final Color grid, textColor, surface, onSurface;
  _ChartPainter({
    required this.lines,
    required this.labels,
    required this.decimals,
    required this.unit,
    required this.hover,
    required this.grid,
    required this.textColor,
    required this.surface,
    required this.onSurface,
  });

  void _text(Canvas canvas, String s, Offset at, {Color? color, double size = 10, TextAlign align = TextAlign.left, double maxW = 120, FontWeight? weight}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color ?? textColor, fontSize: size, fontWeight: weight)),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: maxW);
    final dx = align == TextAlign.right ? at.dx - tp.width : (align == TextAlign.center ? at.dx - tp.width / 2 : at.dx);
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n < 2) return;
    var lo = double.infinity, hi = -double.infinity;
    for (final l in lines) {
      for (final v in l.values) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (!lo.isFinite) return;
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    double x(int i) => plot.left + plot.width * i / (n - 1);
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = lo + (hi - lo) * g / 3;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
      _text(canvas, fmt(v, decimals), Offset(plot.left - 4, y(v) - 6), align: TextAlign.right, maxW: left - 4);
    }
    // Nhãn trục x: đầu, giữa, cuối
    for (final i in {0, (n - 1) ~/ 2, n - 1}) {
      _text(canvas, labels[i], Offset(x(i), plot.bottom + 4),
          align: i == 0 ? TextAlign.left : (i == n - 1 ? TextAlign.right : TextAlign.center), maxW: 70);
    }
    // Căn nhãn đầu/cuối vào trong khung
    for (final l in lines) {
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = l.values[i];
        if (v == null) {
          started = false;
          continue;
        }
        started ? path.lineTo(x(i), y(v)) : path.moveTo(x(i), y(v));
        started = true;
      }
      final paint = Paint()
        ..color = l.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (l.dotted) {
        for (var i = 0; i < n; i++) {
          final v = l.values[i];
          if (v != null) canvas.drawCircle(Offset(x(i), y(v)), 3, Paint()..color = l.color);
        }
        canvas.drawPath(path, paint..strokeWidth = 1.2);
      } else if (l.dashed) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 9) {
            canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }
    final h = hover;
    if (h != null && h < n) {
      canvas.drawLine(Offset(x(h), plot.top), Offset(x(h), plot.bottom), Paint()..color = textColor.withValues(alpha: 0.6));
      final rows = [
        for (final l in lines)
          if (l.values[h] != null) (l, l.values[h]!),
      ];
      final width = 118.0, rowH = 15.0;
      final boxH = 20 + rows.length * rowH;
      var bx = x(h) + 8;
      if (bx + width > size.width) bx = x(h) - 8 - width;
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(bx, plot.top + 2, width, boxH), const Radius.circular(6));
      canvas.drawRRect(box, Paint()..color = surface);
      canvas.drawRRect(box, Paint()
        ..color = grid
        ..style = PaintingStyle.stroke);
      _text(canvas, labels[h], Offset(bx + 6, plot.top + 5), color: onSurface, weight: FontWeight.w700, maxW: width - 12);
      for (final (i, (l, v)) in rows.indexed) {
        final yy = plot.top + 20 + i * rowH;
        canvas.drawCircle(Offset(bx + 10, yy + 6), 3, Paint()..color = l.color);
        _text(canvas, '${fmt(v, decimals)}$unit', Offset(bx + 18, yy), color: onSurface, maxW: width - 24);
        canvas.drawCircle(Offset(x(h), y(v)), 3.5, Paint()..color = l.color);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

class _BarChart extends StatelessWidget {
  final List<String> labels;
  final List<(String, List<double?>, Color)> series;
  final String summary;
  const _BarChart({required this.labels, required this.series, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: summary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _legend(context, [for (final s in series) (s.$1, s.$3, false, false)]),
        ),
        LayoutBuilder(
          builder: (context, cons) => CustomPaint(
            size: Size(cons.maxWidth, 170),
            painter: _BarPainter(labels, series, cs.outlineVariant, cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<String> labels;
  final List<(String, List<double?>, Color)> series;
  final Color grid, textColor;
  _BarPainter(this.labels, this.series, this.grid, this.textColor);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, top = 14.0, bottom = 20.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);
    var hi = 0.0, lo = 0.0;
    for (final s in series) {
      for (final v in s.$2) {
        if (v == null) continue;
        hi = math.max(hi, v);
        lo = math.min(lo, v);
      }
    }
    if (hi == lo) return;
    hi *= 1.08;
    lo *= 1.08;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    void text(String s, Offset at, {TextAlign align = TextAlign.left, double size = 10, double maxW = 80}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: textColor, fontSize: size)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: maxW);
      final dx = align == TextAlign.right ? at.dx - tp.width : (align == TextAlign.center ? at.dx - tp.width / 2 : at.dx);
      tp.paint(canvas, Offset(dx, at.dy));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = lo + (hi - lo) * g / 3;
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
      text(fmt(v, 0), Offset(plot.left - 4, y(v) - 6), align: TextAlign.right, maxW: left - 4);
    }
    final n = labels.length;
    final groupW = plot.width / n;
    final barW = math.min(18.0, groupW * 0.8 / series.length);
    for (var i = 0; i < n; i++) {
      final cx = plot.left + groupW * (i + 0.5);
      for (final (k, s) in series.indexed) {
        final v = s.$2[i];
        if (v == null) continue;
        final bx = cx - barW * series.length / 2 + k * barW;
        final top0 = y(math.max(v, 0)), bottom0 = y(math.min(v, 0));
        canvas.drawRect(Rect.fromLTRB(bx + 0.5, top0, bx + barW - 0.5, bottom0), Paint()..color = s.$3.withValues(alpha: k == 0 ? 1 : 0.7));
        if (groupW >= 44) text(fmt(v, 0), Offset(bx + barW / 2, top0 - 11), align: TextAlign.center, size: 9, maxW: barW * 2.4);
      }
      text(labels[i], Offset(cx, plot.bottom + 4), align: TextAlign.center, size: groupW >= 44 ? 10 : 9, maxW: groupW + 6);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.series != series || old.labels != labels;
}
