// Khung đóng góp ý kiến: soạn báo lỗi / góp ý / đề xuất sửa mã rồi mở trang GitHub đã điền sẵn để gửi.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/feedback.dart';
import '../services/updater.dart';

Future<void> openFeedbackDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const FeedbackDialog());

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  FeedbackKind _kind = FeedbackKind.bug;
  final _title = TextEditingController();
  final _detail = TextEditingController();
  final _steps = TextEditingController();
  String _version = '…';
  String? _error;
  bool _opening = false;

  String get _platform => '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();

  @override
  void initState() {
    super.initState();
    currentVersion().then((v) => mounted ? setState(() => _version = v) : null);
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _steps.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_kind != FeedbackKind.pr && (_title.text.trim().isEmpty || _detail.text.trim().isEmpty)) {
      setState(() => _error = 'Nhập tiêu đề và nội dung trước khi gửi.');
      return;
    }
    final uri = feedbackUri(
      _kind,
      _title.text,
      feedbackBody(_kind, _detail.text, steps: _steps.text, version: _version, platform: _platform),
    );
    setState(() {
      _error = null;
      _opening = true;
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!mounted) return;
    setState(() => _opening = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = 'Không mở được trình duyệt. Bạn có thể mở thủ công: github.com/$feedbackRepo/issues/new');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isPr = _kind == FeedbackKind.pr;
    return AlertDialog(
      title: const Text('Đóng góp ý kiến'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in FeedbackKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() {
                        _kind = k;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (isPr)
                Text(
                  'Pull request cần tài khoản GitHub và một nhánh mã riêng của bạn (fork). App sẽ mở trang so sánh nhánh của dự án để bạn chọn nhánh và tạo pull request. '
                  'Nếu chỉ muốn báo lỗi hoặc đề xuất ý tưởng, hãy chọn Báo lỗi hoặc Góp ý tính năng.',
                  style: text.bodyMedium,
                )
              else ...[
                TextField(
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Tiêu đề', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _detail,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: _kind == FeedbackKind.bug ? 'Mô tả lỗi' : 'Nội dung góp ý',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_kind == FeedbackKind.bug) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _steps,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Các bước tái hiện (không bắt buộc)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Tự đính kèm: phiên bản app $_version, hệ điều hành $_platform.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'App mở trang GitHub đã điền sẵn để bạn xem lại và bấm gửi bằng tài khoản GitHub của mình; app không giữ khóa hay mật khẩu GitHub. '
                        'Nội dung đăng công khai, vì vậy đừng ghi khóa API, mật khẩu hay thông tin cá nhân.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: text.bodySmall?.copyWith(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _opening ? null : _send,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(isPr ? 'Mở trang pull request' : 'Mở GitHub để gửi'),
        ),
      ],
    );
  }
}
