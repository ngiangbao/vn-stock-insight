import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'services/updater.dart';
import 'state.dart';
import 'ui/macro_page.dart';
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
  // Navy for navigation and actions; reserve green/red for market movement.
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF163A5F),
    brightness: brightness,
    surface: dark ? const Color(0xFF111923) : const Color(0xFFF3F6FA),
  ).copyWith(
    primary: dark ? const Color(0xFF82B7E8) : const Color(0xFF163A5F),
    onPrimary: dark ? const Color(0xFF102033) : Colors.white,
    secondary: dark ? const Color(0xFF8FAFCB) : const Color(0xFF526B84),
    surfaceContainerLowest: dark ? const Color(0xFF151F2B) : Colors.white,
  );
  final outline = dark ? const Color(0xFF2B3948) : const Color(0xFFDCE4ED);
  final card = dark ? const Color(0xFF182331) : Colors.white;
  final textTheme = ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamily: 'Roboto',
      ).copyWith(
        bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
        bodySmall: const TextStyle(fontSize: 12, height: 1.4),
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.25),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
  return ThemeData(
    colorScheme: scheme,
    textTheme: textTheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      // Màu chữ phải đặt rõ ràng: titleLarge của app không có màu nên tiêu đề trắng trên nền sáng (không đọc được)
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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

/// Theme của app (công khai để kiểm thử độ tương phản màu ở cả hai chế độ sáng/tối).
ThemeData appTheme(Brightness brightness) => _theme(brightness);

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
    (Icons.account_balance_outlined, Icons.account_balance, 'Vĩ mô'),
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
        final app = AppScope.of(context);
        await app.lan.server.stop();
        await app.runtime.stop();
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
      MacroPage(active: _tab == _macroTab),
      const NewsPage(),
      const SettingsPage(),
    ];
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final body = IndexedStack(index: _tab, children: pages);

    if (width >= 1100) {
      return Scaffold(
        body: Column(children: [
          _DesktopHeader(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: _destinations,
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ]),
      );
    }

    if (wide) {
      return Scaffold(
        body: Row(children: [
          // Cuộn được khi cửa sổ thấp để không tràn khi có nhiều mục
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
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
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    // Điện thoại: thanh dưới tối đa 5 mục. 4 mục chính + "Thêm" (Tin tức, Cài đặt)
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab < _primaryCount ? _tab : _primaryCount,
        onDestinationSelected: (i) => i < _primaryCount ? setState(() => _tab = i) : _openMore(),
        destinations: [
          for (final d in _destinations.take(_primaryCount))
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Thêm'),
        ],
      ),
    );
  }

  static const _macroTab = 3; // vị trí của 'Vĩ mô' trong _destinations

  /// Số mục hiện thẳng trên thanh dưới của điện thoại; các mục còn lại nằm trong "Thêm".
  static const _primaryCount = 4;

  Future<void> _openMore() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = _primaryCount; i < _destinations.length; i++)
            ListTile(
              leading: Icon(_destinations[i].$1),
              title: Text(_destinations[i].$3),
              selected: _tab == i,
              onTap: () => Navigator.pop(c, i),
            ),
        ]),
      ),
    );
    if (picked != null && mounted) setState(() => _tab = picked);
  }
}

class _DesktopHeader extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<(IconData, IconData, String)> destinations;

  const _DesktopHeader({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      child: SizedBox(
        height: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.show_chart_rounded, color: cs.onPrimary, size: 23),
            ),
            const SizedBox(width: 10),
            Text(
              'VN Stock Insight',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 22),
            const VerticalDivider(width: 1, indent: 14, endIndent: 14),
            const SizedBox(width: 14),
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _DesktopNavItem(
                  icon: selectedIndex == i ? destinations[i].$2 : destinations[i].$1,
                  label: destinations[i].$3,
                  selected: selectedIndex == i,
                  onTap: () => onDestinationSelected(i),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 19, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
