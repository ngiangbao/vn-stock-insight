import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/ai/providers.dart';
import 'package:vn_stock_insight/state.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-aikey';
}

AiConfig _cfg({String key = 'sk-or-v1-abc123', String id = 'openrouter'}) =>
    AiConfig(presetById(id), 'https://api.example.com/v1', 'vendor/model', key);

const _schema = {
  'type': 'object',
  'properties': {
    'ok': {'type': 'boolean'},
  },
};

http.Response _json(Object body, [int code = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), code, headers: {'content-type': 'application/json; charset=utf-8', ...headers});

Map<String, dynamic> _ok() => {
  'choices': [
    {
      'finish_reason': 'stop',
      'message': {'content': '{"ok": true}'},
    },
  ],
};

Future<Map<String, dynamic>> _call(AiConfig c, http.Client client) =>
    http.runWithClient(() => generateJson(c, system: 's', prompt: 'p', schema: _schema), () => client);

void main() {
  setUp(() => retryDelay = (_, _) => Duration.zero);

  test('làm sạch API key dán từ web: khoảng trắng, xuống dòng, ký tự ẩn, dấu nháy, tiền tố Bearer', () {
    expect(cleanApiKey('  sk-or-v1-abc \n'), 'sk-or-v1-abc');
    expect(cleanApiKey('sk-or-​v1-abc '), 'sk-or-v1-abc');
    expect(cleanApiKey('"sk-abc"'), 'sk-abc');
    expect(cleanApiKey('Bearer sk-abc'), 'sk-abc');
    expect(isHeaderSafe('sk-or-v1-abc123_X'), isTrue);
    expect(isHeaderSafe('sk-ấ-abc'), isFalse);
    expect(isHeaderSafe(''), isFalse);
  });

  test('429 rồi thành công: tự thử lại, kết quả đúng', () async {
    var calls = 0;
    final r = await _call(
      _cfg(),
      MockClient(
        (req) async => ++calls == 1
            ? _json(
                {
                  'error': {'message': 'rate limited'},
                },
                429,
                {'retry-after': '1'},
              )
            : _json(_ok()),
      ),
    );
    expect(r['ok'], true);
    expect(calls, 2);
  });

  test('lỗi mạng chập chờn rồi thành công; lỗi mạng liên tục báo rõ sau 3 lần', () async {
    var calls = 0;
    final r = await _call(
      _cfg(),
      MockClient((req) async {
        if (++calls < 3) throw http.ClientException('Connection closed before full header was received');
        return _json(_ok());
      }),
    );
    expect(r['ok'], true);
    expect(calls, 3);

    await expectLater(
      _call(_cfg(), MockClient((req) async => throw Exception('Failed host lookup'))),
      throwsA(isA<AiException>().having((e) => e.message, 'message', allOf(contains('Lỗi kết nối mạng'), contains('3 lần')))),
    );
  });

  test('503 quá tải: thử lại 3 lần rồi báo lỗi có gợi ý "không phải do key"', () async {
    var calls = 0;
    await expectLater(
      _call(
        _cfg(),
        MockClient((req) async {
          calls++;
          return _json(
            {
              'error': {'message': 'upstream overloaded'},
            },
            503,
            {'x-request-id': 'req_123'},
          );
        }),
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('HTTP 503'), contains('không phải do key'), contains('req_123')),
        ),
      ),
    );
    expect(calls, 3);
  });

  test('401 sai key: không thử lại, gợi ý kiểm tra key', () async {
    var calls = 0;
    await expectLater(
      _call(
        _cfg(),
        MockClient((req) async {
          calls++;
          return _json({
            'error': {'message': 'No auth credentials found'},
          }, 401);
        }),
      ),
      throwsA(isA<AiException>().having((e) => e.message, 'message', allOf(contains('HTTP 401'), contains('API key sai')))),
    );
    expect(calls, 1);
  });

  test('HTTP 200 nhưng thân là lỗi (OpenRouter): báo lỗi rõ, thử lại lỗi tạm thời, không ném lỗi kiểu dữ liệu', () async {
    var calls = 0;
    final r = await _call(
      _cfg(),
      MockClient(
        (req) async => ++calls == 1
            ? _json({
                'error': {'message': 'Provider returned error', 'code': 502},
              })
            : _json(_ok()),
      ),
    );
    expect(r['ok'], true);
    expect(calls, 2);

    await expectLater(
      _call(
        _cfg(),
        MockClient(
          (req) async => _json({
            'error': {'message': 'Invalid key', 'code': 401},
          }),
        ),
      ),
      throwsA(isA<AiException>().having((e) => e.message, 'message', allOf(contains('Invalid key'), contains('API key')))),
    );
    // Thân 200 không có choices
    await expectLater(
      _call(_cfg(), MockClient((req) async => _json({'id': 'x'}))),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('phản hồi rỗng'))),
    );
  });

  test('OpenRouter 404 "No endpoints found": thử định dạng JSON lỏng hơn thay vì dừng', () async {
    final formats = <String?>[];
    final r = await _call(
      _cfg(),
      MockClient((req) async {
        final body = jsonDecode(req.body) as Map;
        final f = (body['response_format'] as Map?)?['type'] as String?;
        formats.add(f);
        if (f == 'json_schema') {
          return _json({
            'error': {'message': 'No endpoints found that can handle the requested parameters', 'code': 404},
          }, 404);
        }
        return _json(_ok());
      }),
    );
    expect(r['ok'], true);
    expect(formats, ['json_schema', 'json_object']);
  });

  test('model mới đòi max_completion_tokens: tự đổi tham số', () async {
    final params = <List<String>>[];
    final r = await _call(
      _cfg(id: 'openai'),
      MockClient((req) async {
        final body = jsonDecode(req.body) as Map;
        params.add([
          if (body.containsKey('max_tokens')) 'max_tokens',
          if (body.containsKey('max_completion_tokens')) 'max_completion_tokens',
        ]);
        if (body.containsKey('max_tokens')) {
          return _json({
            'error': {
              'message': "Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.",
            },
          }, 400);
        }
        return _json(_ok());
      }),
    );
    expect(r['ok'], true);
    expect(params, [
      ['max_tokens'],
      ['max_completion_tokens'],
    ]);
  });

  test('key chứa ký tự lạ: báo rõ để dán lại, không gọi mạng', () async {
    var calls = 0;
    await expectLater(
      _call(
        _cfg(key: 'sk-ấ-abc'),
        MockClient((req) async {
          calls++;
          return _json(_ok());
        }),
      ),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('ký tự không hợp lệ'))),
    );
    expect(calls, 0);
  });

  test('key có khoảng trắng hoặc xuống dòng vẫn gửi đúng (đã làm sạch) trong header', () async {
    String? auth;
    await _call(
      _cfg(key: '  sk-or-v1-abc123 \n'),
      MockClient((req) async {
        auth = req.headers['Authorization'];
        return _json(_ok());
      }),
    );
    expect(auth, 'Bearer sk-or-v1-abc123');
  });

  group('lưu và đọc key', () {
    Future<AppState> init({Map<String, Object> prefs = const {}, Map<String, String> secure = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      FlutterSecureStorage.setMockInitialValues(secure);
      PathProviderPlatform.instance = _FakePaths();
      final s = AppState();
      await s.init(startDashboard: false);
      return s;
    }

    test('két an toàn trống nhưng key còn trong cài đặt: vẫn đọc được (trước đây bị bỏ sót)', () async {
      final s = await init(prefs: {'flutter.key_openrouter': 'sk-or-from-prefs'});
      expect(s.keyOf('openrouter'), 'sk-or-from-prefs');
    });

    test('két an toàn có key: ưu tiên két', () async {
      final s = await init(prefs: {'flutter.key_openrouter': 'old'}, secure: {'key_openrouter': 'sk-or-secure'});
      expect(s.keyOf('openrouter'), 'sk-or-secure');
    });

    test('key trống lúc mở app nhưng két mở khóa sau đó: resolveAiConfig nạp lại key', () async {
      final s = await init();
      s.setProvider('openrouter');
      expect(s.keyOf('openrouter'), '');
      FlutterSecureStorage.setMockInitialValues({'key_openrouter': 'sk-or-late'});
      final c = await s.resolveAiConfig();
      expect(c.apiKey, 'sk-or-late');
    });

    test('lưu key được làm sạch (bỏ khoảng trắng, ký tự ẩn)', () async {
      final s = await init();
      await s.setProviderConfig('openrouter', apiKey: ' sk-or-​abc \n');
      expect(s.keyOf('openrouter'), 'sk-or-abc');
    });
  });
}
