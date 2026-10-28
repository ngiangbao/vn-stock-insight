import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ai/providers.dart';
import 'package:vn_stock_insight/services/hardware.dart';
import 'package:vn_stock_insight/services/llama_runtime.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/updater.dart';

void main() {
  test('dùng lại phân tích trong cùng ngày Việt Nam và bỏ cache sang ngày mới', () {
    final state = AppState()
      ..analyses['FPT'] = {
        'created_at': '2026-10-28T17:00:00.000Z', // 00:00 ngày 29 tại Việt Nam
        'result': {'signal': 'hold'},
      };

    expect(state.analysisForToday('FPT', now: DateTime.utc(2026, 10, 29, 12)), isNotNull);
    expect(state.analysisForToday('FPT', now: DateTime.utc(2026, 10, 29, 17)), isNull);
    expect(state.analysisForToday('VCB', now: DateTime.utc(2026, 10, 29, 12)), isNull);
    state.dispose();
  });

  test('so sánh phiên bản', () {
    expect(compareVersions('v1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('1.0.0+3', '1.0.0'), 0);
    expect(compareVersions('1.2', '1.10.0'), lessThan(0));
  });

  test('tách JSON từ phản hồi của model chạy trên máy', () {
    expect(extractJson('<think>suy nghĩ {x}</think>\n```json\n{"a": 1}\n```'), {'a': 1});
    expect(extractJson('Kết quả: {"b": [1, 2]} xong'), {
      'b': [1, 2],
    });
    expect(extractJson('không có JSON'), isNull);
  });

  test('chỉ báo kỹ thuật trên chuỗi giá tăng đều', () {
    final bars = [for (var i = 0; i < 260; i++) Bar(i * 86400, 10.0 + i, 11.0 + i, 9.0 + i, 10.0 + i, 1000)];
    final s = analyze('TEST', bars);
    expect(s.close, 269);
    expect(s.data['rsi14'], 100);
    expect(s.signals, contains('Xu hướng tăng (giá > MA20 > MA50)'));
    expect(s.techScore, greaterThan(0));
  });

  test('đề xuất model theo cấu hình', () {
    final models = [
      ModelInfo.fromJson({'name': 'nhỏ', 'ollama': 'a', 'search': 'a', 'size_gb': 2.6, 'quality': 2}),
      ModelInfo.fromJson({'name': 'vừa', 'ollama': 'b', 'search': 'b', 'size_gb': 8.1, 'quality': 4}),
      ModelInfo.fromJson({'name': 'lớn', 'ollama': 'c', 'search': 'c', 'size_gb': 19, 'quality': 5}),
    ];
    const laptop = Hardware('Linux', 'cpu', 8, 16, null, null, false);
    const gpu12 = Hardware('Windows', 'cpu', 16, 32, 'RTX', 12, false);
    const mac36 = Hardware('macOS', 'M3', 12, 36, 'Apple', null, true);
    expect(recommend(models, laptop)?.name, 'nhỏ');
    expect(recommend(models, gpu12)?.name, 'vừa');
    expect(recommend(models, mac36)?.name, 'lớn');
    expect(models[2].fitFor(laptop), Fit.no);
  });

  test('tên thư mục engine giống nhau dù đường dẫn dùng / hay \\ (lỗi xóa nhầm engine trên Windows)', () {
    const listed = r'C:\Users\PC\AppData\Roaming\vn.stockinsight\vn_stock_insight\engine\b11624-win-vulkan-x64';
    const built = r'C:\Users\PC\AppData\Roaming\vn.stockinsight\vn_stock_insight/engine/b11624-win-vulkan-x64';
    expect(listed == built, isFalse); // so cả chuỗi như trước đây: sai
    expect(baseName(listed), baseName(built));
    expect(baseName(r'C:\x\engine\b1-win-cpu-x64\llama-server.exe'), 'llama-server.exe');
    expect(baseName('/home/u/.local/share/x/engine/b1-ubuntu-x64/'), 'b1-ubuntu-x64');
  });
}

