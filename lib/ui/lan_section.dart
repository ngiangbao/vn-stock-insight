// Mục "Chia sẻ trong mạng nội bộ" của màn hình Cài đặt: bật máy chủ chỉ đọc, hiện link/QR/khoá và thiết bị đang xem.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import '../state.dart';

/// Vẽ mã QR. Mã QR luôn đen trên nền trắng (bắt buộc để máy quét đọc được ở cả giao diện tối).
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView(this.data, {super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(data)));
    return Semantics(
      label: 'Mã QR mở trang xem trên thiết bị khác',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(10),
          child: CustomPaint(painter: _QrPainter(image)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  _QrPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = Colors.black;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (image.isDark(r, c)) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.5, cell + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

class LanSection extends StatefulWidget {
  const LanSection({super.key});

  @override
  State<LanSection> createState() => _LanSectionState();
}

class _LanSectionState extends State<LanSection> {
  final _port = TextEditingController();
  String? _selected, _test;
  bool _showKey = false, _testing = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Làm mới danh sách thiết bị đang kết nối
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _port.dispose();
    super.dispose();
  }

  void _copy(String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _regenerate(AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tạo lại khoá truy cập?'),
        content: const Text('Link và mã QR cũ sẽ ngừng hoạt động; các thiết bị đang xem phải nhập khoá mới.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tạo lại')),
        ],
      ),
    );
    if (ok == true) await state.lan.regenerateKey();
  }

  Future<void> _selfTest(AppState state, String ip) async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final r = await state.lan.selfTest(ip);
    if (mounted) {
      setState(() {
        _testing = false;
        _test = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lan = state.lan;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: lan,
      builder: (context, _) {
        if (_port.text.isEmpty) _port.text = '${lan.preferredPort}';
        final addrs = lan.addresses;
        final ip = addrs.any((a) => a.$2 == _selected) ? _selected! : (addrs.isEmpty ? null : addrs.first.$2);
        final url = ip == null ? null : lan.urlFor(ip);
        final clients = lan.server.clients;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Chia sẻ trong mạng nội bộ', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Xem app trên điện thoại, máy tính bảng hoặc máy khác cùng Wi-Fi/mạng LAN qua trình duyệt. Chỉ đọc, có khoá truy cập, '
                'không gửi API key. Mặc định tắt. Trên Android, máy chủ chỉ chạy khi app đang mở.',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật máy chủ nội bộ'),
                subtitle: Text(lan.enabled && lan.port != null ? 'Đang chạy ở cổng ${lan.port}' : 'Đang tắt'),
                value: lan.enabled,
                onChanged: lan.setEnabled,
              ),
              if (lan.error != null) Text(lan.error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(labelText: 'Cổng', helperText: '1024–65535'),
                    onSubmitted: (v) {
                      final p = int.tryParse(v);
                      if (p != null) lan.setPort(p);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton(
                    onPressed: () {
                      final p = int.tryParse(_port.text);
                      if (p != null) lan.setPort(p).then((_) => _port.text = '${lan.preferredPort}');
                    },
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text('Áp dụng'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cho phép thiết bị khác yêu cầu phân tích AI'),
                subtitle: const Text('Mỗi yêu cầu dùng API của bạn và tốn phí. Mặc định tắt: thiết bị khác chỉ xem kết quả đã lưu.'),
                value: lan.allowAnalysis,
                onChanged: lan.setAllowAnalysis,
              ),
              if (lan.enabled && url != null) ...[
                const Divider(height: 24),
                if (addrs.length > 1) ...[
                  Text('Giao diện mạng', style: text.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in addrs)
                      ChoiceChip(
                        label: Text('${a.$1} · ${a.$2}'),
                        selected: a.$2 == ip,
                        onSelected: (_) => setState(() => _selected = a.$2),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                LayoutBuilder(builder: (context, box) {
                  final qr = QrView(url, size: 200);
                  final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Quét mã QR hoặc mở link trên thiết bị cùng mạng:', style: text.bodyMedium),
                    const SizedBox(height: 6),
                    SelectableText(
                      _showKey ? url : url.replaceFirst(lan.key, '••••••••••••••••'),
                      style: text.bodyMedium?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: () => _copy(url, 'Đã sao chép link.'),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Sao chép link'),
                        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                        label: Text(_showKey ? 'Ẩn khoá' : 'Hiện khoá'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _regenerate(state),
                        icon: const Icon(Icons.autorenew, size: 18),
                        label: const Text('Tạo lại khoá'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                      ),
                    ]),
                  ]);
                  return box.maxWidth < 520
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: qr), const SizedBox(height: 12), info])
                      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(width: 16), Expanded(child: info)]);
                }),
                const SizedBox(height: 14),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : () => _selfTest(state, ip!),
                    icon: _testing
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('Tự kiểm tra kết nối'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                  IconButton(
                    tooltip: 'Quét lại địa chỉ mạng',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: lan.refreshAddresses,
                    icon: const Icon(Icons.refresh),
                  ),
                ]),
                if (_test != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_test!, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 14),
                Text('Thiết bị đang kết nối (${clients.length})', style: text.titleSmall),
                if (clients.isEmpty)
                  Text('Chưa có thiết bị nào truy cập trong 2 phút gần đây.', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                else
                  for (final c in clients)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.devices),
                      title: Text(c.ip),
                      subtitle: Text('${c.requests} yêu cầu${c.userAgent.isEmpty ? '' : ' · ${c.userAgent}'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                const SizedBox(height: 10),
                Text(
                  'Nếu thiết bị khác không mở được: Windows sẽ hiện hộp thoại Tường lửa lần đầu, hãy chọn "Cho phép" ở mạng riêng tư. '
                  'Linux có thể cần mở cổng, ví dụ: sudo ufw allow ${lan.port}/tcp. Chỉ nhận kết nối từ mạng nội bộ '
                  '(192.168.x.x, 10.x.x.x, 172.16–31.x.x, Tailscale 100.64–127.x.x); IP công cộng bị từ chối. Không mở cổng này ra Internet.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              if (lan.enabled && url == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Không tìm thấy địa chỉ mạng nội bộ. Hãy kết nối Wi-Fi/LAN rồi bấm quét lại.', style: text.bodySmall),
                ),
              if (lan.enabled && url == null)
                Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: lan.refreshAddresses, child: const Text('Quét lại'))),
            ]),
          ),
        );
      },
    );
  }
}
