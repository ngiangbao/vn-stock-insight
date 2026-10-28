import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/news.dart';
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
    final items = state.news.where((news) {
      if (_watchOnly && !news.tickers.any(state.watchlist.contains)) {
        return false;
      }
      if (q.isNotEmpty &&
          !'${news.title} ${news.summary} ${news.tickers.join(' ')}'
              .toLowerCase()
              .contains(q)) {
        return false;
      }
      return true;
    }).toList();
    final featured = items.isNotEmpty ? items.first : null;
    final latest = featured == null
        ? const <NewsItem>[]
        : items.skip(1).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tin tức thị trường'),
        actions: [
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: state.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới tin tức',
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1520
              ? 4
              : width >= 1080
              ? 3
              : width >= 700
              ? 2
              : 1;
          final mainAxisExtent = switch (columns) {
            4 => 448.0,
            3 => 468.0,
            2 => 500.0,
            _ => 474.0,
          };
          final scroll = CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                sliver: SliverToBoxAdapter(
                  child: _NewsMasthead(
                    width: constraints.maxWidth,
                    onQueryChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                sliver: SliverToBoxAdapter(
                  child: _NewsFilters(
                    watchOnly: _watchOnly,
                    count: items.length,
                    onWatchOnlyChanged: (value) =>
                        setState(() => _watchOnly = value),
                  ),
                ),
              ),
              if (featured != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: _FeaturedNewsCard(
                      item: featured,
                      width: constraints.maxWidth,
                    ),
                  ),
                ),
                if (latest.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
                    sliver: SliverToBoxAdapter(
                      child: _SectionHeading(count: latest.length),
                    ),
                  ),
                if (latest.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: mainAxisExtent,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _NewsCard(item: latest[index]),
                        childCount: latest.length,
                      ),
                    ),
                  ),
              ] else
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyNews(
                    loading: state.loading,
                    hasQuery: q.isNotEmpty || _watchOnly,
                  ),
                ),
            ],
          );
          return RefreshIndicator(onRefresh: state.refresh, child: scroll);
        },
      ),
    );
  }
}

class _NewsMasthead extends StatelessWidget {
  final double width;
  final ValueChanged<String> onQueryChanged;

  const _NewsMasthead({required this.width, required this.onQueryChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = SizedBox(
      width: width < 500 ? double.infinity : 340,
      child: TextField(
        key: const ValueKey('news-search'),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Tìm tin hoặc mã cổ phiếu',
          isDense: true,
        ),
        onChanged: onQueryChanged,
      ),
    );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Bản tin thị trường',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.45,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '48 GIỜ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tin chọn lọc về thị trường, doanh nghiệp và kinh tế',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (width < 760) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, const SizedBox(height: 16), search],
      );
    }
    return Row(
      children: [
        Expanded(child: heading),
        search,
      ],
    );
  }
}

class _NewsFilters extends StatelessWidget {
  final bool watchOnly;
  final int count;
  final ValueChanged<bool> onWatchOnlyChanged;

