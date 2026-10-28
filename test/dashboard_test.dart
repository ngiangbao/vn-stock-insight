import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/dashboard.dart';
import 'package:vn_stock_insight/services/board.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/treemap.dart';
import 'package:vn_stock_insight/ui/dash_widgets.dart';
import 'package:vn_stock_insight/ui/overview_page.dart';

Map<String, dynamic> _e(
  String s,
  double ref,
  double c,
  double va, {
  String bo = 'HSX',
  String st = 'STOCK',
  double frb = 0,
  double frs = 0,
  double ptv = 0,
}) => {
  's': s,
  'ref': ref,
  'c': c,
  'cei': ref * 1.07,
  'flo': ref * 0.93,
  'vo': va * 1000 / (c / 1000),
  'va': va,
  'ptv': ptv,
  'pta': ptv * c,
  'frbv': frb,
  'frsv': frs,
  'st': st,
  'bo': bo,
  'op': ref,
  'h': c,
  'l': ref,
};

double _area(Rect r) => r.width * r.height;
bool _overlap(Rect a, Rect b) => a.deflate(0.001).overlaps(b.deflate(0.001));

void main() {
  worldIndexTests();
  group('treemap', () {
    test('squarify: tổng diện tích đúng, tỉ lệ theo trọng số, không chồng lấn', () {
      final w = <double>[40, 25, 15, 10, 6, 4];
      const bounds = Rect.fromLTWH(10, 20, 300, 200);
      final r = squarify(w, bounds);
      expect(r.fold(0.0, (s, x) => s + _area(x)), closeTo(_area(bounds), 1e-6));
      for (final (i, x) in r.indexed) {
        expect(_area(x) / _area(bounds), closeTo(w[i] / 100, 1e-9));
        expect(bounds.inflate(1e-6).contains(x.topLeft) && bounds.inflate(1e-6).contains(x.bottomRight), isTrue);
        for (var j = i + 1; j < r.length; j++) {
          expect(_overlap(x, r[j]), isFalse, reason: '$i chồng $j');
        }
      }
      expect(r[0].topLeft, bounds.topLeft); // ô lớn nhất ở góc trên trái
    });

    test('squarify bỏ qua trọng số <= 0', () {
      final r = squarify([5, 0, 5], const Rect.fromLTWH(0, 0, 100, 100));
      expect(r[1], Rect.zero);
      expect(_area(r[0]) + _area(r[2]), closeTo(10000, 1e-6));
    });

    test('bố cục 2 cấp: ngành lớn hơn có diện tích lớn hơn, mã nằm trong ngành, không chồng lấn', () {
      final groups = [
        const TreeGroup('A', [TreeItem('a1', 50), TreeItem('a2', 30), TreeItem('a3', 20)]),
        const TreeGroup('B', [TreeItem('b1', 40), TreeItem('b2', 10)]),
        const TreeGroup('C', [TreeItem('c1', 30)]),
        const TreeGroup('D', [TreeItem('d1', 20)]),
      ];
      const bounds = Rect.fromLTWH(0, 0, 600, 400);
      final placed = layoutTwoLevel(groups, bounds);
      expect(placed.map((g) => g.name), ['A', 'B', 'C', 'D']);
      expect(placed.fold(0.0, (s, g) => s + _area(g.rect)), closeTo(_area(bounds), 1e-6));
      for (var i = 0; i < placed.length - 1; i++) {
        expect(_area(placed[i].rect), greaterThanOrEqualTo(_area(placed[i + 1].rect) - 1e-6));
      }
      for (final g in placed) {
        for (final it in g.items) {
          expect(
            g.rect.inflate(0.01).contains(it.rect.topLeft) && g.rect.inflate(0.01).contains(it.rect.bottomRight),
            isTrue,
          );
        }
        for (var i = 0; i < g.items.length; i++) {
          for (var j = i + 1; j < g.items.length; j++) {
            expect(_overlap(g.items[i].rect, g.items[j].rect), isFalse);
          }
        }
        // trong ngành, mã lớn hơn có ô lớn hơn
        for (var i = 0; i < g.items.length - 1; i++) {
          expect(_area(g.items[i].rect), greaterThanOrEqualTo(_area(g.items[i + 1].rect) - 1e-6));
        }
      }
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          expect(_overlap(placed[i].rect, placed[j].rect), isFalse);
        }
      }
    });
  });

  group('bảng giá', () {
    final json = [
      _e('VCB', 56100, 57500, 368110, frb: 1691910, frs: 320500, ptv: 124000),
      _e('TCB', 30000, 29000, 200000),
      _e('XYZ', 10000, 10000, 5000),
      _e('CEI', 10000, 10700, 1000),
      _e('FLR', 10000, 9300, 1000),
      _e('E1', 10000, 10100, 1000, st: 'ETF'),
      {'s': 'NOREF', 'st': 'STOCK', 'bo': 'HSX', 'ref': 0},
    ];

    test('phân tích dữ liệu mẫu, bỏ ETF và mã thiếu giá tham chiếu', () {
      final rows = parseBoard(json);
      expect(rows.map((r) => r.symbol), ['VCB', 'TCB', 'XYZ', 'CEI', 'FLR']);
      expect(rows.first.exchange, 'HOSE');
      expect(rows.first.pct, closeTo(2.4955, 1e-3));
      expect(rows.first.valueMn, 368110);
    });

    test('đếm tăng/giảm/đứng giá, trần/sàn, dòng tiền theo nhóm, khối ngoại', () {
      final st = BoardStats(parseBoard(json));
      expect((st.up, st.down, st.flat), (2, 2, 1));
      expect((st.ceil, st.floor), (1, 1));
      expect(st.upValueMn, 368110 + 1000);
      expect(st.downValueMn, 200000 + 1000);
      expect(st.flatValueMn, 5000);
      expect(st.foreignBuy - st.foreignSell, 1691910 - 320500);
      expect(st.ptVolume, 124000);
      expect(st.totalValueTy, closeTo((st.valueMn + st.ptValueMn) / 1000, 1e-9));
    });

    test('giá bằng 0 (chưa khớp) dùng giá tham chiếu', () {
      final r = parseBoard([_e('ABC', 10000, 0, 0)]).single;
      expect(r.price, 10000);
      expect(r.dir, 0);
    });

    test('gom ngành tự động, mã chưa có ngành vào "Khác", ngành và mã sắp xếp lớn → bé', () {
      final rows = parseBoard([
        _e('VCB', 100, 101, 900),
        _e('TCB', 100, 99, 600),
        _e('HPG', 100, 100, 700),
        _e('NEW', 100, 100, 50),
        _e('ZERO', 100, 100, 0),
      ]);
      final sectors = {
        'VCB': const SectorInfo('Ngân hàng', 1),
        'TCB': const SectorInfo('Ngân hàng', 1),
        'HPG': const SectorInfo('Tài nguyên Cơ bản', 1),
      };
      final g = groupBySector(rows, sectors);
      expect(g.map((x) => x.name), ['Ngân hàng', 'Tài nguyên Cơ bản', 'Khác']);
      expect(g.first.rows.map((r) => r.symbol), ['VCB', 'TCB']);
      expect(g.first.weight, 1500);
      expect(g.expand((x) => x.rows).any((r) => r.symbol == 'ZERO'), isFalse);
    });

    test('chưa có giao dịch thì dùng vốn hóa làm trọng số', () {
      final rows = parseBoard([_e('AAA', 100, 100, 0), _e('BBB', 100, 100, 0)]);
      final g = groupBySector(rows, {'AAA': const SectorInfo('X', 10), 'BBB': const SectorInfo('Y', 30)});
      expect(g.map((x) => x.name), ['Y', 'X']);
    });

    test('màu ô theo biến động', () {
      Color c(double ref, double p) => heatColor(parseBoard([_e('A', ref, p, 1)]).single);
      expect(c(100, 107), heatCeil);
      expect(c(100, 93), heatFloor);
      expect(c(100, 100), heatFlat);
      expect(c(100, 102).g, greaterThan(c(100, 102).r));
      expect(c(100, 98).r, greaterThan(c(100, 98).g));
    });
  });

  group('phân ngành lưu đệm', () {
    final sample = [
      {'ticker': 'VCB', 'viSector': 'Ngân hàng', 'marketCap': 4.6e14},
      {'ticker': 'ABC', 'viSector': null, 'marketCap': 1e9},
    ];

    test('phân tích phản hồi screening', () {
      final m = parseSectors(sample);
      expect(m['VCB']!.name, 'Ngân hàng');
      expect(m['ABC']!.name, 'Khác');
    });

    test('đệm trong 7 ngày, quá hạn thì tự tải lại, lỗi mạng thì dùng bản đệm cũ', () async {
      final dir = Directory.systemTemp.createTempSync('sect');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/sectors.json');
      var calls = 0;
      Future<Map<String, SectorInfo>> fetch() async {
        calls++;
        return parseSectors(sample);
      }

      final t0 = DateTime(2026, 10, 28);
      await loadSectors(f, now: t0, fetch: fetch);
      expect(calls, 1);
      final cached = await loadSectors(f, now: t0.add(const Duration(days: 3)), fetch: fetch);
      expect(calls, 1);
      expect(cached['VCB']!.name, 'Ngân hàng');
      await loadSectors(f, now: t0.add(const Duration(days: 8)), fetch: fetch);
      expect(calls, 2);
      final stale = await loadSectors(
        f,
        now: t0.add(const Duration(days: 30)),
        fetch: () async => throw Exception('offline'),
      );
      expect(stale['VCB']!.name, 'Ngân hàng');
    });
  });

  group('chỉ số và giờ giao dịch', () {
    test('nến ngày và nến phút của DNSE', () {
      final bars = parseBars({
        't': [1793067300, 1793067360],
        'o': [1, 2],
        'h': [3, 4],
        'l': [0.5, 1],
        'c': [2, 3],
        'v': [10, 20],
      });
      expect(bars.length, 2);
      expect(bars.last.c, 3);
      expect(minuteOfDayVN(1793067300), inInclusiveRange(0, 1439));
    });

    test('lastSession chỉ giữ phiên gần nhất', () {
      const day = 86400;
      final t0 = 1793030400; // 00:00 UTC
      final bars = [
        Bar(t0 + 3600, 1, 1, 1, 1, 1),
        Bar(t0 + day + 3600, 2, 2, 2, 2, 2),
        Bar(t0 + day + 3660, 3, 3, 3, 3, 3),
      ];
      expect(lastSession(bars).map((b) => b.c), [2, 3]);
    });

    test('giờ giao dịch 9:00–15:00 giờ VN, thứ 2–6', () {
      expect(isTradingTime(DateTime.utc(2026, 10, 28, 3, 0)), isTrue); // thứ 4, 10:00 VN
      expect(isTradingTime(DateTime.utc(2026, 10, 28, 1, 59)), isFalse); // 8:59 VN
      expect(isTradingTime(DateTime.utc(2026, 10, 28, 8, 30)), isFalse); // 15:30 VN
      expect(isTradingTime(DateTime.utc(2026, 10, 31, 3, 0)), isFalse); // thứ 7
    });

    test('mục tổng quan ẩn khi không có nguồn dữ liệu', () {
      final bars = [Bar(1793030400, 100, 110, 95, 105, 1000), Bar(1793116800, 105, 112, 101, 108, 2000)];
      final q = IndexQuote(indexMetas.firstWhere((m) => m.symbol == 'VN30F1M'), bars);
      final rows = overviewRows(q, const [], null);
      expect(rows.map((r) => r.$1), isNot(contains('KL khớp')));
      expect(rows.map((r) => r.$1), contains('Tổng KL'));
      expect(foreignRows(null, const Color(0xFF00FF00), const Color(0xFFFF0000)), isEmpty);
    });
  });
}

