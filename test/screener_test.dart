import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/board.dart';
import 'package:vn_stock_insight/ui/screener_page.dart';

void main() {
  test('nhận nhiều mã ngăn cách bằng dấu phẩy, khoảng trắng và xuống dòng', () {
    expect(parseTickerCodes('hpg, FPT\nvcb; HPG  SSI'), [
      'HPG',
      'FPT',
      'VCB',
      'SSI',
    ]);
    expect(parseTickerCodes('***'), isEmpty);
  });

  test('đọc tên doanh nghiệp và ba mức giá mua bán từ bảng giá', () {
    final rows = parseBoard([
      {
        's': 'HPG',
        'st': 'STOCK',
        'bo': 'HSX',
        'orgn': 'Tập đoàn Hòa Phát',
        'ref': 21000,
        'c': 20750,
        'cei': 22450,
        'flo': 19550,
        'op': 20800,
        'h': 21100,
        'l': 20500,
        'avgp': 20810,
        'vo': 1000000,
        'va': 20750000,
        'ptv': 0,
        'pta': 0,
        'frbv': 50000,
        'frsv': 40000,
        'bp1': 20700,
        'bv1': 1000,
        'bp2': 20650,
        'bv2': 2000,
        'bp3': 20600,
        'bv3': 3000,
        'ap1': 20800,
        'av1': 4000,
        'ap2': 20850,
        'av2': 5000,
        'ap3': 20900,
        'av3': 6000,
      },
    ]);

    expect(rows, hasLength(1));
    expect(rows.single.name, 'Tập đoàn Hòa Phát');
    expect(rows.single.exchange, 'HOSE');
    expect(rows.single.bids.map((level) => level.price), [20700, 20650, 20600]);
    expect(rows.single.asks.map((level) => level.volume), [4000, 5000, 6000]);
  });
}
