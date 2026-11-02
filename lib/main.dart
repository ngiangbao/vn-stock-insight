import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'services/updater.dart';
import 'state.dart';
import 'ui/cfa_page.dart';
import 'ui/floating_chat.dart';
import 'ui/asset_pages.dart';
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

/// Token thiết kế: nền gradient kem hồng (sáng) hoặc xanh rêu đậm (tối), thẻ bo góc lớn bóng mềm, màu nhấn xanh lục đậm.
/// Cặp màu chữ/nền đều đạt tương phản tối thiểu 4,5:1 trên cả hai đầu của gradient (xem test/theme_test.dart).
class Ds {
  static const lightBg = [
    Color(0xFFF7F1EA),
    Color(0xFFF2E4DD),
    Color(0xFFEBD6D0),
  ];
  static const darkBg = [
    Color(0xFF0D1411),
    Color(0xFF111A16),
    Color(0xFF16191A),
  ];
  static const lightCard = Color(0xFFFFFFFF);
  static const darkCard = Color(0xFF17221D);
  static const lightText = Color(0xFF1C2822);
  static const lightMuted = Color(0xFF55615A);
  static const darkText = Color(0xFFE8F0EB);
  static const darkMuted = Color(0xFFA7B6AD);
  static const lightPrimary = Color(0xFF1E5A3F);
  static const darkPrimary = Color(0xFF7FD1A4);
  static const lightOutline = Color(0xFFE6DAD2);
  static const darkOutline = Color(0xFF28372F);
  static const radius = 22.0;

  static BoxDecoration background(Brightness b) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: b == Brightness.dark ? darkBg : lightBg,
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  // Xanh lục đậm cho điều hướng và hành động; xanh/đỏ dành riêng cho biến động thị trường.
  final dark = brightness == Brightness.dark;
  final primary = dark ? Ds.darkPrimary : Ds.lightPrimary;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Ds.lightPrimary,
        brightness: brightness,
        surface: dark ? const Color(0xFF111A16) : const Color(0xFFF6EFE8),
      ).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF08261A) : Colors.white,
        secondary: dark ? const Color(0xFF9CC9B2) : const Color(0xFF4F6B5C),
        onSurface: dark ? Ds.darkText : Ds.lightText,
        onSurfaceVariant: dark ? Ds.darkMuted : Ds.lightMuted,
        surfaceContainerLowest: dark ? Ds.darkCard : Ds.lightCard,
        surfaceContainerHighest: dark
            ? const Color(0xFF223029)
            : const Color(0xFFF0E7E0),
        outlineVariant: dark ? Ds.darkOutline : Ds.lightOutline,
      );
  final outline = dark ? Ds.darkOutline : Ds.lightOutline;
  final card = dark ? Ds.darkCard : Ds.lightCard;
  final textTheme = ThemeData(brightness: brightness).textTheme
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamily: 'Roboto',
      )
      .copyWith(
        bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
        bodySmall: const TextStyle(fontSize: 12, height: 1.4),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
  final pill = StadiumBorder(side: BorderSide(color: outline));
  return ThemeData(
    colorScheme: scheme,
    textTheme: textTheme,
    useMaterial3: true,
    // Trong suốt để nền gradient của app (xem StockApp.builder) lộ ra phía sau mọi trang, kể cả trang mở bằng Navigator
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ds.radius),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // Màu chữ phải đặt rõ ràng: titleLarge của app không có màu nên tiêu đề trắng trên nền sáng (không đọc được)
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: card.withValues(alpha: dark ? 0.92 : 0.94),
      surfaceTintColor: Colors.transparent,
      shadowColor: dark ? Colors.black : const Color(0xFF5A3A2A),
      elevation: dark ? 0 : 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ds.radius),
        side: BorderSide(color: outline.withValues(alpha: 0.7)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: outline),
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      checkmarkColor: scheme.primary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      dividerColor: outline,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
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
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              state.setUiScale((state.uiScale ?? 1) + 0.1),
          const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
              state.setUiScale((state.uiScale ?? 1) + 0.1),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              state.setUiScale((state.uiScale ?? 1) - 0.1),
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
              state.setUiScale(null),
        },
        child: AutoScale(
          enabled: state.autoScale,
          manual: state.uiScale,
          child: DecoratedBox(
            decoration: Ds.background(Theme.of(context).brightness),
            child: Overlay.wrap(child: FloatingFinanceChat(child: child!)),
          ),
        ),
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
  final _visited = <int>{0};

  void _select(int index) => setState(() {
    _tab = index;
    _visited.add(index);
  });
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
    (Icons.school_outlined, Icons.school, 'CFA'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Trái phiếu'),
    (Icons.pie_chart_outline, Icons.pie_chart, 'Quỹ'),
    (Icons.swap_vert, Icons.swap_vert, 'Phái sinh'),
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
      const CfaPage(),
      _visited.contains(4)
          ? BondsPage(active: _tab == 4)
          : const SizedBox.shrink(),
      _visited.contains(5)
          ? ListedFundsPage(active: _tab == 5)
          : const SizedBox.shrink(),
      _visited.contains(6)
          ? DerivativesPage(active: _tab == 6)
          : const SizedBox.shrink(),
      MacroPage(active: _tab == _macroTab),
      const NewsPage(),
      const SettingsPage(),
    ];
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final body = IndexedStack(index: _tab, children: pages);

    if (wide) {
      // Thanh icon dọc nổi bên trái (bo góc, bóng mềm) cho mọi cửa sổ từ 760 px trở lên
      return Scaffold(
        body: Row(
          children: [
            _FloatingRail(
              selectedIndex: _tab,
              onSelected: _select,
              destinations: _destinations,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    // Điện thoại: 4 mục chính và "Thêm" chứa các thị trường mới cùng tiện ích.
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab < _primaryCount ? _tab : _primaryCount,
        onDestinationSelected: (i) =>
            i < _primaryCount ? _select(i) : _openMore(),
        destinations: [
          for (final d in _destinations.take(_primaryCount))
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'Thêm',
          ),
        ],
      ),
    );
  }

  static const _macroTab = 7; // vị trí của 'Vĩ mô' trong _destinations

  /// Số mục hiện thẳng trên thanh dưới của điện thoại; các mục còn lại nằm trong "Thêm".
  static const _primaryCount = 4;

  Future<void> _openMore() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = _primaryCount; i < _destinations.length; i++)
                ListTile(
                  leading: Icon(_destinations[i].$1),
                  title: Text(_destinations[i].$3),
                  selected: _tab == i,
                  onTap: () => Navigator.pop(c, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _select(picked);
  }
}

