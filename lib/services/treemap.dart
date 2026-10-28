// Treemap squarified (Bruls, Huizing, van Wijk) và bố cục 2 cấp: ngành → mã.

import 'dart:math' as math;
import 'dart:ui';

/// Chia [rect] thành các ô có diện tích tỉ lệ với [weights] (đã sắp xếp giảm dần), ô lớn nhất ở góc trên trái.
/// Trả về danh sách ô cùng thứ tự với [weights]; trọng số <= 0 nhận ô rỗng.
List<Rect> squarify(List<double> weights, Rect rect) {
  final out = List<Rect>.filled(weights.length, Rect.zero);
  final idx = [
    for (var i = 0; i < weights.length; i++)
      if (weights[i] > 0) i,
  ];
  final total = idx.fold(0.0, (s, i) => s + weights[i]);
  if (idx.isEmpty || rect.width <= 0 || rect.height <= 0) return out;
  final scale = rect.width * rect.height / total;

  var free = rect;
  var start = 0;
  while (start < idx.length) {
    final shortSide = math.min(free.width, free.height);
    var end = start + 1;
    var sum = weights[idx[start]] * scale;
    var best = _worst([weights[idx[start]] * scale], sum, shortSide);
    while (end < idx.length) {
      final a = weights[idx[end]] * scale;
      final row = [for (var k = start; k <= end; k++) weights[idx[k]] * scale];
      final w = _worst(row, sum + a, shortSide);
      if (w > best) break;
      best = w;
      sum += a;
      end++;
    }
    // Đặt hàng [start, end) dọc theo cạnh ngắn
    final horizontal = free.width >= free.height; // cạnh ngắn là chiều cao → hàng là một cột
    final thickness = sum / shortSide;
    var offset = 0.0;
    for (var k = start; k < end; k++) {
      final len = weights[idx[k]] * scale / thickness;
      out[idx[k]] = horizontal
          ? Rect.fromLTWH(free.left, free.top + offset, thickness, len)
          : Rect.fromLTWH(free.left + offset, free.top, len, thickness);
      offset += len;
    }
    free = horizontal
        ? Rect.fromLTRB(free.left + thickness, free.top, free.right, free.bottom)
        : Rect.fromLTRB(free.left, free.top + thickness, free.right, free.bottom);
    start = end;
  }
  return out;
}

double _worst(List<double> row, double sum, double side) {
  final maxA = row.reduce(math.max), minA = row.reduce(math.min);
  return math.max(side * side * maxA / (sum * sum), sum * sum / (side * side * minA));
}

class TreeItem {
  final String id;
  final double weight;
  const TreeItem(this.id, this.weight);
}

class TreeGroup {
  final String name;
  final List<TreeItem> items; // đã sắp xếp giảm dần
  const TreeGroup(this.name, this.items);
  double get weight => items.fold(0.0, (s, i) => s + i.weight);
}

class PlacedItem {
  final String id;
  final Rect rect;
  const PlacedItem(this.id, this.rect);
}

class PlacedGroup {
  final String name;
  final Rect rect; // cả khối ngành, gồm tiêu đề
  final Rect header;
  final List<PlacedItem> items;
  const PlacedGroup(this.name, this.rect, this.header, this.items);
}

/// Bố cục 2 cấp. [groups] phải sắp xếp ngành lớn → bé. Mỗi khối ngành chừa tiêu đề cao [headerH]
/// (bỏ tiêu đề nếu khối quá nhỏ) và viền [gap] giữa các khối.
List<PlacedGroup> layoutTwoLevel(List<TreeGroup> groups, Rect bounds, {double headerH = 16, double gap = 1.5}) {
  final live = groups.where((g) => g.weight > 0).toList();
  final rects = squarify([for (final g in live) g.weight], bounds);
  return [
    for (final (i, g) in live.indexed)
      () {
        final r = rects[i];
        final showHeader = r.height >= headerH * 2.2 && r.width >= 40;
        final header = showHeader
            ? Rect.fromLTWH(r.left, r.top, r.width, headerH)
            : Rect.fromLTWH(r.left, r.top, r.width, 0);
        final inner = Rect.fromLTRB(r.left, r.top + header.height, r.right, r.bottom).deflate(gap / 2);
        final cells = inner.width > 0 && inner.height > 0
            ? squarify([for (final it in g.items) it.weight], inner)
            : List.filled(g.items.length, Rect.zero);
        return PlacedGroup(g.name, r, header, [
          for (final (k, it) in g.items.indexed)
            if (cells[k].width > 0 && cells[k].height > 0) PlacedItem(it.id, cells[k]),
        ]);
      }(),
  ];
}
