import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Most rows one import can send.
const maxImportRows = 2000;

/// A problem with the whole file (wrong type, no header row, ...).
class ImportFileException implements Exception {
  ImportFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Reading the file into a table of text cells.

/// Reads an .xlsx or .csv file into rows of cell text. Row i of the result
/// is row i + 1 of the sheet (empty rows are kept as empty lists).
List<List<String>> readSheetTable(Uint8List bytes, String fileName) {
  final ext = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
      : '';
  switch (ext) {
    case 'xlsx':
    case 'xlsm':
      return readXlsx(bytes);
    case 'csv':
    case 'txt':
      return readCsv(_decodeText(bytes));
    case 'xls':
      throw ImportFileException('Old .xls files cannot be read. In Excel, use '
          'File > Save As > Excel Workbook (.xlsx), then import that file.');
    default:
      throw ImportFileException('Choose an Excel (.xlsx) or CSV (.csv) file.');
  }
}

String _decodeText(Uint8List bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    b = Uint8List.sublistView(b, 3);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    // Excel on Windows often saves CSV in the Windows code page.
    return latin1.decode(b);
  }
}

/// Reads the sheet named "Parts", or else the first sheet.
List<List<String>> readXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw ImportFileException('This file could not be opened as an Excel '
        '(.xlsx) file.');
  }
  String? text(String path) {
    final f = zip.findFile(path);
    final data = f?.readBytes();
    return data == null ? null : utf8.decode(data, allowMalformed: true);
  }

  XmlDocument parse(String? xml, String what) {
    if (xml == null) {
      throw ImportFileException('This Excel file has no $what.');
    }
    try {
      return XmlDocument.parse(xml);
    } catch (_) {
      throw ImportFileException('This Excel file is damaged ($what).');
    }
  }

  Iterable<XmlElement> all(XmlNode n, String name) =>
      n.findAllElements(name, namespaceUri: '*');

  // Pick the sheet and find its file.
  final workbook = parse(text('xl/workbook.xml'), 'workbook');
  final sheets = all(workbook, 'sheet').toList();
  if (sheets.isEmpty) throw ImportFileException('This Excel file has no sheets.');
  final sheet = sheets.firstWhere(
    (s) => (s.getAttribute('name') ?? '').trim().toLowerCase() == 'parts',
    orElse: () => sheets.first,
  );
  final relId = sheet.getAttribute('id', namespaceUri: '*');
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final relsXml = text('xl/_rels/workbook.xml.rels');
  if (relsXml != null && relId != null) {
    final rels = parse(relsXml, 'sheet list');
    for (final rel in all(rels, 'Relationship')) {
      if (rel.getAttribute('Id') == relId) {
        final target = rel.getAttribute('Target') ?? '';
        sheetPath =
            target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
  }

  // Shared text (most cells point into this list).
  final shared = <String>[];
  final sharedXml = text('xl/sharedStrings.xml');
  if (sharedXml != null) {
    for (final si in all(parse(sharedXml, 'text list'), 'si')) {
      shared.add(_cellText(si));
    }
  }

  // Number formats like "00000" that show leading zeros on numbers.
  final zeroPad = <int, int>{}; // style index -> digits
  final stylesXml = text('xl/styles.xml');
  if (stylesXml != null) {
    try {
      final styles = XmlDocument.parse(stylesXml);
      final custom = <String, String>{
        for (final f in all(styles, 'numFmt'))
          f.getAttribute('numFmtId') ?? '': f.getAttribute('formatCode') ?? '',
      };
      final cellXfs = all(styles, 'cellXfs').firstOrNull;
      if (cellXfs != null) {
        final xfs = cellXfs.findElements('xf', namespaceUri: '*').toList();
        for (var i = 0; i < xfs.length; i++) {
          final code = custom[xfs[i].getAttribute('numFmtId')] ?? '';
          if (RegExp(r'^0+$').hasMatch(code)) zeroPad[i] = code.length;
        }
      }
    } catch (_) {
      // Formats only add leading zeros; the values still read without them.
    }
  }

  final doc = parse(text(sheetPath), 'sheet');
  final table = <List<String>>[];
  var nextRow = 0;
  for (final row in all(doc, 'row')) {
    final r = int.tryParse(row.getAttribute('r') ?? '');
    final rowIndex = r != null ? r - 1 : nextRow;
    nextRow = rowIndex + 1;
    while (table.length <= rowIndex) {
      table.add([]);
    }
    final cells = table[rowIndex];
    var nextCol = 0;
    for (final c in row.findElements('c', namespaceUri: '*')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? nextCol : _colIndex(ref);
      nextCol = col + 1;
      final type = c.getAttribute('t') ?? 'n';
      final v = c.findElements('v', namespaceUri: '*').firstOrNull?.innerText;
      String value;
      switch (type) {
        case 's':
          final i = int.tryParse(v ?? '');
          value = i != null && i >= 0 && i < shared.length ? shared[i] : '';
        case 'inlineStr':
          final isEl = c.findElements('is', namespaceUri: '*').firstOrNull;
          value = isEl == null ? '' : _cellText(isEl);
        case 'str':
          value = v ?? '';
        case 'b':
          value = v == '1' ? 'TRUE' : 'FALSE';
        case 'e':
          value = '';
        default:
          value = _numberText(v ?? '');
          final pad = zeroPad[int.tryParse(c.getAttribute('s') ?? '') ?? -1];
          if (pad != null && RegExp(r'^\d+$').hasMatch(value)) {
            value = value.padLeft(pad, '0');
          }
      }
      while (cells.length <= col) {
        cells.add('');
      }
      cells[col] = value;
    }
  }
  return table;
}

/// Text of a shared-string item or inline string, without phonetic hints.
String _cellText(XmlElement e) {
  final b = StringBuffer();
  for (final t in e.findAllElements('t', namespaceUri: '*')) {
    if (t.parentElement?.localName == 'rPh') continue;
    b.write(t.innerText);
  }
  return b.toString();
}

/// "B12" -> 1
int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Excel stores 3159.99 as "3159.9899999999998"; show it as people typed it.
String _numberText(String raw) {
  final d = double.tryParse(raw);
  if (d == null || !d.isFinite) return raw;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

/// Splits CSV text into rows. Handles quotes, and ; or tab separators.
List<List<String>> readCsv(String text) {
  final firstLine = text.split('\n').first;
  final sep = [';', '\t'].firstWhere(
    (s) => s.allMatches(firstLine).length > ','.allMatches(firstLine).length,
    orElse: () => ',',
  );
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Turning the table into part rows.

enum ImportField {
  name('Name'),
  partNo('Part No'),
  barcode('Barcode'),
  category('Category'),
  brand('Bike Brand'),
  model('Bike Model'),
  buyPrice('Buy Price'),
  sellPrice('Sell Price'),
  quantity('Quantity'),
  lowStock('Low Stock Level');

  const ImportField(this.label);
  final String label;
}

/// Header spellings each field accepts, after [_headerKey].
const _aliases = <ImportField, Set<String>>{
  ImportField.name: {
    'name', 'partname', 'itemname', 'item', 'description', 'itemdescription',
    'partdescription', 'productname', 'product',
  },
  ImportField.partNo: {
    'partno', 'partnumber', 'partnum', 'itemcode', 'code', 'itemno',
    'itemnumber', 'partcode', 'productcode', 'sku', 'number',
  },
  ImportField.barcode: {
    'barcode', 'qr', 'qrcode', 'barcodeqr', 'barcodeqrcode', 'ean',
  },
  ImportField.category: {'category', 'categories', 'cat', 'type', 'group'},
  ImportField.brand: {'bikebrand', 'brand', 'make', 'bikemake'},
  ImportField.model: {'bikemodel', 'model', 'bike', 'vehiclemodel'},
  ImportField.buyPrice: {
    'buyprice', 'buyingprice', 'unitprice', 'cost', 'costprice', 'unitcost',
    'purchaseprice', 'buy',
  },
  ImportField.sellPrice: {
    'sellprice', 'sellingprice', 'saleprice', 'salesprice', 'price',
    'retailprice', 'mrp', 'sell',
  },
  ImportField.quantity: {
    'quantity', 'qty', 'quitity', 'quantiy', 'qunatity', 'quntity',
    'quanity', 'stock', 'openingstock', 'openingqty', 'instock', 'count',
  },
  ImportField.lowStock: {
    'lowstocklevel', 'lowstock', 'reorderlevel', 'reorder', 'minstock',
    'minqty', 'minimumstock', 'lowlevel',
  },
};

String _headerKey(String h) =>
    h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _tidy(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
String _tidyUpper(String s) => _tidy(s).toUpperCase();

/// A branch a quantity column can belong to.
class ImportBranch {
  const ImportBranch(this.id, this.name);
  final String id;
  final String name;
}

/// One sheet row, tidied and checked.
class ImportRow {
  ImportRow({
    required this.rowNo,
    required this.name,
    this.partNo,
    this.barcode,
    this.category,
    this.brand,
    this.model,
    this.buyPrice,
    this.sellPrice,
    this.lowStock,
    this.stock = const {},
    this.quantity,
    List<String>? errors,
    List<String>? warnings,
  })  : errors = errors ?? [],
        warnings = warnings ?? [];

  /// Row number in the sheet (1 = header row).
  final int rowNo;
  final String name;
  final String? partNo;
  final String? barcode;
  final String? category;
  final String? brand;
  final String? model;
  final double? buyPrice;
  final double? sellPrice;
  final int? lowStock;

  /// Branch id -> quantity, from "`BRANCH` Qty" columns.
  final Map<String, int> stock;

  /// From a plain Quantity column; goes to the branch picked on import.
  final int? quantity;

  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;

  /// Quantities to send: branch columns, plus the plain column at [branchId].
  Map<String, int> stockFor(String? branchId) => {
        ...stock,
        if (quantity != null && branchId != null && !stock.containsKey(branchId))
          branchId: quantity!,
      };

  Map<String, dynamic> toJson({String? quantityBranchId}) => {
        'row': rowNo,
        'name': name,
        'part_no': partNo,
        'barcode': barcode,
        'category': category,
        'brand': brand,
        'model': model,
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'low_stock_level': lowStock,
        'stock': stockFor(quantityBranchId),
      };
}

/// The rows of a sheet and how its columns were read.
class ImportSheet {
  ImportSheet({
    required this.rows,
    required this.headerRow,
    required this.columns,
    required this.branchColumns,
    required this.ignoredColumns,
    required this.hasQuantityColumn,
    required this.blankRows,
  });

  final List<ImportRow> rows;
  final int headerRow;

  /// Field -> header text as written in the sheet.
  final Map<ImportField, String> columns;

  /// Branch id -> header text.
  final Map<String, String> branchColumns;
  final List<String> ignoredColumns;

  /// True when the sheet has a plain Quantity column (no branch in its name).
  final bool hasQuantityColumn;
  final int blankRows;

  List<ImportRow> get validRows => rows.where((r) => r.isValid).toList();
  int get errorCount => rows.where((r) => !r.isValid).length;
}

/// Finds the header row, maps its columns and checks every row.
ImportSheet parseImportSheet(
  List<List<String>> table,
  List<ImportBranch> branches,
) {
  // The header is the first row (of the first 10) with a Name column.
  var headerIndex = -1;
  for (var i = 0; i < table.length && i < 10; i++) {
    if (table[i].any((h) => _aliases[ImportField.name]!.contains(_headerKey(h)))) {
      headerIndex = i;
      break;
    }
  }
  if (headerIndex < 0) {
    throw ImportFileException('Could not find the column names. The first row '
        'should have them: Name, Part No, Category, Sell Price, ...');
  }

  final header = table[headerIndex];
  final fieldCol = <ImportField, int>{};
  final branchCol = <String, int>{};
  final columns = <ImportField, String>{};
  final branchColumns = <String, String>{};
  final ignored = <String>[];
  for (var c = 0; c < header.length; c++) {
    final text = _tidy(header[c]);
    final key = _headerKey(text);
    if (key.isEmpty) continue;

    // "<BRANCH> Qty", "Qty <BRANCH>" or just the branch name.
    final branch = branches.where((b) {
      final bk = _headerKey(b.name);
      if (bk.isEmpty || !key.contains(bk)) return false;
      final rest = key.replaceFirst(bk, '');
      return rest.isEmpty || _aliases[ImportField.quantity]!.contains(rest);
    }).firstOrNull;
    if (branch != null && !branchCol.containsKey(branch.id)) {
      branchCol[branch.id] = c;
      branchColumns[branch.id] = text;
      continue;
    }

    final field = ImportField.values
        .where((f) => _aliases[f]!.contains(key))
        .firstOrNull;
    if (field != null && !fieldCol.containsKey(field)) {
      fieldCol[field] = c;
      columns[field] = text;
    } else {
      ignored.add(text);
    }
  }

  // With branch columns, a plain Quantity column would be ambiguous.
  final hasQuantity = fieldCol.containsKey(ImportField.quantity);
  if (hasQuantity && branchCol.isNotEmpty) {
    ignored.add(columns.remove(ImportField.quantity)!);
    fieldCol.remove(ImportField.quantity);
  }

  final rows = <ImportRow>[];
  var blank = 0;
  final seenKeys = <String, int>{};
  final seenCodes = <String, int>{};
  for (var i = headerIndex + 1; i < table.length; i++) {
    final cells = table[i];
    String cell(int? c) => c == null || c >= cells.length ? '' : cells[c].trim();
    String get(ImportField f) => cell(fieldCol[f]);

    final used = [
      ...fieldCol.values.map(cell),
      ...branchCol.values.map(cell),
    ];
    if (used.every((v) => v.isEmpty)) {
      blank++;
      continue;
    }

    final rowNo = i + 1;
    final errors = <String>[];
    final warnings = <String>[];

    double? money(ImportField f) {
      final raw = get(f);
      if (raw.isEmpty) return null;
      final v = _parseNumber(raw);
      if (v == null) {
        errors.add('${f.label} "$raw" is not a number');
        return null;
      }
      if (v < 0) {
        errors.add('${f.label} cannot be below 0');
        return null;
      }
      return (v * 100).roundToDouble() / 100;
    }

    int? whole(String label, String raw) {
      if (raw.isEmpty) return null;
      final v = _parseNumber(raw);
      if (v == null) {
        errors.add('$label "$raw" is not a number');
        return null;
      }
      if (v < 0) {
        errors.add('$label cannot be below 0');
        return null;
      }
      if (v != v.roundToDouble()) {
        errors.add('$label must be a whole number');
        return null;
      }
      return v.toInt();
    }

    String? optional(String v) => v.isEmpty ? null : v;

    final name = _tidy(get(ImportField.name));
    final partNo = optional(_tidyUpper(get(ImportField.partNo)));
    final barcode = optional(get(ImportField.barcode));
    final category = optional(_tidyUpper(get(ImportField.category)));
    final brand = optional(_tidyUpper(get(ImportField.brand)));
    final model = optional(_tidyUpper(get(ImportField.model)));
    final buy = money(ImportField.buyPrice);
    final sell = money(ImportField.sellPrice);
    final low = whole(ImportField.lowStock.label, get(ImportField.lowStock));
    final quantity = whole(ImportField.quantity.label, get(ImportField.quantity));
    final stock = <String, int>{};
    branchCol.forEach((branchId, c) {
      final q = whole(branchColumns[branchId]!, cell(c));
      if (q != null) stock[branchId] = q;
    });

    if (name.isEmpty) errors.insert(0, 'No name');
    if (model != null && brand == null) {
      errors.add('Bike model needs a bike brand');
    }
    if (name.isNotEmpty) {
      final key = '${name.toUpperCase()}|${partNo ?? ''}';
      final first = seenKeys[key];
      if (first != null) {
        errors.add('Same name and part no as row $first');
      } else {
        seenKeys[key] = rowNo;
      }
    }
    if (barcode != null) {
      final first = seenCodes[barcode];
      if (first != null) {
        errors.add('Same barcode as row $first');
      } else {
        seenCodes[barcode] = rowNo;
      }
    }

    if (fieldCol.containsKey(ImportField.sellPrice) &&
        sell == null &&
        get(ImportField.sellPrice).isEmpty) {
      warnings.add('No selling price (saved as 0)');
    }
    if (buy != null && sell != null && buy > sell) {
      warnings.add('Buy price is more than the selling price');
    }
    final quantities = [?quantity, ...stock.values];
    final high = quantities.where((q) => q > 500).firstOrNull;
    if (high != null) warnings.add('Very high quantity ($high), check it');

    rows.add(ImportRow(
      rowNo: rowNo,
      name: name,
      partNo: partNo,
      barcode: barcode,
      category: category,
      brand: brand,
      model: model,
      buyPrice: buy,
      sellPrice: sell,
      lowStock: low,
      stock: stock,
      quantity: quantity,
      errors: errors,
      warnings: warnings,
    ));
  }

  if (rows.isEmpty) {
    throw ImportFileException('The sheet has no parts under the column names.');
  }
  if (rows.length > maxImportRows) {
    throw ImportFileException('The sheet has ${rows.length} rows. Import at '
        'most $maxImportRows at a time: split it into smaller files.');
  }

  return ImportSheet(
    rows: rows,
    headerRow: headerIndex + 1,
    columns: columns,
    branchColumns: branchColumns,
    ignoredColumns: ignored,
    hasQuantityColumn: fieldCol.containsKey(ImportField.quantity),
    blankRows: blank,
  );
}

/// "Rs. 1,250.00" -> 1250. Null when it is not a number.
double? _parseNumber(String raw) {
  var s = raw.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'^(rs\.?|lkr)\s*'), '');
  s = s.replaceAll(RegExp(r'[,\s]'), '');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

// ---------------------------------------------------------------------------
// What the database said it did (or would do).

enum ImportAction { create, update, skip }

class ImportOutcome {
  const ImportOutcome(this.action, this.message);
  final ImportAction action;
  final String? message;
}

class ImportResult {
  const ImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.outcomes,
    required this.newCategories,
    required this.newBrands,
    required this.newModels,
  });

  final int created;
  final int updated;
  final int skipped;

  /// Row number -> outcome.
  final Map<int, ImportOutcome> outcomes;
  final List<String> newCategories;
  final List<String> newBrands;
  final List<String> newModels;

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    List<String> names(String key) =>
        ((json[key] as List?) ?? const []).map((e) => '$e').toList();
    return ImportResult(
      created: (json['created'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      outcomes: {
        for (final r in (json['rows'] as List? ?? const []))
          ((r as Map)['row'] as num).toInt(): ImportOutcome(
            switch (r['action']) {
              'new' => ImportAction.create,
              'update' => ImportAction.update,
              _ => ImportAction.skip,
            },
            r['message'] as String?,
          ),
      },
      newCategories: names('new_categories'),
      newBrands: names('new_brands'),
      newModels: names('new_models'),
    );
  }
}
