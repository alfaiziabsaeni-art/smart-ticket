import 'dart:convert';

import 'package:web/web.dart' as web;

// Bikin link download sementara, lalu "diklik" otomatis
void downloadFile(String fileName, List<int> bytes) {
  final link = web.HTMLAnchorElement()
    ..href = 'data:application/octet-stream;base64,${base64Encode(bytes)}'
    ..download = fileName;
  link.click();
}