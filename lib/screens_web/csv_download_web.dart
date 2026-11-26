import 'package:web/web.dart' as web;

// Bikin link download sementara, lalu "diklik" otomatis
void downloadCsv(String fileName, String csv) {
  // \uFEFF = penanda UTF-8 biar Excel kebaca huruf/emoji dengan benar
  final link = web.HTMLAnchorElement()
    ..href = 'data:text/csv;charset=utf-8,${Uri.encodeComponent('\uFEFF$csv')}'
    ..download = fileName;
  link.click();
}