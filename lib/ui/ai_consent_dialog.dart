// Hộp thoại xác nhận trước khi gửi dữ liệu tới nhà cung cấp AI đám mây.

import 'package:flutter/material.dart';

import '../ai/providers.dart';

Future<bool> askAiConsent(BuildContext context, AiConfig c) async {
  final host = Uri.tryParse(c.baseUrl)?.host ?? '';
  final viaCli = c.preset.style == ApiStyle.claudeCli;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final cs = Theme.of(context).colorScheme;
      Widget bullet(String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6)),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: text.bodyMedium)),
          ],
        ),
      );
      return AlertDialog(
        title: Text('Gửi dữ liệu tới ${c.preset.name}?'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  viaCli
                      ? 'Phân tích AI chạy qua Claude CLI trên máy bạn, nội dung được gửi tới Anthropic theo tài khoản Claude bạn đã đăng nhập.'
                      : 'Để AI phân tích, app gửi trực tiếp từ máy bạn tới ${c.preset.name}${host.isEmpty ? '' : ' ($host)'}.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text('Nội dung gửi đi có thể gồm:', style: text.titleSmall),
                bullet('mã cổ phiếu, số liệu giá, chỉ báo kỹ thuật, số liệu tài chính, tiêu đề và tóm tắt tin tức liên quan;'),
                bullet(
                  'với phân tích danh mục: các mã, số lượng, giá vốn, mục tiêu đầu tư, khung thời gian và mức chấp nhận rủi ro bạn đã nhập;',
                ),
                bullet('với chat: câu hỏi của bạn và tối đa sáu lượt hội thoại gần nhất.'),
                const SizedBox(height: 10),
                Text(
                  'Nhà cung cấp xử lý và lưu dữ liệu theo chính sách của họ, có thể ở nước ngoài. Tác giả app không nhận và không lưu bản sao. '
                  'Đừng nhập thông tin cá nhân nhận diện được bạn vào câu hỏi hoặc ô mục tiêu đầu tư.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Không muốn gửi dữ liệu ra ngoài? Chọn "Không đồng ý" rồi dùng model chạy trên máy (LM Studio, Ollama). '
                  'Bạn thu hồi đồng ý bất cứ lúc nào trong Cài đặt → Quyền riêng tư.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Không đồng ý'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đồng ý và tiếp tục'),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
