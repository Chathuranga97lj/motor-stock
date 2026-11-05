import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/part.dart';

const maxImagesPerPart = 3;
const _bucket = 'part-images';

/// A picked image not yet uploaded.
class NewImage {
  final Uint8List bytes;
  final String extension; // jpg, png, webp

  const NewImage(this.bytes, this.extension);

  String get contentType => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

class PartsService {
  PartsService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static const _uuid = Uuid();

  String imageUrl(PartImage image) =>
      _db.storage.from(_bucket).getPublicUrl(image.storagePath);

  Future<List<Part>> fetchParts({
    String search = '',
    String? categoryId,
    String? brandId,
    String? bikeModelId,
  }) async {
    var query = _db.from('parts').select(Part.selectColumns);
    // Strip characters that have meaning in PostgREST filter syntax.
    final q = search.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.isNotEmpty) {
      query = query.or('name.ilike.%$q%,part_no.ilike.%$q%');
    }
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (brandId != null) query = query.eq('brand_id', brandId);
    if (bikeModelId != null) query = query.eq('bike_model_id', bikeModelId);
    final rows = await query.order('name');
    return rows.map(Part.fromJson).toList();
  }

  /// Inserts or updates [part], sets [stock] (branch id -> quantity) for the
  /// given branches, removes [removedImages] and uploads [newImages].
  Future<void> savePart(
    Part part, {
    Map<String, int> stock = const {},
    List<PartImage> removedImages = const [],
    List<NewImage> newImages = const [],
  }) async {
    final String partId;
    if (part.id == null) {
      final row =
          await _db.from('parts').insert(part.toRow()).select('id').single();
      partId = row['id'] as String;
    } else {
      partId = part.id!;
      await _db.from('parts').update(part.toRow()).eq('id', partId);
    }

    if (stock.isNotEmpty) {
      await _db.from('stock_levels').upsert([
        for (final e in stock.entries)
          {'part_id': partId, 'branch_id': e.key, 'quantity': e.value},
      ]);
    }

    if (removedImages.isNotEmpty) {
      await _db.storage
          .from(_bucket)
          .remove(removedImages.map((i) => i.storagePath).toList());
      await _db
          .from('part_images')
          .delete()
          .inFilter('id', removedImages.map((i) => i.id).toList());
    }

    final keptCount = part.images.length - removedImages.length;
    for (final (index, image) in newImages.indexed) {
      final path = '$partId/${_uuid.v4()}.${image.extension}';
      await _db.storage.from(_bucket).uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(contentType: image.contentType),
          );
      await _db.from('part_images').insert({
        'part_id': partId,
        'storage_path': path,
        'sort_order': keptCount + index,
      });
    }
  }

  Future<void> deletePart(Part part) async {
    if (part.images.isNotEmpty) {
      await _db.storage
          .from(_bucket)
          .remove(part.images.map((i) => i.storagePath).toList());
    }
    await _db.from('parts').delete().eq('id', part.id!);
  }
}
