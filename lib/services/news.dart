// Gom tin tức từ các nguồn RSS và gắn mã cổ phiếu được nhắc tới.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'market.dart' show userAgent;

const newsFeeds = {
  'CafeF - Chứng khoán': 'https://cafef.vn/thi-truong-chung-khoan.rss',
  'CafeF - Doanh nghiệp': 'https://cafef.vn/doanh-nghiep.rss',
  'Vietstock - Cổ phiếu': 'https://vietstock.vn/830/chung-khoan/co-phieu.rss',
  'Vietstock - Doanh nghiệp': 'https://vietstock.vn/737/doanh-nghiep/hoat-dong-kinh-doanh.rss',
  'Tin nhanh chứng khoán': 'https://www.tinnhanhchungkhoan.vn/rss/chung-khoan-1.rss',
  'VnEconomy - Chứng khoán': 'https://vneconomy.vn/chung-khoan.rss',
  'VnExpress - Kinh doanh': 'https://vnexpress.net/rss/kinh-doanh.rss',
};

class NewsItem {
  final String title, summary, link, source;
  final String? imageUrl;
  final DateTime published;
  final Set<String> tickers;

  NewsItem(this.title, this.summary, this.link, this.source, this.published, this.tickers, {this.imageUrl});

  Map<String, dynamic> toPromptJson() => {
        'title': title,
        'summary': summary,
        'source': source,
        'published': published.toIso8601String().substring(0, 16),
      };
}

final _tag = RegExp(r'<[^>]+>');
final _ws = RegExp(r'\s+');
final _symbol = RegExp(r'\b[A-Z][A-Z0-9]{2}\b');

String _clean(String s) {
  final noTags = s.replaceAll(_tag, ' ');
  final unescaped = XmlDocument.parse('<x>${const HtmlEscape(HtmlEscapeMode.element).convert(noTags)}</x>').innerText;
  return _htmlEntities(unescaped).replaceAll(_ws, ' ').trim();
}

String _htmlEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');


String? _imageUrl(XmlElement item) {
  for (final element in item.descendants.whereType<XmlElement>()) {
    if (!const {'content', 'thumbnail', 'enclosure'}.contains(element.name.local.toLowerCase())) continue;
    final url = element.attributes
        .where((a) => a.name.local.toLowerCase() == 'url' || a.name.local.toLowerCase() == 'href')
        .map((a) => a.value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (url.isEmpty) continue;
    final type = element.attributes
        .where((a) => a.name.local.toLowerCase() == 'type')
        .map((a) => a.value.toLowerCase())
        .firstOrNull;
    final isImage = type?.startsWith('image/') ??
        RegExp(r'\.(jpe?g|png|webp|gif)(?:[?#].*)?$', caseSensitive: false).hasMatch(url);
    final uri = Uri.tryParse(url);
    if (isImage && uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
      return _htmlEntities(url);
    }
  }
  final description = item.getElement('description')?.innerText ?? '';
  final match = RegExp(r'<img\b[^>]*?(?:src|data-src)=([^ >]+)', caseSensitive: false).firstMatch(description);
  final url = match?.group(1)?.replaceAll('"', '').replaceAll("'", '').trim();
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty
      ? _htmlEntities(url)
      : null;
}

DateTime? _parseDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  s = s.trim();
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  // RFC 822: "Wed, 29 Oct 2026 08:15:00 +0700" (hoặc GMT)
  final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|GMT|UTC|[A-Z]{3})?').firstMatch(s);
  if (m == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final month = months.indexOf(m.group(2)!) + 1;
  if (month == 0) return null;
  var dt = DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!),
      int.parse(m.group(5)!), int.parse(m.group(6) ?? '0'));
  final tz = m.group(7);
  if (tz != null && (tz.startsWith('+') || tz.startsWith('-'))) {
    final sign = tz.startsWith('-') ? -1 : 1;
    final offset = Duration(hours: int.parse(tz.substring(1, 3)), minutes: int.parse(tz.substring(3, 5)));
    dt = sign > 0 ? dt.subtract(offset) : dt.add(offset);
  }
  return dt;
}

/// Lấy tin trong [maxAge] gần nhất. [known] là các mã dùng để gắn thẻ tin.
Future<List<NewsItem>> fetchNews(Set<String> known, {Duration maxAge = const Duration(hours: 48)}) async {
  final cutoff = DateTime.now().toUtc().subtract(maxAge);
  final seen = <String>{};
  final items = <NewsItem>[];

  final results = await Future.wait(newsFeeds.entries.map((feed) async {
    try {
      final resp = await http.get(Uri.parse(feed.value), headers: userAgent).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return <NewsItem>[];
      final doc = XmlDocument.parse(utf8.decode(resp.bodyBytes, allowMalformed: true));
      return [
        for (final item in doc.findAllElements('item'))
          () {
            final title = _clean(item.getElement('title')?.innerText ?? '');
            final rawDescription = item.getElement('description')?.innerText ?? '';
            final summary = _clean(rawDescription);
            final published = _parseDate(item.getElement('pubDate')?.innerText)?.toUtc() ?? DateTime.now().toUtc();
            final text = '$title $summary';
            return NewsItem(
              title,
              summary.length > 400 ? summary.substring(0, 400) : summary,
              item.getElement('link')?.innerText.trim() ?? '',
              feed.key,
              published,
              {for (final m in _symbol.allMatches(text)) if (known.contains(m[0])) m[0]!},
              imageUrl: _imageUrl(item),
            );
          }(),
      ];
    } catch (_) {
      return <NewsItem>[];
    }
  }));

  for (final n in results.expand((x) => x)) {
    if (n.title.isEmpty || n.published.isBefore(cutoff)) continue;
    // Cùng một tin hay được đăng lại ở nhiều chuyên mục: khử trùng theo tiêu đề
    if (!seen.add(n.title.toLowerCase())) continue;
    items.add(n);
  }
  items.sort((a, b) => b.published.compareTo(a.published));
  return items;
}

/// Tin liên quan tới một mã: được gắn thẻ hoặc tiêu đề nhắc đúng mã.
List<NewsItem> newsFor(List<NewsItem> news, String symbol, {int limit = 15}) {
  final mention = RegExp('\\b$symbol\\b');
  return news.where((n) => n.tickers.contains(symbol) || mention.hasMatch(n.title)).take(limit).toList();
}
