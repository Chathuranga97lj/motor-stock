import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lookup.dart';
import '../models/part.dart';
import '../services/lookup_service.dart';
import '../services/parts_service.dart';
import '../widgets/lookup_widgets.dart';

class PartFormScreen extends StatefulWidget {
  const PartFormScreen({super.key, this.part});

  /// Null when adding a new part.
  final Part? part;

  @override
  State<PartFormScreen> createState() => _PartFormScreenState();
}

class _PartFormScreenState extends State<PartFormScreen> {
  final _service = PartsService();
  final _lookupService = LookupService();
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.part?.name);
  late final _partNo = TextEditingController(text: widget.part?.partNo);
  late String? _categoryId = widget.part?.categoryId;
  late String? _brandId = widget.part?.brandId;
  late String? _modelId = widget.part?.bikeModelId;
  Lookups _lookups = const Lookups();
  late final _quantity =
      TextEditingController(text: '${widget.part?.quantity ?? 0}');
  late final _buyPrice = TextEditingController(
      text: widget.part?.buyPrice.toStringAsFixed(2) ?? '');
  late final _sellPrice = TextEditingController(
      text: widget.part?.sellPrice.toStringAsFixed(2) ?? '');
  late final _lowStock =
      TextEditingController(text: '${widget.part?.lowStockLevel ?? 2}');

  late final List<PartImage> _existingImages = [...?widget.part?.images];
  final List<PartImage> _removedImages = [];
  final List<NewImage> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.part != null;
  int get _imageCount => _existingImages.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in [_name, _partNo, _quantity, _buyPrice, _sellPrice, _lowStock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLookups() async {
    try {
      final lookups = await _lookupService.fetchAll();
      if (mounted) setState(() => _lookups = lookups);
    } catch (e) {
      _showError('Could not load lists: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImages(ImageSource source) async {
    final remaining = maxImagesPerPart - _imageCount;
    if (remaining <= 0) return;

    // Resize and compress on pick to keep each image ~100-300 KB.
    const maxSide = 1280.0;
    const quality = 75;
    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final file = await _picker.pickImage(
          source: source, maxWidth: maxSide, maxHeight: maxSide,
          imageQuality: quality);
      picked = file == null ? [] : [file];
    } else {
      picked = await _picker.pickMultiImage(
          maxWidth: maxSide, maxHeight: maxSide, imageQuality: quality,
          limit: remaining > 1 ? remaining : null);
    }

    final images = <NewImage>[];
    for (final file in picked.take(remaining)) {
      final ext = file.name.split('.').last.toLowerCase();
      images.add(NewImage(
        await file.readAsBytes(),
        const ['png', 'webp'].contains(ext) ? ext : 'jpg',
      ));
    }
    if (mounted) setState(() => _newImages.addAll(images));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final part = Part(
      id: widget.part?.id,
      name: _name.text.trim(),
      partNo: opt(_partNo),
      categoryId: _categoryId,
      brandId: _brandId,
      bikeModelId: _brandId == null ? null : _modelId,
      quantity: int.parse(_quantity.text),
      buyPrice: double.tryParse(_buyPrice.text) ?? 0,
      sellPrice: double.tryParse(_sellPrice.text) ?? 0,
      lowStockLevel: int.tryParse(_lowStock.text) ?? 0,
      images: widget.part?.images ?? const [],
    );

    try {
      await _service.savePart(part,
          removedImages: _removedImages, newImages: _newImages);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete part?'),
        content: Text('"${widget.part!.name}" and its images will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _service.deletePart(widget.part!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit part' : 'Add part'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildImages(),
              const SizedBox(height: 16),
              _field(_name, 'Part name *',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null),
              _field(_partNo, 'Part number'),
              LookupDropdown(
                label: LookupKind.category.label,
                items: _lookups.categories,
                selectedId: _categoryId,
                onChanged: (id) => setState(() => _categoryId = id),
              ),
              LookupDropdown(
                label: LookupKind.brand.label,
                items: _lookups.brands,
                selectedId: _brandId,
                onChanged: (id) => setState(() {
                  if (id != _brandId) _modelId = null;
                  _brandId = id;
                }),
              ),
              LookupDropdown(
                label: LookupKind.model.label,
                items: _lookups.modelsOf(_brandId),
                selectedId: _modelId,
                hint: _brandId == null ? 'Choose a brand first' : null,
                onChanged: _brandId == null
                    ? null
                    : (id) => setState(() => _modelId = id),
              ),
              Row(children: [
                Expanded(child: _intField(_quantity, 'Quantity *')),
                const SizedBox(width: 12),
                Expanded(child: _intField(_lowStock, 'Low stock alert at')),
              ]),
              Row(children: [
                Expanded(child: _priceField(_buyPrice, 'Buy price')),
                const SizedBox(width: 12),
                Expanded(child: _priceField(_sellPrice, 'Sell price')),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImages() {
    final tiles = <Widget>[
      for (final image in _existingImages)
        _ImageTile(
          image: Image.network(_service.imageUrl(image), fit: BoxFit.cover),
          onRemove: () => setState(() {
            _existingImages.remove(image);
            _removedImages.add(image);
          }),
        ),
      for (final image in _newImages)
        _ImageTile(
          image: Image.memory(image.bytes, fit: BoxFit.cover),
          onRemove: () => setState(() => _newImages.remove(image)),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos ($_imageCount/$maxImagesPerPart)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...tiles,
              if (_imageCount < maxImagesPerPart) ...[
                _AddImageButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => _pickImages(ImageSource.gallery),
                ),
                _AddImageButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  onTap: () => _pickImages(ImageSource.camera),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? Function(String?)? validator,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: TextCapitalization.words,
      ),
    );
  }

  Widget _intField(TextEditingController c, String label) => _field(
        c,
        label,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a number' : null,
      );

  Widget _priceField(TextEditingController c, String label) => _field(
        c,
        label,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
      );
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, required this.onRemove});

  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 100, height: 100, child: image),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: 'Remove photo',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageButton extends StatelessWidget {
  const _AddImageButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 100,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
          ),
          onPressed: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon), const SizedBox(height: 4), Text(label)],
          ),
        ),
      ),
    );
  }
}
