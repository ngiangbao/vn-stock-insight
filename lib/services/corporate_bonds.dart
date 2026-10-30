import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'market.dart' show userAgent;

const corporateBondSource = 'https://api-finfo.vndirect.com.vn/v4/bonds';

String bondPlainText(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
      final s = m[1]!;
      final n = s.startsWith('x')
          ? int.tryParse(s.substring(1), radix: 16)
          : int.tryParse(s);
      return n == null || n > 0x10ffff ? '' : String.fromCharCode(n);
    })
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

DateTime? _date(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.length < 10) return null;
  final s = raw.substring(0, 10), d = DateTime.tryParse(raw.substring(0, 10));
  return d != null && d.toIso8601String().substring(0, 10) == s ? d : null;
}

double? _number(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  return n != null && n.isFinite && n > 0 ? n : null;
}

class CorporateBond {
  final String code,
      originalCode,
      issuer,
      isin,
      market,
      currency,
      sourceStatus,
      rateType,
      rateDescription,
      termLabel;
  final DateTime? issued, maturity;
  final double? faceValue;
  const CorporateBond({
    required this.code,
    required this.issuer,
    this.originalCode = '',
    this.isin = '',
    this.market = '',
    this.currency = 'VND',
    this.sourceStatus = '',
    this.rateType = '',
    this.rateDescription = '',
    this.termLabel = '',
    this.issued,
    this.maturity,
    this.faceValue,
  });

  factory CorporateBond.fromJson(Map<String, dynamic> j) {
    final docs = j['documents'];
    final doc = docs is List && docs.isNotEmpty && docs.first is Map
        ? docs.first as Map
        : const {};
    return CorporateBond(
      code: bondPlainText(j['code']),
      originalCode: bondPlainText(j['originalBondCode']),
      issuer: bondPlainText(j['issuer']),
      isin: bondPlainText(j['isin']),
      market: bondPlainText(j['floor']),
      currency: bondPlainText(j['currencyCode']).isEmpty
          ? 'VND'
          : bondPlainText(j['currencyCode']),
      sourceStatus: bondPlainText(j['bondStatus']),
      rateType: bondPlainText(j['interestType']),
      rateDescription: bondPlainText(
        j['rateDescription'] ?? doc['interestRateDesc'],
      ),
      termLabel: bondPlainText(
        j['termLabel'] ??
            doc['termDesc'] ??
            (j['term'] == null || j['term'] == 0
                ? ''
                : '${j['term']} ${j['termUnit'] ?? ''}'),
      ),
      issued: _date(j['issuedDate']),
      maturity: _date(j['matureDate']),
      faceValue: _number(j['faceValue']),
    );
  }
  Map<String, dynamic> toJson() => {
    'code': code,
    'originalBondCode': originalCode,
    'issuer': issuer,
    'isin': isin,
    'floor': market,
    'currencyCode': currency,
    'bondStatus': sourceStatus,
    'interestType': rateType,
    'rateDescription': rateDescription,
    'termLabel': termLabel,
    'issuedDate': issued?.toIso8601String(),
    'matureDate': maturity?.toIso8601String(),
    'faceValue': faceValue,
  };

  int? remainingDays(DateTime now) {
    if (maturity == null) return null;
    final vn = now.toUtc().add(const Duration(hours: 7));
    return DateTime.utc(
      maturity!.year,
      maturity!.month,
      maturity!.day,
    ).difference(DateTime.utc(vn.year, vn.month, vn.day)).inDays;
  }

  String get rateLabel => switch (rateType) {
    'FIXED' => 'Cố định',
    'UNFIXED' => 'Thả nổi',
    _ => 'Chưa rõ',
  };
}

class CorporateBondSnapshot {
  final List<CorporateBond> bonds;
  final DateTime fetchedAt;
  final int sourceTotal;
  final bool cached;
  final String? warning;
  const CorporateBondSnapshot(
    this.bonds,
    this.fetchedAt,
    this.sourceTotal, {
    this.cached = false,
    this.warning,
  });
}

