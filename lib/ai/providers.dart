// Các nhà cung cấp AI. Claude dùng API gốc của Anthropic; các nhà cung cấp còn lại
// (kể cả LM Studio, Ollama chạy trên máy) dùng chuẩn "chat completions" của OpenAI.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ApiStyle { anthropic, openai }

class ProviderPreset {
  final String id, name, baseUrl, defaultModel, keyHint, note;
  final ApiStyle style;
  final bool local, needsKey;
  final List<String> suggestedModels;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    this.style = ApiStyle.openai,
    this.local = false,
    this.needsKey = true,
    this.keyHint = '',
    this.note = '',
    this.suggestedModels = const [],
  });
}

const providers = [
  ProviderPreset(
    id: 'anthropic',
    name: 'Claude (Anthropic)',
    style: ApiStyle.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    defaultModel: 'claude-opus-5-5',
    suggestedModels: ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'],
    keyHint: 'Tạo key tại platform.claude.com',
  ),
  ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: '',
    keyHint: 'Tạo key tại platform.openai.com',
  ),
  ProviderPreset(
    id: 'gemini',
    name: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: '',
    keyHint: 'Tạo key tại aistudio.google.com',
  ),
  ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter (nhiều model)',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: '',
    keyHint: 'Tạo key tại openrouter.ai',
    note: 'Một key dùng được hàng trăm model của nhiều hãng.',
  ),
  ProviderPreset(id: 'groq', name: 'Groq', baseUrl: 'https://api.groq.com/openai/v1', defaultModel: '', keyHint: 'console.groq.com'),
  ProviderPreset(id: 'mistral', name: 'Mistral', baseUrl: 'https://api.mistral.ai/v1', defaultModel: '', keyHint: 'console.mistral.ai'),
  ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: '',
    keyHint: 'platform.deepseek.com',
  ),
  ProviderPreset(id: 'xai', name: 'xAI (Grok)', baseUrl: 'https://api.x.ai/v1', defaultModel: '', keyHint: 'console.x.ai'),
  ProviderPreset(id: 'together', name: 'Together AI', baseUrl: 'https://api.together.xyz/v1', defaultModel: '', keyHint: 'api.together.ai'),
  ProviderPreset(
    id: 'embedded',
    name: 'Chạy trong app (llama.cpp)',
    baseUrl: '',
    defaultModel: 'local',
    local: true,
    needsKey: false,
    note:
        'Tải model GGUF từ Hugging Face và chạy ngay trong app, không cần cài thêm gì. '
        'Chọn model ở "Model trên máy". Hỗ trợ Windows, macOS, Linux.',
  ),
  ProviderPreset(
    id: 'lmstudio',
    name: 'LM Studio (trên máy)',
    baseUrl: 'http://localhost:1234/v1',
    defaultModel: '',
    local: true,
    needsKey: false,
    note: 'Mở LM Studio → Developer → Start Server. Nên đặt context length ≥ 8192.',
  ),
  ProviderPreset(
    id: 'ollama',
    name: 'Ollama (trên máy)',
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: '',
    local: true,
    needsKey: false,
    note: 'Cài Ollama, rồi tải model ở mục "Model trên máy". Trên Android: nhập địa chỉ IP máy tính trong cùng mạng.',
  ),
  ProviderPreset(
    id: 'custom',
    name: 'Tùy chỉnh (chuẩn OpenAI)',
    baseUrl: 'http://localhost:8080/v1',
    defaultModel: '',
    needsKey: false,
    note: 'Bất kỳ dịch vụ nào có API tương thích OpenAI (llama.cpp server, vLLM, Azure, …).',
  ),
];

ProviderPreset presetById(String id) => providers.firstWhere((p) => p.id == id, orElse: () => providers.first);

class AiConfig {
  final ProviderPreset preset;
  final String baseUrl, model, apiKey, effort;
  const AiConfig(this.preset, this.baseUrl, this.model, this.apiKey, {this.effort = 'medium'});
}

class AiException implements Exception {
  final String message;

