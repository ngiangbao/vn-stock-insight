import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/corporate_bonds.dart';
import '../state.dart';
import 'widgets.dart';

class CorporateBondsPage extends StatefulWidget {
  final bool active;
  final CorporateBondRepository? repository;
  const CorporateBondsPage({super.key, this.active = true, this.repository});
  @override
  State<CorporateBondsPage> createState() => _CorporateBondsPageState();
}

class _CorporateBondsPageState extends State<CorporateBondsPage> {
  CorporateBondRepository? _repo;
  CorporateBondSnapshot? _snapshot;
  Timer? _timer;
  bool _loading = false, _ascending = true;
  String? _error;
  String _query = '', _filter = 'Tất cả từ nguồn';
  int _sort = 0, _page = 0;
  static const _pageSize = 30;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo =
          widget.repository ??
          CorporateBondRepository(
            cacheFile: File(
              '${AppScope.of(context).dataDir.path}${Platform.pathSeparator}corporate_bonds.json',
            ),
          );
      if (widget.active) _load();
      _timer = Timer.periodic(const Duration(minutes: 30), (_) {
        if (widget.active) _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CorporateBondsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.repository == null) _repo?.close();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (_loading || _repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repo!.load(force: force);
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _page = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Không tải được danh mục trái phiếu. Thử làm mới hoặc kiểm tra mạng.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _detail(CorporateBond b) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(b.code),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(b.issuer),
              const SizedBox(height: 12),
              Text('Mã gốc: ${b.originalCode.isEmpty ? '–' : b.originalCode}'),
              Text('ISIN: ${b.isin.isEmpty ? '–' : b.isin}'),
              Text(
                'Phát hành: ${_date(b.issued)} · Đáo hạn: ${_date(b.maturity)}',
              ),
              Text('Mệnh giá: ${fmt(b.faceValue, 0)} ${b.currency}'),
              Text(
                'Kỳ hạn theo nguồn: ${b.termLabel.isEmpty ? '–' : b.termLabel}',
              ),
              Text('Loại lãi suất: ${b.rateLabel}'),
              Text(
                'Điều khoản lãi suất theo tài liệu nguồn: ${b.rateDescription.isEmpty ? 'Chưa có dữ liệu' : b.rateDescription}',
              ),
              const SizedBox(height: 12),
              Text(
                'Trạng thái gốc từ VNDirect: ${b.sourceStatus.isEmpty ? 'Chưa rõ' : b.sourceStatus}',
              ),
              const Text(
                'Ngày đáo hạn không xác nhận trái phiếu đã được trả nợ. Chưa có dữ liệu khối lượng còn lưu hành và giá giao dịch trực tiếp.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(), query = _query.trim().toLowerCase();
    final rows =
        (_snapshot?.bonds ?? <CorporateBond>[]).where((b) {
          if (!'${b.code} ${b.originalCode} ${b.issuer} ${b.isin}'
              .toLowerCase()
              .contains(query)) {
            return false;
          }
          final days = b.remainingDays(now);
          return switch (_filter) {
            'Chưa đáo hạn' =>
              days != null && days >= 0 && b.sourceStatus != 'EXPIRED',
            'Đã đến hạn' => days != null && days < 0,
            'Thiếu ngày đáo hạn' => days == null,
            _ => true,
          };
        }).toList()..sort((a, b) {
          final value = switch (_sort) {
            1 => a.issuer.compareTo(b.issuer),
            2 => (a.faceValue ?? -1).compareTo(b.faceValue ?? -1),
            3 => (a.maturity ?? DateTime(9999)).compareTo(
              b.maturity ?? DateTime(9999),
            ),
            _ => a.code.compareTo(b.code),
          };
          return _ascending ? value : -value;
        });
    final pages = (rows.length / _pageSize).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    final visible = rows.skip(page * _pageSize).take(_pageSize);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Trái phiếu doanh nghiệp',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tự động tải toàn bộ các trang danh mục công khai VNDirect. Nguồn này chưa bao phủ toàn thị trường Việt Nam. Danh mục đầy đủ HNX yêu cầu đăng nhập; chưa kết nối tài khoản dữ liệu.',
        ),
        const SizedBox(height: 8),
        Text(
          _snapshot == null
              ? 'Chưa tải dữ liệu.'
              : '${_snapshot!.bonds.length} mã doanh nghiệp từ ${_snapshot!.sourceTotal} bản ghi nguồn (đã loại loại trái phiếu khác) · cập nhật ${timeVN(_snapshot!.fetchedAt)}${_snapshot!.cached ? ' · bản đã lưu' : ''}. Làm mới tự động tối đa mỗi 6 giờ khi đang dùng.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() {
                  _query = v;
                  _page = 0;
                }),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Tìm mã, ISIN hoặc tổ chức phát hành',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Làm mới trái phiếu',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in [
              'Chưa đáo hạn',
              'Tất cả từ nguồn',
              'Đã đến hạn',
              'Thiếu ngày đáo hạn',
            ])
              ChoiceChip(
                label: Text(filter),
                selected: filter == _filter,
                onSelected: (_) => setState(() {
                  _filter = filter;
                  _page = 0;
                }),
              ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null || _snapshot?.warning != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error ?? _snapshot!.warning!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: FlexTable(
            minWidth: 1450,
            columns: [
              for (final (i, label) in [
                'Mã',
                'Tổ chức phát hành',
                'Mệnh giá',
                'Ngày đáo hạn',
                'Còn lại (ngày)',
                'Loại lãi suất',
                'Thị trường',
                'Chi tiết',
              ].indexed)
                FlexCol(
                  label,
                  i == 1 ? 2 : 1,
                  align: Alignment.center,
                  ascending: _sort == i ? _ascending : null,
                  onSort: i < 4
                      ? () => setState(() {
                          _ascending = _sort == i ? !_ascending : true;
                          _sort = i;
                          _page = 0;
                        })
                      : null,
                ),
            ],
            rows: [
              for (final b in visible)
                FlexRow([
                  Text(b.code, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    b.issuer.isEmpty ? '–' : b.issuer,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    '${fmt(b.faceValue, 0)} ${b.currency}',
                    textAlign: TextAlign.center,
                  ),
                  Text(_date(b.maturity)),
                  Text(b.remainingDays(now)?.toString() ?? '–'),
                  Text(b.rateLabel),
                  Text(b.market.isEmpty ? '–' : b.market),
                  IconButton(
                    tooltip: 'Chi tiết ${b.code}',
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => _detail(b),
                  ),
                ], onTap: () => _detail(b)),
            ],
          ),
        ),
        if (!_loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Không có trái phiếu phù hợp với bộ lọc.'),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${rows.length} mã phù hợp · Trang ${pages == 0 ? 0 : page + 1}/$pages',
              ),
            ),
            IconButton(
              tooltip: 'Trang trước',
              onPressed: page > 0
                  ? () => setState(() => _page = page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Trang sau',
              onPressed: page + 1 < pages
                  ? () => setState(() => _page = page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const Text(
          '“Chưa đáo hạn” lọc theo ngày và trạng thái nguồn, không xác nhận còn dư nợ hay khả năng thanh toán. Trường thiếu hiển thị “–”; điều khoản coupon xem trong Chi tiết.',
        ),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(
              'https://cbonds.hnx.vn/to-chuc-phat-hanh/danh-sach-trai-phieu',
            ),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Tra cứu công bố HNX'),
        ),
      ],
    );
  }
}

String _date(DateTime? d) => d == null
    ? '–'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
