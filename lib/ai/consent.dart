// Xác nhận của người dùng trước khi gửi nội dung phân tích tới nhà cung cấp AI đám mây. Mỗi nhà cung cấp hỏi một lần, lưu trên máy và thu hồi được
// trong Cài đặt → Quyền riêng tư. Model chạy trên máy (LM Studio, Ollama, model nhúng, địa chỉ mạng nội bộ) không cần xác nhận vì dữ liệu không ra ngoài.

import 'providers.dart';

/// Địa chỉ trỏ tới chính máy này hoặc mạng nội bộ: dữ liệu không ra Internet.
bool isLocalAddress(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  if (host == 'localhost' || host == '::1' || host.endsWith('.local') || host.endsWith('.localhost')) return true;
  final m = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(host);
  if (m == null) return false;
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
}

/// Nhà cung cấp [c] có đưa dữ liệu ra ngoài máy/mạng nội bộ không.
bool sendsDataOffDevice(AiConfig c) => !c.preset.local && !isLocalAddress(c.baseUrl);

class AiConsent {
  AiConsent._();

  /// Nhà cung cấp đã được đồng ý (id preset).
  static final Set<String> granted = {};

  /// Gọi khi danh sách đổi để lưu lại.
  static void Function()? onChanged;

  /// Hiện hộp thoại xác nhận; true nếu người dùng đồng ý. Để null khi chạy không giao diện (công cụ dòng lệnh, kiểm thử): khi đó không chặn.
  static Future<bool> Function(AiConfig c)? requester;

  static final Map<String, Future<bool>> _pending = {};

  /// Đảm bảo đã được đồng ý cho [c]; nếu chưa thì hỏi. Ném [AiException] nếu người dùng từ chối.
  static Future<void> ensure(AiConfig c) async {
    if (!sendsDataOffDevice(c) || granted.contains(c.preset.id)) return;
    final ask = requester;
    if (ask == null) return;
    final ok = await (_pending[c.preset.id] ??= ask(c).whenComplete(() {
      _pending.remove(c.preset.id); // không trả về giá trị: trả về Future sẽ khiến whenComplete chờ chính nó
    }));
    if (!ok) {
      throw AiException(
        'Bạn chưa đồng ý gửi dữ liệu tới ${c.preset.name}. Chọn model chạy trên máy, hoặc đồng ý trong Cài đặt → Quyền riêng tư.',
      );
    }
    granted.add(c.preset.id);
    onChanged?.call();
  }

  static void revoke(String id) {
    if (granted.remove(id)) onChanged?.call();
  }
}