void worldIndexTests() {
  group('chỉ số thế giới và phái sinh', () {
    test('đọc nến ngày từ Yahoo, bỏ ngày thiếu giá', () {
      final bars = parseYahooBars({
        'chart': {
          'result': [
            {
              'timestamp': [1793000000, 1793086400, 1793172800],
              'indicators': {
                'quote': [
                  {
                    'open': [10.0, null, 12.0],
                    'high': [11.0, null, 13.0],
                    'low': [9.0, null, 11.0],
                    'close': [10.5, null, 12.5],
                    'volume': [100, null, 300],
                  },
                ],
              },
            },
          ],
        },
      });
      expect(bars.length, 2);
      expect(bars.last.c, 12.5);
      expect(parseYahooBars({'chart': {'result': null}}), isEmpty);
    });

    test('khu vực chọn đúng danh sách chỉ số', () {
      expect(metasOfRegion('vn').map((m) => m.symbol), containsAll(['VNINDEX', 'VN30F2M', 'VN30F1Q', 'VN30F2Q']));
      expect(metasOfRegion('us').map((m) => m.symbol), ['^GSPC', '^IXIC', '^DJI']);
      expect(metasOfRegion('eu'), isNotEmpty);
      expect(metasOfRegion('asia'), isNotEmpty);
      final dash = MarketDashboard(File('/tmp/vnsi-none.json'));
      dash.setRegion('us');
      expect(dash.selected, '^GSPC');
      expect(dash.meta.kind, 'world');
      dash.dispose();
    });
  });
}
