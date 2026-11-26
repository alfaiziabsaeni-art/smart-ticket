import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class TicketService {
  final _db = Supabase.instance.client;

  // Upload audio/foto, kembalikan URL publik
  Future<String> uploadFile(
      String bucket, String path, Uint8List bytes, String contentType) async {
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return _db.storage.from(bucket).getPublicUrl(path);
  }

  // Buat tiket baru
  Future<void> createTicket({
    required String eventId,
    required String reporterName,
    String? audioUrl,
    String? photoUrl,
    String? category,
    String? zone,
    String? urgency,
  }) async {
    await _db.from('tickets').insert({
      'event_id': eventId,
      'reporter_name': reporterName,
      'audio_url': audioUrl,
      'photo_url': photoUrl,
      'category': category,
      'zone': zone,
      'urgency': urgency,
    });
  }

  // Kirim audio yang sudah diupload ke Edge Function; hasilnya tiket jadi
  Future<Map<String, dynamic>> processTicket({
    required String eventId,
    required String reporterName,
    required String audioUrl,
    String? photoUrl,
  }) async {
    final res = await _db.functions.invoke('process-ticket', body: {
      'event_id': eventId,
      'reporter_name': reporterName,
      'audio_url': audioUrl,
      'photo_url': photoUrl,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  // Stream realtime untuk board
  Stream<List<Map<String, dynamic>>> streamTickets(String eventId) {
    return _db
        .from('tickets')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
  }

  Future<void> takeTicket(String id, String name) async {
    await _db.from('tickets').update({
      'status': 'in_progress',
      'taken_by': name,
      'taken_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> doneTicket(String id) async {
    await _db.from('tickets').update({
      'status': 'done',
      'done_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}