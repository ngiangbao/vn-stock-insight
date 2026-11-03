import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/ui/widgets.dart';

class _Page extends StatefulWidget {
  final String name;
  final List<String> log;
  const _Page(this.name, this.log);

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.name}');
  }

  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => setState(() => taps++), child: Text('${widget.name}:$taps'));
}

void main() {
  Widget app(List<String> log, {bool reduce = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Một'),
                Tab(text: 'Hai'),
                Tab(text: 'Ba'),
              ],
            ),
          ),
          body: SmoothTabView(children: [_Page('A', log), _Page('B', log), _Page('C', log)]),
        ),
      ),
    ),
  );

  testWidgets('chỉ dựng trang ở lần mở đầu tiên, quay lại không dựng lại và giữ nguyên trạng thái', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(app(log));
    expect(log, ['init A'], reason: 'trang chưa mở thì chưa dựng');
    await tester.tap(find.text('A:0'));
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);

    await tester.tap(find.text('Hai'));
    await tester.pumpAndSettle();
    expect(find.text('B:0'), findsOneWidget);
    expect(find.text('A:1'), findsNothing, reason: 'trang cũ ẩn đi (không vẽ, không nhận chạm)');

    await tester.tap(find.text('Một'));
    await tester.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget, reason: 'giữ nguyên trạng thái');
    await tester.tap(find.text('Ba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hai'));
    await tester.pumpAndSettle();
    expect(log, ['init A', 'init B', 'init C'], reason: 'mỗi trang chỉ khởi tạo một lần');
  });

  testWidgets('đổi tab có hiệu ứng mờ ngắn, và bỏ hiệu ứng khi hệ thống bật giảm chuyển động', (tester) async {
    await tester.pumpWidget(app([]));
    await tester.tap(find.text('Hai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final fading = tester.widget<FadeTransition>(find.ancestor(of: find.text('B:0'), matching: find.byType(FadeTransition)).first);
    expect(fading.opacity.value, lessThan(1), reason: 'đang mờ dần');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FadeTransition>(find.ancestor(of: find.text('B:0'), matching: find.byType(FadeTransition)).first).opacity.value,
      1,
    );

    await tester.pumpWidget(app([], reduce: true));
    await tester.tap(find.text('Ba'));
    await tester.pump();
    expect(
      tester.widget<FadeTransition>(find.ancestor(of: find.text('C:0'), matching: find.byType(FadeTransition)).first).opacity.value,
      1,
      reason: 'giảm chuyển động',
    );
  });
}