/// Thanh icon dọc nổi: logo, 7 mục chính (icon trên nhãn), menu "Thêm" cho các mục còn lại. Mục đang chọn là viên xanh lục đậm.
/// Mỗi mục rộng 72 × cao 64 px (≥ 48 px) và cuộn được khi cửa sổ thấp.
class _FloatingRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, IconData, String)> destinations;

  const _FloatingRail({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withValues(alpha: dark ? 0.94 : 0.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: (dark ? Colors.black : const Color(0xFF5A3A2A)).withValues(
                alpha: dark ? 0.4 : 0.10,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Semantics(
                      label: 'VN Stock Insight',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.show_chart_rounded,
                          color: cs.onPrimary,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < 7; i++)
                      _RailItem(
                        icon: selectedIndex == i
                            ? destinations[i].$2
                            : destinations[i].$1,
                        label: destinations[i].$3,
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                    const Spacer(),
                    AppMoreMenu(
                      selectedIndex: selectedIndex,
                      onSelected: onSelected,
                      destinations: destinations,
                      vertical: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 72,
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: fg),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hover, click and keyboard accessible menu; delay bridges the gap to the overlay.
class AppMoreMenu extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, IconData, String)> destinations;

  /// Hiển thị như một mục của thanh icon dọc (icon trên nhãn).
  final bool vertical;
  const AppMoreMenu({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.vertical = false,
  });

  @override
  State<AppMoreMenu> createState() => _AppMoreMenuState();
}

class _AppMoreMenuState extends State<AppMoreMenu> {
  final _controller = MenuController();
  final _firstItemFocus = FocusNode();
  Timer? _closeTimer;

  void _enter() {
    _closeTimer?.cancel();
    if (!_controller.isOpen) _controller.open();
  }

  void _leave() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _controller.isOpen) _controller.close();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _firstItemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isOpen) _firstItemFocus.requestFocus();
    }),
    menuChildren: [
      for (var i = 7; i < widget.destinations.length; i++)
        MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _leave(),
          child: MenuItemButton(
            focusNode: i == 7 ? _firstItemFocus : null,
            leadingIcon: Icon(widget.destinations[i].$1),
            trailingIcon: widget.selectedIndex == i
                ? const Icon(Icons.check, size: 18)
                : null,
            onPressed: () {
              _closeTimer?.cancel();
              widget.onSelected(i);
            },
            child: Text(widget.destinations[i].$3),
          ),
        ),
    ],
    builder: (context, controller, child) => MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _leave(),
      child: widget.vertical
          ? _RailItem(
              icon: Icons.more_horiz,
              label: widget.selectedIndex >= 7
                  ? widget.destinations[widget.selectedIndex].$3
                  : 'Thêm',
              selected: widget.selectedIndex >= 7,
              onTap: () {
                _closeTimer?.cancel();
                controller.isOpen ? controller.close() : controller.open();
              },
            )
          : TextButton.icon(
              onPressed: () {
                _closeTimer?.cancel();
                controller.isOpen ? controller.close() : controller.open();
              },
              icon: const Icon(Icons.more_horiz),
              label: Text(
                widget.selectedIndex >= 7
                    ? widget.destinations[widget.selectedIndex].$3
                    : 'Thêm',
              ),
            ),
    ),
  );
}
