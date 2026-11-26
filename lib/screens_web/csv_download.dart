// Kalau jalan di web -> pakai csv_download_web.dart (beneran download file)
// Kalau di mobile    -> pakai csv_download_stub.dart (biar build Android nggak error)
export 'csv_download_stub.dart'
    if (dart.library.js_interop) 'csv_download_web.dart';