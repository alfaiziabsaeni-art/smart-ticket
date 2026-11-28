import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'command_center_screen.dart';

// Divisions added automatically to every new event.
// Same names as the Edge Function (AI auto-dispatch), so there are no typos.
const defaultDivisions = ['Teknis', 'Medis', 'Keamanan', 'Logistik'];

// Address of the deployed web app. The QR opens this link with the event code.
const appUrl = 'https://smart-ticket-4naga.web.app';

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
      // Add the 4 default divisions to the new event
      await supabase.from('divisions').insert([
        for (final division in defaultDivisions)
          {'event_id': data['id'], 'name': division},
      ]);
      if (!mounted) return;
      setState(() {
        event = data;
        zones = [];
      });
      eventNameController.clear();
      await loadDivisionsAndZones();
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

  // Kosongkan event aktif supaya form "Buat Event Baru" muncul lagi
  void startNewEvent() {
    setState(() {
      event = null;
      divisions = [];
      zones = [];
    });
  }

  void openCommandCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommandCenterScreen(
          eventId: event!['id'].toString(),
          eventName: event!['name'].toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isNarrow = MediaQuery.sizeOf(context).width < narrowWidth;

    return Scaffold(
      appBar: AppBar(
        title: Text(event == null ? 'Setup Event' : 'Setup: ${event!['name']}'),
        actions: [
          // Balik ke form "Buat Event Baru"
          if (event != null && isNarrow)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Event Baru',
              onPressed: startNewEvent,
            ),
          if (event != null && !isNarrow)
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Event Baru'),
              onPressed: startNewEvent,
            ),
          // On a phone: icon only, so the title still fits
          if (event != null && isNarrow)
            IconButton(
              icon: const Icon(Icons.dashboard),
              tooltip: 'Buka Command Center',
              onPressed: openCommandCenter,
            ),
          if (event != null && !isNarrow)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                icon: const Icon(Icons.dashboard),
                label: const Text('Buka Command Center'),
                onPressed: openCommandCenter,
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
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

  // Tampilan setelah event ada: 3 kolom (Divisi | Zona | QR Code).
  // Di HP: 3 kartu disusun ke bawah dan bisa di-scroll.
  Widget buildSetupContent() {
    final divisionCard = buildListCard(
      title: 'Divisi',
      hint: 'Nama divisi (misal: Keamanan)',
      icon: Icons.groups,
      controller: divisionController,
      names: [for (final d in divisions) d['name'].toString()],
      onAdd: addDivision,
      onDelete: deleteDivision,
    );
    final zoneCard = buildListCard(
      title: 'Zona Venue',
      hint: 'Nama zona (misal: Gate A)',
      icon: Icons.place,
      controller: zoneController,
      names: zones,
      onAdd: addZone,
      onDelete: deleteZone,
    );
    final qrCard = buildQrCard();

    if (MediaQuery.sizeOf(context).width < narrowWidth) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [qrCard, divisionCard, zoneCard],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: divisionCard),
          const SizedBox(width: 16),
          Expanded(child: zoneCard),
          const SizedBox(width: 16),
          Expanded(child: qrCard),
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
    // Scan with the phone's normal camera -> browser opens Join with the code filled in
    final joinLink = '$appUrl/?code=$eventId';

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
            const Text(
              'Relawan scan QR ini pakai kamera HP',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: joinLink,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            SelectableText(
              joinLink,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SelectableText(
              'Kode event: $eventId',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}