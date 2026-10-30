// ignore_for_file: avoid_print
import 'package:vn_stock_insight/services/corporate_bonds.dart';

Future<void> main() async {
  final repo = CorporateBondRepository();
  try {
    final snapshot = await repo.load(force: true);
    print(
      'VNDirect: ${snapshot.bonds.length}/${snapshot.sourceTotal} mã từ tất cả các trang nguồn.',
    );
    print(
      'Có ngày đáo hạn: ${snapshot.bonds.where((b) => b.maturity != null).length}.',
    );
    print(
      'Danh mục này không đại diện toàn bộ thị trường trái phiếu Việt Nam.',
    );
  } finally {
    repo.close();
  }
}
