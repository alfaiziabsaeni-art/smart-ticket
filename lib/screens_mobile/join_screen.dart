import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'crew_home_screen.dart';

// Same names as the divisions in Setup Event
const kRoles = ['Relawan', 'Teknis', 'Medis', 'Keamanan', 'Logistik', 'Koordinator'];

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String _role = kRoles.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CrewHomeScreen(
          name: _name.text.trim(),
          role: _role,
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
    setState(() => _code.text = code);
    // Name already filled in? Join right away
    if (_name.text.trim().isNotEmpty) _join();
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
                      Text('JOIN AN EVENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                      SizedBox(height: 4),
                      Text('Scan the QR or enter the code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
              const SizedBox(height: 18),
              const Text('Your role', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final r in kRoles)
                    SizedBox(
                      width: 150,
                      height: 52,
                      child: _role == r
                          ? FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: kBlue),
                              onPressed: () => setState(() => _role = r),
                              child: Text(r))
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kInk),
                              onPressed: () => setState(() => _role = r),
                              child: Text(r)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kBlue),
                  onPressed: _busy ? null : _join,
                  child: Text(_busy ? 'Joining…' : 'Join event', style: const TextStyle(fontSize: 16)),
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