  /// Lỗi tạm thời (quá tải, giới hạn tốc độ, mạng chập chờn): thử lại có thể thành công.
  final bool retryable;
  AiException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

/// Làm sạch API key người dùng dán vào: bỏ khoảng trắng, xuống dòng, dấu nháy bao quanh và ký tự ẩn (zero-width, NBSP) thường lẫn vào
/// khi sao chép từ trang web hoặc tài liệu.
String cleanApiKey(String raw) {
  var k = raw.replaceAll(RegExp('[\\s\u00A0\u200B-\u200D\u2060\uFEFF]'), '');
  if (k.length >= 2 && ((k.startsWith('"') && k.endsWith('"')) || (k.startsWith("'") && k.endsWith("'")))) k = k.substring(1, k.length - 1);
  if (k.toLowerCase().startsWith('bearer')) k = k.substring(6);
  return k;
}

/// Header HTTP chỉ nhận ký tự ASCII in được; key chứa ký tự khác (thường do dán nhầm) sẽ làm yêu cầu lỗi khó hiểu.
bool isHeaderSafe(String k) => RegExp(r'^[\x21-\x7E]+$').hasMatch(k);

/// Thời gian chờ giữa các lần thử lại; đổi được trong kiểm thử.
Duration Function(int attempt, Duration? retryAfter) retryDelay = (attempt, retryAfter) {
  if (retryAfter != null) return retryAfter > const Duration(seconds: 30) ? const Duration(seconds: 30) : retryAfter;
  return Duration(seconds: 2 * (1 << attempt)); // 2s, 4s
};

/// Mã HTTP nên thử lại: hết thời gian chờ yêu cầu, giới hạn tốc độ, lỗi hoặc quá tải phía nhà cung cấp.
bool isRetryableStatus(int code) => code == 408 || code == 409 || code == 425 || code == 429 || (code >= 500 && code <= 599);

const _timeout = Duration(minutes: 6);

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

Map<String, String> _openaiHeaders(AiConfig c) => {
  'Content-Type': 'application/json',
  if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${cleanApiKey(c.apiKey)}',
  // OpenRouter dùng 2 header này để ghi nhận ứng dụng
  if (c.preset.id == 'openrouter') ...{'HTTP-Referer': 'https://github.com/ngiangbao/vn-stock-insight', 'X-Title': 'VN Stock Insight'},
};

Map<String, String> _anthropicHeaders(AiConfig c, {bool fallback = false}) => {
  'Content-Type': 'application/json',
  'x-api-key': cleanApiKey(c.apiKey),
  'anthropic-version': '2026-10-21',
  if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
};

String _errorMessage(http.Response resp) {
  var msg = '';
  try {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final err = body is Map ? body['error'] : null;
    final m = err is Map ? err['message'] : (err ?? (body is Map ? body['message'] : null));
    if (m != null) msg = '$m';
  } catch (_) {}
  final hint = switch (resp.statusCode) {
    401 => 'API key sai, hết hạn hoặc bị thu hồi. Kiểm tra lại key trong Cài đặt → AI (dán lại, không thừa ký tự).',
    403 => 'Key không có quyền dùng model này hoặc bị chặn theo khu vực. Thử model khác hoặc kiểm tra quyền của key.',
    402 => 'Tài khoản hết tín dụng hoặc chưa thanh toán. Nạp thêm tín dụng ở nhà cung cấp.',
    404 => 'Không tìm thấy model hoặc đường dẫn API. Kiểm tra tên model và địa chỉ API.',
    408 || 504 => 'Nhà cung cấp phản hồi quá chậm. Thử lại sau ít phút.',
    429 => 'Vượt giới hạn tốc độ hoặc hạn mức của key. App đã tự thử lại; nếu còn lỗi, chờ một lúc hoặc đổi model.',
    >= 500 => 'Nhà cung cấp đang quá tải hoặc lỗi tạm thời, không phải do key. Thử lại sau ít phút.',
    _ => '',
  };
  final id = resp.headers['x-request-id'] ?? resp.headers['request-id'] ?? resp.headers['cf-ray'];
  return [
    'HTTP ${resp.statusCode}${msg.isEmpty ? '' : ': $msg'}',
    if (hint.isNotEmpty) hint,
    if (id != null) '(mã yêu cầu $id)',
  ].join('\n');
}

/// Liệt kê model của nhà cung cấp (để người dùng chọn).
Future<List<String>> listModels(AiConfig c) async {
  final base = _trimSlash(c.baseUrl);
  final http.Response resp;
  try {
    resp = await http
        .get(Uri.parse('$base/models'), headers: c.preset.style == ApiStyle.anthropic ? _anthropicHeaders(c) : _openaiHeaders(c))
        .timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw AiException('Hết thời gian chờ khi kết nối $base');
  } catch (e) {
    throw AiException(
      c.preset.local ? 'Không kết nối được $base. Kiểm tra ${c.preset.name} đã bật server chưa.' : 'Không kết nối được $base: $e',
    );
  }
  if (resp.statusCode != 200) throw AiException(_errorMessage(resp));
  final data = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['data'] as List? ?? [];
  final ids = [for (final m in data) (m as Map)['id'].toString()];
  // Gemini trả về dạng "models/gemini-…"
  return ids.map((id) => id.startsWith('models/') ? id.substring(7) : id).toList()..sort();
}

/// Gọi model và nhận về JSON theo [schema].
Future<Map<String, dynamic>> generateJson(
  AiConfig c, {
  required String system,
  required String prompt,
  required Map<String, dynamic> schema,
  String schemaName = 'result',
  int maxTokens = 16000,
}) async {
  if (c.model.isEmpty) throw AiException('Chưa chọn model. Vào Cài đặt → AI để chọn model.');
  if (c.preset.needsKey && c.apiKey.isEmpty) throw AiException('Chưa nhập API key cho ${c.preset.name}.');
  // Model chạy trên máy có ngữ cảnh ngắn: chừa chỗ cho dữ liệu đầu vào
  if (c.preset.local) maxTokens = maxTokens.clamp(0, 6000);
  return c.preset.style == ApiStyle.anthropic
      ? _anthropic(c, system, prompt, schema, maxTokens)
      : _openai(c, system, prompt, schema, schemaName, maxTokens);
}

const _maxAttempts = 3;

Duration? _retryAfter(http.Response r) {
  final v = int.tryParse(r.headers['retry-after'] ?? '');
  return v == null ? null : Duration(seconds: v.clamp(0, 120));
}

/// Gọi API, tự thử lại (tối đa [_maxAttempts] lần) với lỗi tạm thời: mã 408/429/5xx và lỗi mạng chập chờn.
/// Không thử lại khi sai key (401/403) hay yêu cầu sai (400), và không thử lại khi hết thời gian chờ dài.
Future<http.Response> _post(String url, Map<String, String> headers, Map<String, dynamic> body, AiConfig c) async {
  final key = headers['x-api-key'] ?? headers['Authorization'] ?? '';
  if (key.isNotEmpty && !isHeaderSafe(key.replaceFirst('Bearer ', ''))) {
    throw AiException('API key chứa ký tự không hợp lệ (thường do dán từ trang web). Hãy xóa và dán lại key ở Cài đặt → AI.');
  }
  final canRetry = !c.preset.local;
  for (var attempt = 1; ; attempt++) {
    try {
      final resp = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body)).timeout(_timeout);
      if (canRetry && isRetryableStatus(resp.statusCode) && attempt < _maxAttempts) {
        await Future<void>.delayed(retryDelay(attempt, _retryAfter(resp)));
        continue;
      }
      return resp;
    } on TimeoutException {
      throw AiException('AI phản hồi quá lâu (hơn ${_timeout.inMinutes} phút).', retryable: true);
    } catch (e) {
      if (canRetry && attempt < _maxAttempts) {
        await Future<void>.delayed(retryDelay(attempt, null));
        continue;
      }
      throw AiException(
        c.preset.id == 'embedded'
            ? 'Engine trong app ngừng phản hồi. Hãy thử lại.'
            : c.preset.local
            ? 'Không kết nối được ${c.baseUrl}. Kiểm tra ${c.preset.name} đang chạy và đã nạp model.'
            : 'Lỗi kết nối mạng: $e. Đã thử $attempt lần; kiểm tra mạng rồi thử lại.',
        retryable: true,
      );
    }
  }
}

