import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/feedback.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/settings_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-feedback';
}

void main() {
  group('soạn issue GitHub', () {
    test('báo lỗi: tiêu đề có tiền tố, nội dung có mô tả, bước tái hiện và môi trường', () {
      final body = feedbackBody(FeedbackKind.bug, 'Biểu đồ trắng', steps: '1. Mở FPT', version: '2.15.2', platform: 'linux 7');
      final uri = feedbackUri(FeedbackKind.bug, 'Biểu đồ không hiện', body);
      expect(uri.host, 'github.com');
      expect(uri.path, '/$feedbackRepo/issues/new');
      expect(uri.queryParameters['title'], '[Lỗi] Biểu đồ không hiện');
      expect(uri.queryParameters['labels'], 'bug');
      final b = uri.queryParameters['body']!;
      expect(b, contains('Biểu đồ trắng'));
      expect(b, contains('1. Mở FPT'));
      expect(b, contains('Phiên bản app: 2.15.2'));
      expect(b, contains('linux 7'));
    });

    test('góp ý không có mục các bước tái hiện; nội dung quá dài bị cắt để URL không vượt giới hạn', () {
      final b = feedbackBody(FeedbackKind.idea, 'x' * 20000, steps: 'bỏ qua', version: '1', platform: 'p');
      expect(b, isNot(contains('Các bước tái hiện')));
      expect(b.length, lessThan(maxBodyChars + 100));
      expect(
        feedbackUri(FeedbackKind.idea, 't', b).toString().length,
        lessThan(8000 * 3),
        reason: 'URL đã mã hóa vẫn trong giới hạn của GitHub sau khi cắt',
      );
    });

    test('pull request mở trang so sánh nhánh của dự án', () {
      expect(feedbackUri(FeedbackKind.pr, '', '').path, '/$feedbackRepo/compare');
    });
  });

  Future<AppState> state(WidgetTester tester, double w, double h) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppState();
    await tester.runAsync(() => s.init(startDashboard: false));
    return s;
  }

  Future<void> open(WidgetTester tester, AppState s) async {
    await tester.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('trang cài đặt rộng: dàn hai cột phủ hết chiều ngang cửa sổ, có mục đóng góp ý kiến', (tester) async {
    final s = await state(tester, 1600, 1000);
    await open(tester, s);
    final left = tester.getRect(find.text('Giao diện').first), right = tester.getRect(find.text('Đóng góp ý kiến'));
    expect(right.left, greaterThan(left.left + 500), reason: 'cột phải nằm bên phải');
    final cards = tester.widgetList<Card>(find.byType(Card)).length;
    expect(cards, greaterThanOrEqualTo(5));
    // Thẻ cuối cột phải kết thúc sát mép phải cửa sổ (trừ lề 16)
    final rightCard = tester.getRect(find.ancestor(of: find.text('Đóng góp ý kiến'), matching: find.byType(Card)).first);
    expect(rightCard.right, closeTo(1600 - 16, 2));
    expect(find.text('Gửi ý kiến lên GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('điện thoại 375 px: một cột, không tràn bố cục', (tester) async {
    final s = await state(tester, 375, 800);
    await open(tester, s);
    await tester.scrollUntilVisible(find.text('Gửi ý kiến lên GitHub'), 400, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('khung đóng góp: bắt buộc nhập tiêu đề và nội dung, chọn loại, pull request giải thích rõ', (tester) async {
    final s = await state(tester, 1200, 1000);
    await open(tester, s);
    await tester.ensureVisible(find.text('Gửi ý kiến lên GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gửi ý kiến lên GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('Báo lỗi'), findsOneWidget);
    expect(find.text('Góp ý tính năng'), findsOneWidget);
    expect(find.textContaining('đừng ghi khóa API'), findsOneWidget);
    await tester.tap(find.text('Mở GitHub để gửi'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tiêu đề và nội dung trước khi gửi.'), findsOneWidget);
    await tester.tap(find.text('Đề xuất sửa mã (pull request)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cần tài khoản GitHub'), findsOneWidget);
    expect(find.text('Mở trang pull request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
