// Phân tích CFA: dựng dữ liệu đầu vào (định lượng tính cục bộ + cơ bản + vĩ mô + tin tức), gọi AI, lưu kết quả trên máy;
// và báo cáo bổ sung khắc phục hạn chế dữ liệu của báo cáo AI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/cfa_prompts.dart';
import '../ai/providers.dart';
import '../state.dart';
import 'fundamentals.dart';
import 'macro.dart';
import 'market.dart';
import 'news.dart';
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
  File get _macroCache => File('${dataDir.path}${Platform.pathSeparator}macro_cache.json');

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
    final macro = await macroDigest(_macroCache);
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

  /// Dữ liệu bổ sung dùng cho báo cáo thứ hai: doanh nghiệp cùng ngành, vĩ mô, tin 14 ngày, dòng tiền khối ngoại, hiệu suất so với VN-Index.
  Future<Map<String, dynamic>> gatherExtra(String symbol) async {
    final sector = dash.sectors[symbol]?.name;
    final peers = sector == null
        ? <String>[]
        : (dash.sectors.entries.where((e) => e.value.name == sector && e.key != symbol).toList()
                ..sort((a, b) => b.value.marketCap.compareTo(a.value.marketCap)))
              .take(4)
              .map((e) => e.key)
              .toList();

    Future<Map<String, dynamic>> peer(String s) async {
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

    final results = await Future.wait<dynamic>([
      Future.wait(peers.map(peer)),
      macroDigest(_macroCache),
      fetchNews({symbol}, maxAge: const Duration(days: 14)).catchError((_) => <NewsItem>[]),
      fetchBars(symbol, days: 1900),
      fetchBars('VNINDEX', days: 1900, isIndex: true),
    ]);
    final bars = results[3] as List<Bar>, indexBars = results[4] as List<Bar>;
    final board = [for (final rows in dash.boards.values) ...rows].where((r) => r.symbol == symbol).firstOrNull;
    return {
      'nganh': sector,
      'doanh_nghiep_cung_nganh': results[0],
      'vi_mo': results[1],
      'tin_tuc_14_ngay': newsFor(results[2] as List<NewsItem>, symbol, limit: 25).map((n) => n.toPromptJson()).toList(),
      'hieu_suat_so_voi_vnindex': quantStats(bars, indexBars),
      if (board != null)
        'bang_gia': {
          'gia': board.price / 1000,
          'khoi_luong': board.volume,
          'gia_tri_trieu_dong': board.valueMn,
          'khoi_ngoai_mua': board.foreignBuy,
          'khoi_ngoai_ban': board.foreignSell,
        },
    };
  }

  /// Lập báo cáo bổ sung cho nhận định ngày [dayKey] của [symbol] để khắc phục các hạn chế [gaps]; lưu vào bản ghi.
  Future<Map<String, dynamic>> followUpStock(String symbol, String dayKey, Map<String, dynamic> record, List<String> gaps) async {
    final extra = await gatherExtra(symbol);
    final result = (record['result'] as Map?) ?? const {};
    final first = {
      for (final k in ['stance', 'confidence', 'headline', 'summary', 'valuation', 'earnings', 'thesis', 'risks']) k: result[k],
    };
    final out = await generateJson(
      await resolveAiConfig(),
      system: followUpSystem,
      prompt: followUpPrompt(symbol, first, gaps, extra),
      schema: followUpSchema,
      schemaName: 'followup_report',
    );
    final followUp = {'created_at': DateTime.now().toIso8601String(), 'ai': aiLabel, 'gaps': gaps, 'result': out};
    await saveFollowUp(symbol, dayKey, followUp);
    return followUp;
  }
}
