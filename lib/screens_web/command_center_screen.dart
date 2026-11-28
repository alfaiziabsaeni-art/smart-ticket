import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ticket_service.dart';
import 'lpj_export.dart';

// Batas waktu (SLA): tiket Incoming yang belum diambil > 3 menit akan kedip merah
const slaLimit = Duration(minutes: 3);

// Urgency from the AI / 2-Tap ('low', 'medium', 'high') -> badge text, color, sort order
const urgencyLabel = {'high': 'CRITICAL', 'medium': 'HIGH', 'low': 'NORMAL'};
const urgencyColor = {'high': Colors.red, 'medium': Colors.orange, 'low': Colors.blueGrey};
const urgencyRank = {'high': 0, 'medium': 1, 'low': 2};

// Screens narrower than this (phones) get the phone layout
const narrowWidth = 700.0;

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
  final ticketService = TicketService();

  late final Stream<List<Map<String, dynamic>>> ticketStream;
  List<Map<String, dynamic>> tickets = []; // data terakhir, dipakai buat export Excel
  Map<String, String> divisionNames = {}; // division_id -> nama divisi
  Map<String, String> reviewChoices = {}; // ticket_id -> divisi yang dipilih koordinator

  Timer? blinkTimer;
  bool blinkOn = false;
  int phoneColumn = 0; // on a phone: which column is shown (0 Incoming, 1 Progress, 2 Done)

  @override
  void initState() {
    super.initState();

    // Stream realtime: otomatis update kalau ada tiket baru / berubah
    ticketStream = ticketService.streamTickets(widget.eventId);

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

  Future<void> takeTask(Map<String, dynamic> ticket) async {
    try {
      await ticketService.takeTicket(ticket['id'].toString(), 'Koordinator (Web)');
    } catch (e) {
      showMessage('Gagal mengambil tugas: $e');
    }
  }

  Future<void> markDone(Map<String, dynamic> ticket) async {
    try {
      await ticketService.doneTicket(ticket['id'].toString());
    } catch (e) {
      showMessage('Gagal menyelesaikan tugas: $e');
    }
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
        urgencyLabel[t['urgency']] ?? '',
        divisionNames[t['division_id']?.toString()] ?? '',
        t['status']?.toString() ?? '',
        t['taken_by']?.toString() ?? '',
        formatDateTime(taken),
        formatDateTime(done),
        handlingMinutes,
      ]);
    }

    final safeName = widget.eventName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    try {
      downloadXlsx('LPJ_$safeName.xlsx', rows);
    } catch (e) {
      // e.g. in the Android app (download only works in the browser)
      showMessage('Export gagal: $e');
    }
  }

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < narrowWidth;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Command Center: ${widget.eventName}'),
          actions: [
            // On a phone: icon only, so the title still fits
            if (isNarrow)
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export Excel / LPJ',
                onPressed: exportExcel,
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export Excel / LPJ'),
                  onPressed: exportExcel,
                ),
              ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.view_kanban), text: 'Live Board'),
              Tab(
                icon: const Icon(Icons.rate_review),
                text: isNarrow ? 'Review Queue' : 'Coordinator Review Queue',
              ),
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

            // Urutkan dari yang paling lama dilaporkan
            tickets = [...snapshot.data!]
              ..sort((a, b) => a['created_at'].toString().compareTo(b['created_at'].toString()));

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

  // Most urgent first (CRITICAL, HIGH, NORMAL); same urgency -> oldest first
  List<Map<String, dynamic>> sortByUrgency(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final rankA = urgencyRank[a['urgency']] ?? 1;
      final rankB = urgencyRank[b['urgency']] ?? 1;
      if (rankA != rankB) return rankA.compareTo(rankB);
      return a['created_at'].toString().compareTo(b['created_at'].toString());
    });
    return list;
  }

  Widget buildKanbanBoard() {
    final incoming = sortByUrgency(ticketsWithStatus('incoming'));
    final inProgress = sortByUrgency(ticketsWithStatus('in_progress'));
    final done = ticketsWithStatus('done');

    final columns = [
      buildColumn('Incoming', Colors.grey.shade800, incoming), // netral: oranye khusus badge HIGH
      buildColumn('In Progress', Colors.blue, inProgress),
      buildColumn('Done', Colors.green, done),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Phone: 3 buttons on top, tap one to show that column
        if (constraints.maxWidth < narrowWidth) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 0, label: Text('Incoming (${incoming.length})')),
                      ButtonSegment(value: 1, label: Text('Progress (${inProgress.length})')),
                      ButtonSegment(value: 2, label: Text('Done (${done.length})')),
                    ],
                    selected: {phoneColumn},
                    onSelectionChanged: (selected) {
                      setState(() => phoneColumn = selected.first);
                    },
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: columns[phoneColumn],
                ),
              ),
            ],
          );
        }
        // Laptop: 3 columns that share the width
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final column in columns) Expanded(child: column)],
          ),
        );
      },
    );
  }

  Widget buildColumn(String title, Color color, List<Map<String, dynamic>> items) {
    return Container(
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
            // Urgency badge + AI confidence (proof that the AI sorted this ticket)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                buildUrgencyBadge(ticket['urgency']),
                buildSourceBadge(ticket),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${ticket['category'] ?? 'Laporan'} · ${ticket['zone'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            buildTranscript(ticket['transcript']),
            Text(
              '${ticket['category'] ?? 'Laporan'} · ${ticket['zone'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            buildTranscript(ticket['transcript']),
            _buildTicketPhoto(context, ticket), // <-- TAMBAHKAN DI SINI
            const SizedBox(height: 6),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
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

  // Colored label: CRITICAL (red), HIGH (orange), NORMAL (grey)
  Widget buildUrgencyBadge(dynamic urgency) {
    final color = urgencyColor[urgency] ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        urgencyLabel[urgency] ?? 'NORMAL',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  // "AI 92%" for voice tickets sorted by Gemini, "2-Tap" for tickets from the 2-Tap buttons
  Widget buildSourceBadge(Map<String, dynamic> ticket) {
    final score = ticket['confidence_score'];
    final text = score == null
        ? '2-Tap'
        : 'AI ${(double.parse(score.toString()) * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.deepPurple),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.deepPurple, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Small italic text: what the volunteer actually said (transcript from Gemini)
  Widget buildTranscript(dynamic transcript) {
    if (transcript == null || transcript.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mic, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '"$transcript"',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
            ),
          ),
        ],
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

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            buildUrgencyBadge(ticket['urgency']),
            buildSourceBadge(ticket),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${ticket['category'] ?? 'Laporan'} · ${ticket['zone'] ?? '-'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        buildTranscript(ticket['transcript']),
        Text(
          '${ticket['category'] ?? 'Laporan'} · ${ticket['zone'] ?? '-'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        buildTranscript(ticket['transcript']),
        _buildTicketPhoto(context, ticket), // <-- TAMBAHKAN DI SINI
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
        FilledButton(
          onPressed: selectedDivision == null
              ? null
              : () => approveTicket(ticket, selectedDivision!),
          child: const Text('Kirim ke Incoming'),
        ),
      ],
    );

    final isNarrow = MediaQuery.sizeOf(context).width < narrowWidth;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        // Phone: info on top, dropdown + button below. Laptop: side by side.
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [info, const SizedBox(height: 8), actions],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 12),
                  actions,
                ],
              ),
      ),
    );
  }
  Widget _buildTicketPhoto(BuildContext context, Map<String, dynamic> ticket) {
  final rawUrl = ticket['photo_url'] ?? ticket['image_url'];
  final photoUrl = rawUrl?.toString().trim();

  if (photoUrl == null || photoUrl.isEmpty) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: InteractiveViewer(
              child: Image.network(photoUrl, fit: BoxFit.contain),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          photoUrl,
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Text(
            'Gagal memuat foto',
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ),
      ),
    ),
  );
}
}