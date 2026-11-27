import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens_web/setup_event_screen.dart';
import 'crew_home_screen.dart';
import 'role_screen.dart';

// The QR from Setup Event is a link like https://.../?code=EVENT_ID.
// Take the code out of the link (or keep the text as it is if it is only the code).
String codeFromQr(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri?.queryParameters['code'] ?? value.trim();
}

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Opened from the QR link (?code=...)? Fill in the event code automatically
    final code = Uri.base.queryParameters['code'];
    if (code != null) _code.text = code;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final msg = ScaffoldMessenger.of(context);
    final code = _code.text.trim();
    if (_name.text.trim().isEmpty || code.isEmpty) {
      msg.showSnackBar(const SnackBar(content: Text('Enter your name and the event code')));
      return;
    }
    setState(() => _busy = true);
    try {
      // The event code is the event id (uuid) shown in the QR from Setup Event
      final ev = await Supabase.instance.client.from('events').select().eq('id', code).maybeSingle();
      if (!mounted) return;
      if (ev == null) {
        msg.showSnackBar(const SnackBar(content: Text('Event not found. Check the code.')));
        return;
      }
      final zones = List<String>.from(ev['zones'] ?? <String>[]);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RoleScreen(
          name: _name.text.trim(),
          eventId: code,
          eventName: ev['name'] as String? ?? 'Event',
          zones: zones.isEmpty ? kZones : zones,
        ),
      ));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not join: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Open the camera, read the QR from Setup Event, put the code in the box
  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanPage()),
    );
    if (code == null || !mounted) return;
    setState(() => _code.text = codeFromQr(code));
    // Name already filled in? Go to the next step right away
    if (_name.text.trim().isNotEmpty) _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Smart-Ticket', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBlue)),
              const SizedBox(height: 18),
              Card(
                color: Colors.white,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STEP 1 OF 2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                      SizedBox(height: 4),
                      Text('Join an event', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Scan the QR or enter the event code.', style: TextStyle(fontSize: 14, color: kMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code'),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                    labelText: 'Event code', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Your name', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kBlue),
                  onPressed: _busy ? null : _next,
                  child: Text(_busy ? 'Checking…' : 'Continue', style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              // Committee on a phone can still open Setup Event & Command Center
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Panitia? Buka Setup Event & Command Center'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupEventScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Full-screen camera that closes as soon as a QR code is read
class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false; // the camera can read the same QR many times per second

  void _onDetect(BarcodeCapture capture) {
    if (_done || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan event QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}