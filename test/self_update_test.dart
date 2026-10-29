import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/self_update.dart';
import 'package:vn_stock_insight/services/updater.dart';
import 'package:vn_stock_insight/ui/update_dialog.dart';

const _all = [
  ('vn-stock-insight-v2.7.0-windows-x64-portable.zip', 'https://x/portable.zip'),
  ('vn-stock-insight-v2.7.0-windows-x64-setup.exe', 'https://x/setup.exe'),
  ('vn-stock-insight-v2.7.0-macos.pkg', 'https://x/mac.pkg'),
  ('vn-stock-insight-v2.7.0-macos.zip', 'https://x/mac.zip'),
  ('vn-stock-insight-v2.7.0-linux-x64.tar.gz', 'https://x/linux.tar.gz'),
  ('vn-stock-insight-v2.7.0.apk', 'https://x/app.apk'),
  ('SHA256SUMS.txt', 'https://x/sums'),
];

void main() {
  test('chọn đúng file cho từng nền tảng: tải thủ công, cập nhật tự động, SHA256SUMS', () {
    final w = pickAssets(_all, platform: 'windows');
    expect(w.manual, 'https://x/setup.exe');
    expect(w.auto, 'https://x/setup.exe');
    final m = pickAssets(_all, platform: 'macos');
    expect(m.manual, 'https://x/mac.pkg', reason: 'tải thủ công vẫn là .pkg');
    expect(m.auto, 'https://x/mac.zip', reason: 'cập nhật tự động dùng .app nén');
    final l = pickAssets(_all, platform: 'linux');
    expect(l.auto, 'https://x/linux.tar.gz');
    final a = pickAssets(_all, platform: '.apk');
    expect(a.manual, 'https://x/app.apk');
    expect(a.auto, isNull, reason: 'Android không tự cập nhật');
    expect(w.checksums, 'https://x/sums');
    expect(pickAssets(const [], platform: 'windows').auto, isNull);
  });

  test('đọc SHA256SUMS.txt', () {
    final h = 'a' * 64, g = 'B' * 64;
    final m = parseChecksums('$h  file-one.zip\n$g *dir/file-two.exe\nrác không phải mã\n');
    expect(m['file-one.zip'], h);
    expect(m['file-two.exe'], g.toLowerCase());
    expect(m.length, 2);
  });

  test('tham số bộ cài Windows chạy ngầm, không khởi động lại máy', () {
    expect(windowsInstallerArgs, containsAll(['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS']));
  });

  test('script macOS: đợi app thoát, sao lưu, thay .app, bỏ cờ cách ly, khôi phục khi lỗi, quote đường dẫn có dấu nháy', () {
    final s = macosUpdateScript(pid: 4242, newApp: "/tmp/new/VN Stock Insight.app", targetApp: "/Applications/Tom's App.app");
    expect(s, contains('PID=4242'));
    expect(s, contains("TARGET='/Applications/Tom'\\''s App.app'"));
    expect(s, contains('kill -0'));
    expect(s, contains('ditto'));
    expect(s, contains('xattr -cr'));
    expect(s, contains('mv "\$OLD" "\$TARGET"'), reason: 'khôi phục khi thay lỗi');
    expect(s, contains('open "\$TARGET"'));
    expect(runningAppBundle('/Applications/VN Stock Insight.app/Contents/MacOS/vn_stock_insight'), '/Applications/VN Stock Insight.app');
    expect(runningAppBundle('/usr/bin/dart'), isNull);
  });

  test('script Linux chạy thật: chép đè bản mới, giữ dữ liệu khác và mở lại app', () async {
    final root = await Directory.systemTemp.createTemp('vnsi-upd');
    final target = Directory('${root.path}/install')..createSync();
    final newDir = Directory('${root.path}/new/vn-stock-insight')..createSync(recursive: true);
    File('${target.path}/data.keep').writeAsStringSync('của người dùng');
    File('${target.path}/old.txt').writeAsStringSync('cũ');
    File('${newDir.path}/old.txt').writeAsStringSync('mới');
    File('${newDir.path}/extra.txt').writeAsStringSync('thêm');
    final marker = File('${root.path}/started.marker');
    // "app" giả: ghi dấu khi được mở lại. Bản cũ và bản mới cùng tên file chạy.
    for (final d in [target, newDir]) {
      File('${d.path}/app.sh').writeAsStringSync('#!/bin/sh\necho started > "${marker.path}"\n');
      await Process.run('chmod', ['+x', '${d.path}/app.sh']);
    }
    // pid của một tiến trình đã kết thúc
    final dead = await Process.start('true', []);
    await dead.exitCode;
    final script = File('${root.path}/update.sh')
      ..writeAsStringSync(linuxUpdateScript(pid: dead.pid, newDir: newDir.path, targetDir: target.path, exe: '${target.path}/app.sh'));
    final r = await Process.run('sh', [script.path]);
    expect(r.exitCode, 0);
    for (var i = 0; i < 40 && !marker.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(File('${target.path}/old.txt').readAsStringSync(), 'mới');
    expect(File('${target.path}/extra.txt').readAsStringSync(), 'thêm');
    expect(File('${target.path}/data.keep').readAsStringSync(), 'của người dùng');
    expect(marker.existsSync(), isTrue, reason: 'app được mở lại');
    expect(newDir.existsSync(), isFalse, reason: 'dọn thư mục tạm');
    await root.delete(recursive: true);
  });

  group('tải và kiểm tra (Linux)', () {
    late HttpServer server;
    late Directory root;
    late List<int> tarBytes;
    String? sums;

    setUp(() async {
      HttpOverrides.global = null; // bộ test mặc định trả HTTP 400 cho mọi yêu cầu mạng; ở đây dùng máy chủ cục bộ thật
      root = await Directory.systemTemp.createTemp('vnsi-dl');
      // gói .tar.gz thật có thư mục vn-stock-insight/
      final src = Directory('${root.path}/src/vn-stock-insight')..createSync(recursive: true);
      File('${src.path}/hello.txt').writeAsStringSync('xin chào');
      await Process.run('tar', ['-czf', '${root.path}/pkg.tar.gz', '-C', '${root.path}/src', 'vn-stock-insight']);
      tarBytes = File('${root.path}/pkg.tar.gz').readAsBytesSync();
      sums = '${sha256.convert(tarBytes)}  vn-stock-insight-v9.9.9-linux-x64.tar.gz\n';
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        if (req.uri.path.endsWith('.tar.gz')) {
          req.response.contentLength = tarBytes.length;
          req.response.add(tarBytes);
        } else if (req.uri.path.endsWith('sums.txt') && sums != null) {
          req.response.write(sums);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });

    UpdateInfo info() => UpdateInfo(
      '1.0.0',
      '9.9.9',
      '',
      'https://x',
      null,
      autoUrl: 'http://127.0.0.1:${server.port}/vn-stock-insight-v9.9.9-linux-x64.tar.gz',
      checksumsUrl: 'http://127.0.0.1:${server.port}/sums.txt',
    );

    test('tải đúng file, báo tiến độ, giao script cho launcher rồi thoát app', () async {
      if (!Platform.isLinux) return;
      final stages = <UpdateStage>[];
      double? last;
      String? launched;
      var exited = false;
      await applyUpdate(
        info(),
        workDir: Directory('${root.path}/work'),
        exitApp: () async => exited = true,
        onProgress: (s, p) {
          if (stages.isEmpty || stages.last != s) stages.add(s);
          if (s == UpdateStage.downloading && p != null) last = p;
        },
        launcher: (exe, args) async => launched = args.join(' '),
        currentPid: 12345,
      );
      expect(stages, [UpdateStage.downloading, UpdateStage.verifying, UpdateStage.installing]);
      expect(last, 1.0);
      expect(exited, isTrue);
      expect(launched, endsWith('update.sh'));
      final script = File('${root.path}/work/update.sh').readAsStringSync();
      expect(script, contains('PID=12345'));
      expect(File('${root.path}/work/app/vn-stock-insight/hello.txt').readAsStringSync(), 'xin chào');
    });

    test('mã SHA-256 sai: hủy, không chạy script, không thoát app', () async {
      if (!Platform.isLinux) return;
      sums = '${'0' * 64}  vn-stock-insight-v9.9.9-linux-x64.tar.gz\n';
      var launched = false, exited = false;
      await expectLater(
        applyUpdate(
          info(),
          workDir: Directory('${root.path}/work'),
          exitApp: () async => exited = true,
          launcher: (_, _) async => launched = true,
        ),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('không khớp'))),
      );
      expect(launched, isFalse);
      expect(exited, isFalse);
    });

    test('thiếu SHA256SUMS hoặc thiếu mã cho file: hủy, không cài file không kiểm tra được', () async {
      if (!Platform.isLinux) return;
      sums = null; // máy chủ trả 404
      await expectLater(
        applyUpdate(info(), workDir: Directory('${root.path}/w1'), exitApp: () async {}, launcher: (_, _) async {}),
        throwsA(isA<UpdateException>()),
      );
      sums = '${'1' * 64}  file-khac.tar.gz\n';
      await expectLater(
        applyUpdate(info(), workDir: Directory('${root.path}/w2'), exitApp: () async {}, launcher: (_, _) async {}),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('không có mã'))),
      );
      await expectLater(
        applyUpdate(UpdateInfo('1.0.0', '9.9.9', '', 'https://x', null), exitApp: () async {}),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('không hỗ trợ'))),
      );
    });
  });

  group('hộp thoại cập nhật', () {
    UpdateInfo info({String? auto}) => UpdateInfo(
      '2.6.1',
      '2.7.0',
      'Thay đổi A',
      'https://github.com/x/releases',
      'https://github.com/x/setup.exe',
      autoUrl: auto,
      checksumsUrl: 'https://x/sums',
    );

    Future<void> open(
      WidgetTester tester,
      UpdateInfo i, {
      bool supported = true,
      Future<void> Function(UpdateInfo, Progress)? apply,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showUpdateDialog(c, i, apply: apply, supported: supported),
              child: const Text('mở'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('máy hỗ trợ: nút Cập nhật ngay, hiện tiến độ từng bước', (tester) async {
      final gate = Completer<void>();
      await open(
        tester,
        info(auto: 'https://x/a'),
        apply: (i, onP) async {
          onP(UpdateStage.downloading, 0.4);
          await gate.future;
        },
      );
      expect(find.text('Có phiên bản mới 2.7.0'), findsOneWidget);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Cập nhật ngay')).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Cập nhật ngay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Đang tải bản mới…'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('Để sau'), findsNothing, reason: 'đang cập nhật thì khóa nút');
      gate.complete();
      await tester.pump();
    });

    testWidgets('lỗi: hiện lý do, cho thử lại hoặc tải thủ công', (tester) async {
      await open(
        tester,
        info(auto: 'https://x/a'),
        apply: (i, onP) async => throw UpdateException('Mã SHA-256 của file tải về không khớp'),
      );
      await tester.tap(find.text('Cập nhật ngay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('không khớp'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.text('Tải thủ công'), findsOneWidget);
      expect(find.text('Để sau'), findsOneWidget);
    });

    testWidgets('máy không hỗ trợ cập nhật tự động: vẫn có nút Tải bản mới', (tester) async {
      await open(tester, info(), supported: false);
      expect(find.text('Cập nhật ngay'), findsNothing);
      expect(find.text('Tải bản mới'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
