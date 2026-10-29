import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/analysis_report.dart';
import 'package:vn_stock_insight/ui/analysis_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-analysis';
  @override
  Future<String?> getDownloadsPath() async => '/tmp/vnsi-test-downloads';
}

Map<String, dynamic> _record(DateTime at, String headline) => {
  'symbol': 'FPT',
  'created_at': at.toIso8601String(),
  'ai': 'test',
  'inputs': {
    'technicals': {'close': 52.5, 'change_1d': 1.2},
  },
  'result': {'stance': 'Trung lập', 'confidence': 'Vừa', 'headline': headline, 'summary': 'Tóm tắt $headline'},
};

Map<String, dynamic> _full(DateTime at) => {
  'symbol': 'HPG',
  'created_at': at.toIso8601String(),
  'ai': 'test',
  'inputs': {
    'technicals': {
      'close': 26.45,
      'change_1d': 1.2,
      'change_1y': 12.5,
      'high_52w': 29.0,
      'low_52w': 19.8,
      'volume': 17974700,
      'rsi14': 55.2,
    },
    'fundamentals': {
      'company': {
        'ten': 'CTCP Tập đoàn Hòa Phát',
        'nganh': 'Vật liệu xây dựng',
        'von_hoa_ty_dong': 173000,
        'so_huu_nuoc_ngoai': 0.2158,
        'vietcap_khuyen_nghi': 'MUA',
        'vietcap_gia_muc_tieu': 38000,
      },
      'chi_so_ttm_theo_quy': [
        for (var i = 0; i < 8; i++)
          {
            'ky': 'Q${i % 4 + 1}/${2023 + i ~/ 4}',
            'pe': 13.0 + i,
            'pb': 1.5,
            'roe': 0.1 + i * 0.01,
            'grossMargin': 0.12 + i * 0.01,
            'afterTaxProfitMargin': 0.07,
            'debtToEquity': 0.9,
          },
      ],
      'ket_qua_kinh_doanh_theo_quy_ty_dong': [
        for (var i = 0; i < 8; i++)
          {
            'ky': 'Q${i % 4 + 1}/${2023 + i ~/ 4}',
            'doanh_thu_thuan': 30000 + i * 1500,
            'loi_nhuan_gop': 4000 + i * 300,
            'loi_nhuan_sau_thue_cong_ty_me': 2500 + i * 200,
          },
      ],
    },
  },
  'result': {
    'stance': 'Tích cực',
    'confidence': 'Cao',
    'headline': 'Tăng tốc nhờ Dung Quất 2',
    'summary': 'Tóm tắt ' * 30,
    'scorecard': [
      for (final d in ['Xu hướng giá', 'Định giá']) {'dimension': d, 'score': 4, 'reason': 'Lý do ' * 10},
    ],
    'thesis': {
      'statement': 'Luận điểm',
      'pillars': ['Trụ cột một', 'Trụ cột hai'],
      'invalidation': ['Sai nếu một'],
    },
    'earnings': {
      'summary': 'Kết quả ' * 20,
      'highlights': ['Ý một'],
    },
    'valuation': 'Định giá ' * 10,
    'competition': 'Doanh nghiệp đầu ngành ' * 6,
    'technical': {'summary': 'Kỹ thuật ' * 10, 'key_levels': 'Hỗ trợ 25, kháng cự 29'},
    'catalysts': [
      {'event': 'Công bố KQKD', 'timing': 'Dự kiến tháng 1', 'impact': 'Cao', 'why': 'Lý do'},
    ],
    'scenarios': {'bull': 'Tốt', 'base': 'Vừa', 'bear': 'Xấu'},
    'risks': ['Rủi ro một'],
    'watch_points': ['Theo dõi một'],
    'data_gaps': ['Thiếu dữ liệu'],
  },
};

