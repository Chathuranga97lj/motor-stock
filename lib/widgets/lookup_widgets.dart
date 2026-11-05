import 'package:flutter/material.dart';

import '../models/lookup.dart';

/// Asks for a name. Returns null if cancelled.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String? helperText,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final text = controller.text.trim();
        if (text.isNotEmpty) Navigator.pop(context, text);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Name', helperText: helperText),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Save')),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}

/// A dropdown over one lookup list. Entries are managed on the Lists screen.
class LookupDropdown extends StatelessWidget {
  const LookupDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final List<LookupItem> items;
  final String? selectedId;
  final ValueChanged<String?>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    // Rebuild the field when the selection or list changes from outside.
    final value = items.any((i) => i.id == selectedId) ? selectedId : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('$label|$value|${items.length}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, helperText: hint),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
          for (final item in items)
            DropdownMenuItem<String?>(
                value: item.id,
                child: Text(item.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
