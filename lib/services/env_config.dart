@'
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
}
'@ | Set-Content -Path "lib/services/env_config.dart" -Encoding UTF8
Get-Content lib/services/env_config.dart