  const _NewsFilters({
    required this.watchOnly,
    required this.count,
    required this.onWatchOnlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          avatar: Icon(
            Icons.bookmark_outline,
            size: 17,
            color: watchOnly ? theme.colorScheme.primary : null,
          ),
          label: const Text('Mã đang theo dõi'),
          selected: watchOnly,
          onSelected: onWatchOnlyChanged,
        ),
        Text(
          '$count bài trong 48 giờ qua',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FeaturedNewsCard extends StatelessWidget {
  final NewsItem item;
  final double width;

  const _FeaturedNewsCard({required this.item, required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = width >= 900;
    final image = _NewsImage(item: item, fit: BoxFit.cover);
    final copy = Padding(
      padding: EdgeInsets.all(horizontal ? 24 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Text(
                'TIN NỔI BẬT',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.9,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.18,
              letterSpacing: -0.4,
            ),
          ),
          if (item.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.summary,
              maxLines: horizontal ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          _NewsMetadata(item: item),
          if (item.tickers.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TickerTags(tickers: item.tickers.take(5).toList()),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Đọc bài viết',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Icon(
                Icons.arrow_forward,
                size: 17,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openArticle(item),
        child: horizontal
            ? SizedBox(
                height: 384,
                child: Row(
                  children: [
                    Expanded(flex: 11, child: image),
                    Expanded(flex: 10, child: copy),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: image),
                  copy,
                ],
              ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openArticle(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _NewsImage(item: item, fit: BoxFit.cover),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NewsMetadata(item: item),
                    const SizedBox(height: 9),
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (item.summary.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Expanded(
                        child: Text(
                          item.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    if (item.tickers.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      _TickerTags(tickers: item.tickers.take(4).toList()),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsMetadata extends StatelessWidget {
  final NewsItem item;
  const _NewsMetadata({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            item.source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.circle, size: 4, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          _timeAgo(item.published),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TickerTags extends StatelessWidget {
  final List<String> tickers;
  const _TickerTags({required this.tickers});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 5,
    children: [
      for (final ticker in tickers)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ticker,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ],
  );
}

class _NewsImage extends StatelessWidget {
  final NewsItem item;
  final BoxFit fit;

  const _NewsImage({required this.item, required this.fit});

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl;
    final fallback = _NewsIllustration(title: item.title);
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: fit,
      semanticLabel: 'Ảnh minh họa: ${item.title}',
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                    ),
                  ),
                ),
              ],
            ),
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

class _NewsIllustration extends StatelessWidget {
  final String title;
  const _NewsIllustration({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: 'Ảnh minh họa tin thị trường: $title',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.secondary],
          ),
        ),
        child: CustomPaint(
          painter: _MarketIllustrationPainter(
            grid: scheme.onPrimary.withValues(alpha: 0.12),
            line: scheme.tertiary,
            bars: scheme.onPrimary.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Icon(
              Icons.query_stats,
              size: 44,
              color: scheme.onPrimary.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketIllustrationPainter extends CustomPainter {
  final Color grid, line, bars;
  const _MarketIllustrationPainter({
    required this.grid,
    required this.line,
    required this.bars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    const heights = [
      0.22,
      0.37,
      0.29,
      0.52,
      0.43,
      0.63,
      0.48,
      0.74,
      0.61,
      0.83,
      0.7,
      0.91,
    ];
    final barWidth = size.width / (heights.length * 2.4);
    final barPaint = Paint()..color = bars;
    final points = <Offset>[];
    for (var i = 0; i < heights.length; i++) {
      final x = (i + 0.5) * size.width / heights.length;
      final y = size.height * (1 - heights[i]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - barWidth / 2, y, x + barWidth / 2, size.height),
          const Radius.circular(3),
        ),
        barPaint,
      );
      points.add(Offset(x, y - 8));
    }
    final chart = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      chart.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      chart,
      Paint()
        ..color = line
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MarketIllustrationPainter old) =>
      grid != old.grid || line != old.line || bars != old.bars;
}

class _SectionHeading extends StatelessWidget {
  final int count;
  const _SectionHeading({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Mới nhất',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count bài',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.view_quilt_outlined,
          size: 19,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _EmptyNews extends StatelessWidget {
  final bool loading, hasQuery;
  const _EmptyNews({required this.loading, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              loading ? Icons.hourglass_empty : Icons.newspaper_outlined,
              size: 42,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              loading
                  ? 'Đang tải tin tức…'
                  : hasQuery
                  ? 'Không tìm thấy tin phù hợp'
                  : 'Chưa có tin mới',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              loading
                  ? 'Các nguồn tin đang được cập nhật.'
                  : 'Hãy thử từ khóa khác hoặc làm mới danh sách tin.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime published) {
  final difference = DateTime.now().toUtc().difference(published.toUtc());
  if (difference.inSeconds <= 0 || difference.inMinutes < 1) return 'Vừa xong';
  if (difference.inHours < 1) return '${difference.inMinutes} phút trước';
  if (difference.inHours < 24) return '${difference.inHours} giờ trước';
  return timeVN(published);
}

void _openArticle(NewsItem item) {
  final uri = Uri.tryParse(item.link);
  if (uri != null && uri.hasScheme) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
