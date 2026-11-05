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
  final String? categoryId;
  final String? brandId;
  final String? bikeModelId;
  // Display names, filled from the linked lists when reading.
  final String? categoryName;
  final String? brandName;
  final String? bikeModelName;
  /// Quantity per branch id. A missing branch means 0.
  final Map<String, int> stock;
  final double buyPrice;
  final double sellPrice;
  final int lowStockLevel;
  final DateTime? updatedAt;
  final List<PartImage> images;

  const Part({
    this.id,
    required this.name,
    this.partNo,
    this.categoryId,
    this.brandId,
    this.bikeModelId,
    this.categoryName,
    this.brandName,
    this.bikeModelName,
    this.stock = const {},
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.lowStockLevel = 2,
    this.updatedAt,
    this.images = const [],
  });

  int quantityAt(String? branchId) => stock[branchId] ?? 0;

  Part withStock(Map<String, int> stock) => Part(
        id: id,
        name: name,
        partNo: partNo,
        categoryId: categoryId,
        brandId: brandId,
        bikeModelId: bikeModelId,
        categoryName: categoryName,
        brandName: brandName,
        bikeModelName: bikeModelName,
        stock: stock,
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        lowStockLevel: lowStockLevel,
        updatedAt: updatedAt,
        images: images,
      );

  int get totalQuantity => stock.values.fold(0, (a, b) => a + b);

  bool isLowStockAt(String? branchId) => quantityAt(branchId) <= lowStockLevel;

  /// Columns to select so the linked names and stock come back with each part.
  static const selectColumns = '*, part_images(*), '
      'stock_levels(branch_id, quantity), '
      'category:category_id(name), brand:brand_id(name), '
      'bike_model:bike_model_id(name)';

  factory Part.fromJson(Map<String, dynamic> json) {
    String? nameOf(String key) =>
        (json[key] as Map<String, dynamic>?)?['name'] as String?;

    final images = (json['part_images'] as List<dynamic>? ?? [])
        .map((e) => PartImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Part(
      id: json['id'] as String?,
      name: json['name'] as String,
      partNo: json['part_no'] as String?,
      categoryId: json['category_id'] as String?,
      brandId: json['brand_id'] as String?,
      bikeModelId: json['bike_model_id'] as String?,
      categoryName: nameOf('category'),
      brandName: nameOf('brand'),
      bikeModelName: nameOf('bike_model'),
      stock: {
        for (final row in (json['stock_levels'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>())
          row['branch_id'] as String: (row['quantity'] as num).toInt(),
      },
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
        'category_id': categoryId,
        'brand_id': brandId,
        'bike_model_id': bikeModelId,
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'low_stock_level': lowStockLevel,
      };
}
