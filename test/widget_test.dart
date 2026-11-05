import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/part.dart';

void main() {
  test('Part.fromJson parses row with images sorted', () {
    final part = Part.fromJson({
      'id': 'p1',
      'name': 'Brake pad',
      'part_no': 'BP-100',
      'quantity': 1,
      'buy_price': 450,
      'sell_price': 600.5,
      'low_stock_level': 2,
      'updated_at': '2026-11-04T10:00:00Z',
      'part_images': [
        {'id': 'i2', 'part_id': 'p1', 'storage_path': 'p1/b.jpg', 'sort_order': 1},
        {'id': 'i1', 'part_id': 'p1', 'storage_path': 'p1/a.jpg', 'sort_order': 0},
      ],
    });

    expect(part.name, 'Brake pad');
    expect(part.isLowStock, isTrue);
    expect(part.images.map((i) => i.id), ['i1', 'i2']);
  });
}
