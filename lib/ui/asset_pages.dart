import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dashboard.dart' show isTradingTime;
import '../services/instruments.dart';
import '../services/market.dart';
import 'chart.dart';
import 'rates_tab.dart';
import 'widgets.dart';

class BondsPage extends StatelessWidget {
  const BondsPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Trái phiếu'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Lợi suất Chính phủ'),
            Tab(text: 'Định giá & tra cứu'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [RatesTab(bondsOnly: true), BondCalculator()],
      ),
    ),
  );
}

class BondCalculator extends StatefulWidget {
  const BondCalculator({super.key});
  @override
  State<BondCalculator> createState() => _BondCalculatorState();
}

class _BondCalculatorState extends State<BondCalculator> {
  final _form = GlobalKey<FormState>();
  final _coupon = TextEditingController(text: '5');
  final _yield = TextEditingController(text: '6');
  final _years = TextEditingController(text: '5');
  double? _price;
  @override
  void dispose() {
    _coupon.dispose();
    _yield.dispose();
    _years.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Công cụ định giá theo giả định',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Mệnh giá 100, trả coupon hằng năm, hoàn trả gốc cuối kỳ; tính tại ngày trả coupon, chưa gồm lãi dồn tích, thuế và phí. Kết quả không phải giá giao dịch hay báo giá của tổ chức phát hành.',
      ),
      const SizedBox(height: 16),
      Form(
        key: _form,
        child: _AssetFields(
          children: [
            _number(_coupon, 'Coupon (%/năm)'),
            _number(_yield, 'Lợi suất yêu cầu (%/năm)'),
            _number(_years, 'Số năm còn lại', integer: true),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                setState(
                  () => _price = bondPrice(
                    coupon: _parse(_coupon.text)!,
                    yieldPercent: _parse(_yield.text)!,
                    years: int.parse(_years.text.trim()),
                  ),
                );
              },
              child: const Text('Tính giá'),
            ),
          ],
        ),
      ),
      if (_price != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Giá lý thuyết: ${fmt(_price, 3)} / 100 mệnh giá',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      const Divider(height: 32),
      Text(
        'Tra cứu công bố chính thức',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const Text(
        'Chưa kết nối bảng giá và hồ sơ trái phiếu doanh nghiệp tự động. Tra cứu mã, đơn vị phát hành, kỳ hạn và công bố tại HNX.',
      ),
      _SourceLink(
        'Trái phiếu Chính phủ — HNX',
        'https://www.hnx.vn/vi-vn/trai-phieu.html',
      ),
      _SourceLink(
        'Danh sách trái phiếu — HNX',
        'https://stoxvn.hnx.vn/vi-vn/trai-phieu/danh-sach-trai-phieu.html',
      ),
      _SourceLink('Trái phiếu doanh nghiệp — HNX', 'https://cbonds.hnx.vn/'),
    ],
  );
}

double? _parse(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.'));
Widget _number(
  TextEditingController controller,
  String label, {
  bool integer = false,
}) => TextFormField(
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: InputDecoration(labelText: label),
  validator: (s) {
    final n = _parse(s ?? '');
    if (n == null || !n.isFinite || n < 0) return 'Nhập số không âm hợp lệ';
    if (integer &&
        (int.tryParse((s ?? '').trim()) == null || n < 1 || n > 100)) {
      return 'Nhập số nguyên từ 1 đến 100';
    }
    return null;
  },
);

class _SourceLink extends StatelessWidget {
  final String title, url;
  const _SourceLink(this.title, this.url);
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: const Icon(Icons.open_in_new),
    onTap: () async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        if (await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } catch (_) {
        /* Present the failure below. */
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Không mở được trang nguồn.')),
      );
    },
  );
}

class ListedFundsPage extends StatelessWidget {
  final bool active;
  const ListedFundsPage({super.key, this.active = true});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Quỹ'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Quỹ niêm yết / ETF'),
            Tab(text: 'Quỹ mở / NAV'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          InstrumentQuotesPage(active: active),
          const FundNavTracker(),
        ],
      ),
    ),
  );
}

class DerivativesPage extends StatelessWidget {
  final bool active;
  const DerivativesPage({super.key, this.active = true});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phái sinh')),
    body: InstrumentQuotesPage(derivative: true, active: active),
  );
}

