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

  Future<List<Part>> fetchParts({String search = ''}) async {
    var query = _db.from('parts').select('*, part_images(*)');
    // Strip characters that have meaning in PostgREST filter syntax.
    final q = search.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.isNotEmpty) {
      query = query.or(
        'name.ilike.%$q%,part_no.ilike.%$q%,brand.ilike.%$q%,bike_model.ilike.%$q%',
      );
    }
    final rows = await query.order('name');
    return rows.map(Part.fromJson).toList();
  }

  /// Inserts or updates [part], removes [removedImages] and uploads [newImages].
  Future<void> savePart(
    Part part, {
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

  /// Adds [delta] (can be negative) to the part's quantity.
  Future<void> adjustQuantity(Part part, int delta) async {
    final next = (part.quantity + delta).clamp(0, 1 << 31);
    await _db.from('parts').update({'quantity': next}).eq('id', part.id!);
  }
}
