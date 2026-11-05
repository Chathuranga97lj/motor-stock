import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/branch.dart';
import '../models/lookup.dart';
import '../models/part.dart';
import '../services/lookup_service.dart';
import '../services/parts_service.dart';
import '../widgets/lookup_widgets.dart';
import '../widgets/transfer_sheet.dart';

class PartFormScreen extends StatefulWidget {
  const PartFormScreen({
    super.key,
    this.part,
    required this.branches,
    this.branchId,
    this.isSuperAdmin = false,
  });

  /// Only a super admin can delete parts and transfer stock.
  final bool isSuperAdmin;

  /// Null when adding a new part.
  final Part? part;
  final List<Branch> branches;

  /// The branch the user is working in; transfers start from here.
  final String? branchId;

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
  // Stock as last saved, and the editable quantity per branch.
  late Map<String, int> _savedStock = {...?widget.part?.stock};
  late final Map<String, TextEditingController> _quantities = {
    for (final b in widget.branches)
      b.id: TextEditingController(text: '${_savedStock[b.id] ?? 0}'),
  };
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
  // True once a transfer was made, so the list reloads even without saving.
  bool _changedStock = false;

  bool get _isEdit => widget.part != null;
  int get _imageCount => _existingImages.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _partNo, _buyPrice, _sellPrice, _lowStock, //
      ..._quantities.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _transfer() async {
    final result = await showTransferSheet(
      context,
      part: widget.part!.withStock(_savedStock),
      branches: widget.branches,
      fromBranchId: widget.branchId,
    );
    if (result == null || !mounted) return;
    // Apply the move to both the saved stock and the fields on screen.
    void move(String branchId, int delta) {
      _savedStock[branchId] = (_savedStock[branchId] ?? 0) + delta;
      final field = _quantities[branchId]!;
      field.text = '${(int.tryParse(field.text) ?? 0) + delta}';
    }

    setState(() {
      _savedStock = {..._savedStock};
      move(result.fromBranchId, -result.quantity);
      move(result.toBranchId, result.quantity);
      _changedStock = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transferred ${result.quantity}')));
  }

  /// Branch quantities that differ from what is saved (all of them for a new part).
  Map<String, int> _stockToSave() => {
        for (final e in _quantities.entries)
          if (!_isEdit ||
              int.parse(e.value.text) != (_savedStock[e.key] ?? 0))
            e.key: int.parse(e.value.text),
      };

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
      buyPrice: double.tryParse(_buyPrice.text) ?? 0,
      sellPrice: double.tryParse(_sellPrice.text) ?? 0,
      lowStockLevel: int.tryParse(_lowStock.text) ?? 0,
      images: widget.part?.images ?? const [],
    );

    try {
      await _service.savePart(part,
          stock: _stockToSave(),
          removedImages: _removedImages,
          newImages: _newImages);
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
    // After a transfer, going back still tells the list to reload.
    return PopScope(
      canPop: !_changedStock,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final canTransfer =
        widget.isSuperAdmin && _isEdit && widget.branches.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit part' : 'Add part'),
        actions: [
          if (canTransfer)
            IconButton(
              tooltip: 'Transfer stock',
              icon: const Icon(Icons.local_shipping_outlined),
              onPressed: _saving ? null : _transfer,
            ),
          if (_isEdit && widget.isSuperAdmin)
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
              _buildStock(canTransfer),
              _intField(_lowStock, 'Low stock alert at (per branch)'),
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

  Widget _buildStock(bool canTransfer) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Stock by branch',
                      style: theme.textTheme.titleSmall)),
              if (canTransfer)
                TextButton.icon(
                  onPressed: _saving ? null : _transfer,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Transfer'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.branches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('No branches found. Run the branches SQL migration.',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          for (final b in widget.branches)
            _intField(_quantities[b.id]!,
                '${b.name}${b.isMain ? ' (main)' : ''} quantity'),
        ],
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