class InstrumentQuotesPage extends StatefulWidget {
  final bool derivative, active;
  final Future<List<InstrumentQuote>> Function()? loader;
  const InstrumentQuotesPage({
    super.key,
    this.derivative = false,
    this.active = true,
    this.loader,
  });
  @override
  State<InstrumentQuotesPage> createState() => _InstrumentQuotesPageState();
}

class _InstrumentQuotesPageState extends State<InstrumentQuotesPage> {
  List<InstrumentQuote> _quotes = [];
  List<Bar> _spot = [];
  final _search = TextEditingController();
  Timer? _timer;
  bool _loading = false, _ascending = true;
  int _sort = 0;
  String? _error;
  DateTime? _fetched;
  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (widget.active && isTradingTime(DateTime.now())) _load();
    });
  }

  @override
  void didUpdateWidget(covariant InstrumentQuotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quotes =
          await (widget.loader?.call() ??
              (widget.derivative ? loadDerivativeQuotes() : loadFundQuotes()));
      final spot = widget.derivative && widget.loader == null
          ? await fetchBars('VN30', kind: 'index')
          : <Bar>[];
      if (!mounted) return;
      // Retain previously known symbols on partial failure and label them stale.
      final next = {for (final q in _quotes) q.symbol: q};
      final missing = next.keys
          .where((s) => !quotes.any((q) => q.symbol == s))
          .toList();
      setState(() {
        for (final q in quotes) {
          next[q.symbol] = q;
        }
        _quotes = next.values.toList();
        _spot = spot;
        if (quotes.isEmpty) {
          _error = 'Không tải được dữ liệu. Dữ liệu cũ (nếu có) được giữ lại. Hãy thử lại.';
        } else {
          _fetched = DateTime.now();
          if (missing.isNotEmpty) {
            _error =
                'Chưa cập nhật được ${missing.join(', ')}; đang giữ dữ liệu cũ của các mã này.';
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Không tải được dữ liệu. Dữ liệu cũ (nếu có) được giữ lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        _quotes
            .where((q) => q.symbol.contains(_search.text.trim().toUpperCase()))
            .toList()
          ..sort((a, b) {
            final n = switch (_sort) {
              1 => a.price.compareTo(b.price),
              2 => (a.change ?? -double.infinity).compareTo(
                b.change ?? -double.infinity,
              ),
              3 => a.bars.last.v.compareTo(b.bars.last.v),
              _ => a.symbol.compareTo(b.symbol),
            };
            return _ascending ? n : -n;
          });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.derivative
              ? 'Hợp đồng tương lai VN30 · Giá theo điểm. Các mã F1M/F2M/F1Q/F2Q là chuỗi kỳ hạn luân chuyển của nguồn, không phải mã hợp đồng đáo hạn cụ thể.'
              : 'Giá quỹ niêm yết theo nghìn đồng/CCQ, không phải NAV. Nguồn Vietcap dùng tìm mã ETF; dữ liệu biểu đồ DNSE/VNDirect. Khi không tải được danh sách, thử các mã mẫu E1VFVN30, FUEVFVND, FUEVN100.',
        ),
        const SizedBox(height: 8),
        Text(
          'Làm mới mỗi 45 giây khi đang xem trong giờ giao dịch. ${_fetched == null ? 'Chưa tải thành công.' : 'Lần tải thành công: ${timeVN(_fetched!)}.'} Ngày dữ liệu hiển thị riêng cho từng mã.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Tìm mã',
                ),
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Làm mới dữ liệu',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!_loading && rows.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Không có mã phù hợp.'),
          ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: FlexTable(
            minWidth: widget.derivative ? 1050 : 900,
            columns: [
              for (final (i, label) in [
                'Mã',
                widget.derivative ? 'Giá (điểm)' : 'Giá (nghìn đ)',
                'Biến động',
                'Khối lượng',
                'Ngày dữ liệu',
                if (widget.derivative) 'Basis (điểm)',
                'Biểu đồ',
              ].indexed)
                FlexCol(
                  label,
                  1,
                  align: Alignment.center,
                  ascending: i < 4 && _sort == i ? _ascending : null,
                  onSort: i < 4
                      ? () => setState(() {
                          _ascending = _sort == i ? !_ascending : true;
                          _sort = i;
                        })
                      : null,
                ),
            ],
            rows: [
              for (final q in rows)
                FlexRow([
                  Text(q.symbol),
                  Text(fmt(q.price)),
                  Pct(q.change),
                  Text(fmt(q.bars.last.v, 0)),
                  Text(q.date),
                  if (widget.derivative) Text(fmt(sameSessionBasis(q, _spot))),
                  IconButton(
                    tooltip: 'Biểu đồ ${q.symbol}',
                    icon: const Icon(Icons.candlestick_chart),
                    onPressed: () => openChart(
                      context,
                      q.symbol,
                      kind: q.derivative ? 'derivative' : 'stock',
                    ),
                  ),
                ]),
            ],
          ),
        ),
        if (widget.derivative)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Basis = giá tương lai − VN30, chỉ tính khi cùng ngày dữ liệu; “–” khi chưa đủ dữ liệu. Chuỗi luân chuyển có thể đổi hợp đồng qua kỳ đáo hạn.',
            ),
          ),
      ],
    );
  }
}

