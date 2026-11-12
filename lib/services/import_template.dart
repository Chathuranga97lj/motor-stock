import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Column headers of the parts import sheet, in order. Branch quantity
/// columns ("`BRANCH` Qty") go between [templateHeadersBeforeQty] and
/// [templateHeadersAfterQty].
const templateHeadersBeforeQty = [
  'Name',
  'Part No',
  'Barcode',
  'Category',
  'Bike Brand',
  'Bike Model',
  'Buy Price',
  'Sell Price',
];
const templateHeadersAfterQty = ['Low Stock Level'];

String branchQtyHeader(String branch) => '$branch Qty';

/// One example row for the Parts sheet. [qty] is keyed by branch name.
class TemplateExample {
  const TemplateExample({
    required this.name,
    this.partNo = '',
    this.barcode = '',
    this.category = '',
    this.brand = '',
    this.model = '',
    this.buyPrice,
    this.sellPrice,
    this.qty = const {},
    this.lowStock,
  });

  final String name;
  final String partNo;
  final String barcode;
  final String category;
  final String brand;
  final String model;
  final num? buyPrice;
  final num? sellPrice;
  final Map<String, int> qty;
  final int? lowStock;
}

/// Names already in the app, shown on the Lists sheet and offered as
/// drop-downs (typing a new name is still allowed).
class TemplateLists {
  const TemplateLists({
    this.categories = const [],
    this.brands = const [],
    this.models = const [],
  });

  final List<String> categories;
  final List<String> brands;

  /// (brand, model) pairs.
  final List<(String, String)> models;
}

