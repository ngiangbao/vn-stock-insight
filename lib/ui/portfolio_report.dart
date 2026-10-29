// Báo cáo phân tích danh mục đầu tư: tóm tắt, đối chiếu với chính sách đầu tư (IPS), vị thế (tỷ trọng so với đóng góp rủi ro),
// hiệu suất so với VN-Index, đa dạng hóa (tương quan, ngành), kiểm tra sức chịu đựng, rồi phần diễn giải của AI.
// Mọi biểu đồ đều kèm số liệu bằng chữ, không chỉ phân biệt bằng màu.

import 'package:flutter/material.dart';

import 'analysis_report.dart' show ReportSection;
import 'cfa_report.dart';
import 'widgets.dart';

double? _n(dynamic x) => x is num ? x.toDouble() : null;
String _pct(dynamic x, [int d = 1]) => _n(x) == null ? '–' : '${fmt(_n(x)! * 100, d)}%';
String _num(dynamic x, [int d = 2]) => _n(x) == null ? '–' : fmt(_n(x), d);

/// Tiền nghìn đồng -> chuỗi "x,x tỷ" hoặc "x triệu".
String money(dynamic thousand) {
  final v = _n(thousand);
  if (v == null) return '–';
  final dong = v * 1000;
  if (dong.abs() >= 1e9) return '${fmt(dong / 1e9, 2)} tỷ';
  return '${fmt(dong / 1e6, 1)} triệu';
}

