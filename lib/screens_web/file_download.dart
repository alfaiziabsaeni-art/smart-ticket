// Kalau jalan di web -> pakai file_download_web.dart (beneran download file)
// Kalau di mobile    -> pakai file_download_stub.dart (biar build Android nggak error)
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';