/// Builds the parts import workbook: a Parts sheet to fill in, a How to fill
/// sheet and a Lists sheet with the names already in the app.
Uint8List buildImportTemplate({
  required List<String> branches,
  TemplateLists lists = const TemplateLists(),
  List<TemplateExample> examples = const [],
}) {
  final headers = [
    ...templateHeadersBeforeQty,
    ...branches.map(branchQtyHeader),
    ...templateHeadersAfterQty,
  ];
  final colOf = {for (var i = 0; i < headers.length; i++) headers[i]: i};

  // ---------- Parts sheet ----------
  final parts = _SheetWriter();
  parts.row([
    for (final h in headers)
      _Cell(h, h == 'Name' ? _Style.headerRequired : _Style.header),
  ], height: 30);
  for (final e in examples) {
    final cells = List<_Cell?>.filled(headers.length, null);
    void put(String header, Object? v, _Style style) {
      if (v == null || (v is String && v.isEmpty)) return;
      cells[colOf[header]!] = _Cell(v, style);
    }

    put('Name', e.name, _Style.text);
    put('Part No', e.partNo, _Style.textFormat);
    put('Barcode', e.barcode, _Style.textFormat);
    put('Category', e.category, _Style.text);
    put('Bike Brand', e.brand, _Style.text);
    put('Bike Model', e.model, _Style.text);
    put('Buy Price', e.buyPrice, _Style.money);
    put('Sell Price', e.sellPrice, _Style.money);
    for (final b in branches) {
      put(branchQtyHeader(b), e.qty[b], _Style.whole);
    }
    put('Low Stock Level', e.lowStock, _Style.whole);
    parts.row(cells);
  }
  final widths = <double>[
    for (final h in headers)
      switch (h) {
        'Name' => 30,
        'Part No' => 20,
        'Barcode' => 18,
        'Category' => 23,
        'Bike Brand' => 14,
        'Bike Model' => 16,
        'Low Stock Level' => 15,
        _ => 14,
      },
  ];
  // Text format on Part No / Barcode keeps leading zeros (01210).
  final columnStyles = <int, _Style>{
    for (final h in headers)
      colOf[h]!: switch (h) {
        'Part No' || 'Barcode' => _Style.textFormat,
        'Buy Price' || 'Sell Price' => _Style.money,
        'Low Stock Level' => _Style.whole,
        _ when h.endsWith(' Qty') => _Style.whole,
        _ => _Style.text,
      },
  };
  const lastRow = 2000;
  final validations = <String>[];
  String listRef(int col, int count) {
    final c = _colName(col);
    return "Lists!\$$c\$2:\$$c\$${count + 1}";
  }

  void listValidation(String header, int listCol, int count) {
    if (count == 0) return;
    final c = _colName(colOf[header]!);
    // showErrorMessage off: the list is a suggestion, new names are allowed.
    validations.add('<dataValidation type="list" allowBlank="1" '
        'showInputMessage="1" showErrorMessage="0" sqref="${c}2:$c$lastRow">'
        '<formula1>${_esc(listRef(listCol, count))}</formula1></dataValidation>');
  }

  listValidation('Category', 0, lists.categories.length);
  listValidation('Bike Brand', 2, lists.brands.length);
  listValidation('Bike Model', 5, lists.models.length);
  void numberValidation(String header, String type, String message) {
    final c = _colName(colOf[header]!);
    validations.add('<dataValidation type="$type" operator="greaterThanOrEqual" '
        'allowBlank="1" showErrorMessage="1" errorTitle="Check this number" '
        'error="${_esc(message)}" sqref="${c}2:$c$lastRow">'
        '<formula1>0</formula1></dataValidation>');
  }

  numberValidation('Buy Price', 'decimal', 'Enter the price as a number, e.g. 1250');
  numberValidation('Sell Price', 'decimal', 'Enter the price as a number, e.g. 1250');
  for (final b in branches) {
    numberValidation(branchQtyHeader(b), 'whole',
        'Enter a whole number, 0 or more');
  }
  numberValidation('Low Stock Level', 'whole', 'Enter a whole number, 0 or more');

  final partsXml = parts.build(
    widths: widths,
    columnStyles: columnStyles,
    freezeTopRow: true,
    autoFilterCols: headers.length,
    extraAfterSheetData: validations.isEmpty
        ? ''
        : '<dataValidations count="${validations.length}">'
            '${validations.join()}</dataValidations>',
  );

  // ---------- How to fill sheet ----------
  final help = _SheetWriter();
  help.row([_Cell('How to fill the Parts sheet', _Style.title)], height: 24);
  help.row([
    _Cell('One row for each part. The first row (the column names) must stay '
        'as it is. Empty rows are skipped. Only the Parts sheet is read.',
        _Style.wrap),
  ], height: 32);
  if (examples.isNotEmpty) {
    help.row([
      _Cell('The filled rows in the Parts sheet are examples. Type over them '
          'or delete them before importing.', _Style.note),
    ], height: 18);
  }
  help.row([]);
  help.row([
    _Cell('Column', _Style.header),
    _Cell('Needed?', _Style.header),
    _Cell('What to enter', _Style.header),
    _Cell('Example', _Style.header),
  ], height: 22);
  final branchList = branches.join(', ');
  final guide = <(String, String, String, String)>[
    ('Name', 'Yes', 'Part name as staff will search for it. Check the spelling.',
        'Fork Cover R'),
    ('Part No', 'No', 'Item code / part number. Write the full code, including '
        'the colour code for coloured parts.', '64200 KZK D01ZC'),
    ('Barcode', 'No', 'Number under the barcode or QR code on the box. Leave '
        'empty if there is none; it can be scanned in the app later.',
        '8901234567890'),
    ('Category', 'No', 'Pick from the list (Lists sheet). A new name adds a '
        'new category.', 'BODY PARTS'),
    ('Bike Brand', 'No', 'Pick from the list. A new name adds a new brand.',
        'HONDA'),
    ('Bike Model', 'No', 'Model of the brand in the same row. Needs a Bike '
        'Brand. A new name adds a new model.', 'HORNET'),
    ('Buy Price', 'No', 'Cost price you pay, in rupees. Numbers only.', '880'),
    ('Sell Price', 'Recommended', 'Price on the bill, in rupees. Numbers only. '
        'Empty means 0.', '1100'),
    for (final b in branches)
      (branchQtyHeader(b), 'No', 'Opening stock at $b. Whole number. Empty '
          'means 0.', '4'),
    ('Low Stock Level', 'No', 'Warn when stock goes down to this. Empty means 2.',
        '2'),
  ];
  for (final g in guide) {
    help.row([
      _Cell(g.$1, _Style.bold),
      _Cell(g.$2, _Style.wrap),
      _Cell(g.$3, _Style.wrap),
      _Cell(g.$4, _Style.text),
    ]);
  }
  help.row([]);
  help.row([_Cell('Good to know', _Style.subtitle)], height: 20);
  final notes = [
    'A part already in the app (same Name and same Part No) is not added again: '
        'its prices and details are updated and its stock is not changed.',
    'Two rows with the same Name and the same Part No are not allowed.',
    'Each barcode can belong to only one part.',
    if (branches.length > 1)
      'Fill the stock for every branch ($branchList) in the same file.',
    'Part No and Barcode columns are set as text so leading zeros stay (01210).',
    'Pictures are added in the app after importing.',
    'The app shows a preview before saving anything.',
  ];
  final firstNoteRow = help.rowCount + 1;
  for (final n in notes) {
    help.row([_Cell('•  $n', _Style.wrap)], height: n.length > 100 ? 28 : 16);
  }
  final helpXml = help.build(
    widths: [22, 14, 62, 20],
    merges: [
      'A2:D2',
      if (examples.isNotEmpty) 'A3:D3',
      for (var r = firstNoteRow; r <= help.rowCount; r++) 'A$r:D$r',
    ],
  );

  // ---------- Lists sheet ----------
  final listSheet = _SheetWriter();
  listSheet.row([
    _Cell('Categories', _Style.header),
    null,
    _Cell('Bike Brands', _Style.header),
    null,
    _Cell('Model brand', _Style.header),
    _Cell('Bike Models', _Style.header),
  ]);
  final rows = [
    lists.categories.length,
    lists.brands.length,
    lists.models.length,
  ].fold(0, (a, b) => a > b ? a : b);
  for (var i = 0; i < rows; i++) {
    listSheet.row([
      i < lists.categories.length ? _Cell(lists.categories[i], _Style.text) : null,
      null,
      i < lists.brands.length ? _Cell(lists.brands[i], _Style.text) : null,
      null,
      i < lists.models.length ? _Cell(lists.models[i].$1, _Style.text) : null,
      i < lists.models.length ? _Cell(lists.models[i].$2, _Style.text) : null,
    ]);
  }
  final listsXml = listSheet.build(widths: [24, 3, 18, 3, 16, 24], freezeTopRow: true);

  return _zip({
    '[Content_Types].xml': _contentTypes(3),
    '_rels/.rels': _rootRels,
    'docProps/app.xml': _appXml,
    'xl/workbook.xml': _workbook(['Parts', 'How to fill', 'Lists']),
    'xl/_rels/workbook.xml.rels': _workbookRels(3),
    'xl/styles.xml': _styles,
    'xl/worksheets/sheet1.xml': partsXml,
    'xl/worksheets/sheet2.xml': helpXml,
    'xl/worksheets/sheet3.xml': listsXml,
  });
}

