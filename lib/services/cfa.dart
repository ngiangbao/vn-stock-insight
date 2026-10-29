// Phân tích CFA: dựng dữ liệu đầu vào (định lượng tính cục bộ + cơ bản + vĩ mô + tin tức), gọi AI, lưu kết quả trên máy;
// và báo cáo bổ sung khắc phục hạn chế dữ liệu của báo cáo AI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/cfa_prompts.dart';
import '../ai/portfolio_prompts.dart';
import '../ai/providers.dart';
import '../state.dart';
import 'fundamentals.dart';
import 'macro.dart';
import 'market.dart';
import 'news.dart';
import 'portfolio.dart';
import 'quant.dart';

/// Các bản phân tích CFA đã lưu trên máy (cfa_reports.json), mới nhất trước.
class CfaStore extends ChangeNotifier {
  final File file;
  static const maxReports = 60;
  List<Map<String, dynamic>> reports = [];
  CfaStore(this.file);

  Future<void> load() async {
    try {
      if (await file.exists()) {
        reports = [for (final r in jsonDecode(await file.readAsString()) as List) Map<String, dynamic>.from(r as Map)];
      }
    } catch (_) {
      reports = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(reports), flush: true);
    } catch (_) {
      // Không ghi được ra đĩa thì vẫn giữ trong bộ nhớ của phiên này.
    }
  }

  Future<void> add(Map<String, dynamic> record) async {
    reports = [record, ...reports.where((r) => r['id'] != record['id'])].take(maxReports).toList();
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    reports = [
      for (final r in reports)
        if (r['id'] != id) r,
    ];
    notifyListeners();
    await _save();
  }
}

/// Số liệu vĩ mô mới nhất và kỳ trước, gọn cho prompt. Trả về {} nếu không tải được.
Future<Map<String, dynamic>> macroDigest(File? cacheFile) async {
  try {
    final snap = await MacroRepository(cacheFile: cacheFile).load().timeout(const Duration(seconds: 40));
    return {
      for (final e in snap.series.entries)
        if (e.value.latest != null)
          e.key: {
            'chi_tieu': e.value.def.title,
            'don_vi': e.value.def.unit,
            'moi_nhat': {'ky': e.value.latest!.label, 'gia_tri': e.value.latest!.value},
            if (e.value.previous != null) 'ky_truoc': {'ky': e.value.previous!.label, 'gia_tri': e.value.previous!.value},
          },
    };
  } catch (_) {
    return {};
  }
}

String _dayKey(DateTime t) => t.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

extension CfaAnalysis on AppState {
  File get macroCacheFile => File('${dataDir.path}${Platform.pathSeparator}macro_cache.json');

  /// Phân tích CFA một mã và lưu lại. Ném [AiException] hoặc lỗi mạng để giao diện hiển thị.
  Future<Map<String, dynamic>> analyzeCfa(String symbol, {CfaAssumptions assumptions = const CfaAssumptions()}) async {
    symbol = symbol.trim().toUpperCase();
    final results = await Future.wait([fetchBars(symbol, days: 1900), fetchBars('VNINDEX', days: 1900, isIndex: true)]);
    final bars = results[0], indexBars = results[1];
    if (bars.length < 60) throw AiException('Không tìm thấy đủ dữ liệu giá cho mã $symbol (cần ít nhất 60 phiên).');
    final snap = analyze(symbol, bars);
    final fund = await fetchFundamentals(symbol);
    final quant = quantStats(bars, indexBars, rf: assumptions.rf);
    final valuation = cfaValuation(fund, bars.last.c, (quant?['beta'] as num?)?.toDouble(), assumptions);
    final macro = await macroDigest(macroCacheFile);
    final newsList = news.isNotEmpty ? news : await fetchNews({symbol});
    final inputs = {
      'quant': quant ?? {'ghi_chu': 'Không đủ dữ liệu chung với VN-Index để tính chỉ số định lượng.'},
      'valuation': valuation,
      'technicals': snap.toPromptJson(),
      'fundamentals': fund,
      'macro': macro,
      'news': newsFor(newsList, symbol).map((n) => n.toPromptJson()).toList(),
    };
    final result = await generateJson(
      await resolveAiConfig(),
      system: cfaSystem,
      prompt: cfaPrompt(symbol, inputs),
      schema: cfaSchema,
      schemaName: 'cfa_analysis',
    );
    final now = DateTime.now();
    final rel = relativeSeries(bars, indexBars);
    final company = (fund['company'] as Map?) ?? const {};
    final record = <String, dynamic>{
      'id': '${now.millisecondsSinceEpoch}-$symbol',
      'symbol': symbol,
      'name': company['ten'],
      'sector': company['nganh'],
      'day': _dayKey(now),
      'created_at': now.toIso8601String(),
      'ai': aiLabel,
      'price': bars.last.c,
      'assumptions': assumptions.toJson(),
      'inputs': inputs,
      'series': {
        'dates': rel.dates,
        'stock': [for (final v in rel.stock) double.parse(v.toStringAsFixed(2))],
        'index': [for (final v in rel.index) double.parse(v.toStringAsFixed(2))],
      },
      'result': result,
    };
    await cfa.add(record);
    return record;
  }
}

