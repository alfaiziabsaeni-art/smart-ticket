import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ticket_service.dart'; // adjust if your file name differs

const kBlue = Color(0xFF1D4ED8);
const kBg = Color(0xFFF1F5F9);
const kInk = Color(0xFF0F172A);
const kMuted = Color(0xFF475569);
const kRed = Color(0xFFDC2626);
const kYellow = Color(0xFFD97706);
const kGreen = Color(0xFF059669);

const kZones = ['Main Stage', 'Gate A', 'East Toilet', 'Food Court', 'Parking', 'Backstage']; // fallback only
const kIssues = ['Power', 'Medical', 'Crowd', 'Security', 'Water', 'Other'];

void _say(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// Value saved in tickets.category for each 2-Tap issue.
// Same categories as the AI (Edge Function process-ticket).
const kIssueCategory = {
  'Power': 'Listrik',
  'Medical': 'Medis',
  'Crowd': 'Keamanan',
  'Security': 'Keamanan',
  'Water': 'Kebersihan',
  'Other': 'Lainnya',
};

// Category -> division name. Same mapping as CATEGORY_TO_DIVISION in the Edge Function.
const kCategoryToDivision = {
  'Listrik': 'Teknis',
  'Medis': 'Medis',
  'Keamanan': 'Keamanan',
  'Logistik': 'Logistik',
  'Kebersihan': 'Logistik',
};

// Find the division id for a category in this event (null if there is no matching division)
Future<String?> _findDivisionId(String eventId, String? category) async {
  final divisionName = kCategoryToDivision[category];
  if (divisionName == null) return null;
  final divisions = await Supabase.instance.client
      .from('divisions')
      .select('id, name')
      .eq('event_id', eventId);
  for (final d in divisions) {
    if (d['name'].toString().toLowerCase() == divisionName.toLowerCase()) {
      return d['id'].toString();
    }
  }
  return null;
}

final _picker = ImagePicker();

Future<XFile?> _pickPhoto() => _picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      maxWidth: 1280,
      imageQuality: 80,
    );

Future<String?> _uploadPhoto(XFile? f, String eventId) async {
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  return TicketService().uploadFile(
      'photos', '$eventId/${DateTime.now().millisecondsSinceEpoch}.jpg', bytes, 'image/jpeg');
}

class CrewHomeScreen extends StatelessWidget {
  final String name;
  final String role;
  final String eventId;
  final String eventName;
  final List<String> zones;
  const CrewHomeScreen({
    super.key,
    required this.name,
    required this.role,
    required this.eventId,
    required this.eventName,
    required this.zones,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eventName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text('$name · $role', style: const TextStyle(fontSize: 13, color: kMuted)),
            ],
          ),
          bottom: const TabBar(
            labelColor: kBlue,
            indicatorColor: kBlue,
            tabs: [Tab(text: 'Voice'), Tab(text: '2-Tap')],
          ),
        ),
        body: TabBarView(children: [
          _VoiceTab(eventId: eventId, name: name, zones: zones),
          _TwoTapTab(eventId: eventId, name: name, zones: zones),
        ]),
      ),
    );
  }
}

class _VoiceTab extends StatefulWidget {
  final String eventId, name;
  final List<String> zones;
  const _VoiceTab({required this.eventId, required this.name, required this.zones});
  @override
  State<_VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<_VoiceTab> {
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _busy = false;
  XFile? _photo;
  late String _zone = widget.zones.first;

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) _say(context, 'Microphone permission is needed');
        return;
      }
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/report_${DateTime.now().millisecondsSinceEpoch}.wav';
      // 16 kHz mono: file kecil, cepat di-upload, cukup jelas buat AI
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) _say(context, 'Cannot record: $e');
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final path = await _rec.stop();
      if (path == null) throw 'No audio recorded';
      final bytes = await XFile(path).readAsBytes();
      final svc = TicketService();
      final audioUrl = await svc.uploadFile(
          'audio', '${widget.eventId}/${DateTime.now().millisecondsSinceEpoch}.wav', bytes, 'audio/wav');
      final photoUrl = await _uploadPhoto(_photo, widget.eventId);
      // NOTE: the selected zone is not sent; the AI reads it from the audio.
      final res = await svc.processTicket(
        eventId: widget.eventId,
        reporterName: widget.name,
        audioUrl: audioUrl,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      _say(context, 'Ticket created${res['category'] != null ? ': ${res['category']}' : ''}');
      setState(() => _photo = null);
    } on FunctionException catch (e) {
      // Tampilkan pesan error asli dari Edge Function (misal: Gemini gagal -> ...)
      final details = e.details;
      final msg = details is Map ? details['error'] : details;
      if (mounted) _say(context, 'AI error (${e.status}): ${msg ?? e.reasonPhrase}');
    } catch (e) {
      if (mounted) _say(context, 'Failed to send report: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final f = await _pickPhoto();
    if (f != null && mounted) setState(() => _photo = f);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _zone,
            decoration: const InputDecoration(labelText: 'Zone', filled: true, fillColor: Colors.white),
            items: [for (final z in widget.zones) DropdownMenuItem(value: z, child: Text(z))],
            onChanged: (v) => setState(() => _zone = v ?? _zone),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: 'Hold to speak',
                    child: GestureDetector(
                      onLongPressStart: _busy ? null : (_) => _start(),
                      onLongPressEnd: _busy ? null : (_) => _stop(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _recording ? 220 : 200,
                        height: _recording ? 220 : 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _busy ? kMuted : (_recording ? kRed : kBlue),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_busy ? Icons.hourglass_top : Icons.mic, color: Colors.white, size: 56),
                            const SizedBox(height: 8),
                            Text(_busy ? 'Sending…' : (_recording ? 'Recording…' : 'Hold to speak'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Say what is wrong, where, and how urgent.', style: TextStyle(color: kMuted)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _addPhoto,
              icon: Icon(_photo == null ? Icons.photo_camera_outlined : Icons.check_circle),
              label: Text(_photo == null ? 'Add photo (optional)' : 'Photo attached (tap to change)'),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('YOUR RECENT REPORTS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kMuted)),
          ),
          const SizedBox(height: 8),
          _MyReports(eventId: widget.eventId, name: widget.name),
        ],
      ),
    );
  }
}