void main() {
  for (final w in [1000.0, 700.0, 360.0]) {
    testWidgets('báo cáo dạng nghiên cứu hiển thị đủ phần, không tràn (${w.toInt()} px)', (tester) async {
      tester.view.physicalSize = Size(w, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final at = DateTime.now();
      final bars = [
        for (var i = 0; i < 300; i++)
          Bar(at.millisecondsSinceEpoch ~/ 1000 - (300 - i) * 86400, 20 + i * .02, 21 + i * .02, 19 + i * .02, 20 + i * .02, 1e6),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: w,
                child: ResearchReport(_full(at), bars: bars, indexBars: bars, exchange: 'HOSE'),
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'BÁO CÁO DOANH NGHIỆP',
        'Khuyến nghị',
        'Thông tin cổ phiếu',
        'Diễn biến giá',
        'BẢNG CHẤM ĐIỂM',
        'KẾT QUẢ KINH DOANH VÀ CHỈ SỐ TÀI CHÍNH',
        'Doanh thu thuần (tỷ đồng)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('HPG (HOSE)'), findsOneWidget);
      expect(find.textContaining('Giá mục tiêu Vietcap'), findsOneWidget);
      expect(find.textContaining('liên hệ', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('lịch sử nhận định chỉ giữ 7 ngày gần nhất, mỗi ngày một bản', () {
    final state = AppState();
    final base = DateTime.utc(2026, 10, 1, 5);
    for (var i = 0; i < 10; i++) {
      state.rememberAnalysis('FPT', _record(base.add(Duration(days: i)), 'ngày $i'));
    }
    // ghi lại cùng ngày thì thay thế
    state.rememberAnalysis('FPT', _record(base.add(const Duration(days: 9, hours: 2)), 'mới hơn'));
    final days = state.historyFor('FPT');
    expect(days.length, AppState.historyDays);
    expect(days.first.$1, '2026-10-10');
    expect(days.first.$2['result']['headline'], 'mới hơn');
    expect(days.last.$1, '2026-10-04');
    state.dispose();
  });

  for (final w in [1400.0, 1000.0, 600.0]) {
    testWidgets('trang phân tích AI: hôm qua bên trái, hôm nay bên phải, chọn ngày so sánh (${w.toInt()} px)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      final now = DateTime.now();
      for (final (back, name) in [(3, 'cũ ba ngày'), (1, 'hôm qua'), (0, 'hôm nay')]) {
        final r = _record(now.subtract(Duration(days: back)), name);
        state.rememberAnalysis('FPT', r);
        if (back == 0) state.analyses['FPT'] = r;
      }

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: AnalysisPage('FPT')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Hôm qua'), findsWidgets);
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('HÔM QUA'), findsOneWidget);
      expect(find.text('HÔM NAY'), findsOneWidget);
      final yesterday = tester.getTopLeft(find.text('HÔM QUA'));
      final today = tester.getTopLeft(find.text('HÔM NAY'));
      if (w >= 900) {
        expect(yesterday.dx, lessThan(today.dx), reason: 'hôm qua bên trái');
        expect(today.dx, greaterThan(w / 2 - 20));
        // nội dung giãn hết chiều ngang cửa sổ
        expect(tester.getTopRight(find.byType(Card).last).dx, greaterThan(w - 40));
      } else {
        expect(yesterday.dy, lessThan(today.dy), reason: 'màn hình hẹp xếp hôm qua trước hôm nay');
      }

      final older = find.widgetWithText(ChoiceChip, vnShort(now.subtract(const Duration(days: 3))));
      expect(older, findsOneWidget);
      await tester.ensureVisible(older);
      await tester.tap(older);
      await tester.pump();
      expect(find.text('CŨ BA NGÀY'), findsOneWidget);
      expect(find.text('HÔM QUA'), findsNothing);
      expect(find.text('HÔM NAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      state.dispose();
    });
  }

  testWidgets('nút Xuất PDF chụp báo cáo hôm nay và lưu file PDF', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();
    await tester.runAsync(() => state.init(startDashboard: false));
    final r = _full(DateTime.now());
    state.rememberAnalysis('HPG', r);
    state.analyses['HPG'] = r;
    final out = File('/tmp/vnsi-test-downloads/bao-cao-HPG-${vietnamDayKey(DateTime.now())}.pdf');
    if (out.existsSync()) out.deleteSync();

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AnalysisPage('HPG')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final buttons = find.widgetWithText(OutlinedButton, 'Xuất PDF');
    expect(buttons, findsNWidgets(2));
    await tester.ensureVisible(buttons.last);
    await tester.tap(buttons.last);
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !out.existsSync(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    for (var i = 0; i < 40 && find.text('Đang xuất…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), greaterThan(5000));
    expect(String.fromCharCodes(out.readAsBytesSync().take(5)), '%PDF-');
    expect(find.textContaining('Đã lưu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String vnShort(DateTime d) {
  final v = d.toUtc().add(const Duration(hours: 7));
  return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}';
}
