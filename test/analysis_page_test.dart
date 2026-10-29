import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/analysis_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-analysis';
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

void main() {
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

      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: AnalysisPage('FPT'))));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Hôm qua'), findsWidgets);
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('hôm qua'), findsOneWidget);
      expect(find.text('hôm nay'), findsOneWidget);
      final yesterday = tester.getTopLeft(find.text('hôm qua'));
      final today = tester.getTopLeft(find.text('hôm nay'));
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
      expect(find.text('cũ ba ngày'), findsOneWidget);
      expect(find.text('hôm qua'), findsNothing);
      expect(find.text('hôm nay'), findsOneWidget);
      expect(tester.takeException(), isNull);
      state.dispose();
    });
  }
}

String vnShort(DateTime d) {
  final v = d.toUtc().add(const Duration(hours: 7));
  return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}';
}
