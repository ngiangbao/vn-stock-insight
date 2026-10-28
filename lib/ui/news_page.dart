import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';
import 'widgets.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  String _query = '';
  bool _watchOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    final items = state.news.where((n) {
      if (_watchOnly && !n.tickers.any(state.watchlist.contains)) return false;
      if (q.isNotEmpty && !'${n.title} ${n.summary} ${n.tickers.join(' ')}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    return PageFrame(
      title: 'Tin tức 48 giờ',
      onRefresh: state.refresh,
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 320,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm theo mã hoặc từ khóa'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          FilterChip(
            label: const Text('Chỉ mã đang theo dõi'),
            selected: _watchOnly,
            onSelected: (v) => setState(() => _watchOnly = v),
          ),
          Text('${items.length} tin', style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(state.loading ? 'Đang tải tin…' : 'Không có tin phù hợp.'),
              ),
            for (final (i, n) in items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (n.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(n.summary, maxLines: 3, overflow: TextOverflow.ellipsis)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final t in n.tickers) Tag(t, color: Theme.of(context).colorScheme.primary),
                    Text('${n.source} · ${timeVN(n.published)}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ]),
                onTap: n.link.isEmpty ? null : () => launchUrl(Uri.parse(n.link), mode: LaunchMode.externalApplication),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