/// Fetch every page in the provider's catalog; this provider does NOT cover the
/// entire Vietnamese corporate bond market. No inference of outstanding volume.
class CorporateBondRepository {
  final http.Client _client;
  final File? cacheFile;
  final Duration maxAge;
  CorporateBondRepository({
    http.Client? client,
    this.cacheFile,
    this.maxAge = const Duration(hours: 6),
  }) : _client = client ?? http.Client();
  void close() => _client.close();

  Future<CorporateBondSnapshot?> _cached() async {
    try {
      if (cacheFile == null || !await cacheFile!.exists()) return null;
      final j =
          jsonDecode(await cacheFile!.readAsString()) as Map<String, dynamic>;
      final bonds = (j['bonds'] as List)
          .map(
            (r) => CorporateBond.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      return CorporateBondSnapshot(
        bonds,
        DateTime.parse(j['fetchedAt'] as String),
        j['sourceTotal'] as int,
        cached: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CorporateBondSnapshot> load({bool force = false}) async {
    final old = await _cached();
    if (!force &&
        old != null &&
        DateTime.now().difference(old.fetchedAt) < maxAge) {
      return old;
    }
    try {
      final bonds = <String, CorporateBond>{};
      final seen = <String>{};
      var pages = 1, total = 0, received = 0;
      for (var page = 1; page <= pages; page++) {
        final uri = Uri.parse(corporateBondSource).replace(
          queryParameters: {'size': '100', 'page': '$page', 'sort': 'code:asc'},
        );
        final r = await _client
            .get(uri, headers: userAgent)
            .timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) {
          throw const FormatException('Source unavailable');
        }
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (j['currentPage'] != page || j['data'] is! List) {
          throw const FormatException('Invalid page');
        }
        final data = j['data'] as List;
        if (page == 1) {
          if (j['totalPages'] is! int || j['totalElements'] is! int) {
            throw const FormatException('Missing totals');
          }
          pages = j['totalPages'] as int;
          total = j['totalElements'] as int;
        }
        if (pages < 1 ||
            pages > 500 ||
            (j['totalPages'] != null && j['totalPages'] != pages) ||
            (j['totalElements'] != null && j['totalElements'] != total) ||
            data.isEmpty) {
          throw const FormatException('Incomplete catalog');
        }
        received += data.length;
        for (final row in data) {
          if (row is! Map) throw const FormatException('Invalid bond');
          final raw = Map<String, dynamic>.from(row);
          if (!seen.add(bondPlainText(raw['code']))) {
            throw const FormatException('Duplicate page');
          }
          // The endpoint is a corporate catalog; reject explicit other types.
          if (raw['bondType'] != null && raw['bondType'] != 'CORPORATE') {
            continue;
          }
          final bond = CorporateBond.fromJson(raw);
          if (bond.code.isEmpty) throw const FormatException('Missing code');
          bonds[bond.code] = bond;
        }
      }
      if (received != total || bonds.isEmpty) {
        throw const FormatException('Incomplete catalog');
      }
      final snapshot = CorporateBondSnapshot(
        bonds.values.toList(),
        DateTime.now(),
        total,
      );
      if (cacheFile != null) {
        try {
          await cacheFile!.parent.create(recursive: true);
          final temp = File('${cacheFile!.path}.tmp');
          await temp.writeAsString(
            jsonEncode({
              'fetchedAt': snapshot.fetchedAt.toIso8601String(),
              'sourceTotal': total,
              'bonds': snapshot.bonds.map((b) => b.toJson()).toList(),
            }),
            flush: true,
          );
          await temp.rename(cacheFile!.path);
        } catch (_) {
          /* A cache write failure must not hide a successful fetch. */
        }
      }
      return snapshot;
    } catch (_) {
      if (old != null) {
        return CorporateBondSnapshot(
          old.bonds,
          old.fetchedAt,
          old.sourceTotal,
          cached: true,
          warning: 'Không tải đủ danh mục mới; đang giữ bản đã lưu.',
        );
      }
      rethrow;
    }
  }
}
