import 'package:flutter_dotenv/flutter_dotenv.dart';

 /// Call AppConfig.load() in main() before other init.

class AppConfig {
  AppConfig._();

  /// Loads .env; call once at startup.
  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get googleMapsApiKey => _required('GOOGLE_MAPS_API_KEY');
  static String get supabaseUrl       => _required('SUPABASE_URL');
  static String get supabaseAnonKey   => _required('SUPABASE_ANON_KEY');

  static String _required(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty || value.startsWith('YOUR_')) {
      throw StateError(
        '  Missing env key: "$key"\n'
        '  Copy .env.example to .env and fill in your real values.',
      );
    }
    return value;
  }
}
