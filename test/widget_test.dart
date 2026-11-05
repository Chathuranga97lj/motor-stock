import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/lookup.dart';
import 'package:motor_stock/models/part.dart';
import 'package:motor_stock/services/lookup_service.dart';

void main() {
  test('Part.fromJson parses row with linked names and sorted images', () {
    final part = Part.fromJson({
      'id': 'p1',
      'name': 'Brake pad',
      'part_no': 'BP-100',
      'category_id': 'c1',
      'brand_id': 'b1',
      'bike_model_id': 'm1',
      'category': {'name': 'BODY PARTS'},
      'brand': {'name': 'HONDA'},
      'bike_model': {'name': 'DIO BS4'},
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
    expect(part.brandName, 'HONDA');
    expect(part.bikeModelName, 'DIO BS4');
    expect(part.toRow()['bike_model_id'], 'm1');
  });

  test('Part.fromJson handles parts with no linked lists', () {
    final part = Part.fromJson({'id': 'p2', 'name': 'Oil', 'category': null});
    expect(part.categoryName, isNull);
    expect(part.brandId, isNull);
  });

  test('models are filtered by brand', () {
    const lookups = Lookups(models: [
      LookupItem(id: 'm1', name: 'DIO OLD', brandId: 'honda'),
      LookupItem(id: 'm2', name: 'CT 100 NEW', brandId: 'bajaj'),
    ]);
    expect(lookups.modelsOf('honda').map((m) => m.name), ['DIO OLD']);
    expect(lookups.modelsOf(null), isEmpty);
  });

  test('names are trimmed and upper-cased', () {
    expect(LookupService.normalize('  discover   135cc '), 'DISCOVER 135CC');
  });
}
