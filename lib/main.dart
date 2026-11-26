import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/env_config.dart';
import 'screens_web/setup_event_screen.dart';
import 'screens_mobile/join_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  runApp(const SmartTicketApp());
}

class SmartTicketApp extends StatelessWidget {
  const SmartTicketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart-Ticket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
        ),
        useMaterial3: true,
      ),
      routes: {
        '/web': (context) => SetupEventScreen(),
        '/join': (context) => JoinScreen(),
      },
      home: const _EntryRouter(),
    );
  }
}

class _EntryRouter extends StatelessWidget {
  const _EntryRouter();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return JoinScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return JoinScreen();
        }
        return SetupEventScreen();
      },
    );
  }
}