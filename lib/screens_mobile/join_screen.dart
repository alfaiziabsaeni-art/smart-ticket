import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'crew_home_screen.dart';

const kRoles = ['Field Crew', 'Technical', 'Medical', 'Security', 'Logistics', 'Coordinator'];

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
                  // TODO: open scanner (package: mobile_scanner)
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('QR scanner coming soon'))),
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