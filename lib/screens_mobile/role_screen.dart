import 'package:flutter/material.dart';
import 'crew_home_screen.dart';

const kRoles = [
  ('Field Crew', 'General reports from the field'),
  ('Technical', 'Power, sound, equipment'),
  ('Medical', 'First aid and injuries'),
  ('Security', 'Crowd, gates, safety'),
  ('Logistics', 'Water, toilets, supplies'),
  ('Coordinator', 'Reviews and assigns tickets'),
];

class RoleScreen extends StatefulWidget {
  final String name;
  final String eventId;
  final String eventName;
  final List<String> zones;
  const RoleScreen({
    super.key,
    required this.name,
    required this.eventId,
    required this.eventName,
    required this.zones,
  });
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  String _role = kRoles.first.$1;

  void _continue() {
    // TODO: save crew member + role to Supabase if the backend needs it
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => CrewHomeScreen(
          name: widget.name,
          role: _role,
          eventId: widget.eventId,
          eventName: widget.eventName,
          zones: widget.zones,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(backgroundColor: Colors.white, title: Text(widget.eventName)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('STEP 2 OF 2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
              const SizedBox(height: 4),
              Text('Hi ${widget.name}, choose your role',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final r in kRoles)
                      Card(
                        color: _role == r.$1 ? const Color(0xFFDBEAFE) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: _role == r.$1 ? kBlue : const Color(0xFFE2E8F0), width: 1.5),
                        ),
                        child: ListTile(
                          minTileHeight: 64,
                          title: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(r.$2),
                          trailing: _role == r.$1 ? const Icon(Icons.check_circle, color: kBlue) : null,
                          onTap: () => setState(() => _role = r.$1),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kBlue),
                  onPressed: _continue,
                  child: const Text('Open dashboard', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}