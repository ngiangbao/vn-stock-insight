import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/insight.dart';
import 'package:vn_stock_insight/services/market.dart';

// Phiên thứ i: bắt đầu thứ Hai 06/01/2025, bỏ qua cuối tuần
int _t(int i) {
  final base = DateTime.utc(2025, 1, 6, 3);
  var d = base;
  var k = 0;
  while (k < i) {
    d = d.add(const Duration(days: 1));
    if (d.weekday <= DateTime.friday) k++;
  }
  return d.millisecondsSinceEpoch ~/ 1000;
}

Bar _bar(int i, double o, double c, {double? h, double? l, double v = 1000}) =>
    Bar(_t(i), o, h ?? (o > c ? o : c) + 0.2, l ?? (o < c ? o : c) - 0.2, c, v);

List<Bar> _trend(int n, double start, double step, {double v = 1000}) => [
  for (var i = 0; i < n; i++) _bar(i, start + step * i, start + step * (i + 1), v: v),
];

void main() {
  test('nến tuần: gộp 5 phiên thành 1 tuần, giữ mở đầu tuần, cao nhất, thấp nhất, đóng cuối tuần, cộng khối lượng', () {
    final d = [for (var i = 0; i < 12; i++) _bar(i, 10.0 + i, 10.5 + i, h: 11.0 + i, l: 9.0 + i, v: 100)];
    final w = weeklyBars(d);
    expect(w.length, 3);
    expect(w.first.o, 10.0);
    expect(w.first.c, 14.5);
    expect(w.first.h, 15.0);
    expect(w.first.l, 9.0);
    expect(w.first.v, 500);
    expect(w.last.v, 200);
  });

  test('nến giờ: gộp nến phút theo khung 1 giờ và 4 giờ (sáng/chiều)', () {
    // 09:00 đến 10:59 giờ VN = 02:00 đến 03:59 UTC, mỗi 30 phút
    final base = DateTime.utc(2026, 10, 30, 2).millisecondsSinceEpoch ~/ 1000;
    final src = [for (var i = 0; i < 4; i++) Bar(base + i * 1800, 10.0 + i, 11.0 + i, 9.0 + i, 10.5 + i, 100)];
    expect(hourlyBars(src, 1).length, 2, reason: '09:00-09:59 và 10:00-10:59');
    expect(hourlyBars(src, 4).length, 1, reason: 'cùng buổi sáng');
    expect(hourlyBars(src, 4).first.v, 400);
  });

  test('điểm sức khỏe: xu hướng tăng điểm cao, xu hướng giảm điểm thấp, trọng số cộng đủ 100', () {
    final idx = _trend(300, 1000, 0.5);
    final up = healthScore(_trend(300, 10, 0.1), idx)!;
    final down = healthScore(_trend(300, 50, -0.1), idx)!;
    expect(up.parts.fold<int>(0, (a, p) => a + p.weight), 100);
    expect(up.total, greaterThan(down.total + 25));
    expect(up.label, 'Mạnh');
    expect(down.label, 'Yếu');
    expect(up.parts.map((p) => p.name), ['Xu hướng', 'Động lượng', 'Dòng tiền', 'Sức mạnh tương đối']);
    expect(healthScore(_trend(30, 10, 0.1), idx), isNull, reason: 'dưới 60 phiên chưa đủ dữ liệu');
    // Điểm sụt giảm so với 6 tuần trước khi giá đảo chiều giảm
    final turn = [..._trend(200, 10, 0.1), for (var i = 0; i < 40; i++) _bar(200 + i, 30 - i * 0.2, 29.8 - i * 0.2)];
    final h = healthScore(turn, idx)!;
    expect(h.previous, isNotNull);
    expect(h.delta!, lessThan(0));
  });

  test('dấu hiệu tạo đáy: phiên bán tháo và vượt giữ MA50 được nhận ra', () {
    final idx = _trend(100, 1000, 0.5);
    // giảm đều rồi một phiên khối lượng lớn đóng cửa cao trong biên độ
    final bars = [..._trend(90, 50, -0.2, v: 1000)];
    bars.add(Bar(_t(90), 32.0, 33.0, 30.0, 32.8, 5000));
    final s = bottomSignals(bars, idx);
    expect(s.length, 6);
    expect(s[1].met, isTrue, reason: 'phiên bán tháo');
    expect(s[4].met, isNull, reason: 'độ rộng thị trường chưa có nguồn dữ liệu');
    expect(s[5].met, isFalse, reason: 'giá còn dưới MA50');
    // tăng mạnh vượt MA50 và giữ 3 phiên
    final up = [..._trend(60, 20, -0.1), ..._trend(40, 14, 0.3)];
    expect(bottomSignals(up, idx)[5].met, isTrue);
    expect(bottomSignals(_trend(20, 10, 0.1), idx).every((x) => x.met == null), isTrue);
  });

  test('vùng giá: gom đỉnh đáy gần nhau, đếm số lần chạm, tách kháng cự và hỗ trợ quanh giá', () {
    // dao động quanh 10 đến 12 nhiều lần, giá hiện tại 11
    final bars = <Bar>[];
    for (var i = 0; i < 160; i++) {
      final wave = (i % 20) < 10 ? 10.0 + (i % 20) * 0.2 : 12.0 - ((i % 20) - 10) * 0.2;
      bars.add(_bar(i, wave, wave + 0.05, h: wave + 0.1, l: wave - 0.1));
    }
    bars.add(_bar(160, 11.0, 11.0, h: 11.1, l: 10.9));
    final z = priceZones(bars)!;
    expect(z.nearestResistance, isNotNull);
    expect(z.nearestSupport, isNotNull);
    expect(z.nearestResistance!.low, greaterThan(z.close));
    expect(z.nearestSupport!.high, lessThan(z.close));
    expect(z.nearestResistance!.touches, greaterThanOrEqualTo(3), reason: 'vùng 12 bị chạm nhiều lần');
    expect(z.resistances.first.low, lessThanOrEqualTo(z.resistances.last.low));
    expect(priceZones(_trend(20, 10, 0.1)), isNull);
  });

  test('Fibonacci: nhịp giảm thì các mức hồi nằm trên đáy là kháng cự; 50% nằm giữa đỉnh và đáy', () {
    // đỉnh 20 ở phiên 10, giảm về 10 ở phiên 70, rồi đi ngang gần 11
    final bars = <Bar>[
      for (var i = 0; i < 10; i++) _bar(i, 18.0 + i * 0.2, 18.2 + i * 0.2),
      _bar(10, 19.8, 19.9, h: 20.0, l: 19.5),
      for (var i = 11; i < 70; i++) _bar(i, 19.8 - (i - 10) * 0.15, 19.65 - (i - 10) * 0.15),
      _bar(70, 10.2, 10.0, h: 10.4, l: 10.0),
      for (var i = 71; i < 100; i++) _bar(i, 10.8, 11.0, h: 11.1, l: 10.7),
    ];
    final z = priceZones(bars)!;
    final half = z.fib.firstWhere((f) => f.ratio == 0.5);
    expect(half.price, closeTo(15.0, 0.1));
    expect(half.support, isFalse);
    expect(half.label, 'Fibonacci 50% (kháng cự)');
    expect(z.fib.firstWhere((f) => f.ratio == 0.618).label, contains('61,8%'));
  });

  test('kịch bản: mốc tích cực = kháng cự gần × 1,02; không có hỗ trợ thì nói rõ', () {
    final bars = [..._trend(120, 60, -0.1), _bar(120, 50, 50)];
    final z = priceZones(bars)!;
    final sc = scenarios(bars, z);
    if (z.nearestResistance != null) {
      expect(sc.positiveLevel, closeTo(z.nearestResistance!.high * 1.02, 1e-9));
      expect(sc.positive, contains('vượt kháng cự gần 2%'));
    }
    expect(vnNum(57100), '57.100');
    expect(vnNum(10760000.4), '10.760.000');
    expect(vnNum(1.5, 1), '1,5');
  });

  test('xu hướng theo khung và tóm tắt: giảm có chữ "Đang giảm" và ghi dưới MA200', () {
    final down = _trend(400, 80, -0.1);
    final idx = _trend(400, 1000, 0.1);
    expect(trendFrame(down)!.direction, 'Giảm');
    expect(trendFrame(down)!.text, 'Giảm · 3/3 phiếu');
    expect(trendFrame(_trend(400, 10, 0.1))!.direction, 'Tăng');
    expect(trendFrame(_trend(20, 10, 0.1)), isNull);
    final h = healthScore(down, idx);
    final z = priceZones(down);
    final sum = trendSummary('FPT', down, h, z, z == null ? null : scenarios(down, z))!;
    expect(sum.headline, startsWith('FPT Đang giảm'));
    expect(sum.headline, contains('dưới MA200'));
    expect(sum.detail, startsWith('Khung tuần giảm'));
    expect(sum.week, isNotNull);
  });
}