/// Chỉ số cơ bản gọn của một mã (kỳ gần nhất) để so sánh với các doanh nghiệp cùng ngành.
Future<Map<String, dynamic>> peerSnapshot(String s) async {
  try {
    final f = await fetchFundamentals(s);
    final q = ((f['chi_so_ttm_theo_quy'] as List?) ?? const []);
    final last = q.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(q.last as Map);
    return {
      'ma': s,
      'ten': (f['company'] as Map?)?['ten'],
      'von_hoa_ty_dong': (f['company'] as Map?)?['von_hoa_ty_dong'],
      for (final k in ['pe', 'pb', 'roe', 'grossMargin', 'afterTaxProfitMargin', 'debtToEquity'])
        if (last[k] != null) k: last[k],
    };
  } catch (_) {
    return {'ma': s, 'loi': 'không tải được'};
  }
}

/// Phân tích danh mục đầu tư.
extension PortfolioAnalysis on AppState {
  /// Phân tích lại danh mục [id] bằng giá và dữ liệu mới nhất, lưu thêm một bản vào lịch sử của danh mục.
  Future<Map<String, dynamic>> analyzePortfolio(String id, {CfaAssumptions assumptions = const CfaAssumptions()}) async {
    final p = portfolios.byId(id);
    if (p == null) throw AiException('Không tìm thấy danh mục.');
    final holdings = [for (final h in (p['holdings'] as List).cast<Map>()) Map<String, dynamic>.from(h)];
    if (holdings.where((h) => ((h['shares'] as num?) ?? 0) > 0).isEmpty) {
      throw AiException('Danh mục chưa có cổ phiếu nào. Hãy thêm ít nhất một mã với số lượng lớn hơn 0.');
    }
    final symbols = {for (final h in holdings) '${h['symbol']}'.toUpperCase()}.toList();
    final fetched = await Future.wait([for (final s in symbols) fetchBars(s, days: 1900), fetchBars('VNINDEX', days: 1900, isIndex: true)]);
    final bars = {for (var i = 0; i < symbols.length; i++) symbols[i]: fetched[i]};
    final index = fetched.last;
    final cash = ((p['cash'] as num?)?.toDouble() ?? 0) * 1000; // triệu đồng -> nghìn đồng
    final stats = portfolioStats(
      holdings: holdings,
      bars: bars,
      index: index,
      cash: cash,
      rf: assumptions.rf,
      sectors: {for (final s in symbols) if (dash.sectors[s] != null) s: dash.sectors[s]!.name},
    );
    if (stats == null) {
      throw AiException('Không đủ dữ liệu giá để phân tích: cần ít nhất 60 phiên chung với VN-Index cho mọi mã (${symbols.join(', ')}).');
    }
    final rows = (stats['vi_the'] as List).cast<Map<String, dynamic>>();
    final snapList = await Future.wait([for (final r in rows.take(15)) peerSnapshot(r['ma'] as String)]);
    final snaps = {for (final s in snapList) s['ma'] as String: s};
    final newsList = news.isNotEmpty ? news : await fetchNews(symbols.toSet());
    final inputs = {
      'stats': {for (final e in stats.entries) if (e.key != 'chuoi') e.key: e.value},
      'valuation': weightedValuation(rows, snaps),
      'fundamentals': snapList,
      'macro': await macroDigest(macroCacheFile),
      'news': [
        for (final s in symbols.take(15))
          for (final n in newsFor(newsList, s, limit: 3)) {'ma': s, ...n.toPromptJson()},
      ],
    };
    final result = await generateJson(
      await resolveAiConfig(),
      system: portfolioSystem,
      prompt: portfolioPrompt(p, inputs),
      schema: portfolioSchema,
      schemaName: 'portfolio_analysis',
    );
    final now = DateTime.now();
    final series = stats['chuoi'] as Map<String, dynamic>;
    final analysis = <String, dynamic>{
      'id': '${now.millisecondsSinceEpoch}',
      'created_at': now.toIso8601String(),
      'ai': aiLabel,
      'assumptions': assumptions.toJson(),
      'ips': {'goal': p['goal'], 'horizon': p['horizon'], 'risk': p['risk']},
      'snapshot': holdings,
      'cash': p['cash'],
      'inputs': inputs,
      'series': series,
      'result': result,
    };
    await portfolios.addAnalysis(id, analysis);
    return analysis;
  }
}
