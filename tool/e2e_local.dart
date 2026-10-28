// ignore_for_file: avoid_print

// Kiểm thử đầu-cuối chế độ chạy model trong app (không cần giao diện):
// cài engine llama.cpp → nạp model GGUF → lấy dữ liệu thật → phân tích chuyên sâu → kiểm tra JSON.
//
// Chạy: dart run tool/e2e_local.dart <đường-dẫn-model.gguf> [mã, mặc định FPT]

import 'dart:io';

import 'package:vn_stock_insight/ai/prompts.dart';
import 'package:vn_stock_insight/ai/providers.dart';
import 'package:vn_stock_insight/services/fundamentals.dart';
import 'package:vn_stock_insight/services/llama_runtime.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/news.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Dùng: dart run tool/e2e_local.dart <model.gguf> [mã]');
    exit(2);
  }
  final symbol = args.length > 1 ? args[1] : 'FPT';
  final dir = await Directory.systemTemp.createTemp('vnsi-e2e');
  final runtime = LlamaRuntime(dir, () => File('assets/runtime.json').readAsString());
  final watch = Stopwatch()..start();
  void log(String s, [double? p]) => print('[${watch.elapsed.inSeconds}s] $s${p == null ? '' : ' ${(p * 100).toStringAsFixed(0)}%'}');

  try {
    final url = await runtime.start(args[0], onStatus: log);
    log('Engine: ${(await runtime.installed())!['variant']} tại $url');

    final bars = await fetchBars(symbol);
    final snap = analyze(symbol, bars);
    final news = await fetchNews({symbol});
    final inputs = {
      'technicals': snap.toPromptJson(),
      'fundamentals': await fetchFundamentals(symbol),
      'news': newsFor(news, symbol).map((n) => n.toPromptJson()).toList(),
    };
    log('Dữ liệu: ${bars.length} phiên, ${(inputs['news'] as List).length} tin');

    final result = await generateJson(
      AiConfig(presetById('embedded'), url, 'local', ''),
      system: stockSystem,
      prompt: stockPrompt(symbol, inputs),
      schema: stockSchema,
      schemaName: 'stock_analysis',
    );
    log('Xong phân tích');
    final missing = (stockSchema['required'] as List).where((k) => !result.containsKey(k)).toList();
    print('Nhận định: ${result['stance']} · ${result['headline']}');
    print('Bảng điểm: ${(result['scorecard'] as List).map((x) => '${x['dimension']}=${x['score']}').join(', ')}');
    print(missing.isEmpty ? 'OK: đủ các trường theo schema' : 'THIẾU trường: $missing');
    exitCode = missing.isEmpty ? 0 : 1;
  } finally {
    await runtime.stop();
    await dir.delete(recursive: true);
  }
}
