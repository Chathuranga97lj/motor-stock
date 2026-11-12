import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/services/import_template.dart';
import 'package:motor_stock/services/part_import.dart';

const _branches = [
  ImportBranch('ibb', 'IBBAGAMUWA'),
  ImportBranch('mel', 'MELSIRIPURA'),
];

ImportSheet _parse(List<List<String>> table) => parseImportSheet(table, _branches);

/// A small .xlsx the way Excel saves it: text in sharedStrings.xml and a
/// "00000" number format on one cell.
Uint8List _excelStyleXlsx() {
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  final files = {
    'xl/workbook.xml': '<workbook xmlns="$ns" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Stock" sheetId="1" r:id="rId7"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId7" Type="worksheet" Target="/xl/worksheets/data.xml"/>'
            '</Relationships>',
    'xl/sharedStrings.xml': '<sst xmlns="$ns">'
        '<si><t>Item Name</t></si>'
        '<si><t>Code</t></si>'
        '<si><r><t>Selling </t></r><r><t>Price</t></r></si>'
        '<si><t>Qty</t></si>'
        '<si><t>Brake Pad</t></si>'
        '</sst>',
    'xl/styles.xml': '<styleSheet xmlns="$ns">'
        '<numFmts count="1"><numFmt numFmtId="170" formatCode="00000"/></numFmts>'
        '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="170"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/data.xml': '<worksheet xmlns="$ns"><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>'
        '<c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c></row>'
        '<row r="3"><c r="A3" t="s"><v>4</v></c><c r="B3" s="1"><v>1210</v></c>'
        '<c r="C3"><v>3159.9899999999998</v></c><c r="D3"><v>12</v></c></row>'
        '</sheetData></worksheet>',
  };
  final archive = Archive();
  files.forEach((name, xml) =>
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(xml))));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('readCsv', () {
    test('handles quotes, commas inside quotes and CRLF', () {
      final rows = readCsv('Name,Price\r\n"Bolt, small",120\r\n"Say ""hi""",5\r\n');
      expect(rows, [
        ['Name', 'Price'],
        ['Bolt, small', '120'],
        ['Say "hi"', '5'],
      ]);
    });

    test('detects ; separated files', () {
      expect(readCsv('Name;Price\nBolt;1,50'), [
        ['Name', 'Price'],
        ['Bolt', '1,50'],
      ]);
    });
  });

  group('readSheetTable', () {
    test('reads an Excel-style file with shared text and number formats', () {
      final table = readSheetTable(_excelStyleXlsx(), 'stock.xlsx');
      expect(table[0], ['Item Name', 'Code', 'Selling Price', 'Qty']);
      expect(table[1], isEmpty); // row 2 is missing in the file
      expect(table[2], ['Brake Pad', '01210', '3159.99', '12']);
    });

    test('refuses other file types with a clear message', () {
      expect(
        () => readSheetTable(Uint8List(0), 'old.xls'),
        throwsA(isA<ImportFileException>()
            .having((e) => e.message, 'message', contains('.xlsx'))),
      );
      expect(() => readSheetTable(Uint8List(0), 'photo.jpg'),
          throwsA(isA<ImportFileException>()));
      expect(() => readSheetTable(Uint8List.fromList([1, 2, 3]), 'bad.xlsx'),
          throwsA(isA<ImportFileException>()));
    });
  });

  group('parseImportSheet', () {
    test("reads the client's own column names", () {
      final sheet = _parse([
        ['    NAME', 'Item Code', 'category', 'Selling Price', 'Unit Price ',
          'Quitity', 'Image Search', 'Image Status'],
        ['Dio  Bor', '01210', 'ENGINE', '14500', '11568', '1', 'https://x', 'ok'],
        ['Bush Kit', '05141 kpl  840', 'engine', '730', '552', '8', '', ''],
      ]);
      expect(sheet.columns, {
        ImportField.name: 'NAME',
        ImportField.partNo: 'Item Code',
        ImportField.category: 'category',
        ImportField.sellPrice: 'Selling Price',
        ImportField.buyPrice: 'Unit Price',
        ImportField.quantity: 'Quitity',
      });
      expect(sheet.ignoredColumns, ['Image Search', 'Image Status']);
      expect(sheet.hasQuantityColumn, isTrue);

      final first = sheet.rows.first;
      expect(first.rowNo, 2);
      expect(first.name, 'Dio Bor');
      expect(first.partNo, '01210');
      expect(first.buyPrice, 11568);
      expect(first.sellPrice, 14500);
      expect(first.toJson(quantityBranchId: 'mel')['stock'], {'mel': 1});
      expect(sheet.rows[1].partNo, '05141 KPL 840');
      expect(sheet.rows[1].category, 'ENGINE');
    });

    test('reads one quantity column per branch', () {
      final sheet = _parse([
        ['Name', 'IBBAGAMUWA Qty', 'Qty MELSIRIPURA', 'Quantity'],
        ['Horn', '2', '', '9'],
      ]);
      expect(sheet.branchColumns.keys, ['ibb', 'mel']);
      // A plain Quantity column next to branch columns is not used.
      expect(sheet.hasQuantityColumn, isFalse);
      expect(sheet.ignoredColumns, ['Quantity']);
      expect(sheet.rows.single.stockFor('mel'), {'ibb': 2});
    });

    test('finds the header under a title row and skips empty rows', () {
      final sheet = _parse([
        ['OSHU stock list'],
        [],
        ['Name', 'Sell Price'],
        ['Horn', '700'],
        ['', ''],
        ['Belt', '1500'],
      ]);
      expect(sheet.headerRow, 3);
      expect(sheet.blankRows, 1);
      expect(sheet.rows.map((r) => r.rowNo), [4, 6]);
    });

    test('reads prices written with Rs. and commas', () {
      final row = _parse([
        ['Name', 'Sell Price', 'Buy Price'],
        ['Crank Shaft', 'Rs. 27,000.00', ' 21559.987 '],
      ]).rows.single;
      expect(row.sellPrice, 27000);
      expect(row.buyPrice, 21559.99);
      expect(row.isValid, isTrue);
    });

    test('marks rows that cannot be imported', () {
      final sheet = _parse([
        ['Name', 'Part No', 'Barcode', 'Bike Brand', 'Bike Model', 'Sell Price', 'Qty'],
        ['', 'X1', '', '', '', '100', '1'], // 2: no name
        ['Seat', '', '', '', 'DIO', '100', '1'], // 3: model without brand
        ['Belt', 'B1', '', '', '', 'abc', '1'], // 4: price not a number
        ['Cable', 'C1', '', '', '', '-5', '1'], // 5: negative
        ['Bulb', 'L1', '', '', '', '50', '2.5'], // 6: half a bulb
        ['Horn', 'H1', '111', '', '', '700', '1'], // 7: ok
        ['horn ', 'h1', '', '', '', '700', '1'], // 8: same as row 7
        ['Horn Relay', 'H2', '111', '', '', '700', '1'], // 9: same barcode
      ]);
      String errorsOf(int rowNo) =>
          sheet.rows.firstWhere((r) => r.rowNo == rowNo).errors.join('; ');
      expect(errorsOf(2), 'No name');
      expect(errorsOf(3), 'Bike model needs a bike brand');
      expect(errorsOf(4), 'Sell Price "abc" is not a number');
      expect(errorsOf(5), 'Sell Price cannot be below 0');
      expect(errorsOf(6), 'Quantity must be a whole number');
      expect(errorsOf(7), '');
      expect(errorsOf(8), 'Same name and part no as row 7');
      expect(errorsOf(9), 'Same barcode as row 7');
      expect(sheet.validRows.map((r) => r.rowNo), [7]);
    });

    test('warns about rows worth a second look', () {
      final sheet = _parse([
        ['Name', 'Sell Price', 'Buy Price', 'Qty'],
        ['Bush', '', '100', '1'],
        ['Fork Cover', '90', '340', '2'],
        ['Park Bulb', '50', '30', '910'],
      ]);
      expect(sheet.rows[0].warnings, ['No selling price (saved as 0)']);
      expect(sheet.rows[1].warnings, ['Buy price is more than the selling price']);
      expect(sheet.rows[2].warnings, ['Very high quantity (910), check it']);
      expect(sheet.errorCount, 0);
    });

    test('needs a Name column', () {
      expect(
        () => _parse([
          ['Code', 'Price'],
          ['A1', '10'],
        ]),
        throwsA(isA<ImportFileException>()),
      );
    });
  });

  test('the template reads back into the same rows', () {
    final bytes = buildImportTemplate(
      branches: const ['IBBAGAMUWA', 'MELSIRIPURA'],
      lists: const TemplateLists(
        categories: ['BODY PARTS'],
        brands: ['HONDA'],
        models: [('HONDA', 'DIO BS4')],
      ),
      examples: const [
        TemplateExample(
          name: 'Brake Pad',
          partNo: '06455 KPP N01',
          barcode: '0123',
          category: 'CONSUMABLES ITEMS',
          brand: 'HONDA',
          model: 'DIO BS4',
          buyPrice: 2120.5,
          sellPrice: 2650,
          qty: {'IBBAGAMUWA': 2, 'MELSIRIPURA': 1},
          lowStock: 3,
        ),
      ],
    );
    final sheet = _parse(readSheetTable(bytes, 'template.xlsx'));
    expect(sheet.ignoredColumns, isEmpty);
    expect(sheet.columns.length, ImportField.values.length - 1); // no plain Qty
    final row = sheet.rows.single;
    expect(row.toJson(), {
      'row': 2,
      'name': 'Brake Pad',
      'part_no': '06455 KPP N01',
      'barcode': '0123',
      'category': 'CONSUMABLES ITEMS',
      'brand': 'HONDA',
      'model': 'DIO BS4',
      'buy_price': 2120.5,
      'sell_price': 2650.0,
      'low_stock_level': 3,
      'stock': {'ibb': 2, 'mel': 1},
    });
  });

  test('ImportResult reads the database answer', () {
    final result = ImportResult.fromJson({
      'created': 2,
      'updated': 1,
      'skipped': 1,
      'rows': [
        {'row': 2, 'action': 'new'},
        {'row': 3, 'action': 'update', 'message': 'Already in the app'},
        {'row': 4, 'action': 'skip', 'message': 'Barcode already used by Horn'},
      ],
      'new_categories': ['ENGINE'],
      'new_brands': [],
      'new_models': ['HONDA HORNET'],
    });
    expect(result.created, 2);
    expect(result.outcomes[2]!.action, ImportAction.create);
    expect(result.outcomes[3]!.action, ImportAction.update);
    expect(result.outcomes[4]!.message, 'Barcode already used by Horn');
    expect(result.newCategories, ['ENGINE']);
    expect(result.newModels, ['HONDA HORNET']);
    expect(ImportResult.fromJson(const {}).outcomes, isEmpty);
  });
}
