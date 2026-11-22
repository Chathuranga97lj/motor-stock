import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/part.dart';
import '../utils/paging.dart';
import '../utils/text.dart';
import 'part_import.dart';

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
    // Strip characters that have meaning in PostgREST filter syntax.
    final q = cleanSearch(search);
    // Read in pages: one request returns at most 1000 rows.
    final rows = await fetchAllPages((from, to) {
      var query = _db.from('parts').select(Part.selectColumns);
      if (q.isNotEmpty) {
        query =
            query.or('name.ilike.%$q%,part_no.ilike.%$q%,barcode.ilike.%$q%');
      }
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (brandId != null) query = query.eq('brand_id', brandId);
      if (bikeModelId != null) query = query.eq('bike_model_id', bikeModelId);
      // order() is Z→A unless ascending is set. id keeps pages stable when
      // names repeat. The final sort ignores case, so "signal Bulb" sits next
      // to "Signal Light".
      return query
          .order('name', ascending: true)
          .order('id', ascending: true)
          .range(from, to);
    });
    return rows.map(Part.fromJson).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Part> fetchPart(String id) async {
    final row =
        await _db.from('parts').select(Part.selectColumns).eq('id', id).single();
    return Part.fromJson(row);
  }

  /// The part with this scanned barcode, or null if no part has it.
  Future<Part?> findByBarcode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final row = await _db
        .from('parts')
        .select(Part.selectColumns)
        .eq('barcode', c)
        .maybeSingle();
    return row == null ? null : Part.fromJson(row);
  }

  /// Inserts or updates [part], sets [stock] (branch id -> quantity) for the
  /// given branches, removes [removedImages] and uploads [newImages].
  /// Returns the part's id.
  Future<String> savePart(
    Part part, {
    Map<String, int> stock = const {},
    List<PartImage> removedImages = const [],
    List<NewImage> newImages = const [],
  }) async {
    final String partId;
    try {
      if (part.id == null) {
        final row =
            await _db.from('parts').insert(part.toRow()).select('id').single();
        partId = row['id'] as String;
      } else {
        partId = part.id!;
        await _db.from('parts').update(part.toRow()).eq('id', partId);
      }
    } on PostgrestException catch (e) {
      // The only unique rule on parts is the barcode.
      if (e.code == '23505') {
        throw Exception('This barcode is already used by another part');
      }
      rethrow;
    }

    if (stock.isNotEmpty) {
      await _db.from('stock_levels').upsert([
        for (final e in stock.entries)
          {'part_id': partId, 'branch_id': e.key, 'quantity': e.value},
      ]);
    }

    if (removedImages.isNotEmpty) {
      // Rows first: if this fails the photos are still there to show.
      await _db
          .from('part_images')
          .delete()
          .inFilter('id', removedImages.map((i) => i.id).toList());
      await _removeFiles(removedImages);
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
    return partId;
  }

  /// Sends checked sheet rows to the database. With [dryRun] nothing is
  /// saved and the result says what would happen to each row.
  Future<ImportResult> importParts(
    List<Map<String, dynamic>> rows, {
    required bool dryRun,
    bool updateStock = false,
  }) async {
    try {
      final result = await _db.rpc('import_parts', params: {
        'p_rows': rows,
        'p_dry_run': dryRun,
        'p_update_stock': updateStock,
      });
      return ImportResult.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      // PGRST202: the function is not in the database yet.
      if (e.code == 'PGRST202') {
        throw Exception('Import is not set up in the database yet. Run '
            'supabase/011_import_parts.sql in the Supabase SQL Editor.');
      }
      throw Exception(e.message);
    }
  }

  Future<void> deletePart(Part part) async {
    // The part first (its image rows go with it), then the files, so a
    // failed delete never leaves a part without its photos.
    await _db.from('parts').delete().eq('id', part.id!);
    await _removeFiles(part.images);
  }

  /// Removes photo files whose rows are already deleted. A failure only
  /// leaves an unused file in Storage, so it is not reported.
  Future<void> _removeFiles(List<PartImage> images) async {
    if (images.isEmpty) return;
    try {
      await _db.storage
          .from(_bucket)
          .remove(images.map((i) => i.storagePath).toList());
    } catch (_) {
      // Nothing points at the files any more.
    }
  }
}
