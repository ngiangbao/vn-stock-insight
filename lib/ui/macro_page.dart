// Trang "Vĩ mô": tab chủ đề, lưới thẻ biểu đồ cùng kích thước, chọn khoảng thời gian,
// bảng số liệu thay thế cho biểu đồ (hỗ trợ trình đọc màn hình và bàn phím).

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/macro.dart';
import '../state.dart';
import 'macro_chart.dart';
import 'widgets.dart' show fmt, timeLocal;

const _ranges = [('5 năm', 5), ('10 năm', 10), ('20 năm', 20), ('Toàn bộ', 0)];

class MacroPage extends StatefulWidget {
  /// Chỉ dùng trong kiểm thử để thay nguồn dữ liệu.
  final MacroRepository? repository;

  /// Trang đang được hiển thị. Số liệu chỉ được tải khi trang được mở lần đầu
  /// (trang nằm sẵn trong IndexedStack nên không được tải ngay lúc mở app).
  final bool active;
  const MacroPage({super.key, this.repository, this.active = true});

  @override
  State<MacroPage> createState() => _MacroPageState();
}

class _MacroPageState extends State<MacroPage> {
  late final MacroRepository _repo;
  bool _started = false;
  bool _loading = false;
  MacroSnapshot? _snap;
  int _years = 20;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startOnce();
  }

  @override
  void didUpdateWidget(MacroPage old) {
    super.didUpdateWidget(old);
    _startOnce();
  }

  void _startOnce() {
    if (_started || !widget.active) return;
    _started = true;
    _repo = widget.repository ??
        MacroRepository(cacheFile: File('${AppScope.of(context).dataDir.path}${Platform.pathSeparator}macro_cache.json'));
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final snap = await _repo.load(force: force);
      if (mounted) setState(() => _snap = snap);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final snap = _snap;
    final failed = snap?.failed.length ?? 0;

    return DefaultTabController(
      length: macroTabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kinh tế vĩ mô'),
            if (snap != null) Text('Cập nhật lúc ${timeLocal(snap.fetchedAt)}', style: text.bodySmall),
          ]),
          actions: [
            _loading
                ? Semantics(
                    label: 'Đang tải số liệu vĩ mô',
                    child: const SizedBox.square(
                      dimension: 48,
                      child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ),
                  )
                : IconButton(
                    onPressed: () => _load(force: true),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Làm mới số liệu',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in macroTabs) Tab(text: t.title)],
          ),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Khoảng thời gian', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                for (final (label, years) in _ranges)
                  ChoiceChip(
                    label: Text(label),
                    selected: _years == years,
                    onSelected: (_) => setState(() => _years = years),
                  ),
              ]),
            ),
          ),
          if (failed > 0 && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(children: [
                    Icon(Icons.cloud_off_outlined, color: cs.onErrorContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Không tải được $failed chỉ tiêu. Kiểm tra kết nối mạng rồi thử lại.',
                        style: text.bodyMedium?.copyWith(color: cs.onErrorContainer),
                      ),
                    ),
                    TextButton(onPressed: () => _load(force: true), child: const Text('Thử lại')),
                  ]),
                ),
              ),
            ),
          Expanded(
            // Vuốt ngang trên biểu đồ dùng để xem từng kỳ, nên chuyển tab bằng cách bấm vào tab (tránh xung đột cử chỉ)
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final t in macroTabs) _TabGrid(t, snap, _loading, _years, () => _load(force: true))],
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabGrid extends StatelessWidget {
  final MacroTab tab;
  final MacroSnapshot? snap;
  final bool loading;
  final int years;
  final VoidCallback onRetry;
  const _TabGrid(this.tab, this.snap, this.loading, this.years, this.onRetry);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Cỡ chữ hệ thống lớn thì thẻ cao hơn tương ứng (skill: kiểm tra với cỡ chữ lớn nhất)
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverGrid(
              // Mọi thẻ cùng kích thước; số cột đổi theo chiều rộng cửa sổ
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 360 * textScale,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final id = tab.ids[i];
                  return MacroCard(def: macroDef(id), series: snap?.series[id], loading: loading, years: years, onRetry: onRetry);
                },
                childCount: tab.ids.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                'Nguồn: World Bank (số liệu thực tế hàng năm), IMF World Economic Outlook (thực tế và dự báo hàng năm), '
                'Yahoo Finance (tỷ giá hàng tháng). Số liệu hàng năm có độ trễ tùy nguồn nên kỳ mới nhất có thể là năm trước. '
                'Số liệu hàng tháng của Tổng cục Thống kê (CPI, xuất nhập khẩu theo tháng...) chưa có nguồn công khai miễn phí '
                'nên chưa được hiển thị. Chỉ mang tính tham khảo.',
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class MacroCard extends StatelessWidget {
  final MacroDef def;
  final MacroSeries? series;
  final bool loading;
  final int years;
  final VoidCallback onRetry;
  const MacroCard({super.key, required this.def, required this.series, required this.loading, required this.years, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = series;
    final latest = s?.latest;
    final prev = s?.previous;
    final diff = latest != null && prev != null ? latest.value - prev.value : null;

    Widget body;
    if (s != null) {
      body = MacroChart(s, years: years);
    } else if (loading) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Đang tải số liệu…', style: text.bodyMedium),
        ]),
      );
    } else {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('Chưa tải được số liệu này', style: text.bodyMedium),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(def.title, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
            IconButton(
              onPressed: s == null ? null : () => _showTable(context, s),
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Xem bảng số liệu',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ]),
          // Vùng giá trị mới nhất có chiều cao tối thiểu (không cố định) nên không tràn khi chữ hệ thống lớn;
          // chiều cao thẻ tăng theo cỡ chữ (xem _TabGrid) nên các thẻ vẫn bằng nhau
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: latest == null
                  ? null
                  : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: fmt(latest.value, def.decimals), style: text.titleLarge?.copyWith(fontSize: 26)),
                        TextSpan(text: '  ${def.unit}', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        TextSpan(text: '  ·  ${latest.label}', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ])),
                      if (diff != null)
                        Row(children: [
                          // Mũi tên + dấu +/− truyền đạt hướng thay đổi, không chỉ dựa vào màu
                          Icon(
                            diff > 0 ? Icons.arrow_upward : (diff < 0 ? Icons.arrow_downward : Icons.remove),
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${diff > 0 ? '+' : (diff < 0 ? '−' : '')}${fmt(diff.abs(), def.decimals)} ${def.diffUnit} so với ${prev!.label}',
                              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                    ]),
            ),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: body)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Đơn vị: ${def.unit} · Kỳ báo cáo: ${def.frequency} · Nguồn: ${def.sourceName}',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bảng số liệu: thay thế cho biểu đồ (đọc được bằng trình đọc màn hình, cuộn bằng bàn phím).
void _showTable(BuildContext context, MacroSeries s) {
  final text = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final rows = s.points.reversed.toList();
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(s.def.title),
      content: SizedBox(
        width: 440,
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(macroSummary(s), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Kỳ', style: text.labelLarge)),
            Expanded(child: Text('Giá trị (${s.def.unit})', style: text.labelLarge, textAlign: TextAlign.end)),
            Expanded(child: Text('Loại', style: text.labelLarge, textAlign: TextAlign.end)),
          ]),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemExtent: 40,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final p = rows[i];
                return Row(children: [
                  Expanded(child: Text(p.label)),
                  Expanded(child: Text(fmt(p.value, s.def.decimals), textAlign: TextAlign.end)),
                  Expanded(child: Text(p.forecast ? 'Dự báo' : 'Thực tế', textAlign: TextAlign.end)),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Đóng'))],
    ),
  );
}
