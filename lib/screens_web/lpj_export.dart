import 'package:excel/excel.dart';

import 'file_download.dart';

// Bikin file Excel (.xlsx) dari daftar baris, lalu langsung di-download.
// Baris pertama dianggap judul kolom (dibikin tebal).
void downloadXlsx(String fileName, List<List<String>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];

  for (final row in rows) {
    sheet.appendRow([
      // Kalau isinya angka (misal "3"), simpan sebagai angka biar bisa dihitung di Excel
      for (final value in row)
        int.tryParse(value) != null
            ? IntCellValue(int.parse(value))
            : TextCellValue(value),
    ]);
  }

  for (var col = 0; col < rows.first.length; col++) {
    // Judul kolom dibikin tebal
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        .cellStyle = CellStyle(bold: true);
    // Lebar kolom: kolom "Laporan" (index 3) dibikin paling lebar
    sheet.setColumnWidth(col, col == 3 ? 45 : 20);
  }

  final bytes = excel.encode();
  if (bytes == null) return;
  downloadFile(fileName, bytes);
}