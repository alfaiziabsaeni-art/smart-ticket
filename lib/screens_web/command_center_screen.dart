import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lpj_export.dart';

// Batas waktu (SLA): tiket Incoming yang belum diambil > 3 menit akan kedip merah
const slaLimit = Duration(minutes: 3);

// Status tiket yang dipakai di tabel 'tickets':
// 'review'      -> masuk Coordinator Review Queue (AI ragu / belum ada divisi)
// 'incoming'    -> sudah dikirim ke divisi, belum diambil
// 'in_progress' -> sudah diambil (Take Task)
// 'done'        -> selesai

class CommandCenterScreen extends StatefulWidget {
  final String eventId;
  final String eventName;

  const CommandCenterScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  final supabase = Supabase.instance.client;

  late final Stream<List<Map<String, dynamic>>> ticketStream;
  List<Map<String, dynamic>> tickets = []; // data terakhir, dipakai buat export Excel
  Map<String, String> divisionNames = {}; // division_id -> nama divisi
  Map<String, String> reviewChoices = {}; // ticket_id -> divisi yang dipilih koordinator

  Timer? blinkTimer;
  bool blinkOn = false;

  @override
  void initState() {
    super.initState();

    // Stream realtime: otomatis update kalau ada tiket baru / berubah
    ticketStream = supabase
        .from('tickets')
        .stream(primaryKey: ['id'])
        .eq('event_id', widget.eventId)
        .order('created_at', ascending: true);

    loadDivisions();

    // Tiap 1 detik: ganti warna kedip + update timer di kartu
    blinkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => blinkOn = !blinkOn);
    });
  }

  @override
  void dispose() {
    blinkTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDivisions() async {
    try {
      final data = await supabase
          .from('divisions')
          .select()
          .eq('event_id', widget.eventId);
      if (!mounted) return;
      setState(() {
        divisionNames = {
          for (final d in data) d['id'].toString(): d['name'].toString(),
        };
      });
    } catch (e) {
      showMessage('Gagal memuat divisi: $e');
    }
  }

  // Ubah status tiket + simpan jam-nya
  Future<void> updateTicket(dynamic id, Map<String, dynamic> changes) async {
    try {
      await supabase.from('tickets').update(changes).eq('id', id);
    } catch (e) {
      showMessage('Gagal update tiket: $e');
    }
  }

  void takeTask(Map<String, dynamic> ticket) {
    updateTicket(ticket['id'], {
      'status': 'in_progress',
      'taken_by': 'Koordinator (Web)',
      'taken_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void markDone(Map<String, dynamic> ticket) {
    updateTicket(ticket['id'], {
      'status': 'done',
      'done_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Koordinator pilih divisi, lalu tiket dikirim ke kolom Incoming
  void approveTicket(Map<String, dynamic> ticket, String divisionId) {
    updateTicket(ticket['id'], {
      'status': 'incoming',
      'division_id': divisionId,
    });
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- Helper waktu ----------

  DateTime? parseTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  // Ubah waktu jadi teks "2026-11-26 11:19:24" (jam lokal, tanpa milidetik)
  String formatDateTime(DateTime? time) {
    if (time == null) return '';
    return time.toLocal().toString().substring(0, 19);
  }

  // Waktu SLA dihitung dari jam relawan lapor
  DateTime? incomingTime(Map<String, dynamic> ticket) {
    return parseTime(ticket['created_at']);
  }

  bool isOverSla(Map<String, dynamic> ticket) {
    if (ticket['status'] != 'incoming') return false;
    final start = incomingTime(ticket);
    if (start == null) return false;
    return DateTime.now().difference(start) > slaLimit;
  }

  // ---------- Export Excel / LPJ ----------

  void exportExcel() {
    if (tickets.isEmpty) {
      showMessage('Belum ada tiket untuk di-export');
      return;
    }

    final rows = <List<String>>[
      [
        'No',
        'Waktu Lapor',
        'Pelapor',
        'Laporan',
        'Kategori',
        'Zona',
        'Urgensi',
        'Divisi',
        'Status',
        'Diambil Oleh',
        'Waktu Diambil',
        'Waktu Selesai',
        'Lama Penanganan (menit)',
      ],
    ];

    for (var i = 0; i < tickets.length; i++) {
      final t = tickets[i];
      final created = parseTime(t['created_at']);
      final taken = parseTime(t['taken_at']);
      final done = parseTime(t['done_at']);

      String handlingMinutes = '';
      if (created != null && done != null) {
        handlingMinutes = done.difference(created).inMinutes.toString();
      }

      rows.add([
        '${i + 1}',
        formatDateTime(created),
        t['reporter_name']?.toString() ?? '',
        t['transcript']?.toString() ?? '',
        t['category']?.toString() ?? '',
        t['zone']?.toString() ?? '',
        t['urgency']?.toString() ?? '',
        divisionNames[t['division_id']?.toString()] ?? '',
        t['status']?.toString() ?? '',
        t['taken_by']?.toString() ?? '',
        formatDateTime(taken),
        formatDateTime(done),
        handlingMinutes,
      ]);
    }

    final safeName = widget.eventName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    downloadXlsx('LPJ_$safeName.xlsx', rows);
  }

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Command Center: ${widget.eventName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Export Excel / LPJ'),
                onPressed: exportExcel,
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.view_kanban), text: 'Live Board'),
              Tab(icon: Icon(Icons.rate_review), text: 'Coordinator Review Queue'),
            ],
          ),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: ticketStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            tickets = snapshot.data!;

            return TabBarView(
              children: [
                buildKanbanBoard(),
                buildReviewQueue(),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> ticketsWithStatus(String status) {
    return tickets.where((t) => t['status'] == status).toList();
  }

  Widget buildKanbanBoard() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildColumn('Incoming', Colors.orange, ticketsWithStatus('incoming')),
          buildColumn('In Progress', Colors.blue, ticketsWithStatus('in_progress')),
          buildColumn('Done', Colors.green, ticketsWithStatus('done')),
        ],
      ),
    );
  }

  Widget buildColumn(String title, Color color, List<Map<String, dynamic>> items) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$title (${items.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Kosong'))
                  : ListView(
                      children: [for (final t in items) buildTicketCard(t)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTicketCard(Map<String, dynamic> ticket) {
    final status = ticket['status'];
    final overSla = isOverSla(ticket);
    final start = incomingTime(ticket);
    final age = start == null ? null : DateTime.now().difference(start);

    // Kalau lewat SLA: warna kartu gonta-ganti merah / putih tiap detik
    Color cardColor = Colors.white;
    if (overSla && blinkOn) {
      cardColor = Colors.red.shade300;
    } else if (overSla) {
      cardColor = Colors.red.shade50;
    }

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: overSla ? Colors.red : Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overSla)
              const Text(
                '⚠ LEWAT SLA 3 MENIT',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            Text(
              ticket['transcript']?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                buildChip(Icons.category, ticket['category']),
                buildChip(Icons.place, ticket['zone']),
                buildChip(Icons.priority_high, ticket['urgency']),
                buildChip(Icons.groups, divisionNames[ticket['division_id']?.toString()]),
                buildChip(Icons.person, ticket['reporter_name']),
              ],
            ),
            const SizedBox(height: 6),
            if (age != null && status != 'done')
              Text(
                'Menunggu: ${formatDuration(age)}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            if (status == 'incoming')
              FilledButton(
                onPressed: () => takeTask(ticket),
                child: const Text('Take Task'),
              ),
            if (status == 'in_progress')
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => markDone(ticket),
                child: const Text('Done'),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildChip(IconData icon, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(value.toString(), style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget buildReviewQueue() {
    final reviewTickets = ticketsWithStatus('review');

    if (reviewTickets.isEmpty) {
      return const Center(child: Text('Tidak ada tiket yang perlu di-review'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final t in reviewTickets) buildReviewCard(t)],
    );
  }

  Widget buildReviewCard(Map<String, dynamic> ticket) {
    final ticketId = ticket['id'].toString();

    // Pilihan awal dropdown = divisi tebakan AI (kalau ada)
    String? selectedDivision =
        reviewChoices[ticketId] ?? ticket['division_id']?.toString();
    if (!divisionNames.containsKey(selectedDivision)) {
      selectedDivision = null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket['transcript']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kategori: ${ticket['category'] ?? '-'}  |  '
                    'Zona: ${ticket['zone'] ?? '-'}  |  '
                    'Urgensi: ${ticket['urgency'] ?? '-'}',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: selectedDivision,
              hint: const Text('Pilih divisi'),
              items: [
                for (final entry in divisionNames.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => reviewChoices[ticketId] = value);
              },
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: selectedDivision == null
                  ? null
                  : () => approveTicket(ticket, selectedDivision!),
              child: const Text('Kirim ke Incoming'),
            ),
          ],
        ),
      ),
    );
  }
}