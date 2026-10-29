import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/self_update.dart';
import '../services/updater.dart';

/// Thoát app đúng cách (chạy các bước dọn dẹp như tắt máy chủ chia sẻ, engine AI) trước khi bộ cài/script thay file.
Future<void> _exitApp() async {
  await ServicesBinding.instance.exitApplication(AppExitType.required);
  exit(0);
}

/// Hộp thoại có bản mới. Nếu máy hỗ trợ, nút "Cập nhật ngay" tải, kiểm tra, cài và mở lại app; nếu không thì mở trang tải.
/// [apply] và [supported] chỉ dùng khi kiểm thử.
void showUpdateDialog(BuildContext context, UpdateInfo info, {Future<void> Function(UpdateInfo, Progress)? apply, bool? supported}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => _UpdateDialog(info, apply: apply, supported: supported ?? canSelfUpdate(info)),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final Future<void> Function(UpdateInfo, Progress)? apply;
  final bool supported;
  const _UpdateDialog(this.info, {this.apply, required this.supported});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  UpdateStage? _stage;
  double? _progress;
  String? _error;

  String get _stageText => switch (_stage) {
    UpdateStage.downloading => 'Đang tải bản mới…',
    UpdateStage.verifying => 'Đang kiểm tra toàn vẹn (SHA-256)…',
    UpdateStage.installing => 'Đang cài đặt, app sẽ tự mở lại…',
    null => 'Đang chuẩn bị…',
  };

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = null;
      _progress = null;
    });
    try {
      void onProgress(UpdateStage s, double? p) {
        if (mounted) {
          setState(() {
            _stage = s;
            _progress = p;
          });
        }
      }

      final run = widget.apply ?? ((i, p) => applyUpdate(i, exitApp: _exitApp, onProgress: p));
      await run(widget.info, onProgress);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Có phiên bản mới ${info.latest}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 400),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bạn đang dùng ${info.current}.'),
              if (widget.supported && !_busy && _error == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Bấm "Cập nhật ngay": app tự tải, kiểm tra, cài bản mới và mở lại. Dữ liệu và cài đặt của bạn được giữ nguyên.',
                  style: text.bodyMedium,
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  label: _stageText,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_stageText),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _stage == UpdateStage.downloading ? _progress : null),
                      if (_stage == UpdateStage.downloading && _progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${(_progress! * 100).round()}%', style: text.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: cs.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Không cập nhật tự động được: $_error\nBạn vẫn có thể tải bản mới thủ công.',
                            style: text.bodyMedium?.copyWith(color: cs.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (info.notes.trim().isNotEmpty && !_busy) ...[
                const SizedBox(height: 12),
                Text('Thay đổi:', style: text.titleSmall),
                const SizedBox(height: 4),
                Text(info.notes.trim()),
              ],
            ],
          ),
        ),
      ),
      actions: _busy
          ? const []
          : [
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Để sau'),
              ),
              if (info.downloadUrl == null || info.downloadUrl != info.pageUrl)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => launchUrl(Uri.parse(info.pageUrl), mode: LaunchMode.externalApplication),
                  child: const Text('Xem trên GitHub'),
                ),
              if (widget.supported)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _update,
                  child: Text(_error == null ? 'Cập nhật ngay' : 'Thử lại'),
                )
              else if (info.downloadUrl != null)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () {
                    launchUrl(Uri.parse(info.downloadUrl!), mode: LaunchMode.externalApplication);
                    Navigator.pop(context);
                  },
                  child: const Text('Tải bản mới'),
                ),
              if (widget.supported && _error != null && info.downloadUrl != null)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => launchUrl(Uri.parse(info.downloadUrl!), mode: LaunchMode.externalApplication),
                  child: const Text('Tải thủ công'),
                ),
            ],
    );
  }
}