// ---------- Claude (Messages API) ----------
Future<Map<String, dynamic>> _anthropic(AiConfig c, String system, String prompt, Map<String, dynamic> schema, int maxTokens) async {
  // Opus và Sonnet hỗ trợ fallback phía server: nếu bộ lọc an toàn từ chối nhầm,
  // API tự chạy lại yêu cầu trên model dự phòng thay vì trả về lỗi.
  final fallback = c.model.startsWith('claude-opus') || c.model.startsWith('claude-sonnet') || c.model.startsWith('claude-fable');
  final resp = await _post('${_trimSlash(c.baseUrl)}/messages', _anthropicHeaders(c, fallback: fallback), {
    'model': c.model,
    'max_tokens': maxTokens,
    'system': system,
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
    'output_config': {
      'effort': c.effort,
      'format': {'type': 'json_schema', 'schema': schema},
    },
    if (fallback) 'fallbacks': 'default',
  }, c);
  if (resp.statusCode != 200) throw AiException(_errorMessage(resp));
  final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  switch (body['stop_reason']) {
    case 'refusal':
      throw AiException('AI từ chối yêu cầu này.');
    case 'max_tokens':
      throw AiException('Kết quả quá dài và bị cắt. Hãy thử lại.');
  }
  final text = (body['content'] as List).cast<Map>().firstWhere((b) => b['type'] == 'text', orElse: () => {})['text'];
  if (text == null) throw AiException('AI không trả về nội dung.');
  return jsonDecode(text as String) as Map<String, dynamic>;
}

