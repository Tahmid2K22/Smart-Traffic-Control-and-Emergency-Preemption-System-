import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central accessor for all secret keys loaded from the .env file.
///
/// Usage:
///   1. Call `await AppConfig.load();` inside `main()` before any other init.
///   2. Access keys via `AppConfig.googleMapsApiKey`, etc.
///   3. NEVER hard-code keys in Dart source files — always read from here.
class AppConfig {
  AppConfig._();

  /// Loads the .env asset. Must be called once at app startup.
  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get googleMapsApiKey => _required('GOOGLE_MAPS_API_KEY');
  static String get supabaseUrl       => _required('SUPABASE_URL');
  static String get supabaseAnonKey   => _required('SUPABASE_ANON_KEY');

  static String _required(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty || value.startsWith('YOUR_')) {
      throw StateError(
        '❌  Missing env key: "$key"\n'
        '   → Copy .env.example to .env and fill in your real values.',
      );
    }
    return value;
  }
}
