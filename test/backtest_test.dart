import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/backtest.dart';
import 'package:vn_stock_insight/services/market.dart';

List<Bar> series(int n, double Function(int) close, {int t0 = 1700000000}) => [
  for (var i = 0; i < n; i++) Bar(t0 + i * 86400, close(i), close(i) * 1.01, close(i) * 0.99, close(i), 1e6 + (i % 7) * 1e4),
];

void main() {
  group('kiểm định điểm sức khỏe', () {
    test('cần đủ lịch sử, ít hơn thì trả null', () {
      expect(backtestHealth(series(80, (i) => 20 + i * .1), series(80, (i) => 1000.0 + i)), isNull);
    });

    test('chuỗi sóng có xu hướng: có mẫu ở các nhóm và tổng mẫu khớp số điểm lấy mẫu', () {
      final bars = series(600, (i) => 30 + 10 * math.sin(i / 25) + i * .01);
      final index = series(600, (i) => 1000 + 50 * math.sin(i / 40));
      final r = backtestHealth(bars, index)!;
      final expected = ((600 - 1 - backtestHorizon - 59) / backtestStep).floor() + 1;
      expect(r.samples, expected);
      expect(r.buckets.values.where((b) => b.n > 0).length, greaterThan(1));
      for (final b in r.buckets.values) {
        expect(b.wins, lessThanOrEqualTo(b.n));
      }
    });

    test('chỉ dùng dữ liệu đến thời điểm đó: đổi giá tương lai không làm đổi điểm quá khứ', () {
      final a = series(400, (i) => 30 + 10 * math.sin(i / 25));
      final b = [...a.sublist(0, 300), for (final x in a.sublist(300)) Bar(x.t, x.o * 3, x.h * 3, x.l * 3, x.c * 3, x.v)];
      final index = series(400, (i) => 1000.0 + i);
      // Các điểm lấy mẫu cách cuối ≥ 100 phiên không bị ảnh hưởng bởi 100 phiên cuối đã đổi, ngoại trừ lợi suất nhìn trước: so riêng điểm
      final ra = backtestHealth(a.sublist(0, 300), index)!, rb = backtestHealth(b.sublist(0, 300), index)!;
      expect(ra.toJson(), rb.toJson());
    });

    test('verdict: Mạnh hơn Yếu ≥ 1 điểm % là ok, không hơn là fail, ít mẫu là weak', () {
      const strongBest = HealthBacktest({'Mạnh': BucketStat(10, 7, 50), 'Yếu': BucketStat(10, 4, 10)});
      const flipped = HealthBacktest({'Mạnh': BucketStat(10, 3, 5), 'Yếu': BucketStat(10, 6, 30)});
      const few = HealthBacktest({'Mạnh': BucketStat(3, 3, 30), 'Yếu': BucketStat(3, 0, -9)});
      expect(strongBest.verdict, 'ok');
      expect(flipped.verdict, 'fail');
      expect(few.verdict, 'weak');
    });

    test('lưu và đọc lại JSON giữ nguyên số liệu', () {
      const r = HealthBacktest({'Mạnh': BucketStat(10, 7, 50.5), 'Trung tính': BucketStat(4, 2, 3), 'Yếu': BucketStat(0, 0, 0)});
      expect(HealthBacktest.fromJson(r.toJson()).toJson(), r.toJson());
    });
  });

  group('độ rộng thị trường', () {
    // 60 mã: giá giảm đều 80 phiên rồi hồi; mọi mã cùng nhịp nên độ rộng chạm đáy rồi hồi
    List<Bar> stock(int k) => series(140, (i) => i < 120 ? 100 - i * .4 + k * .01 : 52 + (i - 120) * 1.5 + k * .01);

    test('tỷ lệ mã trên MA50 chạy từ thấp lên cao và tạo dấu hiệu hồi từ dưới 20%', () {
      final s = breadthSeries([for (var k = 0; k < 60; k++) stock(k)]);
      expect(s.length, 60);
      expect(s.every((x) => x >= 0 && x <= 100), isTrue);
      expect(s.reduce(math.min), lessThan(20));
      expect(s.last, greaterThan(20));
      expect(breadthSignal(s, universe: 60).met, isTrue);
    });

    test('luôn dưới 20% hoặc luôn cao thì chưa phải hồi', () {
      expect(breadthSignal(List.filled(40, 10.0)).met, isFalse);
      expect(breadthSignal(List.filled(40, 60.0)).met, isFalse);
    });

    test('quá ít dữ liệu thì không kết luận', () {
      expect(breadthSignal([10, 30]).met, isNull);
      expect(breadthSeries([series(30, (i) => 10.0 + i)]), isEmpty);
    });
  });

  group('hàng đợi kiểm định', () {
    final bars = series(500, (i) => 30 + 10 * math.sin(i / 25));
    final log = <String>[];
    Future<List<Bar>> fetch(String s, {bool isIndex = false, int days = 1500}) async {
      log.add(s);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return bars;
    }

    setUp(() {
      log.clear();
      SharedPreferences.setMockInitialValues({});
    });

    test('danh sách theo dõi chạy trước mã người dùng mở, mỗi mã một lần', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BacktestStore(prefs, fetch: fetch, universe: () async => ['AAA'], parallel: 1);
      store.request('XYZ'); // mở xem trước nhưng phải đứng sau danh sách theo dõi
      store.enqueueWatchlist(['FPT', 'VCB']);
      expect(store.stateOf('XYZ'), isIn([BacktestState.queued, BacktestState.running]));
      for (var i = 0; i < 200 && !['XYZ', 'FPT', 'VCB'].every((x) => store.stateOf(x) == BacktestState.done); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final order = log.where((s) => ['FPT', 'VCB', 'XYZ'].contains(s)).toList();
      expect(order.first, 'XYZ', reason: 'XYZ đã bắt đầu ngay khi hàng đợi còn trống');
      expect(order.where((s) => s == 'FPT').length, 1);
      expect(store.stateOf('FPT'), BacktestState.done);
      expect(store.resultOf('VCB'), isNotNull);
      expect(store.pooled!.$2, 3);
    });

    test('mã người dùng mở đứng sau mọi mã trong danh sách theo dõi dù xếp hàng trước', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BacktestStore(prefs, fetch: fetch, universe: () async => [], parallel: 1);
      store.enqueueWatchlist(['A']); // chạy ngay
      store.request('CLICK');
      store.enqueueWatchlist(['W1', 'W2']);
      for (var i = 0; i < 300 && !['A', 'W1', 'W2', 'CLICK'].every((x) => store.stateOf(x) == BacktestState.done); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final order = log.where((s) => s != 'VNINDEX').toList();
      expect(order, ['A', 'W1', 'W2', 'CLICK']);
    });

    test('kết quả lưu trong ngày: mở lại không tải giá lại; sang ngày mới thì tính lại', () async {
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 11, 3, 3);
      final a = BacktestStore(prefs, fetch: fetch, universe: () async => [], now: () => now);
      a.enqueueWatchlist(['FPT']);
      for (var i = 0; i < 100 && a.stateOf('FPT') != BacktestState.done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(a.stateOf('FPT'), BacktestState.done);
      log.clear();
      final b = BacktestStore(prefs, fetch: fetch, universe: () async => [], now: () => now);
      expect(b.stateOf('FPT'), BacktestState.done, reason: 'đọc từ bộ nhớ lưu');
      b.enqueueWatchlist(['FPT']);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(log.where((s) => s == 'FPT'), isEmpty, reason: 'không tải lại trong ngày');
      now = now.add(const Duration(days: 1));
      expect(b.stateOf('FPT'), BacktestState.none, reason: 'sang ngày mới');
      final c = BacktestStore(prefs, fetch: fetch, universe: () async => [], now: () => now);
      expect(c.stateOf('FPT'), BacktestState.none);
    });

    test('lỗi tải giá: đánh dấu failed, không treo hàng đợi', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BacktestStore(
        prefs,
        fetch: (s, {bool isIndex = false, int days = 1}) async => throw Exception('mạng'),
        universe: () async => [],
      );
      store.enqueueWatchlist(['FPT']);
      for (var i = 0; i < 50 && store.stateOf('FPT') != BacktestState.failed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.stateOf('FPT'), BacktestState.failed);
    });

    test('độ rộng chạy sau khi các mã đã xong và được lưu', () async {
      final prefs = await SharedPreferences.getInstance();
      List<Bar> st(int k) => series(140, (i) => i < 120 ? 100 - i * .4 + k * .01 : 52 + (i - 120) * 1.5 + k * .01);
      final store = BacktestStore(
        prefs,
        fetch: (s, {bool isIndex = false, int days = 1}) async => s.startsWith('S') ? st(int.parse(s.substring(1))) : bars,
        universe: () async => [for (var k = 0; k < 60; k++) 'S$k'],
      );
      store.enqueueWatchlist(['FPT']);
      for (var i = 0; i < 200 && store.breadth == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.breadth, isNotNull);
      expect(store.breadthBottomSignal.met, isTrue);
      expect(prefs.getString('backtest_v1'), contains('"breadth"'));
    });
  });
}
