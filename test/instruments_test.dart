import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart';
import 'package:vn_stock_insight/services/board.dart';
import 'package:vn_stock_insight/services/instruments.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/ui/asset_pages.dart';

void main() {
  test(
    'bond valuation: par, zero coupon, premium/discount and invalid input',
    () {
      expect(
        bondPrice(coupon: 5, yieldPercent: 5, years: 10),
        closeTo(100, 1e-9),
      );
      expect(bondPrice(coupon: 0, yieldPercent: 0, years: 5), 100);
      expect(
        bondPrice(coupon: 0, yieldPercent: 10, years: 1),
        closeTo(100 / 1.1, 1e-9),
      );
      expect(bondPrice(coupon: 7, yieldPercent: 5, years: 5), greaterThan(100));
      expect(bondPrice(coupon: 3, yieldPercent: 5, years: 5), lessThan(100));
      expect(
        () => bondPrice(coupon: 5, yieldPercent: -1, years: 5),
        throwsArgumentError,
      );
      expect(
        () => bondPrice(coupon: double.nan, yieldPercent: 5, years: 5),
        throwsArgumentError,
      );
      expect(
        () => bondPrice(coupon: 5, yieldPercent: 5, years: 0),
        throwsArgumentError,
      );
    },
  );

  test('basis refuses mismatched sessions; fund discovery leaves stock parser unchanged', () {
    const future = InstrumentQuote('VN30F1M', [
      Bar(86400, 101, 101, 101, 101, 10),
    ], derivative: true);
    expect(
      sameSessionBasis(future, [const Bar(86400, 100, 100, 100, 100, 10)]),
      1,
    );
    expect(
      sameSessionBasis(future, [const Bar(0, 100, 100, 100, 100, 10)]),
      isNull,
    );
    expect(sameSessionBasis(future, []), isNull);
    final payload = [
      {'s': 'FPT', 'st': 'STOCK', 'ref': 10000, 'c': 11000},
      {'s': 'ETF1', 'st': 'ETF', 'ref': 20000, 'c': 21000},
      {'s': 'CW1', 'st': 'CW', 'ref': 1000, 'c': 1200},
    ];
    expect(parseBoard(payload).single.symbol, 'FPT');
    expect(
      parseBoard(payload, securityTypes: {'ETF', 'FUND'}).single.symbol,
      'ETF1',
    );
  });

  testWidgets(
    'hover menu stays open across trigger and overlay; leaves and Escape close it',
    (tester) async {
      int? selected;
      final destinations = [
        for (final label in [
          'Tổng quan',
          'Theo dõi',
          'Bộ lọc',
          'CFA',
          'Trái phiếu',
          'Chứng chỉ quỹ',
          'Phái sinh',
          'Vĩ mô',
          'Tin tức',
          'Cài đặt',
        ])
          (Icons.circle_outlined, Icons.circle, label),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: AppMoreMenu(
                selectedIndex: 0,
                onSelected: (i) => selected = i,
                destinations: destinations,
              ),
            ),
          ),
        ),
      );
      expect(find.widgetWithText(MenuItemButton, 'Cài đặt'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(
        tester.getCenter(find.widgetWithText(TextButton, 'Thêm')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Cài đặt'), findsOneWidget);
      await mouse.moveTo(
        tester.getCenter(find.widgetWithText(MenuItemButton, 'Tin tức')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(MenuItemButton, 'Cài đặt'), findsOneWidget);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Tin tức'));
      await tester.pumpAndSettle();
      expect(selected, 8);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getCenter(find.widgetWithText(TextButton, 'Thêm')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Vĩ mô'), findsNothing);
      await mouse.moveTo(const Offset(700, 500));
      await mouse.moveTo(
        tester.getCenter(find.widgetWithText(TextButton, 'Thêm')),
      );
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.widgetWithText(MenuItemButton, 'Vĩ mô'), findsNothing);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'quotes retain data after failed refresh; narrow viewport and search',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstrumentQuotesPage(
              loader: () async {
                if (calls++ > 0) throw StateError('offline');
                return [
                  const InstrumentQuote('E1VFVN30', [
                    Bar(86400, 10, 11, 9, 10, 100),
                  ]),
                ];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('E1VFVN30'), findsOneWidget);
      await tester.tap(find.byTooltip('Làm mới dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.text('E1VFVN30'), findsOneWidget);
      expect(find.textContaining('Dữ liệu cũ'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'NOPE');
      await tester.pump();
      expect(find.text('E1VFVN30'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual NAV persists, replaces same day and rejects impossible dates',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FundNavTracker())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mã / tên quỹ'),
        'myfund',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'NAV/CCQ (đồng)'),
        '12345,67',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày NAV (yyyy-MM-dd)'),
        '2026-02-30',
      );
      await tester.tap(find.text('Lưu NAV'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập ngày hợp lệ dạng yyyy-MM-dd'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày NAV (yyyy-MM-dd)'),
        '2026-10-30',
      );
      await tester.tap(find.text('Lưu NAV'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MYFUND · 12.345,67'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FundNavTracker())),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('MYFUND · 12.345,67'), findsOneWidget);
      await tester.tap(find.byTooltip('Xóa bản ghi NAV'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MYFUND ·'), findsNothing);
    },
  );
}
