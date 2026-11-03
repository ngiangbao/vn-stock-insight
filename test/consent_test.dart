import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/ai/consent.dart';
import 'package:vn_stock_insight/ai/providers.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/ai_consent_dialog.dart';

/// Máy không có dịch vụ keyring: mọi thao tác với kho khóa đều lỗi.
class _NoKeyring extends FlutterSecureStorage {
  const _NoKeyring();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'no-keyring');

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'no-keyring');
}

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-consent';
}

AiConfig cfg(String id, {String? url, String key = 'k'}) {
  final p = presetById(id);
  return AiConfig(p, url ?? p.baseUrl, p.defaultModel.isEmpty ? 'm' : p.defaultModel, key);
}

void main() {
  tearDown(() {
    AiConsent.requester = null;
    AiConsent.onChanged = null;
    AiConsent.granted.clear();
  });

  test('địa chỉ nội bộ không cần xác nhận, địa chỉ Internet thì cần', () {
    for (final u in [
      'http://localhost:1234/v1',
      'http://127.0.0.1:11434/v1',
      'http://192.168.1.10:11434/v1',
      'http://10.0.0.5/v1',
      'http://172.20.1.1/v1',
      'http://may-tinh.local:8080',
    ]) {
      expect(isLocalAddress(u), isTrue, reason: u);
    }
    for (final u in ['https://api.openai.com/v1', 'http://172.32.0.1/v1', 'http://8.8.8.8/v1', 'not a url', '']) {
      expect(isLocalAddress(u), isFalse, reason: u);
    }
    expect(sendsDataOffDevice(cfg('ollama')), isFalse);
    expect(sendsDataOffDevice(cfg('lmstudio')), isFalse);
    expect(sendsDataOffDevice(cfg('openai')), isTrue);
    expect(
      sendsDataOffDevice(cfg('openai', url: 'http://localhost:8000/v1')),
      isFalse,
      reason: 'dịch vụ tương thích OpenAI trỏ về máy mình',
    );
  });

  test('nhà cung cấp đám mây: hỏi một lần, nhớ lại, cuộc gọi đồng thời dùng chung một câu hỏi', () async {
    var asked = 0;
    final gate = Completer<bool>();
    AiConsent.requester = (c) {
      asked++;
      return gate.future;
    };
    var saved = 0;
    AiConsent.onChanged = () => saved++;
    final a = AiConsent.ensure(cfg('openai')), b = AiConsent.ensure(cfg('openai'));
    gate.complete(true);
    await Future.wait([a, b]);
    expect(asked, 1);
    expect(AiConsent.granted, contains('openai'));
    expect(saved, greaterThan(0));
    await AiConsent.ensure(cfg('openai'));
    expect(asked, 1, reason: 'đã đồng ý thì không hỏi lại');
    await AiConsent.ensure(cfg('groq'));
    expect(asked, 2, reason: 'mỗi nhà cung cấp hỏi riêng');
    AiConsent.revoke('openai');
    expect(AiConsent.granted, isNot(contains('openai')));
  });

  test('từ chối thì ném lỗi tiếng Việt và generateJson không gọi mạng; model trên máy không bị hỏi', () async {
    AiConsent.requester = (c) async => false;
    await expectLater(
      generateJson(cfg('openai'), system: 's', prompt: 'p', schema: const {}),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('Bạn chưa đồng ý gửi dữ liệu tới'))),
    );
    var asked = 0;
    AiConsent.requester = (c) async {
      asked++;
      return false;
    };
    await AiConsent.ensure(cfg('ollama'));
    expect(asked, 0);
  });

  test('chạy không giao diện (không đăng ký hộp thoại) thì không chặn', () async {
    AiConsent.requester = null;
    await AiConsent.ensure(cfg('openai'));
  });

  testWidgets('hộp thoại xác nhận: nêu rõ nhà cung cấp và dữ liệu gửi đi; trả đúng lựa chọn; dùng được từ khóa điều hướng gốc', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('nền')),
      ),
    );
    bool? result;
    unawaited(askAiConsent(key.currentContext!, cfg('openai')).then((v) => result = v));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gửi dữ liệu tới OpenAI'), findsOneWidget);
    expect(find.textContaining('api.openai.com'), findsOneWidget);
    expect(find.textContaining('mục tiêu đầu tư'), findsWidgets);
    await tester.tap(find.text('Không đồng ý'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    unawaited(askAiConsent(key.currentContext!, cfg('openai')).then((v) => result = v));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng ý và tiếp tục'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  group('lưu API key', () {
    Future<AppState> state(WidgetTester tester, {required bool secureWorks}) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      final s = AppState();
      if (!secureWorks) s.useSecureStorage(const _NoKeyring());
      await tester.runAsync(() => s.init(startDashboard: false));
      return s;
    }

    testWidgets('máy không có kho khóa: mặc định KHÔNG ghi key ra đĩa, chỉ giữ trong phiên', (tester) async {
      final s = await state(tester, secureWorks: false);
      expect(s.allowPlainKeys, isFalse);
      await tester.runAsync(() => s.setProviderConfig('openai', apiKey: 'sk-test-123'));
      expect(s.keyOf('openai'), 'sk-test-123', reason: 'vẫn dùng được trong phiên');
      expect(s.secureStorageOk, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('key_openai'), isNull, reason: 'không lưu dạng văn bản thường khi chưa được phép');
    });

    testWidgets('người dùng chủ động cho phép thì ghi; tắt đi thì xóa sạch bản không mã hóa', (tester) async {
      final s = await state(tester, secureWorks: false);
      await tester.runAsync(() => s.setProviderConfig('openai', apiKey: 'sk-test-123'));
      await tester.runAsync(() => s.setAllowPlainKeys(true));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('key_openai'), 'sk-test-123');
      await tester.runAsync(() => s.setAllowPlainKeys(false));
      expect(prefs.getString('key_openai'), isNull);
      expect(s.allowPlainKeys, isFalse);
    });

    testWidgets('đồng ý gửi dữ liệu được lưu và nạp lại sau khi mở app', (tester) async {
      final s = await state(tester, secureWorks: true);
      AiConsent.requester = (c) async => true;
      await tester.runAsync(() => AiConsent.ensure(cfg('openai')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      AiConsent.granted.clear();
      final again = AppState();
      await tester.runAsync(() => again.init(startDashboard: false));
      expect(AiConsent.granted, contains('openai'));
      s.dash.dispose();
      again.dash.dispose();
    });
  });
}
