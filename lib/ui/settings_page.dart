import 'package:flutter/material.dart';

import '../ai/providers.dart';
import '../services/ssi.dart';
import '../services/updater.dart';
import '../state.dart';
import 'lan_section.dart';
import 'local_models_page.dart';
import 'update_dialog.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _ssiId = TextEditingController();
  final _ssiSecret = TextEditingController();
  bool _ssiLoaded = false, _ssiShow = false, _ssiBusy = false;
  String? _ssiStatus;
  bool _ssiOk = false;
  String? _loadedFor;
  List<String> _models = [];
  bool _busy = false, _showKey = false;
  String? _status;
  bool _statusOk = false;
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    currentVersion().then((v) => mounted ? setState(() => _version = v) : null);
  }

  void _syncFields(AppState state) {
    if (!_ssiLoaded) {
      _ssiLoaded = true;
      _ssiId.text = state.ssiId;
      _ssiSecret.text = state.ssiSecret;
    }
    if (_loadedFor == state.providerId) return;
    _loadedFor = state.providerId;
    _url.text = state.baseUrlOf(state.providerId);
    _key.text = state.keyOf(state.providerId);
    _model.text = state.modelOf(state.providerId);
    _models = state.provider.suggestedModels.toList();
    _status = null;
  }

  Future<void> _save(AppState state) =>
      state.setProviderConfig(state.providerId, baseUrl: _url.text, apiKey: _key.text, model: _model.text);

  Future<void> _loadModels(AppState state) async {
    await _save(state);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final list = await listModels(state.aiConfig);
      setState(() {
        _models = list;
        _statusOk = true;
        _status = 'Kết nối thành công: ${list.length} model.';
        if (_model.text.isEmpty && list.isNotEmpty) _model.text = list.first;
      });
      await _save(state);
    } catch (e) {
      setState(() {
        _statusOk = false;
        _status = e.toString();
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveSsi(AppState state) => state.setSsi(id: _ssiId.text, secret: _ssiSecret.text);

  Future<void> _testSsi(AppState state) async {
    await _saveSsi(state);
    setState(() {
      _ssiBusy = true;
      _ssiStatus = null;
    });
    final r = await SsiSource.instance.test();
    if (mounted) {
      setState(() {
        _ssiBusy = false;
        _ssiOk = r.ok;
        _ssiStatus = r.message;
      });
    }
  }

  Widget _ssiSection(AppState state, TextTheme text) {
    final ssi = SsiSource.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dùng SSI FastConnect cho giá cổ phiếu trong phiên'),
          subtitle: const Text('Tùy chọn. Cần tài khoản SSI và khóa FastConnect Data; khi SSI lỗi, app tự dùng nguồn mặc định.'),
          value: state.ssiEnabled,
          onChanged: (v) async {
            await _saveSsi(state);
            await state.setSsi(enabled: v);
          },
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (f) => f ? null : _saveSsi(state),
          child: TextField(
            controller: _ssiId,
            decoration: const InputDecoration(labelText: 'ConsumerID'),
            onEditingComplete: () => _saveSsi(state),
          ),
        ),
        const SizedBox(height: 12),
        Focus(
          onFocusChange: (f) => f ? null : _saveSsi(state),
          child: TextField(
            controller: _ssiSecret,
            obscureText: !_ssiShow,
            decoration: InputDecoration(
              labelText: 'ConsumerSecret',
              suffixIcon: IconButton(
                icon: Icon(_ssiShow ? Icons.visibility_off : Icons.visibility),
                tooltip: _ssiShow ? 'Ẩn' : 'Hiện',
                onPressed: () => setState(() => _ssiShow = !_ssiShow),
              ),
            ),
            onEditingComplete: () => _saveSsi(state),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lấy khóa: đăng ký dịch vụ API với SSI (quầy hoặc môi giới), rồi tạo khóa ở mục Dịch vụ API trên iBoard (khóa chỉ hiện một lần). '
          'Khóa được lưu trong kho khóa bảo mật của máy bạn.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _ssiBusy ? null : () => _testSsi(state),
              child: _ssiBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Kiểm tra kết nối SSI'),
            ),
            if (_ssiStatus != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _ssiOk ? Icons.check_circle_outline : Icons.error_outline,
                      size: 18,
                      color: _ssiOk ? Tone.up(context) : Tone.down(context),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(_ssiStatus!, style: text.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
        if (_ssiStatus == null && state.ssiEnabled && ssi.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Lần gọi gần nhất lỗi: ${ssi.lastError}', style: text.bodySmall?.copyWith(color: Tone.flat(context))),
          ),
        if (_ssiStatus == null && state.ssiEnabled && ssi.lastError == null && ssi.lastOk != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Đang dùng giá SSI, lần gần nhất ${timeLocal(ssi.lastOk!)}.', style: text.bodySmall),
          ),
      ],
    );
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await checkForUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        showUpdateDialog(context, info);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bạn đang dùng phiên bản mới nhất (${info.current}).')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không kiểm tra được cập nhật: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _syncFields(state);
    final p = state.provider;
    final text = Theme.of(context).textTheme;

    Widget section(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );

    return PageFrame(
      title: 'Cài đặt',
      children: [
        section('Giao diện', [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Hệ thống')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Sáng')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Tối')),
            ],
            // Không hiện thêm dấu tick (đã có nền chọn) để vừa màn hình 375 px; chiều cao chạm tối thiểu 48
            showSelectedIcon: false,
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 48))),
            selected: {state.themeMode},
            onSelectionChanged: (s) => state.setTheme(s.first),
          ),
          const SizedBox(height: 14),
          Text('Cỡ giao diện', style: text.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(label: const Text('Tự động'), selected: state.uiScale == null, onSelected: (_) => state.setUiScale(null)),
              for (final s in AutoScale.presets)
                ChoiceChip(
                  label: Text('${(s * 100).round()}%'),
                  selected: state.uiScale != null && (state.uiScale! - s).abs() < 0.01,
                  onSelected: (_) => state.setUiScale(s),
                ),
              if (state.uiScale != null && !AutoScale.presets.any((s) => (state.uiScale! - s).abs() < 0.01))
                ChoiceChip(label: Text('${(state.uiScale! * 100).round()}%'), selected: true, onSelected: (_) {}),
            ],
          ),
          const SizedBox(height: 4),
          Text('Phím tắt: Ctrl + / Ctrl − để phóng to/thu nhỏ, Ctrl 0 để trở về Tự động.', style: text.bodySmall),
          if (state.uiScale == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tự co giãn nhẹ theo chiều rộng cửa sổ'),
              subtitle: const Text('Ở chế độ Tự động: giao diện co giãn trong khoảng 85–115% khi đổi kích thước cửa sổ'),
              value: state.autoScale,
              onChanged: state.setAutoScale,
            ),
        ]),
        const SizedBox(height: 14),
        section('AI', [
          DropdownButtonFormField<String>(
            initialValue: state.providerId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nhà cung cấp'),
            items: [
              for (final x in providers)
                DropdownMenuItem(
                  value: x.id,
                  child: Row(
                    children: [
                      Icon(x.local ? Icons.computer : Icons.cloud_outlined, size: 18),
                      const SizedBox(width: 8),
                      // Co lại và cắt bằng "…" khi tên dài hoặc màn hình hẹp / cỡ chữ lớn
                      Expanded(child: Text(x.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              _save(state);
              state.setProvider(id);
            },
          ),
          if (p.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(p.note, style: text.bodySmall),
            ),
          if (p.id == 'embedded') ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory),
              title: Text(state.embeddedModel?.split(RegExp(r'[/\\]')).last ?? 'Chưa chọn model'),
              subtitle: const Text('Model GGUF chạy ngay trong app'),
              trailing: FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocalModelsPage())),
                child: Text(state.embeddedModel == null ? 'Tải & chọn model' : 'Đổi model'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Focus(
              onFocusChange: (f) => f ? null : _save(state),
              child: TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'Địa chỉ API (base URL)'),
                onEditingComplete: () => _save(state),
              ),
            ),
            if (p.needsKey || p.id == 'custom') ...[
              const SizedBox(height: 12),
              // Lưu cả khi rời ô nhập (bấm ra ngoài, nhấn Tab), không chỉ khi nhấn Enter: dán key rồi bấm ra ngoài vẫn được lưu
              Focus(
                onFocusChange: (f) => f ? null : _save(state),
                child: TextField(
                  controller: _key,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    labelText: p.needsKey ? 'API key' : 'API key (nếu có)',
                    helperText: p.keyHint.isEmpty ? null : p.keyHint,
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                      tooltip: _showKey ? 'Ẩn API key' : 'Hiện API key',
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                  onEditingComplete: () => _save(state),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
              if (!state.secureStorageOk)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Máy này không có kho khóa bảo mật (keyring), API key được lưu trong cài đặt của app.',
                    style: text.bodySmall?.copyWith(color: Tone.flat(context)),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    key: ValueKey('model-${state.providerId}-${_models.length}'),
                    initialValue: TextEditingValue(text: _model.text),
                    optionsBuilder: (v) => _models.where((m) => m.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (v) {
                      _model.text = v;
                      _save(state);
                    },
                    fieldViewBuilder: (context, controller, focus, onSubmit) {
                      return TextField(
                        controller: controller,
                        focusNode: focus,
                        onChanged: (v) => _model.text = v,
                        decoration: const InputDecoration(labelText: 'Model', helperText: 'Gõ để tìm, hoặc bấm "Tải danh sách"'),
                        onEditingComplete: () {
                          onSubmit();
                          _save(state);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : OutlinedButton(onPressed: () => _loadModels(state), child: const Text('Tải danh sách')),
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!, style: TextStyle(color: _statusOk ? Tone.up(context) : Tone.down(context))),
              ),
          ],
          if (p.style == ApiStyle.anthropic) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: state.effort,
              decoration: const InputDecoration(
                labelText: 'Mức suy nghĩ (effort)',
                helperText: 'Cao hơn: phân tích kỹ hơn nhưng lâu và tốn hơn',
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Thấp')),
                DropdownMenuItem(value: 'medium', child: Text('Trung bình')),
                DropdownMenuItem(value: 'high', child: Text('Cao')),
              ],
              onChanged: (v) => v == null ? null : state.setEffort(v),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  await _save(state);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu. AI đang dùng: ${state.aiLabel}')));
                  }
                },
                child: const Text('Lưu'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocalModelsPage())),
                icon: const Icon(Icons.memory),
                label: const Text('Model trên máy: đánh giá cấu hình & tải model'),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 14),
        const LanSection(),
        const SizedBox(height: 14),
        section('Nguồn giá SSI (tùy chọn)', [_ssiSection(state, text)]),
        const SizedBox(height: 14),
        section('Cập nhật', [
          Text('Phiên bản hiện tại: ${_version.isEmpty ? '…' : _version}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tự kiểm tra cập nhật khi mở app'),
            value: state.autoCheckUpdates,
            onChanged: state.setAutoCheckUpdates,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _checking ? null : _checkUpdate,
              icon: _checking
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update),
              label: const Text('Kiểm tra cập nhật'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          'Dữ liệu giá: DNSE/VNDirect. Số liệu tài chính: Vietcap IQ. Tin tức: CafeF, Vietstock, VnExpress, VnEconomy, '
          'Tin nhanh chứng khoán. $disclaimer',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
