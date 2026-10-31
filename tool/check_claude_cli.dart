// Kiểm tra thủ công với Claude CLI thật: dart run tool/check_claude_cli.dart [model]
import 'package:vn_stock_insight/services/claude_cli.dart';

Future<void> main(List<String> args) async {
  final cli = ClaudeCli();
  final path = await cli.find();
  print('path: $path');
  if (path == null) return;
  print('version: ${await cli.version(path)}');
  final auth = await cli.authStatus(path);
  print('loggedIn: ${auth.loggedIn} (${auth.method})');
  if (!auth.loggedIn) return;
  final sw = Stopwatch()..start();
  final r = await cli.generate(
    path: path,
    system: 'Trả lời đúng định dạng yêu cầu.',
    prompt: 'Mã cổ phiếu VNM thuộc ngành nào ở Việt Nam? Trả lời một cụm từ ngắn.',
    schema: {
      'type': 'object',
      'properties': {'sector': {'type': 'string'}},
      'required': ['sector'],
    },
    model: args.isEmpty ? 'haiku' : args.first,
  );
  print('structured: ${r.structured} cost: ${r.costUsd} in ${sw.elapsed.inSeconds}s');
}