// ---------------------------------------------------------------------------
// Minimal xlsx writing.

enum _Style {
  normal, // 0
  header, // 1
  headerRequired, // 2
  text, // 3
  textFormat, // 4  (number format "@")
  money, // 5
  whole, // 6
  title, // 7
  subtitle, // 8
  wrap, // 9
  bold, // 10
  note, // 11
}

class _Cell {
  const _Cell(this.value, [this.style = _Style.normal]);
  final Object value;
  final _Style style;
}

class _Row {
  _Row(this.cells, this.height);
  final List<_Cell?> cells;
  final double? height;
}

class _SheetWriter {
  final rows = <_Row>[];
  int get rowCount => rows.length;

  void row(List<_Cell?> cells, {double? height}) => rows.add(_Row(cells, height));

  String build({
    required List<double> widths,
    Map<int, _Style> columnStyles = const {},
    bool freezeTopRow = false,
    int? autoFilterCols,
    List<String> merges = const [],
    String extraAfterSheetData = '',
  }) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    b.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    b.write('<sheetViews><sheetView workbookViewId="0">');
    if (freezeTopRow) {
      b.write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    b.write('<cols>');
    for (var i = 0; i < widths.length; i++) {
      final style = columnStyles[i];
      b.write('<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"'
          '${style == null ? '' : ' style="${style.index}"'}/>');
    }
    b.write('</cols><sheetData>');
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final h = row.height;
      b.write('<row r="${r + 1}"${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        if (cell == null) continue;
        final ref = '${_colName(c)}${r + 1}';
        final s = cell.style.index;
        final v = cell.value;
        if (v is num) {
          b.write('<c r="$ref" s="$s"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">'
              '${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (autoFilterCols != null) {
      b.write('<autoFilter ref="A1:${_colName(autoFilterCols - 1)}1"/>');
    }
    if (merges.isNotEmpty) {
      b.write('<mergeCells count="${merges.length}">');
      for (final m in merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    b.write(extraAfterSheetData);
    b.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>');
    // Print landscape, all columns on one page width.
    b.write('<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>');
    b.write('</worksheet>');
    return b.toString();
  }
}

String _colName(int index) {
  var n = index + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  });
  return ZipEncoder().encodeBytes(archive);
}

String _contentTypes(int sheets) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
    ..write('<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>');
  for (var i = 1; i <= sheets; i++) {
    b.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  b.write('</Types>');
  return b.toString();
}

const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const _appXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>OSHU Stock</Application></Properties>';

String _workbook(List<String> names) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    ..write('<bookViews><workbookView activeTab="0"/></bookViews><sheets>');
  for (var i = 0; i < names.length; i++) {
    b.write('<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  b.write('</sheets></workbook>');
  return b.toString();
}

String _workbookRels(int sheets) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 1; i <= sheets; i++) {
    b.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  b.write('<Relationship Id="rId${sheets + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  b.write('</Relationships>');
  return b.toString();
}

// Fonts: 0 Arial 10, 1 Arial 10 bold white, 2 Arial 14 bold navy,
// 3 Arial 11 bold navy, 4 Arial 10 bold, 5 Arial 10 italic grey.
// Fills: 2 navy (header), 3 red (required header).
// cellXfs follow the _Style enum order.
const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>'
    '<fonts count="6">'
    '<font><sz val="10"/><name val="Arial"/><family val="2"/></font>'
    '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>'
    '<font><b/><sz val="14"/><color rgb="FF0B1A45"/><name val="Arial"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><color rgb="FF0B1A45"/><name val="Arial"/><family val="2"/></font>'
    '<font><b/><sz val="10"/><name val="Arial"/><family val="2"/></font>'
    '<font><i/><sz val="10"/><color rgb="FF5A6275"/><name val="Arial"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF0B1A45"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE5251E"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color rgb="FFC9CFDB"/></left><right style="thin"><color rgb="FFC9CFDB"/></right>'
    '<top style="thin"><color rgb="FFC9CFDB"/></top><bottom style="thin"><color rgb="FFC9CFDB"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="12">'
    // 0 normal
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 header
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
    // 2 header (required column)
    '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
    // 3 text cell
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top"/></xf>'
    // 4 text-formatted cell (keeps leading zeros)
    '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>'
    // 5 money
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 6 whole number
    '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 7 title
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 8 subtitle
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 9 wrapped text
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    // 10 bold
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top"/></xf>'
    // 11 note
    '<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