// ---------- Chuẩn OpenAI (OpenAI, Gemini, OpenRouter, Groq, …, LM Studio, Ollama) ----------
Future<Map<String, dynamic>> _openai(
  AiConfig c,
  String system,
  String prompt,
  Map<String, dynamic> schema,
  String schemaName,
  int maxTokens,
) async {
  final url = '${_trimSlash(c.baseUrl)}/chat/completions';
  final schemaHint =
      '\n\nTrả lời DUY NHẤT bằng một đối tượng JSON hợp lệ theo JSON Schema sau, không kèm giải thích:\n'
      '${jsonEncode(schema)}';

  // Không phải nhà cung cấp/model nào cũng hỗ trợ json_schema: thử lần lượt từ chặt đến lỏng.
  final attempts = <Map<String, dynamic>?>[
    {
      'type': 'json_schema',
      'json_schema': {'name': schemaName, 'strict': true, 'schema': schema},
    },
    {'type': 'json_object'},
    null,
  ];

  AiException? lastError;
  var tokenParam = 'max_tokens';
  for (final format in attempts) {
    http.Response resp;
    var bodyError = 0; // số lần gặp lỗi tạm thời nằm trong thân phản hồi 200 (OpenRouter hay trả kiểu này)
    while (true) {
      resp = await _post(url, _openaiHeaders(c), {
        'model': c.model,
        tokenParam: maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': format == null || format['type'] != 'json_schema' ? prompt + schemaHint : prompt},
        ],
        'response_format': ?format,
      }, c);
      // Một số model mới (dòng o, GPT-5) từ chối max_tokens và đòi max_completion_tokens
      if (resp.statusCode == 400 &&
          tokenParam == 'max_tokens' &&
          utf8.decode(resp.bodyBytes, allowMalformed: true).contains('max_completion_tokens')) {
        tokenParam = 'max_completion_tokens';
        continue;
      }
      // Lỗi nằm trong thân phản hồi 200: {"error": {...}}
      if (resp.statusCode == 200) {
        final err = _bodyError(resp);
        if (err != null) {
          if (err.retryable && ++bodyError < _maxAttempts && !c.preset.local) {
            await Future<void>.delayed(retryDelay(bodyError, null));
            continue;
          }
          throw err;
        }
      }
      break;
    }
    final msg = utf8.decode(resp.bodyBytes, allowMalformed: true);
    // 400/422: định dạng không được hỗ trợ; 404 "No endpoints found…" (OpenRouter): không có nhà cung cấp nào hỗ trợ tham số này
    if (resp.statusCode == 400 || resp.statusCode == 422 || (resp.statusCode == 404 && msg.contains('No endpoints'))) {
      lastError = AiException(_errorMessage(resp));
      continue; // thử định dạng lỏng hơn
    }
    if (resp.statusCode != 200) throw AiException(_errorMessage(resp), retryable: isRetryableStatus(resp.statusCode));

    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      lastError = AiException('Nhà cung cấp trả về phản hồi rỗng (không có nội dung). Thử lại hoặc đổi model.', retryable: true);
      continue;
    }
    final choice = choices.first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      throw AiException(
        c.preset.local
            ? 'Kết quả bị cắt vì hết độ dài. Hãy tăng context length của model (≥ 8192) trong ${c.preset.name}.'
            : 'Kết quả quá dài và bị cắt. Hãy thử lại.',
      );
    }
    final content = (choice['message'] as Map?)?['content']?.toString() ?? '';
    final parsed = extractJson(content);
    if (parsed != null) return parsed;
    lastError = AiException('AI trả về nội dung không đúng định dạng JSON. Hãy thử lại hoặc dùng model mạnh hơn.', retryable: true);
  }
  throw lastError ?? AiException('Không gọi được AI.');
}

/// Lỗi nằm trong thân phản hồi HTTP 200 (`{"error": {"message", "code"}}`), null nếu không có.
AiException? _bodyError(http.Response resp) {
  try {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is Map && body['error'] != null) {
      final e = body['error'];
      final msg = e is Map ? (e['message'] ?? e) : e;
      final code = e is Map ? int.tryParse('${e['code']}') : null;
      return AiException(
        'Nhà cung cấp báo lỗi: $msg${code == null ? '' : ' (mã $code)'}${code == 401 || code == 403 ? '\nKiểm tra lại API key và quyền dùng model.' : ''}',
        retryable: code == null || isRetryableStatus(code),
      );
    }
  } catch (_) {}
  return null;
}

/// Lấy đối tượng JSON từ văn bản model trả về (bỏ phần suy nghĩ `<think>…</think>` và khung ```json```).
Map<String, dynamic>? extractJson(String text) {
  var s = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  final start = s.indexOf('{'), end = s.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final v = jsonDecode(s.substring(start, end + 1));
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
