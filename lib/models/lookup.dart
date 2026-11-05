/// The three dropdown lists a part can be tagged with.
enum LookupKind {
  category('categories', 'Category', 'Categories'),
  brand('brands', 'Bike brand', 'Brands'),
  model('bike_models', 'Bike model', 'Models');

  const LookupKind(this.table, this.label, this.pluralLabel);

  final String table;
  final String label;
  final String pluralLabel;
}

/// One entry of a dropdown list. [brandId] is set only for bike models.
class LookupItem {
  final String id;
  final String name;
  final String? brandId;

  const LookupItem({required this.id, required this.name, this.brandId});

  factory LookupItem.fromJson(Map<String, dynamic> json) => LookupItem(
        id: json['id'] as String,
        name: json['name'] as String,
        brandId: json['brand_id'] as String?,
      );
}

/// All dropdown lists, loaded together.
class Lookups {
  final List<LookupItem> categories;
  final List<LookupItem> brands;
  final List<LookupItem> models;

  const Lookups({
    this.categories = const [],
    this.brands = const [],
    this.models = const [],
  });

  List<LookupItem> of(LookupKind kind) => switch (kind) {
        LookupKind.category => categories,
        LookupKind.brand => brands,
        LookupKind.model => models,
      };

  List<LookupItem> modelsOf(String? brandId) =>
      brandId == null ? const [] : models.where((m) => m.brandId == brandId).toList();
}