class PortfolioReport extends StatelessWidget {
  final Map<String, dynamic> portfolio;
  final Map<String, dynamic> analysis;
  const PortfolioReport(this.portfolio, this.analysis, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from(analysis['result'] as Map);
    final inputs = Map<String, dynamic>.from(analysis['inputs'] as Map);
    final st = Map<String, dynamic>.from((inputs['stats'] as Map?) ?? const {});
    final q = Map<String, dynamic>.from((st['chi_so_danh_muc'] as Map?) ?? const {});
    final div = Map<String, dynamic>.from((st['da_dang_hoa'] as Map?) ?? const {});
    final val = Map<String, dynamic>.from((inputs['valuation'] as Map?) ?? const {});
    final rows = ((st['vi_the'] as List?) ?? const []).cast<Map>();
    final series = Map<String, dynamic>.from((analysis['series'] as Map?) ?? const {});
    final a = Map<String, dynamic>.from((analysis['assumptions'] as Map?) ?? const {});
    final ips = Map<String, dynamic>.from((analysis['ips'] as Map?) ?? const {});
    final created = DateTime.parse(analysis['created_at']);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final brand = Tone.up(context);
    final rating = '${r['rating']}';
    final ratingTone = switch (rating) {
      'Cân đối' => Tone.up(context),
      'Cần xem lại' => Tone.down(context),
      _ => Tone.flat(context),
    };
    final notes = {for (final h in ((r['holdings'] as List?) ?? const []).cast<Map>()) '${h['symbol']}': h};

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
    final ipsAi = m('ips'),
        risk = m('risk'),
        ret = m('returns'),
        valAi = m('valuation'),
        divAi = m('diversification'),
        reb = m('rebalancing');
    final scenarios = ((r['scenarios'] as List?) ?? const []).cast<Map>();

    final tiles = <(String, String)>[
      ('Tổng giá trị', money(st['tong_gia_tri_nghin_dong'])),
      ('Số mã', '${st['so_ma'] ?? '–'}'),
      ('Lợi suất 1 năm', _pct(q['loi_suat_nam'])),
      ('Biến động năm', _pct(div['bien_dong_danh_muc_nam'])),
      ('Sharpe', _num(q['sharpe'])),
      ('Beta so với VN-Index', _num(q['beta'])),
      ('Sụt giảm tối đa', _pct(q['sut_giam_toi_da'])),
      ('VaR 95% 1 ngày', _pct(q['var95_1_ngay'], 2)),
      ('Tỷ số đa dạng hóa', _num(div['ty_so_da_dang_hoa'])),
      ('Số mã hiệu dụng', _num(div['so_ma_hieu_dung'], 1)),
      ('Mã lớn nhất', _pct(div['ty_trong_ma_lon_nhat'])),
      ('P/E / P/B', '${_num(val['pe'], 1)} / ${_num(val['pb'])}'),
      ('ROE theo tỷ trọng', _pct(val['roe'])),
      ('Tiền mặt', _pct(st['ty_trong_tien_mat'])),
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
                    'BÁO CÁO PHÂN TÍCH DANH MỤC ĐẦU TƯ',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${portfolio['name']}'.toUpperCase(),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: brand),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tag(rating, color: ratingTone),
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
          child: Text(
            'Độ tin cậy: ${r['confidence'] ?? '–'} · Số liệu đến ngày ${st['den_ngay'] ?? '–'}',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) ReportTile(t.$1, t.$2)]),
        ReportSection(
          '1. Chính sách đầu tư (IPS)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportKV([
                ('Mục tiêu', '${ips['goal'] ?? '–'}'),
                ('Khung thời gian', '${ips['horizon'] ?? '–'}'),
                ('Chấp nhận rủi ro', '${ips['risk'] ?? '–'}'),
              ]),
              const SizedBox(height: 10),
              sub('Mục tiêu', ipsAi['objective']),
              sub('Khung thời gian', ipsAi['horizon']),
              sub('Mức chấp nhận rủi ro', ipsAi['risk_tolerance']),
              sub('Kết luận', ipsAi['verdict']),
            ],
          ),
        ),
        ReportSection(
          '2. Vị thế và đóng góp rủi ro',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WeightRiskBars(rows),
              const SizedBox(height: 12),
              _HoldingsTable(rows, notes),
              if ((st['ma_bi_bo_qua_thieu_du_lieu_gia'] as List?)?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Không đủ dữ liệu giá nên bị bỏ qua: ${(st['ma_bi_bo_qua_thieu_du_lieu_gia'] as List).join(', ')}.',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        ReportSection(
          '3. Hiệu suất so với VN-Index',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((series['dates'] as List?)?.isNotEmpty ?? false)
                RelChart(
                  series,
                  mainKey: 'danh_muc',
                  benchKey: 'vnindex',
                  mainLabel: 'Danh mục',
                  title: 'Lợi suất tích lũy 1 năm: danh mục so với VN-Index',
                ),
              const SizedBox(height: 10),
              QuantTable(q),
              const SizedBox(height: 10),
              para(ret['summary']),
              sub('Đóng góp lợi suất', ret['attribution']),
              sub('Lợi suất điều chỉnh rủi ro', ret['risk_adjusted']),
            ],
          ),
        ),
        ReportSection(
          '4. Rủi ro, đa dạng hóa và sức chịu đựng',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportKV([
                (
                  'Biến động danh mục / tương quan trung bình giữa các cặp',
                  '${_pct(div['bien_dong_danh_muc_nam'])} / ${_num(div['tuong_quan_binh_quan_cap'])}',
                ),
                ('HHI / số mã hiệu dụng', '${_num(div['hhi'], 3)} / ${_num(div['so_ma_hieu_dung'], 1)}'),
                ('Tỷ trọng mã lớn nhất / 3 mã lớn nhất', '${_pct(div['ty_trong_ma_lon_nhat'])} / ${_pct(div['ty_trong_3_ma_lon_nhat'])}'),
                ('Số ngành', '${div['so_nganh'] ?? '–'}'),
              ]),
              const SizedBox(height: 10),
              _SectorBars(((st['nganh'] as List?) ?? const []).cast<Map>()),
              const SizedBox(height: 10),
              _Correlation(Map<String, dynamic>.from((st['tuong_quan'] as Map?) ?? const {})),
              const SizedBox(height: 10),
              _Stress(Map<String, dynamic>.from((st['kiem_tra_suc_chiu_dung'] as Map?) ?? const {})),
              const SizedBox(height: 10),
              para(risk['summary']),
              sub('Tập trung', risk['concentration']),
              sub('Tương quan', risk['correlation']),
              sub('Rủi ro đuôi', risk['tail']),
              sub('Sức chịu đựng', risk['stress']),
            ],
          ),
        ),
        ReportSection(
          '5. Định giá và đa dạng hóa',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              para(valAi['summary']),
              sub('Phong cách', valAi['style']),
              para(divAi['summary']),
              sub('Ngành', divAi['sectors']),
              if ((divAi['considerations'] as List?)?.isNotEmpty ?? false) ...[
                Text('Hướng cân nhắc', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(divAi['considerations']),
              ],
            ],
          ),
        ),
        ReportSection(
          '6. Tái cân bằng',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              para(reb['approach']),
              if ((reb['triggers'] as List?)?.isNotEmpty ?? false) ...[
                Text('Điều kiện xem lại', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Bullets(reb['triggers']),
                const SizedBox(height: 8),
              ],
              sub('Chi phí', reb['costs']),
            ],
          ),
        ),
        if ((r['behavioral'] as List?)?.isNotEmpty ?? false) ReportSection('7. Sai lệch hành vi cần lưu ý', Bullets(r['behavioral'])),
        if (scenarios.isNotEmpty)
          ReportSection(
            '8. Kịch bản có xác suất',
            LayoutBuilder(
              builder: (context, c) {
                final cards = [
                  for (final s in scenarios) ScenarioCard({...Map<String, dynamic>.from(s), 'price_effect': s['effect']}),
                ];
                return c.maxWidth >= 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: cards[i])],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: c)],
                      );
              },
            ),
          ),
        if ((r['monitoring'] as List?)?.isNotEmpty ?? false) ReportSection('9. Chỉ tiêu cần theo dõi', Bullets(r['monitoring'])),
        if ((r['risks'] as List?)?.isNotEmpty ?? false) ReportSection('10. Rủi ro', Bullets(r['risks'])),
        ReportSection('11. Đạo đức và giới hạn của phân tích', para(r['ethics'])),
        if ((r['data_gaps'] as List?)?.isNotEmpty ?? false) ReportSection('Hạn chế dữ liệu', Bullets(r['data_gaps'])),
        Divider(height: 28, color: cs.outlineVariant),
        Text(
          'Giả định: lãi suất phi rủi ro ${_pct(a['rf'])}. Tỷ trọng hiện tại được giữ không đổi trong 1 năm để tính lợi suất và rủi ro lịch sử; '
          'các mức "cân nhắc" cho từng mã chỉ là gợi ý định tính, không phải lệnh mua/bán. '
          'Chỉ số định lượng tính cục bộ từ giá DNSE và VN-Index; phần diễn giải do AI viết. Phân tích lúc ${timeVN(created)} · ${analysis['ai']}. '
          '$disclaimer Đây không phải sản phẩm của CFA Institute.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// Tỷ trọng vốn so với tỷ trọng đóng góp rủi ro của từng mã; số liệu in bên phải thanh nên không chỉ dựa vào màu.
class _WeightRiskBars extends StatelessWidget {
  final List<Map> rows;
  const _WeightRiskBars(this.rows);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c1 = Tone.up(context), c2 = Tone.flat(context);
    final maxV = rows.fold<double>(
      0.01,
      (m, r) => [m, _n(r['ty_trong']) ?? 0, _n(r['dong_gop_rui_ro']) ?? 0].reduce((a, b) => a > b ? a : b),
    );
    Widget bar(double? v, Color c, {bool hatched = false}) => LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth * ((v ?? 0).clamp(0, maxV) / maxV);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: w < 2 && (v ?? 0) > 0 ? 2 : w,
            height: 9,
            decoration: BoxDecoration(
              color: hatched ? c.withValues(alpha: 0.25) : c,
              border: hatched ? Border.all(color: c, width: 1.5) : null,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tỷ trọng vốn so với đóng góp rủi ro', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 18, height: 9, color: c1),
                const SizedBox(width: 6),
                Flexible(child: Text('Tỷ trọng vốn (thanh đặc)', style: text.bodySmall)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c2.withValues(alpha: 0.25),
                    border: Border.all(color: c2, width: 1.5),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text('Đóng góp rủi ro (thanh viền)', style: text.bodySmall)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              label: '${r['ma']}: tỷ trọng ${_pct(r['ty_trong'])}, đóng góp rủi ro ${_pct(r['dong_gop_rui_ro'])}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text('${r['ma']}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      child: Column(
                        children: [bar(_n(r['ty_trong']), c1), const SizedBox(height: 3), bar(_n(r['dong_gop_rui_ro']), c2, hatched: true)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 112,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _pct(r['ty_trong']),
                            style: text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            _pct(r['dong_gop_rui_ro']),
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
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

class _HoldingsTable extends StatelessWidget {
  final List<Map> rows;
  final Map<String, Map> notes;
  const _HoldingsTable(this.rows, this.notes);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String t, {bool bold = false, bool right = true, double w = 78}) => SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        child: Text(
          t,
          textAlign: right ? TextAlign.end : TextAlign.start,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
    final head = [
      ('Mã', 56.0, false),
      ('Giá trị', 92.0, true),
      ('Tỷ trọng', 78.0, true),
      ('Rủi ro', 70.0, true),
      ('Lãi/lỗ', 74.0, true),
      ('Lợi suất', 78.0, true),
      ('Biến động', 78.0, true),
      ('Beta', 56.0, true),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: cs.surfaceContainerHighest,
            child: Row(
              children: [
                for (final h in head) cell(h.$1, bold: true, w: h.$2, right: h.$3),
                cell('Cân nhắc (định tính)', bold: true, w: 190, right: false),
              ],
            ),
          ),
          for (final (i, r) in rows.indexed)
            Container(
              color: i.isEven ? null : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell('${r['ma']}', bold: true, w: 56, right: false),
                  cell(money(r['gia_tri_nghin_dong']), w: 92),
                  cell(_pct(r['ty_trong']), w: 78),
                  cell(_pct(r['dong_gop_rui_ro']), w: 70),
                  cell(_n(r['lai_lo_pct']) == null ? '–' : '${_n(r['lai_lo_pct'])! > 0 ? '+' : ''}${fmt(_n(r['lai_lo_pct']), 1)}%', w: 74),
                  cell(_pct(r['loi_suat_nam']), w: 78),
                  cell(_pct(r['bien_dong_nam']), w: 78),
                  cell(_num(r['beta']), w: 56),
                  cell('${notes['${r['ma']}']?['consideration'] ?? '–'}', w: 190, right: false),
                ],
              ),
            ),
          if (notes.values.any((n) => '${n['comment'] ?? ''}'.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                width: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rows)
                      if ('${notes['${r['ma']}']?['comment'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${r['ma']}: ',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: '${notes['${r['ma']}']!['comment']}'),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectorBars extends StatelessWidget {
  final List<Map> sectors;
  const _SectorBars(this.sectors);

  @override
  Widget build(BuildContext context) {
    if (sectors.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final color = Tone.up(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tỷ trọng theo ngành', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final s in sectors)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 150, child: Text('${s['nganh']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: box.maxWidth * (_n(s['ty_trong']) ?? 0).clamp(0.0, 1.0),
                        height: 10,
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    _pct(s['ty_trong']),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ma trận tương quan: số in rõ ở từng ô, ô tương quan cao (từ 0,7) in đậm có viền để không chỉ dựa vào màu.
class _Correlation extends StatelessWidget {
  final Map<String, dynamic> corr;
  const _Correlation(this.corr);

  @override
  Widget build(BuildContext context) {
    final names = ((corr['ma'] as List?) ?? const []).cast<String>();
    final mat = ((corr['ma_tran'] as List?) ?? const []).cast<List>();
    if (names.length < 2) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final base = Tone.down(context);
    Widget cell(String t, {Color? bg, bool bold = false, bool border = false}) => Container(
      width: 52,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: border ? Border.all(color: base, width: 1.5) : null,
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tương quan lợi suất ngày giữa các mã (ô viền đậm: từ 0,7 trở lên)',
          style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: [
              Row(
                children: [
                  cell(''),
                  for (final n in names) cell(n, bold: true, bg: cs.surfaceContainerHighest),
                ],
              ),
              for (var i = 0; i < names.length; i++)
                Row(
                  children: [
                    cell(names[i], bold: true, bg: cs.surfaceContainerHighest),
                    for (var j = 0; j < names.length; j++)
                      () {
                        final v = _n(mat[i][j]) ?? 0;
                        final high = i != j && v >= 0.7;
                        return cell(
                          fmt(v, 2),
                          bg: i == j ? cs.surfaceContainerHighest : base.withValues(alpha: (v.clamp(0, 1)) * 0.28),
                          bold: high,
                          border: high,
                        );
                      }(),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stress extends StatelessWidget {
  final Map<String, dynamic> s;
  const _Stress(this.s);

  @override
  Widget build(BuildContext context) {
    final shocks = ((s['cu_soc_theo_beta'] as List?) ?? const []).cast<Map>();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Kiểm tra sức chịu đựng', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ReportKV([
          for (final x in shocks)
            ('VN-Index giảm ${(-(_n(x['vnindex_pct']) ?? 0)).toStringAsFixed(0)}% (theo beta)', '${_num(x['danh_muc_uoc_tinh_pct'], 1)}%'),
          ('Ngày tệ nhất 1 năm', '${_num(s['te_nhat_1_ngay_pct'])}%'),
          ('20 phiên tệ nhất 1 năm', '${_num(s['te_nhat_20_phien_pct'], 1)}%'),
        ]),
        if ('${s['luu_y'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${s['luu_y']}', style: text.bodySmall),
          ),
      ],
    );
  }
}