/// Manual NAV ledger for open-end funds without a connected NAV data feed.
class FundNavTracker extends StatefulWidget {
  const FundNavTracker({super.key});
  @override
  State<FundNavTracker> createState() => _FundNavTrackerState();
}

class _FundNavTrackerState extends State<FundNavTracker> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _nav = TextEditingController(),
      _date = TextEditingController();
  List<Map<String, dynamic>> _entries = [];
  SharedPreferences? _prefs;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = (jsonDecode(
        prefs.getString('fund_nav_entries') ?? '[]',
      ) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _entries = entries;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không đọc được sổ NAV đã lưu.');
    }
  }

  Future<void> _persist(List<Map<String, dynamic>> entries) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!await _prefs!.setString('fund_nav_entries', jsonEncode(entries))) {
        throw StateError('save');
      }
      if (mounted) {
        setState(() {
          _entries = entries;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không lưu được sổ NAV. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nav.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Sổ NAV quỹ mở', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Nhập NAV/CCQ và ngày định giá từ công bố của công ty quản lý quỹ. Dữ liệu do bạn nhập, lưu trên máy; chưa có nguồn NAV tự động. Giá giao dịch ETF và NAV được theo dõi riêng.',
      ),
      const SizedBox(height: 16),
      Form(
        key: _form,
        child: _AssetFields(
          children: [
            SizedBox(
              child: TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Mã / tên quỹ'),
                validator: (s) =>
                    (s ?? '').trim().isEmpty ? 'Nhập mã hoặc tên quỹ' : null,
              ),
            ),
            _number(_nav, 'NAV/CCQ (đồng)'),
            SizedBox(
              child: TextFormField(
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Ngày NAV (yyyy-MM-dd)',
                ),
                validator: (s) {
                  final d = DateTime.tryParse(s ?? '');
                  return d == null || d.toIso8601String().substring(0, 10) != s
                      ? 'Nhập ngày hợp lệ dạng yyyy-MM-dd'
                      : null;
                },
              ),
            ),
            FilledButton(
              onPressed: _prefs == null || _saving
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      final name = _name.text.trim().toUpperCase(),
                          date = _date.text;
                      await _persist(
                        [
                          ..._entries.where(
                            (e) => e['name'] != name || e['date'] != date,
                          ),
                          {
                            'name': name,
                            'nav': _parse(_nav.text),
                            'date': date,
                          },
                        ]..sort(
                          (a, b) => '${b['date']}'.compareTo('${a['date']}'),
                        ),
                      );
                    },
              child: const Text('Lưu NAV'),
            ),
          ],
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_entries.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Chưa có bản ghi NAV.'),
        ),
      for (final entry in _entries)
        ListTile(
          title: Text(
            '${entry['name']} · ${fmt(entry['nav'] as num?, 2)} đ/CCQ',
          ),
          subtitle: Text('${entry['date']} · Nhập thủ công'),
          trailing: IconButton(
            tooltip: 'Xóa bản ghi NAV',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving
                ? null
                : () => _persist([..._entries]..remove(entry)),
          ),
        ),
    ],
  );
}

/// Equal columns use the entire available width, then wrap on narrow screens.
class _AssetFields extends StatelessWidget {
  final List<Widget> children;
  const _AssetFields({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 1000 ? 4 : (box.maxWidth >= 560 ? 2 : 1);
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: child is FilledButton
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: child,
                    )
                  : child,
            ),
        ],
      );
    },
  );
}