// The 2 latest tickets sent by this volunteer, updated in realtime
class _MyReports extends StatefulWidget {
  final String eventId, name;
  const _MyReports({required this.eventId, required this.name});
  @override
  State<_MyReports> createState() => _MyReportsState();
}

class _MyReportsState extends State<_MyReports> {
  late final Stream<List<Map<String, dynamic>>> _stream =
      TicketService().streamTickets(widget.eventId);

  // Status in the database -> text and color shown to the volunteer
  static const _statusText = {
    'review': 'In review',
    'incoming': 'Waiting',
    'in_progress': 'In progress',
    'done': 'Done',
  };
  static const _statusColor = {
    'review': kYellow,
    'incoming': kYellow,
    'in_progress': kBlue,
    'done': kGreen,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading…', style: TextStyle(color: kMuted));
        }
        // streamTickets is sorted newest first, so take(2) = the 2 latest (more rows overflow small phones)
        final mine = snapshot.data!
            .where((t) => t['reporter_name'] == widget.name)
            .take(2)
            .toList();
        if (mine.isEmpty) {
          return const Text('No reports yet', style: TextStyle(color: kMuted));
        }
        return Column(
          children: [
            for (final t in mine)
              _ReportRow(
                '${t['category'] ?? 'Report'} · ${t['zone'] ?? '-'}',
                _statusText[t['status']] ?? t['status'].toString(),
                _statusColor[t['status']] ?? kMuted,
              ),
          ],
        );
      },
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String title, status;
  final Color color;
  const _ReportRow(this.title, this.status, this.color);
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        trailing: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _TwoTapTab extends StatefulWidget {
  final String eventId, name;
  final List<String> zones;
  const _TwoTapTab({required this.eventId, required this.name, required this.zones});
  @override
  State<_TwoTapTab> createState() => _TwoTapTabState();
}

class _TwoTapTabState extends State<_TwoTapTab> {
  String? _zone;
  String? _issue;
  bool _urgent = false;
  bool _busy = false;
  XFile? _photo;

  Future<void> _send() async {
    if (_zone == null || _issue == null) {
      _say(context, 'Pick a zone and an issue first');
      return;
    }
    setState(() => _busy = true);
    try {
      final photoUrl = await _uploadPhoto(_photo, widget.eventId);
      final category = kIssueCategory[_issue];
      final divisionId = await _findDivisionId(widget.eventId, category);
      await TicketService().createTicket(
        eventId: widget.eventId,
        reporterName: widget.name,
        photoUrl: photoUrl,
        category: category,
        zone: _zone,
        urgency: _urgent ? 'high' : 'low', // shown as CRITICAL / NORMAL in Command Center
        divisionId: divisionId,
      );
      if (!mounted) return;
      _say(context, 'Ticket sent: $_issue at $_zone');
      setState(() {
        _zone = null;
        _issue = null;
        _urgent = false;
        _photo = null;
      });
    } catch (e) {
      if (mounted) _say(context, 'Failed to send ticket: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final f = await _pickPhoto();
    if (f != null && mounted) setState(() => _photo = f);
  }

  Widget _grid(List<String> items, String? selected, ValueChanged<String> onTap) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final i in items)
          SizedBox(
            width: 104,
            height: 56,
            child: selected == i
                ? FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kBlue),
                    onPressed: () => onTap(i),
                    child: Text(i, textAlign: TextAlign.center))
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kInk),
                    onPressed: () => onTap(i),
                    child: Text(i, textAlign: TextAlign.center)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const h = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('1 · Where?', style: h),
        const SizedBox(height: 10),
        _grid(widget.zones, _zone, (v) => setState(() => _zone = v)),
        const SizedBox(height: 20),
        const Text('2 · What?', style: h),
        const SizedBox(height: 10),
        _grid(kIssues, _issue, (v) => setState(() => _issue = v)),
        const SizedBox(height: 20),
        const Text('3 · How urgent?', style: h),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Normal')),
            ButtonSegment(value: true, label: Text('High')),
          ],
          selected: {_urgent},
          onSelectionChanged: (s) => setState(() => _urgent = s.first),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _addPhoto,
            icon: Icon(_photo == null ? Icons.photo_camera_outlined : Icons.check_circle),
            label: Text(_photo == null ? 'Add photo (optional)' : 'Photo attached (tap to change)'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlue),
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'Sending…' : 'Send ticket', style: const TextStyle(fontSize: 17)),
          ),
        ),
      ],
    );
  }
}