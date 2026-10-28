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
  ProviderPreset(id: 'deepseek', name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', defaultModel: '', keyHint: 'platform.deepseek.com'),
  ProviderPreset(id: 'xai', name: 'xAI (Grok)', baseUrl: 'https://api.x.ai/v1', defaultModel: '', keyHint: 'console.x.ai'),
  ProviderPreset(id: 'together', name: 'Together AI', baseUrl: 'https://api.together.xyz/v1', defaultModel: '', keyHint: 'api.together.ai'),
  ProviderPreset(
    id: 'embedded',
    name: 'Chạy trong app (llama.cpp)',
    baseUrl: '',
    defaultModel: 'local',
    local: true,
    needsKey: false,
    note: 'Tải model GGUF từ Hugging Face và chạy ngay trong app, không cần cài thêm gì. '
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
  AiException(this.message);
  @override
  String toString() => message;
}

const _timeout = Duration(minutes: 6);

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

Map<String, String> _openaiHeaders(AiConfig c) => {
      'Content-Type': 'application/json',
      if (c.apiKey.isNotEmpty) 'Authorization': 'Bearer ${c.apiKey}',
      // OpenRouter dùng 2 header này để ghi nhận ứng dụng
      if (c.preset.id == 'openrouter') ...{'HTTP-Referer': 'https://github.com/ngiangbao/vn-stock-insight', 'X-Title': 'VN Stock Insight'},
    };

Map<String, String> _anthropicHeaders(AiConfig c, {bool fallback = false}) => {
      'Content-Type': 'application/json',
      'x-api-key': c.apiKey,
      'anthropic-version': '2026-10-21',
      if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    };

String _errorMessage(http.Response resp) {
  try {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final err = body is Map ? body['error'] : null;
    final msg = err is Map ? err['message'] : (err ?? body['message']);
    if (msg != null) return 'HTTP ${resp.statusCode}: $msg';
  } catch (_) {}
  return 'HTTP ${resp.statusCode}';
}

/// Liệt kê model của nhà cung cấp (để người dùng chọn).
Future<List<String>> listModels(AiConfig c) async {
  final base = _trimSlash(c.baseUrl);
  final http.Response resp;
  try {
    resp = await http
        .get(Uri.parse('$base/models'),
            headers: c.preset.style == ApiStyle.anthropic ? _anthropicHeaders(c) : _openaiHeaders(c))
        .timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw AiException('Hết thời gian chờ khi kết nối $base');
  } catch (e) {
    throw AiException(c.preset.local
        ? 'Không kết nối được $base. Kiểm tra ${c.preset.name} đã bật server chưa.'
        : 'Không kết nối được $base: $e');
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

Future<http.Response> _post(String url, Map<String, String> headers, Map<String, dynamic> body, AiConfig c) async {
  try {
    return await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body)).timeout(_timeout);
  } on TimeoutException {
    throw AiException('AI phản hồi quá lâu (hơn ${_timeout.inMinutes} phút).');
  } catch (e) {
    throw AiException(c.preset.id == 'embedded'
        ? 'Engine trong app ngừng phản hồi. Hãy thử lại.'
        : c.preset.local
            ? 'Không kết nối được ${c.baseUrl}. Kiểm tra ${c.preset.name} đang chạy và đã nạp model.'
            : 'Lỗi kết nối: $e');
  }
}

// ---------- Claude (Messages API) ----------
Future<Map<String, dynamic>> _anthropic(
    AiConfig c, String system, String prompt, Map<String, dynamic> schema, int maxTokens) async {
  // Opus và Sonnet hỗ trợ fallback phía server: nếu bộ lọc an toàn từ chối nhầm,
  // API tự chạy lại yêu cầu trên model dự phòng thay vì trả về lỗi.
  final fallback = c.model.startsWith('claude-opus') || c.model.startsWith('claude-sonnet') || c.model.startsWith('claude-fable');
  final resp = await _post(
    '${_trimSlash(c.baseUrl)}/messages',
    _anthropicHeaders(c, fallback: fallback),
    {
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
    },
    c,
  );
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
Future<Map<String, dynamic>> _openai(AiConfig c, String system, String prompt, Map<String, dynamic> schema,
    String schemaName, int maxTokens) async {
  final url = '${_trimSlash(c.baseUrl)}/chat/completions';
  final schemaHint = '\n\nTrả lời DUY NHẤT bằng một đối tượng JSON hợp lệ theo JSON Schema sau, không kèm giải thích:\n'
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
  for (final format in attempts) {
    final resp = await _post(
      url,
      _openaiHeaders(c),
      {
        'model': c.model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': format == null || format['type'] != 'json_schema' ? prompt + schemaHint : prompt},
        ],
        'response_format': ?format,
      },
      c,
    );
    if (resp.statusCode == 400 || resp.statusCode == 422) {
      lastError = AiException(_errorMessage(resp));
      continue; // thử định dạng lỏng hơn
    }
    if (resp.statusCode != 200) throw AiException(_errorMessage(resp));

    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choice = (body['choices'] as List).first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      throw AiException(c.preset.local
          ? 'Kết quả bị cắt vì hết độ dài. Hãy tăng context length của model (≥ 8192) trong ${c.preset.name}.'
          : 'Kết quả quá dài và bị cắt. Hãy thử lại.');
    }
    final content = (choice['message'] as Map)['content']?.toString() ?? '';
    final parsed = extractJson(content);
    if (parsed != null) return parsed;
    lastError = AiException('AI trả về nội dung không đúng định dạng JSON. Hãy thử model khác mạnh hơn.');
  }
  throw lastError ?? AiException('Không gọi được AI.');
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
