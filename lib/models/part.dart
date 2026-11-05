class PartImage {
  final String id;
  final String partId;
  final String storagePath;
  final int sortOrder;

  const PartImage({
    required this.id,
    required this.partId,
    required this.storagePath,
    required this.sortOrder,
  });

  factory PartImage.fromJson(Map<String, dynamic> json) => PartImage(
        id: json['id'] as String,
        partId: json['part_id'] as String,
        storagePath: json['storage_path'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class Part {
  final String? id;
  final String name;
  final String? partNo;
  final String? brand;
  final String? bikeModel;
  final String? category;
  final int quantity;
  final double buyPrice;
  final double sellPrice;
  final int lowStockLevel;
  final DateTime? updatedAt;
  final List<PartImage> images;

  const Part({
    this.id,
    required this.name,
    this.partNo,
    this.brand,
    this.bikeModel,
    this.category,
    this.quantity = 0,
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.lowStockLevel = 2,
    this.updatedAt,
    this.images = const [],
  });

  bool get isLowStock => quantity <= lowStockLevel;

  factory Part.fromJson(Map<String, dynamic> json) {
    final images = (json['part_images'] as List<dynamic>? ?? [])
        .map((e) => PartImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Part(
      id: json['id'] as String?,
      name: json['name'] as String,
      partNo: json['part_no'] as String?,
      brand: json['brand'] as String?,
      bikeModel: json['bike_model'] as String?,
      category: json['category'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      buyPrice: (json['buy_price'] as num?)?.toDouble() ?? 0,
      sellPrice: (json['sell_price'] as num?)?.toDouble() ?? 0,
      lowStockLevel: (json['low_stock_level'] as num?)?.toInt() ?? 2,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      images: images,
    );
  }

  /// Columns written to the `parts` table (id and timestamps are set by the DB).
  Map<String, dynamic> toRow() => {
        'name': name,
        'part_no': partNo,
        'brand': brand,
        'bike_model': bikeModel,
        'category': category,
        'quantity': quantity,
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'low_stock_level': lowStockLevel,
      };
}
