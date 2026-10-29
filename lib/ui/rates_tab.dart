// Tab "Lãi suất hằng ngày" của trang Vĩ mô: đường cong lợi suất TPCP, lãi suất điều hành, liên ngân hàng, CPI, lãi suất thực tự tính,
// lãi suất tiền gửi theo kỳ hạn và ghi chú về lãi suất cho vay. Thẻ cùng kích thước như các tab còn lại; biểu đồ có số liệu bằng chữ
// và chú giải, giá trị hiện khi rê chuột/chạm; chiều tăng giảm có mũi tên và dấu, không chỉ dựa vào màu.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/rates.dart';
import '../state.dart';
import 'widgets.dart' show fmt, timeLocal;

class RatesTab extends StatefulWidget {
  /// Chỉ dùng trong kiểm thử để thay nguồn dữ liệu.
  final RatesRepository? repository;
  const RatesTab({super.key, this.repository});

  @override
  State<RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends State<RatesTab> {
  RatesRepository? _repo;
  RatesSnapshot? _snap;
  Map<String, double>? _prev;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      final dir = AppScope.of(context).dataDir.path;
      _repo =
          widget.repository ??
          RatesRepository(
            cacheFile: File('$dir${Platform.pathSeparator}rates_cache.json'),
            historyFile: File('$dir${Platform.pathSeparator}rates_history.json'),
          );
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final prev = await _repo!.previousDay();
      final snap = await _repo!.load(force: force);
      if (mounted) {
        setState(() {
          _snap = snap;
          _prev = prev;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = _snap;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    final cards = <Widget>[
      _CurveCard(s, _prev, _loading),
      _StatCard(
        title: 'Lãi suất điều hành',
        value: s?.policy,
        prev: _prev?['policy'],
        note: 'Lãi suất do Ngân hàng Nhà nước quy định, làm nền cho mặt bằng lãi suất thị trường.',
        source: 'TradingEconomics qua TradingView',
        asOf: s == null ? null : 'cập nhật ${timeLocal(s.fetchedAt)}',
        loading: _loading,
      ),
      _StatCard(
        title: 'Lãi suất liên ngân hàng',
        value: s?.interbank,
        prev: _prev?['interbank'],
        note: 'Lãi suất vay mượn giữa các ngân hàng, phản ánh độ căng của thanh khoản hệ thống. Kỳ hạn theo nguồn, có thể là qua đêm.',
        source: 'TradingEconomics qua TradingView',
        asOf: s?.interbankDate == null ? null : 'số liệu ngày ${_vn(s!.interbankDate!)}',
        loading: _loading,
      ),
      _StatCard(
        title: 'Lạm phát CPI so với cùng kỳ',
        value: s?.cpiYoy,
        prev: _prev?['cpi'],
        note: s?.coreCpi == null
            ? 'CPI là số đã qua, công bố hằng tháng.'
            : 'Lạm phát lõi ${fmt(s!.coreCpi, 2)}%. CPI công bố hằng tháng nên là số đã qua.',
        source: 'TradingEconomics qua TradingView',
        asOf: s?.cpiPeriod == null ? null : 'kỳ ${_month(s!.cpiPeriod!)}',
        loading: _loading,
      ),
      _RealCard(s, _loading),
      _DepositCard(s, _prev, _loading),
      const _LoanCard(),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s == null
                          ? 'Đang tải lãi suất…'
                          : 'Cập nhật lúc ${timeLocal(s.fetchedAt)}${s.fromCache ? ' (bản đã lưu)' : ''}. Số liệu làm mới mỗi 30 phút khi mở tab.',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  _loading
                      ? Semantics(
                          label: 'Đang tải lãi suất',
                          child: const SizedBox.square(
                            dimension: 48,
                            child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5)),
                          ),
                        )
                      : IconButton(
                          onPressed: () => _load(force: true),
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Làm mới lãi suất',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                ],
              ),
            ),
          ),
          if ((s?.failed.isNotEmpty ?? false) && !_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, color: cs.onErrorContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Không tải được: ${s!.failed.join(', ')}. Kiểm tra kết nối mạng rồi làm mới.',
                            style: text.bodyMedium?.copyWith(color: cs.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 360 * scale,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildListDelegate(cards),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                'Nguồn: TradingEconomics qua điểm cuối công khai của TradingView (lợi suất TPCP, lãi suất điều hành, liên ngân hàng, CPI), CafeF (lãi suất tiền gửi các ngân hàng; không rõ kênh quầy hay trực tuyến). '
                'Lãi suất thực là số tự tính: lãi suất danh nghĩa trừ CPI cùng kỳ gần nhất. Mũi tên so với ngày gần nhất app đã lưu trên máy này, nên cần mở app vài ngày mới có. '
                'Điểm cuối của TradingView không có tài liệu chính thức và có thể thay đổi. Chỉ mang tính tham khảo.',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _vn(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}' : iso;
String _month(String iso) => iso.length >= 7 ? '${iso.substring(5, 7)}/${iso.substring(0, 4)}' : iso;

/// Mũi tên và chênh lệch so với lần lưu trước (điểm phần trăm), không chỉ dựa vào màu.
Widget _delta(BuildContext context, double? now, double? prev) {
  final text = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  if (now == null || prev == null) {
    return Text('Chưa có số liệu ngày trước để so sánh', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant));
  }
  final d = now - prev;
  return Row(
    children: [
      Icon(d > 0.0049 ? Icons.arrow_upward : (d < -0.0049 ? Icons.arrow_downward : Icons.remove), size: 16, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          '${d > 0.0049 ? '+' : (d < -0.0049 ? '−' : '')}${fmt(d.abs(), 2)} điểm % so với lần lưu trước',
          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _CardShell extends StatelessWidget {
  final String title, source;
  final String? asOf;
  final Widget? header;
  final Widget body;

  /// Thân thẻ cuộn được khi chữ dài hoặc cỡ chữ hệ thống lớn, để không bị cắt hay tràn; thẻ vẫn giữ nguyên kích thước.
  final bool scroll;
  const _CardShell({required this.title, required this.source, required this.body, this.header, this.asOf, this.scroll = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: header ?? const SizedBox.shrink()),
            Expanded(
              child: scroll
                  ? LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: IntrinsicHeight(child: body),
                        ),
                      ),
                    )
                  : body,
            ),
            const SizedBox(height: 8),
            Text(
              'Nguồn: $source${asOf == null ? '' : ' · $asOf'}',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _big(BuildContext context, double? v, {String unit = '%'}) {
  final text = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  if (v == null) return Text('–', style: text.titleLarge?.copyWith(fontSize: 26));
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '${v < 0 ? '−' : ''}${fmt(v.abs(), 2)}', style: text.titleLarge?.copyWith(fontSize: 26)),
        TextSpan(
          text: '  $unit',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String title, note, source;
  final double? value, prev;
  final String? asOf;
  final bool loading;
  const _StatCard({
    required this.title,
    required this.value,
    required this.prev,
    required this.note,
    required this.source,
    required this.asOf,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _CardShell(
      scroll: true,
      title: title,
      source: source,
      asOf: asOf,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _big(context, value, unit: '%/năm'),
          _delta(context, value, prev),
        ],
      ),
      body: value == null && loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(value == null ? 'Chưa tải được số liệu này.' : note, style: text.bodyMedium),
            ),
    );
  }
}

class _RealCard extends StatelessWidget {
  final RatesSnapshot? s;
  final bool loading;
  const _RealCard(this.s, this.loading);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rows = <(String, double?, double?)>[
      ('Trái phiếu 10 năm', s?.y10, s?.real10y),
      ('Tiền gửi 12 tháng (trung bình)', s?.dep12, s?.realDeposit12),
      ('Lãi suất điều hành', s?.policy, s?.realPolicy),
    ];
    String signed(double v) => '${v > 0 ? '+' : (v < 0 ? '−' : '')}${fmt(v.abs(), 2)}%';
    return _CardShell(
      scroll: true,
      title: 'Lãi suất thực (tự tính)',
      source: 'tính từ các chỉ tiêu bên cạnh',
      asOf: s?.cpiPeriod == null ? null : 'CPI kỳ ${_month(s!.cpiPeriod!)}',
      header: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: s?.real10y == null ? '–' : signed(s!.real10y!), style: text.titleLarge?.copyWith(fontSize: 26)),
            TextSpan(
              text: '  trái phiếu 10 năm',
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: s == null
          ? Center(child: loading ? const CircularProgressIndicator() : const Text('Chưa tải được số liệu này.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 5, child: Text('Chỉ tiêu', style: text.labelLarge)),
                    Expanded(
                      flex: 2,
                      child: Text('Danh nghĩa', style: text.labelLarge, textAlign: TextAlign.end),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Thực', style: text.labelLarge, textAlign: TextAlign.end),
                    ),
                  ],
                ),
                const Divider(),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: Text(r.$1)),
                        Expanded(flex: 2, child: Text(r.$2 == null ? '–' : '${fmt(r.$2, 2)}%', textAlign: TextAlign.end)),
                        Expanded(
                          flex: 2,
                          child: Text(
                            r.$3 == null ? '–' : signed(r.$3!),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(
                  s?.real10y == null
                      ? 'Thiếu CPI hoặc lãi suất để tính.'
                      : (s!.real10y! < 0
                            ? 'Lãi suất thực âm: lợi suất danh nghĩa thấp hơn lạm phát, người giữ trái phiếu bị mất sức mua.'
                            : 'Lãi suất thực dương: lợi suất danh nghĩa cao hơn lạm phát.'),
                  style: text.bodySmall,
                ),
              ],
            ),
    );
  }
}

/// Biểu đồ theo hạng mục (kỳ hạn): đường nối các điểm hoặc cột, nhãn giá trị trên từng điểm, rê chuột/chạm để xem chi tiết.
class _CategoryChart extends StatefulWidget {
  final List<String> labels;
  final List<double?> values;
  final bool bars;
  final List<String>? details;
  final String summary;
  const _CategoryChart({required this.labels, required this.values, required this.summary, this.bars = false, this.details});

  @override
  State<_CategoryChart> createState() => _CategoryChartState();
}

class _CategoryChartState extends State<_CategoryChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = widget.labels.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              void track(Offset p) {
                final i = ((p.dx - 36) / math.max(1, box.maxWidth - 36 - 8) * n).floor().clamp(0, n - 1);
                if (i != _hover) setState(() => _hover = i);
              }

              return Semantics(
                label: widget.summary,
                child: MouseRegion(
                  onHover: (e) => track(e.localPosition),
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (e) => track(e.localPosition),
                    onHorizontalDragUpdate: (e) => track(e.localPosition),
                    child: CustomPaint(
                      size: Size(box.maxWidth, box.maxHeight),
                      painter: _CategoryPainter(
                        widget.labels,
                        widget.values,
                        widget.bars,
                        Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3ECF7F) : const Color(0xFF0F8A4A),
                        cs.outlineVariant,
                        cs.onSurfaceVariant,
                        cs.onSurface,
                        _hover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _hover == null
              ? 'Rê chuột hoặc chạm vào biểu đồ để xem chi tiết.'
              : (widget.details?[_hover!] ??
                    '${widget.labels[_hover!]}: ${widget.values[_hover!] == null ? '–' : '${fmt(widget.values[_hover!], 2)}%'}'),
          style: text.bodySmall?.copyWith(fontWeight: _hover == null ? FontWeight.w400 : FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CategoryPainter extends CustomPainter {
  final List<String> labels;
  final List<double?> values;
  final bool bars;
  final Color main, grid, muted, strong;
  final int? hover;
  _CategoryPainter(this.labels, this.values, this.bars, this.main, this.grid, this.muted, this.strong, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 36.0, r = 8.0, t = 14.0, b = 20.0;
    final w = size.width - l - r, h = size.height - t - b;
    final vs = [for (final v in values) ?v];
    if (w <= 0 || h <= 0 || vs.isEmpty) return;
    var lo = bars ? 0.0 : vs.reduce(math.min), hi = vs.reduce(math.max);
    if (!bars) {
      final pad = math.max((hi - lo) * 0.25, 0.1);
      lo -= pad;
      hi += pad;
    } else {
      hi *= 1.15;
    }
    final n = labels.length;
    double x(int i) => l + (i + 0.5) / n * w;
    double y(double v) => t + h - (v - lo) / (hi - lo) * h;

    void txt(String s, Offset at, {bool right = false, bool center = false, Color? color, bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 11, color: color ?? muted, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(right ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx), at.dy - tp.height / 2));
    }

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      canvas.drawLine(Offset(l, y(v)), Offset(l + w, y(v)), gp);
      txt('${fmt(v, 1)}%', Offset(l - 4, y(v)), right: true);
    }
    for (var i = 0; i < n; i++) {
      txt(labels[i], Offset(x(i), size.height - 8), center: true, color: hover == i ? strong : muted, bold: hover == i);
    }
    if (bars) {
      final bw = math.min(w / n * 0.62, 34.0);
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x(i) - bw / 2, y(v), x(i) + bw / 2, y(lo)), const Radius.circular(3)),
          Paint()..color = hover == i ? main : main.withValues(alpha: 0.75),
        );
        txt(fmt(v, 2), Offset(x(i), y(v) - 8), center: true, color: strong, bold: true);
      }
    } else {
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        started ? path.lineTo(x(i), y(v)) : path.moveTo(x(i), y(v));
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = main
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        canvas.drawCircle(Offset(x(i), y(v)), hover == i ? 5 : 3.5, Paint()..color = main);
        if (hover == i || i == 0 || i == n - 1 || labels[i] == '10N') {
          txt(fmt(v, 2), Offset(x(i), y(v) - 12), center: true, color: strong, bold: true);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CategoryPainter old) => old.hover != hover || old.values != values || old.main != main || old.bars != bars;
}

class _CurveCard extends StatelessWidget {
  final RatesSnapshot? s;
  final Map<String, double>? prev;
  final bool loading;
  const _CurveCard(this.s, this.prev, this.loading);

  @override
  Widget build(BuildContext context) {
    final y = s?.yields ?? const <int, double>{};
    final labels = [for (final t in yieldTenors) t.$1];
    final values = [for (final t in yieldTenors) y[t.$2]];
    final spread = y[10] != null && y[1] != null ? y[10]! - y[1]! : null;
    return _CardShell(
      title: 'Đường cong lợi suất trái phiếu chính phủ',
      source: 'TradingEconomics qua TradingView',
      asOf: s == null ? null : 'cập nhật ${timeLocal(s!.fetchedAt)}',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: y[10] == null ? '–' : fmt(y[10], 2), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26)),
                TextSpan(
                  text:
                      '  %/năm (10 năm)${spread == null ? '' : ' · chênh 10N − 1N: ${spread >= 0 ? '+' : '−'}${fmt(spread.abs(), 2)} điểm %'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _delta(context, y[10], prev?['y10']),
        ],
      ),
      body: y.isEmpty
          ? Center(child: loading ? const CircularProgressIndicator() : const Text('Chưa tải được số liệu này.'))
          : _CategoryChart(
              labels: labels,
              values: values,
              summary:
                  'Đường cong lợi suất trái phiếu chính phủ: ${[for (final t in yieldTenors)
                    if (y[t.$2] != null) '${t.$1} ${fmt(y[t.$2], 2)}%'].join(', ')}.',
              details: [for (final t in yieldTenors) 'Kỳ hạn ${t.$2} năm: ${y[t.$2] == null ? '–' : '${fmt(y[t.$2], 2)}%/năm'}'],
            ),
    );
  }
}

