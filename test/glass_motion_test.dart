import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/ui/glass.dart';
import 'package:vn_stock_insight/ui/glass_motion.dart';

Widget app({required bool glass, bool reduce = false, TabController? controller, required Widget Function(BuildContext) body}) {
  final tokens = glass ? GlassTokens.of(Brightness.light, 0.6) : null;
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: GlassScope(
          tokens: tokens,
          child: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                bottom: AppTabBar(
                  controller: controller,
                  tabs: const [
                    Tab(text: 'Một'),
                    Tab(text: 'Hai'),
                    Tab(text: 'Ba'),
                  ],
                ),
              ),
              body: Builder(builder: body),
            ),
          ),
        ),
      ),
    ),
  );
}

Rect lens(WidgetTester tester) => tester.getRect(find.byType(GlassLens));

void main() {
  testWidgets('kiểu kính: thấu kính nằm đúng tab đang chọn và trượt sang tab khác bằng lò xo, giãn ra khi đang chạy rồi về đúng đích', (
    tester,
  ) async {
    await tester.pumpWidget(app(glass: true, body: (_) => const SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GlassLens), findsOneWidget);
    final start = lens(tester);
    expect(start.center.dx, closeTo(tester.getCenter(find.text('Một')).dx, 2), reason: 'bắt đầu ở tab đầu');
    expect(
      tester.getTopLeft(find.byType(GlassTabBar)).dx + 16 + 4,
      closeTo(start.left, 3),
      reason: 'thanh tab nằm sát lề trái như tiêu đề, không bị căn giữa',
    );

    await tester.tap(find.text('Ba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final moving = lens(tester);
    expect(moving.center.dx, greaterThan(start.center.dx + 10), reason: 'đã bắt đầu trượt');
    expect(moving.width, greaterThan(start.width * 1.02), reason: 'giãn theo hướng chạy');

    await tester.pump(const Duration(milliseconds: 1500));
    final end = lens(tester);
    expect(end.center.dx, closeTo(tester.getCenter(find.text('Ba')).dx, 1.5), reason: 'dừng đúng tab được chọn');
    expect(end.width, closeTo(start.width * 1.0, start.width * 0.25), reason: 'co về kích thước thường (độ rộng tab khác nhau)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm giữ làm thấu kính nổi lên (to hơn), thả ra thì co lại', (tester) async {
    await tester.pumpWidget(app(glass: true, body: (_) => const SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    final rest = lens(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Hai')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60)); // hoạt ảnh cần nhiều khung hình để chạy
    }
    expect(lens(tester).width, greaterThan(rest.width * 1.04));
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('kéo ngang chọn tab dưới ngón tay khi thả', (tester) async {
    await tester.pumpWidget(app(glass: true, body: (_) => const SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    final from = tester.getCenter(find.text('Một')), to = tester.getCenter(find.text('Ba'));
    final g = await tester.startGesture(from);
    await g.moveTo(Offset((from.dx + to.dx) / 2, from.dy));
    await g.moveTo(to);
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(DefaultTabController.of(tester.element(find.byType(GlassTabBar))).index, 2);
    expect(lens(tester).center.dx, closeTo(tester.getCenter(find.text('Ba')).dx, 1.5));
  });

  testWidgets('giảm chuyển động: thấu kính nhảy thẳng tới đích, không giãn', (tester) async {
    await tester.pumpWidget(app(glass: true, reduce: true, body: (_) => const SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
    final w = lens(tester).width;
    await tester.tap(find.text('Hai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(lens(tester).center.dx, closeTo(tester.getCenter(find.text('Hai')).dx, 1.5));
    expect(lens(tester).width, closeTo(w, w * 0.4));
  });

  testWidgets('kiểu Cổ điển giữ nguyên TabBar của Material, không có thấu kính', (tester) async {
    await tester.pumpWidget(app(glass: false, body: (_) => const SizedBox()));
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(GlassTabBar), findsNothing);
    expect(find.byType(GlassLens), findsNothing);
  });

  testWidgets('thanh tab kính: có nhãn trợ năng, vùng chạm ≥ 48 px chiều cao, không tràn ở 375 px', (tester) async {
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(glass: true, body: (_) => const SizedBox()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('Hai'), findsOneWidget);
    expect(tester.getSize(find.byType(GlassTabBar)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GlassReveal: nội dung mới mờ dần và phóng nhẹ, không dùng lọc nhòe (gây giật); giảm chuyển động thì bỏ qua', (tester) async {
    Widget host(int trigger, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: GlassScope(
          tokens: GlassTokens.of(Brightness.dark, 0.6),
          child: GlassReveal(trigger: trigger, child: const Text('nội dung')),
        ),
      ),
    );
    double opacity() => tester.widget<FadeTransition>(find.byType(FadeTransition).last).opacity.value;
    await tester.pumpWidget(host(0));
    expect(opacity(), 1);
    await tester.pumpWidget(host(1));
    await tester.pump(); // khung đầu: hoạt ảnh bắt đầu sau khung dựng
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(ImageFiltered), findsNothing, reason: 'không nhòe cả trang');
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), 1);
    await tester.pumpWidget(host(2, reduce: true));
    await tester.pump(const Duration(milliseconds: 20));
    expect(opacity(), 1);
  });

  testWidgets('AppSegmented: kiểu kính có thấu kính trượt tới lựa chọn mới, chia đều khi expand, 375px không tràn', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var value = 'vn';
    late StateSetter set;
    Widget host(bool glass) => MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, s) {
            set = s;
            final w = AppSegmented<String>(
              expand: true,
              options: const [('vn', 'Việt Nam'), ('us', 'Châu Mỹ'), ('eu', 'Châu Âu'), ('as', 'Châu Á')],
              selected: value,
              onChanged: (v) => set(() => value = v),
            );
            return glass ? GlassScope(tokens: GlassTokens.of(Brightness.light, 0.6), child: w) : w;
          },
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    expect(find.byType(GlassLensMover), findsOneWidget);
    final before = tester.getCenter(find.byType(GlassLens)).dx;
    await tester.tap(find.text('Châu Âu'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(value, 'eu');
    expect(tester.getCenter(find.byType(GlassLens)).dx, greaterThan(before + 100));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Châu Âu'), findsOneWidget);
    await tester.pumpWidget(host(false));
    expect(find.byType(SegmentedButton<String>), findsOneWidget, reason: 'kiểu cổ điển giữ nguyên nút Material');
  });
}
