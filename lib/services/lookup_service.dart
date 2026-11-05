import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lookup.dart';

class LookupService {
  LookupService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static String normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  Future<Lookups> fetchAll() async {
    final results = await Future.wait([
      _db.from(LookupKind.category.table).select('id, name').order('name'),
      _db.from(LookupKind.brand.table).select('id, name').order('name'),
      _db.from(LookupKind.model.table).select('id, name, brand_id').order('name'),
    ]);
    List<LookupItem> parse(List<Map<String, dynamic>> rows) =>
        rows.map(LookupItem.fromJson).toList();
    return Lookups(
      categories: parse(results[0]),
      brands: parse(results[1]),
      models: parse(results[2]),
    );
  }

  /// Adds an entry and returns it. [brandId] is required for models.
  Future<LookupItem> add(LookupKind kind, String name, {String? brandId}) async {
    try {
      final row = await _db
          .from(kind.table)
          .insert({
            'name': normalize(name),
            if (kind == LookupKind.model) 'brand_id': brandId,
          })
          .select()
          .single();
      return LookupItem.fromJson(row);
    } on PostgrestException catch (e) {
      throw _friendly(e, kind);
    }
  }

  Future<void> rename(LookupKind kind, LookupItem item, String name) async {
    try {
      await _db
          .from(kind.table)
          .update({'name': normalize(name)}).eq('id', item.id);
    } on PostgrestException catch (e) {
      throw _friendly(e, kind);
    }
  }

  Future<void> delete(LookupKind kind, LookupItem item) =>
      _db.from(kind.table).delete().eq('id', item.id);

  /// How many parts use this entry (shown before deleting).
  Future<int> usageCount(LookupKind kind, LookupItem item) async {
    final column = switch (kind) {
      LookupKind.category => 'category_id',
      LookupKind.brand => 'brand_id',
      LookupKind.model => 'bike_model_id',
    };
    return _db.from('parts').count().eq(column, item.id);
  }

  Exception _friendly(PostgrestException e, LookupKind kind) =>
      Exception(e.code == '23505'
          ? '${kind.label} already exists'
          : e.message);
}
