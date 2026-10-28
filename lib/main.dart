import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'services/updater.dart';
import 'state.dart';
import 'ui/news_page.dart';
import 'ui/overview_page.dart';
import 'ui/screener_page.dart';
import 'ui/settings_page.dart';
import 'ui/update_dialog.dart';
import 'ui/watchlist_page.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(AppScope(state: state, child: const StockApp()));
  state.refresh();
}

ThemeData _theme(Brightness brightness) {
  // Bảng màu tài chính: xanh ngọc chuyên nghiệp, nền dịu; xanh/đỏ dành riêng
  // cho sắc thái tăng giảm giá trong Tone.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF087F5B),
    brightness: brightness,
    surface: brightness == Brightness.light ? const Color(0xFFF7F9FC) : const Color(0xFF111820),
  );
  final outline = brightness == Brightness.light ? const Color(0xFFE1E7ED) : const Color(0xFF2C3742);
  final textTheme = ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamily: 'Roboto',
      );
  return ThemeData(
    colorScheme: scheme,
    textTheme: textTheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: brightness == Brightness.light ? Colors.white : const Color(0xFF18212B),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: outline)),
      isDense: true,
    ),
    visualDensity: VisualDensity.standard,
  );
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return MaterialApp(
      title: 'VN Stock Insight',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: state.themeMode,
      // Ctrl + / Ctrl - để phóng to/thu nhỏ giao diện, Ctrl 0 để trở về tự động
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () => state.setUiScale((state.uiScale ?? 1) + 0.1),
          const SingleActivator(LogicalKeyboardKey.add, control: true): () => state.setUiScale((state.uiScale ?? 1) + 0.1),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () => state.setUiScale((state.uiScale ?? 1) - 0.1),
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => state.setUiScale(null),
        },
        child: AutoScale(enabled: state.autoScale, manual: state.uiScale, child: child!),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  static const _destinations = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Tổng quan'),
    (Icons.star_outline, Icons.star, 'Theo dõi'),
    (Icons.filter_list, Icons.filter_list, 'Bộ lọc'),
    (Icons.newspaper_outlined, Icons.newspaper, 'Tin tức'),
    (Icons.settings_outlined, Icons.settings, 'Cài đặt'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
    // Tắt engine chạy model khi đóng app để không để lại tiến trình chạy ngầm
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await AppScope.of(context).runtime.stop();
        return AppExitResponse.exit;
      },
      onDetach: () => AppScope.of(context).runtime.killNow(),
    );
  }

  Future<void> _autoCheckUpdate() async {
    if (!AppScope.of(context).autoCheckUpdates) return;
    try {
      final info = await checkForUpdate();
      if (info.hasUpdate && mounted) showUpdateDialog(context, info);
    } catch (_) {
      // Không có mạng hoặc GitHub lỗi: bỏ qua, người dùng vẫn kiểm tra thủ công được trong Cài đặt
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const OverviewPage(),
      const WatchlistPage(),
      const ScreenerPage(),
      const NewsPage(),
      const SettingsPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = IndexedStack(index: _tab, children: pages);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.show_chart, size: 30),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
