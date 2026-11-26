import 'package:flutter/material.dart';

const kBlue = Color(0xFF1D4ED8);
const kBg = Color(0xFFF1F5F9);
const kInk = Color(0xFF0F172A);
const kMuted = Color(0xFF475569);
const kRed = Color(0xFFDC2626);

const kZones = ['Main Stage', 'Gate A', 'East Toilet', 'Food Court', 'Parking', 'Backstage'];
const kIssues = ['Power', 'Medical', 'Crowd', 'Security', 'Water', 'Other'];

void _say(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class CrewHomeScreen extends StatelessWidget {
  final String name;
  final String role;
  const CrewHomeScreen({super.key, this.name = 'Crew', this.role = 'Field Crew'});

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
              const Text('Campus Fest 2026', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text('$name · $role', style: const TextStyle(fontSize: 13, color: kMuted)),
            ],
          ),
          bottom: const TabBar(
            labelColor: kBlue,
            indicatorColor: kBlue,
            tabs: [Tab(text: 'Voice'), Tab(text: '2-Tap')],
          ),
        ),
        body: const TabBarView(children: [_VoiceTab(), _TwoTapTab()]),
      ),
    );
  }
}

class _VoiceTab extends StatefulWidget {
  const _VoiceTab();
  @override
  State<_VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<_VoiceTab> {
  bool _recording = false;
  String _zone = kZones.first;

  void _start() {
    // TODO: start recording (package: record) + ask mic permission
    setState(() => _recording = true);
  }

  void _stop() {
    // TODO: stop recording, upload audio, call Gemini, create ticket in Supabase
    setState(() => _recording = false);
    _say(context, 'Voice report captured (mock)');
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
            items: [for (final z in kZones) DropdownMenuItem(value: z, child: Text(z))],
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
                      onLongPressStart: (_) => _start(),
                      onLongPressEnd: (_) => _stop(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _recording ? 220 : 200,
                        height: _recording ? 220 : 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _recording ? kRed : kBlue,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.mic, color: Colors.white, size: 56),
                            const SizedBox(height: 8),
                            Text(_recording ? 'Recording…' : 'Hold to speak',
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
              // TODO: image_picker
              onPressed: () => _say(context, 'Photo picker coming soon'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Add photo (optional)'),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('YOUR RECENT REPORTS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kMuted)),
          ),
          const SizedBox(height: 8),
          const _ReportRow('Generator down · Main Stage', 'In progress', kBlue),
          const _ReportRow('Leaking toilet · East Toilet', 'Done', Color(0xFF047857)),
        ],
      ),
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
  const _TwoTapTab();
  @override
  State<_TwoTapTab> createState() => _TwoTapTabState();
}

class _TwoTapTabState extends State<_TwoTapTab> {
  String? _zone;
  String? _issue;
  bool _urgent = false;

  void _send() {
    if (_zone == null || _issue == null) {
      _say(context, 'Pick a zone and an issue first');
      return;
    }
    // TODO: insert ticket into Supabase (category=_issue, zone=_zone, urgency)
    _say(context, 'Ticket sent: $_issue at $_zone${_urgent ? ' (HIGH)' : ''} (mock)');
    setState(() {
      _zone = null;
      _issue = null;
      _urgent = false;
    });
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
        _grid(kZones, _zone, (v) => setState(() => _zone = v)),
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
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlue),
            onPressed: _send,
            child: const Text('Send ticket', style: TextStyle(fontSize: 17)),
          ),
        ),
      ],
    );
  }
}