class _DepositCard extends StatelessWidget {
  final RatesSnapshot? s;
  final Map<String, double>? prev;
  final bool loading;
  const _DepositCard(this.s, this.prev, this.loading);

  @override
  Widget build(BuildContext context) {
    final d = s?.deposits ?? const <int, DepositStat>{};
    final labels = [for (final t in depositTerms) '${t}T'];
    final values = [for (final t in depositTerms) d[t]?.avg];
    return _CardShell(
      title: 'Lãi suất tiền gửi theo kỳ hạn',
      source: 'CafeF, trung bình các ngân hàng',
      asOf: s == null ? null : 'cập nhật ${timeLocal(s!.fetchedAt)}',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: d[12] == null ? '–' : fmt(d[12]!.avg, 2),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26),
                ),
                TextSpan(
                  text: '  %/năm (12 tháng, ${d[12]?.banks ?? 0} ngân hàng)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _delta(context, d[12]?.avg, prev?['dep12']),
        ],
      ),
      body: d.isEmpty
          ? Center(child: loading ? const CircularProgressIndicator() : const Text('Chưa tải được số liệu này.'))
          : _CategoryChart(
              labels: labels,
              values: values,
              bars: true,
              summary:
                  'Lãi suất tiền gửi trung bình theo kỳ hạn: ${[for (final t in depositTerms)
                    if (d[t] != null) '$t tháng ${fmt(d[t]!.avg, 2)}%'].join(', ')}.',
              details: [
                for (final t in depositTerms)
                  d[t] == null
                      ? '$t tháng: không có số liệu'
                      : '$t tháng: trung bình ${fmt(d[t]!.avg, 2)}%, thấp nhất ${fmt(d[t]!.min, 2)}%, cao nhất ${fmt(d[t]!.max, 2)}%${d[t]!.bestBank == null ? '' : ' (${d[t]!.bestBank})'}',
              ],
            ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _CardShell(
      scroll: true,
      title: 'Lãi suất cho vay',
      source: 'Ngân hàng Nhà nước Việt Nam',
      header: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Chưa có nguồn công khai cập nhật hằng ngày', style: text.titleSmall),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Ngân hàng Nhà nước công bố lãi suất cho vay bình quân của các tổ chức tín dụng theo từng tháng, trễ khoảng 3 tuần (bản tin "Diễn biến lãi suất của tổ chức tín dụng đối với khách hàng"). '
            'App không tự suy ra số cho vay để tránh hiển thị số không chính xác. Lãi suất liên ngân hàng và tiền gửi ở bên cạnh là các chỉ báo hằng ngày gần nhất.',
            style: text.bodyMedium,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => launchUrl(Uri.parse('https://sbv.gov.vn/')),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Mở trang Ngân hàng Nhà nước'),
            ),
          ),
          Text('Trang mở trong trình duyệt của bạn.', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
