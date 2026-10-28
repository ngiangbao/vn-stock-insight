import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/updater.dart';

void showUpdateDialog(BuildContext context, UpdateInfo info) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Có phiên bản mới ${info.latest}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Bạn đang dùng ${info.current}.'),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Thay đổi:', style: Theme.of(c).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(info.notes.trim()),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Để sau')),
        if (info.downloadUrl == null || info.downloadUrl != info.pageUrl)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(info.pageUrl), mode: LaunchMode.externalApplication),
            child: const Text('Xem trên GitHub'),
          ),
        if (info.downloadUrl != null)
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(info.downloadUrl!), mode: LaunchMode.externalApplication);
              Navigator.pop(c);
            },
            child: const Text('Tải bản mới'),
          ),
      ],
    ),
  );
}
