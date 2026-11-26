import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'command_center_screen.dart';

// Halaman Setup Event untuk Ketua Panitia:
// 1. Bikin event (kalau belum ada)
// 2. Tambah / hapus divisi
// 3. Tambah / hapus zona venue
// 4. Tampilkan QR Code buat relawan join
class SetupEventScreen extends StatefulWidget {
  const SetupEventScreen({super.key});

  @override
  State<SetupEventScreen> createState() => _SetupEventScreenState();
}

class _SetupEventScreenState extends State<SetupEventScreen> {
  final supabase = Supabase.instance.client;

  final eventNameController = TextEditingController();
  final divisionController = TextEditingController();
  final zoneController = TextEditingController();

  Map<String, dynamic>? event; // event yang lagi aktif
  List<Map<String, dynamic>> divisions = [];
  List<String> zones = []; // zona disimpan di kolom 'zones' (text[]) tabel events
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadLatestEvent();
  }

  @override
  void dispose() {
    eventNameController.dispose();
    divisionController.dispose();
    zoneController.dispose();
    super.dispose();
  }

  // Ambil event terakhir yang dibuat, biar pas refresh halaman datanya nggak hilang
  Future<void> loadLatestEvent() async {
    try {
      final data = await supabase
          .from('events')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      event = data;
      if (event != null) {
        await loadDivisionsAndZones();
      }
    } catch (e) {
      showMessage('Gagal memuat event: $e');
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  Future<void> loadDivisionsAndZones() async {
    final divisionData = await supabase
        .from('divisions')
        .select()
        .eq('event_id', event!['id'])
        .order('name');

    if (!mounted) return;
    setState(() {
      divisions = List<Map<String, dynamic>>.from(divisionData);
      zones = List<String>.from(event!['zones'] ?? []);
    });
  }

  Future<void> createEvent() async {
    final name = eventNameController.text.trim();
    if (name.isEmpty) {
      showMessage('Nama event belum diisi');
      return;
    }

    try {
      final data =
          await supabase.from('events').insert({'name': name}).select().single();
      if (!mounted) return;
      setState(() {
        event = data;
        divisions = [];
        zones = [];
      });
      eventNameController.clear();
    } catch (e) {
      showMessage('Gagal membuat event: $e');
    }
  }

  Future<void> addDivision() async {
    final name = divisionController.text.trim();
    if (name.isEmpty) return;

    try {
      await supabase.from('divisions').insert({
        'event_id': event!['id'],
        'name': name,
      });
      divisionController.clear();
      await loadDivisionsAndZones();
    } catch (e) {
      showMessage('Gagal menambah divisi: $e');
    }
  }

  Future<void> deleteDivision(int index) async {
    try {
      await supabase.from('divisions').delete().eq('id', divisions[index]['id']);
      await loadDivisionsAndZones();
    } catch (e) {
      showMessage('Gagal menghapus divisi: $e');
    }
  }

  Future<void> addZone() async {
    final name = zoneController.text.trim();
    if (name.isEmpty) return;
    await saveZones([...zones, name]);
    zoneController.clear();
  }

  Future<void> deleteZone(int index) async {
    final newZones = [...zones];
    newZones.removeAt(index);
    await saveZones(newZones);
  }

  // Simpan daftar zona ke kolom 'zones' di tabel events
  Future<void> saveZones(List<String> newZones) async {
    try {
      final data = await supabase
          .from('events')
          .update({'zones': newZones})
          .eq('id', event!['id'])
          .select()
          .single();
      if (!mounted) return;
      setState(() {
        event = data;
        zones = newZones;
      });
    } catch (e) {
      showMessage('Gagal menyimpan zona: $e');
    }
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(event == null ? 'Setup Event' : 'Setup: ${event!['name']}'),
        actions: [
          if (event != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                icon: const Icon(Icons.dashboard),
                label: const Text('Buka Command Center'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CommandCenterScreen(
                        eventId: event!['id'].toString(),
                        eventName: event!['name'].toString(),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      body: event == null ? buildCreateEventForm() : buildSetupContent(),
    );
  }

  // Tampilan kalau belum ada event sama sekali
  Widget buildCreateEventForm() {
    return Center(
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Buat Event Baru',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: eventNameController,
              decoration: const InputDecoration(
                labelText: 'Nama event (misal: Festival Musik 2026)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => createEvent(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: createEvent,
                child: const Text('Buat Event'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tampilan setelah event ada: 3 kolom (Divisi | Zona | QR Code)
  Widget buildSetupContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: buildListCard(
              title: 'Divisi',
              hint: 'Nama divisi (misal: Keamanan)',
              icon: Icons.groups,
              controller: divisionController,
              names: [for (final d in divisions) d['name'].toString()],
              onAdd: addDivision,
              onDelete: deleteDivision,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: buildListCard(
              title: 'Zona Venue',
              hint: 'Nama zona (misal: Gate A)',
              icon: Icons.place,
              controller: zoneController,
              names: zones,
              onAdd: addZone,
              onDelete: deleteZone,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: buildQrCard()),
        ],
      ),
    );
  }

  Widget buildListCard({
    required String title,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required List<String> names,
    required void Function() onAdd,
    required void Function(int index) onDelete,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title (${names.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: hint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (names.isEmpty) const Text('Belum ada data'),
            for (var i = 0; i < names.length; i++)
              ListTile(
                leading: Icon(icon),
                title: Text(names[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildQrCard() {
    final eventId = event!['id'].toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'QR Code Join Event',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('Relawan scan QR ini dari aplikasi mobile'),
            const SizedBox(height: 16),
            // Isi QR = event id. Aplikasi mobile (Rafi) tinggal baca id ini.
            QrImageView(
              data: eventId,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'ID: $eventId',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}